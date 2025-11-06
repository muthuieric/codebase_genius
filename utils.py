import git
import os
import shutil  # More robust for directory removal
from tree_sitter import Language, Parser
import tree_sitter_python as tspython

# --- Imports for Jac parsing ---
# We use the Jac compiler's internal parser API
from jaclang.compiler.parser import JacParser
from jaclang.compiler.absyntree import AstNode, Ability, Architype

# --- Imports for Diagram Generation ---
try:
    import networkx as nx
    import networkx_mermaid as nxm
except ImportError:
    print("Warning: 'networkx' and 'networkx-mermaid' not installed. Diagram generation will fail.")
    print("Please run: pip install networkx networkx-mermaid")


# --- (Phase 1) ---
def clone_repo(url: str, temp_dir: str = "./temp_repo") -> str:
    """Clones a public git repo to a temporary directory."""
    try:
        if os.path.exists(temp_dir):
            print(f"Cleaning up old repo at {temp_dir}...")
            shutil.rmtree(temp_dir)
        print(f"Cloning {url} to {temp_dir}...")
        git.Repo.clone_from(url, temp_dir)
        print("Clone complete.")
        return temp_dir
    except Exception as e:
        print(f"Error cloning repo: {e}")
        return None

# --- (Phase 2 & 3) ---

# --- Tree-sitter Setup for Python ---
PY_LANGUAGE = Language(tspython.language())
py_parser = Parser(PY_LANGUAGE)

# --- Tree-sitter Queries ---
# These queries find the nodes we care about.
# @name captures the identifier node
# @...definition captures the entire code block
py_queries = {
    "functions": PY_LANGUAGE.query("""
        (function_definition
            name: (identifier) @name
            parameters: (parameters) @params
            body: (block) @body
        ) @function.definition
    """),
    "classes": PY_LANGUAGE.query("""
        (class_definition
            name: (identifier) @name
            body: (block) @body
        ) @class.definition
    """),
    "calls": PY_LANGUAGE.query("""
        (call
            function: (identifier) @name
        ) @call
    """),
    "imports_from": PY_LANGUAGE.query("""
        (import_from_statement
            module_name: (dotted_name) @module
            name: (dotted_name) @import
        ) @import_from
    """),
    "imports": PY_LANGUAGE.query("""
        (import_statement
            name: (dotted_name) @module
        ) @import
    """)
}

def get_node_text(node, content_bytes):
    """Helper to extract text from a tree-sitter node."""
    return content_bytes[node.start_byte:node.end_byte].decode('utf8')

def get_docstring(body_node, content_bytes):
    """Helper to extract a docstring from a function/class body."""
    if (body_node.child_count > 0 and
        body_node.children.type == 'expression_statement' and
        body_node.children.children.type == 'string'):
        return get_node_text(body_node.children.children, content_bytes)
    return ""

def analyze_python_code(file_content: str) -> dict:
    """
    Parses Python code using tree-sitter and extracts classes,
    functions, calls, and imports.
    """
    content_bytes = bytes(file_content, "utf8")
    tree = py_parser.parse(content_bytes)
    root_node = tree.root_node

    results = {
        "functions":, "classes":, "calls":, "imports":
    }

    # Capture functions
    captures_funcs = py_queries["functions"].captures(root_node)
    func_nodes = {}
    for node, name in captures_funcs:
        if name == "function.definition":
            func_nodes[node.id] = {"def_node": node}
        elif name in ["name", "params", "body"]:
            if node.parent.id in func_nodes:
                func_nodes[node.parent.id][name] = node
    
    for data in func_nodes.values():
        if "name" not in data: continue
        results["functions"].append({
            "name": get_node_text(data["name"], content_bytes),
            "signature": f"def {get_node_text(data['name'], content_bytes)}{get_node_text(data['params'], content_bytes)}",
            "docstring": get_docstring(data["body"], content_bytes),
            "code_body": get_node_text(data["def_node"], content_bytes),
            "start_line": data["def_node"].start_point,
            "end_line": data["def_node"].end_point
        })

    # Capture classes
    captures_classes = py_queries["classes"].captures(root_node)
    class_nodes = {}
    for node, name in captures_classes:
        if name == "class.definition":
            class_nodes[node.id] = {"def_node": node}
        elif name in ["name", "body"]:
             if node.parent.id in class_nodes:
                class_nodes[node.parent.id][name] = node

    for data in class_nodes.values():
        if "name" not in data: continue
        results["classes"].append({
            "name": get_node_text(data["name"], content_bytes),
            "docstring": get_docstring(data["body"], content_bytes),
            "code_body": get_node_text(data["def_node"], content_bytes),
            "start_line": data["def_node"].start_point,
            "end_line": data["def_node"].end_point
        })

    # Capture function calls
    captures_calls = py_queries["calls"].captures(root_node)
    for node, name in captures_calls:
        if name == "name":
            # Find the function/class this call belongs to
            parent_func = node.parent
            while parent_func and parent_func.type not in ['function_definition', 'class_definition']:
                parent_func = parent_func.parent
            
            owner_name = None
            if parent_func:
                owner_node = parent_func.child_by_field_name("name")
                if owner_node:
                    owner_name = get_node_text(owner_node, content_bytes)

            results["calls"].append({
                "call_name": get_node_text(node, content_bytes),
                "line_number": node.start_point,
                "owner_function": owner_name # Name of the func that made the call
            })
    
    #... (Import capture logic would be similar)...

    return results

