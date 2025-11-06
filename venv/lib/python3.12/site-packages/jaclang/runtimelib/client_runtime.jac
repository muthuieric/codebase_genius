"""Client-side runtime for Jac JSX and walker interactions."""

# JSX factory function
cl def __jacJsx(tag: any, props: dict = {}, children: list = []) -> dict {
    return {"tag": tag, "props": props, "children": children};
}

# DOM rendering function
cl def renderJsxTree(node: any, container: any) -> None {
    container.replaceChildren(__buildDom(node));
}

# Internal: Build DOM from JSX tree
cl def __buildDom(node: any) -> any {
    if node == None {
        return document.createTextNode("");
    }

    if not __isObject(node) {
        return document.createTextNode(String(node));
    }

    # Handle component functions
    tag = node.get("tag");
    if __isFunction(tag) {
        props = node.get("props", {});
        return __buildDom(tag(props));
    }

    # Create element
    element = document.createElement(tag if tag else "div");

    # Apply properties
    props = node.get("props", {});
    for key in __objectKeys(props) {
        value = props.get(key);
        __applyProp(element, key, value);
    }

    # Render children
    children = node.get("children", []);
    for child in children {
        childDom = __buildDom(child);
        if childDom {
            element.appendChild(childDom);
        }
    }

    return element;
}

# Internal: Apply property to DOM element
cl def __applyProp(element: any, key: str, value: any) -> None {
    if key.startswith("on") {
        # Event handler: onclick -> click
        event = key[2:].lower();
        element.addEventListener(event, value);
    } elif key == "className" or key == "class" {
        element.className = value;
    } elif key == "style" and __isObject(value) {
        # Style object
        for styleKey in __objectKeys(value) {
            element.style[styleKey] = value.get(styleKey);
        }
    } elif key != "children" {
        element.setAttribute(key, String(value));
    }
}

# Walker spawn function
cl async def __jacSpawn(walker: str, fields: dict = {}) -> any {
    token = __getLocalStorage("jac_token");

    response = await fetch(
        f"/walker/{walker}",
        {
            "method": "POST",
            "headers": {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {token}" if token else ""
            },
            "body": JSON.stringify({"nd": "root", **fields})
        }
    );

    if not response.ok {
        error_text = await response.text();
        raise Exception(f"Walker {walker} failed: {error_text}");
    }

    return JSON.parse(await response.text());
}

# Function call function - calls server-side functions from client
cl async def __jacCallFunction(function_name: str, args: dict = {}) -> any {
    token = __getLocalStorage("jac_token");

    response = await fetch(
        f"/function/{function_name}",
        {
            "method": "POST",
            "headers": {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {token}" if token else ""
            },
            "body": JSON.stringify({"args": args})
        }
    );

    if not response.ok {
        error_text = await response.text();
        raise Exception(f"Function {function_name} failed: {error_text}");
    }

    data = JSON.parse(await response.text());
    return data.get("result");
}

# Authentication helpers
cl async def jacSignup(username: str, password: str) -> dict {
    response = await fetch(
        "/user/create",
        {
            "method": "POST",
            "headers": {"Content-Type": "application/json"},
            "body": JSON.stringify({"username": username, "password": password})
        }
    );

    if response.ok {
        data = JSON.parse(await response.text());
        token = data.get("token");
        if token {
            __setLocalStorage("jac_token", token);
            return {"success": True, "token": token, "username": username};
        }
        return {"success": False, "error": "No token received"};
    } else {
        error_text = await response.text();
        try {
            error_data = JSON.parse(error_text);
            return {"success": False, "error": error_data.get("error", "Signup failed")};
        } except Exception {
            return {"success": False, "error": error_text};
        }
    }
}

cl async def jacLogin(username: str, password: str) -> bool {
    response = await fetch(
        "/user/login",
        {
            "method": "POST",
            "headers": {"Content-Type": "application/json"},
            "body": JSON.stringify({"username": username, "password": password})
        }
    );

    if response.ok {
        data = JSON.parse(await response.text());
        token = data.get("token");
        if token {
            __setLocalStorage("jac_token", token);
            return True;
        }
    }
    return False;
}

cl def jacLogout() -> None {
    __removeLocalStorage("jac_token");
}

cl def jacIsLoggedIn() -> bool {
    token = __getLocalStorage("jac_token");
    return token != None and token != "";
}

# Browser API shims
cl def __getLocalStorage(key: str) -> str {
    storage = globalThis.localStorage;
    return storage.getItem(key) if storage else "";
}

cl def __setLocalStorage(key: str, value: str) -> None {
    storage = globalThis.localStorage;
    if storage {
        storage.setItem(key, value);
    }
}

cl def __removeLocalStorage(key: str) -> None {
    storage = globalThis.localStorage;
    if storage {
        storage.removeItem(key);
    }
}

cl def __isObject(value: any) -> bool {
    if value == None {
        return False;
    }
    return Object.prototype.toString.call(value) == "[object Object]";
}

cl def __isFunction(value: any) -> bool {
    return Object.prototype.toString.call(value) == "[object Function]";
}

