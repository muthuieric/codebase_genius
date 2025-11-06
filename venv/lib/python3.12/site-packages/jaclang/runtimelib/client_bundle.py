"""Client bundle generation utilities for Jac web front-ends."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import Any, Iterable, Sequence

from jaclang.compiler.program import JacProgram


class ClientBundleError(RuntimeError):
    """Raised when the client bundle cannot be generated."""


@dataclass(slots=True)
class ClientBundle:
    """Container for a compiled client bundle."""

    module_name: str
    code: str
    client_functions: list[str]
    client_globals: list[str]
    hash: str


@dataclass(slots=True)
class _CachedBundle:
    signature: str
    bundle: ClientBundle


class ClientBundleBuilder:
    """Compile Jac modules and runtime support into a browser-ready bundle."""

    def __init__(self, runtime_path: Path | None = None) -> None:
        """Initialise the builder with an optional override for the runtime path."""
        self.runtime_path = runtime_path or Path(__file__).with_name(
            "client_runtime.jac"
        )
        self._cache: dict[str, _CachedBundle] = {}

    def build(self, module: ModuleType, force: bool = False) -> ClientBundle:
        """Build (or reuse) a client bundle for the supplied module."""
        # Derive source path from module __file__ (replace .py with .jac)
        if not hasattr(module, "__file__") or not module.__file__:
            raise ClientBundleError(
                f"Module '{module.__name__}' has no __file__ attribute"
            )
        module_path = module.__file__.replace(".py", ".jac")

        source_path = Path(module_path).resolve()
        runtime_path = self.runtime_path.resolve()
        signature = self._signature([source_path, runtime_path])

        cached = self._cache.get(module.__name__)
        if not force and cached and cached.signature == signature:
            return cached.bundle

        bundle = self._compile_bundle(module, source_path, runtime_path)
        self._cache[module.__name__] = _CachedBundle(signature=signature, bundle=bundle)
        return bundle

    def _compile_bundle(
        self,
        module: ModuleType,
        module_path: Path,
        runtime_path: Path,
    ) -> ClientBundle:
        """Compile bundle pieces and stitch them together."""
        runtime_js = self._compile_to_js(runtime_path)

        # Get manifest from JacProgram
        from jaclang.runtimelib.machine import JacMachine as Jac

        mod = Jac.program.mod.hub.get(str(module_path))
        manifest = mod.gen.client_manifest if mod else None

        module_js = self._compile_to_js(module_path)

        client_exports = sorted(dict.fromkeys(manifest.exports)) if manifest else []

        client_globals_map: dict[str, Any] = {}
        if manifest:
            for name in manifest.globals:
                if name in manifest.globals_values:
                    client_globals_map[name] = manifest.globals_values[name]
                elif hasattr(module, name):
                    client_globals_map[name] = getattr(module, name)
                else:
                    client_globals_map[name] = None
        client_globals_map = {
            key: client_globals_map[key] for key in sorted(client_globals_map)
        }

        registration_js = self._generate_registration_js(
            module.__name__, client_exports, client_globals_map
        )

        bundle_pieces = [
            "// Jac client runtime",
            runtime_js,
            "",
            f"// Client module: {module.__name__}",
            module_js,
            "",
            registration_js,
        ]
        bundle_code = "\n".join(piece for piece in bundle_pieces if piece is not None)
        bundle_hash = hashlib.sha256(bundle_code.encode("utf-8")).hexdigest()

        return ClientBundle(
            module_name=module.__name__,
            code=bundle_code,
            client_functions=client_exports,
            client_globals=list(client_globals_map.keys()),
            hash=bundle_hash,
        )

    def _compile_to_js(self, source_path: Path) -> str:
        """Compile the provided Jac file into JavaScript."""
        program = JacProgram()
        mod = program.compile(str(source_path))
        if program.errors_had:
            formatted = "\n".join(str(err) for err in program.errors_had)
            raise ClientBundleError(
                f"Failed to compile '{source_path}' for client bundle:\n{formatted}"
            )
        return mod.gen.js or ""

    @staticmethod
    def _signature(paths: Iterable[Path]) -> str:
        """Compute a cache signature based on file modification times."""
        parts: list[str] = []
        for path in paths:
            try:
                stat = path.stat()
                parts.append(f"{path}:{stat.st_mtime_ns}")
            except FileNotFoundError:
                parts.append(f"{path}:missing")
        return hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()

    @staticmethod
    def _generate_registration_js(
        module_name: str,
        client_functions: Sequence[str],
        client_globals: dict[str, Any],
    ) -> str:
        """Generate registration code that exposes client symbols globally."""
        globals_entries: list[str] = []
        for name, value in client_globals.items():
            identifier = json.dumps(name)
            try:
                value_literal = json.dumps(value)
            except TypeError:
                value_literal = "null"
            globals_entries.append(f"{identifier}: {value_literal}")

        globals_literal = (
            "{ " + ", ".join(globals_entries) + " }" if globals_entries else "{}"
        )
        functions_literal = json.dumps(list(client_functions))
        module_literal = json.dumps(module_name)

        # Use the registration function from client_runtime.jac
        return f"__jacRegisterClientModule({module_literal}, {functions_literal}, {globals_literal});"