def analyze_jac_code(file_content: str) -> dict:
    """
    Parses Jac code using the Jac compiler's internal parser
    and extracts archetypes (classes/nodes) and abilities (functions).
    """
    try:
        # Use the JacParser to parse a string of Jac code
        parse_result = JacParser(mod_path="temp.jac", input_ir=file_content)
        root_node = parse_result.ir
        
        results = {"functions":, "classes":, "calls":, "imports":}

        # Jac's AST is different. We walk it to find Archetypes and Abilities.
        if root_node and hasattr(root_node, 'body'):
            for item in root_node.body:
                if isinstance(item, Architype):
                    # This is a 'node', 'edge', 'walker', or 'class'
                    results["classes"].append({
                        "name": item.name.value,
                        "docstring": item.doc.value if item.doc else "",
                        "code_body": item.to_jac_str(),
                        "start_line": item.loc.first_line,
                        "end_line": item.loc.last_line
                    })
                elif isinstance(item, Ability):
                    # This is a 'can' (function)
                    results["functions"].append({
                        "name": item.name_ref.name_spec.value,
                        "signature": item.to_jac_str().split('{').strip(),
                        "docstring": item.doc.value if item.doc else "",
                        "code_body": item.to_jac_str(),
                        "start_line": item.loc.first_line,
                        "end_line": item.loc.last_line
                    })
        
        return results

    except Exception as e:
        print(f"Error parsing Jac code: {e}")
        return {"functions":, "classes":, "calls":, "imports":}

# --- (This part is for Phase 3) ---
def save_markdown(repo_name: str, content: str) -> str:
    """Saves final markdown to a local file."""
    output_dir = os.path.join("./outputs", repo_name)
    os.makedirs(output_dir, exist_ok=True)
    save_path = os.path.join(output_dir, "docs.md")
    
    with open(save_path, "w", encoding="utf-8") as f:
        f.write(content)
    return save_path

def create_mermaid_chart(nodes: list, edges: list) -> str:
    """
    Generates a Mermaid graph string from lists of nodes and edges
    using networkx-mermaid.
    """
    if "nx" not in globals() or "nxm" not in globals():
        print("NetworkX/Mermaid libraries not loaded. Skipping diagram.")
        return ""
        
    if not nodes:
        return ""

    G = nx.DiGraph()
    for n in nodes:
        G.add_node(n["id"], label=n["label"])
    
    for e in edges:
        # Ensure nodes exist before adding edge
        if not G.has_node(e["from"]):
            G.add_node(e["from"], label=e["from"])
        if not G.has_node(e["to"]):
            G.add_node(e["to"], label=e["to"])
        G.add_edge(e["from"], e["to"])

    try:
        # Build the Mermaid Diagram string
        builder = nxm.builders.DiagramBuilder(
            orientation=nxm.DiagramOrientation.TOP_BOTTOM
        )
        mermaid_diagram = builder.build(G)
        
        # The builder.build() returns the full Mermaid string
        return str(mermaid_diagram)
    except Exception as e:
        print(f"Error generating Mermaid chart: {e}")
        return ""