cl def __objectKeys(obj: any) -> list {
    if obj == None {
        return [];
    }
    return Object.keys(obj);
}

# Low-level helpers
cl def __jacHasOwn(obj: any, key: any) -> bool {
    try {
        return Object.prototype.hasOwnProperty.call(obj, key);
    } except Exception {
        return False;
    }
}

# Internal polyfill for Python-style dict.get on plain JS objects
cl def __jacEnsureObjectGetPolyfill() -> None {
    proto = Object.prototype;
    if proto.get {
        return;
    }

    # Define the polyfill function inline
    def get_polyfill(key: any, defaultValue: any = None) -> any {
        if __jacHasOwn(this, key) {
            return this[key];
        }
        if defaultValue != None {
            return defaultValue;
        }
        return None;
    }

    Object.defineProperty(
        proto,
        "get",
        {
            "value": get_polyfill,
            "configurable": True,
            "writable": True
        }
    );
}

# Common utility helpers
cl def __jacGetDocument(scope: any) -> any {
    try {
        return scope.document;
    } except Exception {
        return None;
    }
}

cl def __jacParseJsonObject(text: str) -> any {
    try {
        parsed = JSON.parse(text);
        if __isObject(parsed) {
            return parsed;
        }
        console.error("[Jac] Hydration payload is not an object");
        return None;
    } except Exception as err {
        console.error("[Jac] Failed to parse hydration payload", err);
        return None;
    }
}

cl def __jacBuildOrderedArgs(order: list, argsDict: dict) -> list {
    result = [];
    if not order {
        return result;
    }
    values = argsDict if __isObject(argsDict) else {};
    for name in order {
        result.push(values.get(name));
    }
    return result;
}

cl def __jacResolveRenderer(scope: any) -> any {
    if scope.renderJsxTree {
        return scope.renderJsxTree;
    }
    if __isFunction(renderJsxTree) {
        return renderJsxTree;
    }
    return None;
}

cl def __jacResolveTarget(
    moduleRecord: dict,
    registry: dict,
    name: str
) -> any {
    moduleFunctions = (
        moduleRecord.moduleFunctions
        if moduleRecord and moduleRecord.moduleFunctions
        else {}
    );
    if __jacHasOwn(moduleFunctions, name) {
        return moduleFunctions[name];
    }
    registryFunctions = (
        registry.functions
        if registry and registry.functions
        else {}
    );
    if __jacHasOwn(registryFunctions, name) {
        return registryFunctions[name];
    }
    return None;
}

cl def __jacSafeCallTarget(
    target: any,
    scope: any,
    orderedArgs: list,
    targetName: str
) -> dict {
    try {
        result = target.apply(scope, orderedArgs);
        return {"ok": True, "value": result};
    } except Exception as err {
        console.error("[Jac] Error executing client function " + targetName, err);
        return {"ok": False, "value": None};
    }
}

# Runtime support helpers for client module registration / hydration
cl def __jacGlobalScope() -> any {
    try {
        return globalThis;
    } except Exception {}
    try {
        return window;
    } except Exception {}
    try {
        return self;
    } except Exception {}
    return {};
}

cl def __jacEnsureRegistry() -> dict {
    scope = __jacGlobalScope();
    registry = scope.__jacClient;
    if not registry {
        registry = {
            "functions": {},
            "globals": {},
            "modules": {},
            "state": {"globals": {}},
            "__hydration": {"registered": False},
            "lastModule": None
        };
        scope.__jacClient = registry;
        return registry;
    }
    if not registry.functions {
        registry.functions = {};
    }
    if not registry.globals {
        registry.globals = {};
    }
    if not registry.modules {
        registry.modules = {};
    }
    if not registry.state {
        registry.state = {"globals": {}};
    } elif not registry.state.globals {
        registry.state.globals = {};
    }
    if not registry.__hydration {
        registry.__hydration = {"registered": False};
    }
    return registry;
}

cl def __jacApplyRender(renderer: any, container: any, node: any) -> None {
    if not renderer or not container {
        return;
    }
    try {
        renderer(node, container);
    } except Exception as err {
        console.error("[Jac] Failed to render JSX tree", err);
    }
}

cl def __jacHydrateFromDom(defaultModuleName: str) -> None {
    __jacEnsureObjectGetPolyfill();
    scope = __jacGlobalScope();
    documentRef = __jacGetDocument(scope);
    if not documentRef {
        return;
    }

    initEl = documentRef.getElementById("__jac_init__");
    rootEl = documentRef.getElementById("__jac_root");
    if not initEl or not rootEl {
        return;
    }

    dataset = initEl.dataset if initEl.dataset else None;
    if dataset and dataset.jacHydrated == "true" {
        return;
    }
    if dataset {
        dataset.jacHydrated = "true";
    }

    payloadText = initEl.textContent if initEl.textContent else "{}";
    payload = __jacParseJsonObject(payloadText);
    if not payload {
        return;
    }

    targetName = payload.get("function");
    if not targetName {
        return;
    }

    fallbackModule = defaultModuleName if defaultModuleName else "";
    moduleCandidate = payload.get("module");
    moduleName = moduleCandidate if moduleCandidate else fallbackModule;

    registry = __jacEnsureRegistry();
    modulesStore = registry.modules if registry.modules else {};
    moduleRecord = modulesStore[moduleName] if __jacHasOwn(modulesStore, moduleName) else None;
    if not moduleRecord {
        console.error("[Jac] Client module not registered: " + moduleName);
        return;
    }

    argOrderRaw = payload.get("argOrder", []);
    argOrder = argOrderRaw if Array.isArray(argOrderRaw) else [];
    argsDictRaw = payload.get("args", {});
    argsDict = argsDictRaw if __isObject(argsDictRaw) else {};
    orderedArgs = __jacBuildOrderedArgs(argOrder, argsDict);

    payloadGlobalsRaw = payload.get("globals", {});
    payloadGlobals = payloadGlobalsRaw if __isObject(payloadGlobalsRaw) else {};
    registry.state.globals[moduleName] = payloadGlobals;
    for gName in __objectKeys(payloadGlobals) {
        gValue = payloadGlobals[gName];
        scope[gName] = gValue;
        registry.globals[gName] = gValue;
    }

    target = __jacResolveTarget(moduleRecord, registry, targetName);
    if not target {
        console.error("[Jac] Client function not found: " + targetName);
        return;
    }

    renderer = __jacResolveRenderer(scope);
    if not renderer {
        console.warn("[Jac] renderJsxTree is not available in client bundle");
    }

    callOutcome = __jacSafeCallTarget(target, scope, orderedArgs, targetName);
    if not callOutcome or not callOutcome.get("ok") {
        return;
    }
    value = callOutcome.get("value");

    if value and __isObject(value) and __isFunction(value.then) {
        value.then(
            lambda node: any -> None {
                __jacApplyRender(renderer, rootEl, node);
            }
        ).catch(
            lambda err: any -> None {
                console.error("[Jac] Error resolving client function promise", err);
            }
        );
    } else {
        __jacApplyRender(renderer, rootEl, value);
    }
}

cl def __jacExecuteHydration() -> None {
    registry = __jacEnsureRegistry();
    defaultModule = registry.lastModule if registry.lastModule else "";
    __jacHydrateFromDom(defaultModule);
}

cl def __jacEnsureHydration(moduleName: str) -> None {
    __jacEnsureObjectGetPolyfill();
    registry = __jacEnsureRegistry();
    registry.lastModule = moduleName;

    existingHydration = registry.__hydration if registry.__hydration else None;
    hydration = existingHydration if existingHydration else {"registered": False};
    registry.__hydration = hydration;

    scope = __jacGlobalScope();
    documentRef = __jacGetDocument(scope);
    if not documentRef {
        return;
    }

    alreadyRegistered = hydration.registered if hydration.registered else False;
    if not alreadyRegistered {
        hydration.registered = True;
        documentRef.addEventListener(
            "DOMContentLoaded",
            lambda _event: any -> None {
                __jacExecuteHydration();
            },
            {"once": True}
        );
    }

    if documentRef.readyState != "loading" {
        __jacExecuteHydration();
    }
}

cl def __jacRegisterClientModule(
    moduleName: str,
    clientFunctions: list = [],
    clientGlobals: dict = {}
) -> None {
    __jacEnsureObjectGetPolyfill();
    scope = __jacGlobalScope();
    registry = __jacEnsureRegistry();

    moduleFunctions = {};
    registeredFunctions = [];
    if clientFunctions {
        for funcName in clientFunctions {
            funcRef = scope[funcName];
            if not funcRef {
                console.error("[Jac] Client function not found during registration: " + funcName);
                continue;
            }
            moduleFunctions[funcName] = funcRef;
            registry.functions[funcName] = funcRef;
            scope[funcName] = funcRef;
            registeredFunctions.push(funcName);
        }
    }

    moduleGlobals = {};
    globalNames = [];
    globalsMap = clientGlobals if clientGlobals else {};
    for gName in __objectKeys(globalsMap) {
        globalNames.push(gName);
        defaultValue = globalsMap[gName];
        existing = scope[gName];
        if existing == None {
            scope[gName] = defaultValue;
            moduleGlobals[gName] = defaultValue;
        } else {
            moduleGlobals[gName] = existing;
        }
        registry.globals[gName] = scope[gName];
    }

    modulesStore = registry.modules if registry.modules else {};
    existingRecord = modulesStore[moduleName] if __jacHasOwn(modulesStore, moduleName) else None;
    moduleRecord = existingRecord if existingRecord else {};
    moduleRecord.moduleFunctions = moduleFunctions;
    moduleRecord.moduleGlobals = moduleGlobals;
    moduleRecord.functions = registeredFunctions;
    moduleRecord.globals = globalNames;
    moduleRecord.defaults = globalsMap;
    registry.modules[moduleName] = moduleRecord;

    stateGlobals = registry.state.globals;
    if not __jacHasOwn(stateGlobals, moduleName) {
        stateGlobals[moduleName] = {};
    }

    __jacEnsureHydration(moduleName);
}
