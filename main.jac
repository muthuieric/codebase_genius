# --- Imports ---
import utils;
import os;
import from byllm.lib { Model }

# --- AI Configuration ---
glob llm = Model(model_name="gemini/gemini-2.0-flash");

# --- Graph Schema (Our Database) ---

# == Physical Graph (Built by RepoMapper) ==
node Directory {
    has path: str;
    has name: str;
}

node File {
    has path: str;
    has name: str;
    has content: str;
}

edge contains; # A Directory "contains" a File or Directory

# == Logical Graph (Built by CodeAnalyzer) ==
node Module {
    has name: str;
    has file_path: str;
    
    # Store raw parse data for Pass 2 (Linking)
    has raw_calls: list;
    has raw_imports: list;
}

node Class {
    has name: str;
    has docstring: str;
    has code_body: str;
    has start_line: int;
    has end_line: int;
}

node Function {
    has name: str;
    has signature: str;
    has docstring: str;
    has code_body: str;
    has start_line: int;
    has end_line: int;
}

# == Edges for the Logical Graph ==

# Connects a File to the Module it represents
edge contains_code;

# Connects a container to its contents
# Module --(defines)--> Class
# Module --(defines)--> Function
# Class  --(defines)--> Function (i.e., a method)
edge defines;

# Connects a Module to a Module it imports
edge imports {
    has alias: str; # e.g., import numpy as np -> alias="np"
}

# Connects a Class to its parent Class
edge inherits;

# Connects a Function (caller) to a Function (callee)
edge calls {
    has line_number: int;
}

# --- Agent 2: Repo Mapper ---
walker RepoMapper {
    has repo_path: str;
    has ignore_list: list = [".git", ".venv", "venv", "__pycache__", "node_modules"];
    
    # 1. Start by creating the root node for the repo
    can map_repo with `root entry {
        root_dir_node = Directory(
            path=self.repo_path,
            name=os.path.basename(self.repo_path)
        );
        root ++> root_dir_node;
        self.walk_dir(root_dir_node);
        
        # 2. After mapping, find and summarize the README
        readme_node = self.find_readme(root_dir_node);
        if readme_node {
            summary = self.summarize_readme(readme_node.content);
            report {"status": "Repo Mapped", "readme_summary": summary};
        } else {
            report {"status": "Repo Mapped", "readme_summary": "No README found."};
        }
    }
    
    # 3. This is a recursive function to walk the directory
    def walk_dir(current_dir_node: Directory) {
        try {
            for item in os.listdir(current_dir_node.path) {
                if item in self.ignore_list {
                    continue;
                }
                
                item_path = os.path.join(current_dir_node.path, item);
                
                if os.path.isdir(item_path) {
                    new_dir = Directory(path=item_path, name=item);
                    current_dir_node ++> new_dir;
                    self.walk_dir(new_dir);
                } else {
                    try {
                        with open(item_path, "r", encoding="utf-8") as f {
                            content = f.read();
                        }
                        new_file = File(path=item_path, name=item, content=content);
                        current_dir_node ++> new_file;
                    } except Exception {
                        print(f"Could not read file {item_path}");
                    }
                }
            }
        } except Exception {
            print(f"Could not list directory {current_dir_node.path}");
        }
    }
    
    # 4. Helper to find the README
    def find_readme(start_node: Directory) -> File {
        # Jac's graph query: "Find a child of start_node
        # that is a File and its name is README.md"
        readme_list = [start_node --> File(name.lower() == "readme.md")];
        if readme_list {
            return readme_list;
        }
        return null;
    }

    # 5. Our first byLLM function!
    """Summarize this README file into a concise, one-paragraph overview."""
    def summarize_readme(readme_content: str) -> str by llm();
}


# --- Agent 3: CodeAnalyzer (Pass 1 - Node Creation) ---
walker CodeAnalyzer {
    has file_node: File; # This is passed in by the Supervisor

    can analyze_code with `root entry {
        analysis_data = {};
        
        if self.file_node.name.endsWith(".py") {
            analysis_data = utils.analyze_python_code(self.file_node.content);
        } elif self.file_node.name.endsWith(".jac") {
            analysis_data = utils.analyze_jac_code(self.file_node.content);
        } else {
            report {"status": "skipped", "reason": "Not a.py or.jac file"};
            disengage;
        }

        # 1. Create the Module node
        mod = Module(
            name=self.file_node.name,
            file_path=self.file_node.path
        );
        # Connect File (physical) to Module (logical)
        self.file_node ++> mod;

        # 2. Create Function nodes
        for func_data in analysis_data["functions"] {
            func_node = Function(
                name=func_data["name"],
                signature=func_data["signature"],
                docstring=func_data["docstring"],
                code_body=func_data["code_body"],
                start_line=func_data["start_line"],
                end_line=func_data["end_line"]
            );
            # Connect Module to the Function it defines
            mod ++> func_node;
        }

        # 3. Create Class nodes
        for class_data in analysis_data["classes"] {
            class_node = Class(
                name=class_data["name"],
                docstring=class_data["docstring"],
                code_body=class_data["code_body"],
                start_line=class_data["start_line"],
                end_line=class_data["end_line"]
            );
            # Connect Module to the Class it defines
            mod ++> class_node;
        }
        
        # 4. Store call/import data for Pass 2
        # We attach this raw data to the module node
        mod.raw_calls = analysis_data["calls"];
        mod.raw_imports = analysis_data["imports"];

        report {"status": "analyzed", "file": self.file_node.name};
    }
}

# --- Agent 3b: GraphLinker (Pass 2 - Edge Creation) ---
walker GraphLinker {
    
    can link_graph with `root entry {
        # Visit every Module node that was created
        visit [--> File --> Module];
    }
    
    # This ability runs on each Module node
    can link_module with Module entry {
        # TODO: Implement linking logic
        # 1. Loop through here.raw_imports
        # 2. Find the target Module nodes in the graph
        # 3. Create 'imports' edges
        
        # 4. Loop through here.raw_calls
        # 5. Find the 'owner_function' node within this module
        # 6. Find the target 'call_name' Function node (this is complex,
        #    requires resolving imports)
        # 7. Create 'calls' edge:
        #    owner_func_node ++> call_node;
        
        print(f"Linking module {here.name}...");
    }
}


# --- Agent 4: DocGenie (Documentation Synthesis) ---
walker DocGenie {
    has final_markdown: str = "";

    can generate_doc with `root entry {
        
        # 1. Project Overview (from RepoMapper's summary)
        # The Supervisor stored this on the root node
        self.final_markdown = self.final_markdown + "# Project Documentation\n\n";
        if root.readme_summary {
             self.final_markdown = self.final_markdown + "## Project Overview\n\n";
             self.final_markdown = self.final_markdown + root.readme_summary + "\n\n";
        }

        # 2. API Reference (by traversing the CCG)
        self.final_markdown = self.final_markdown + "## API Reference\n\n";
        
        # Find all Module nodes in the graph
        all_modules = [root -->* File --> Module];
        
        for mod in all_modules {
            self.final_markdown = self.final_markdown + f"### Module: `{mod.name}`\n\n";
            
            # Find functions defined IN THIS module
            mod_funcs = [mod --> Function];
            for func in mod_funcs {
                self.final_markdown = self.final_markdown + f"#### ` {func.name} `\n\n";
                self.final_markdown = self.final_markdown + f"```jac\n{func.signature}\n```\n\n";
                
                # 3. Use byLLM to synthesize prose
                prose = self.explain_function(
                    code_body=func.code_body,
                    docstr=func.docstring
                );
                self.final_markdown = self.final_markdown + prose + "\n\n";
                
                # 4. Generate a call diagram for this function
                diagram_md = self.generate_call_diagram(func);
                self.final_markdown = self.final_markdown + diagram_md + "\n\n";
            }
            #... (A similar loop for Classes)...
        }
        
        # 5. Report the final, complete markdown document
        report {"markdown": self.final_markdown};
    }

    # 3. AI Synthesis Ability (using Gemini)
    "You are a technical writer. Explain this code function to a junior
    developer. Provide a concise, one-paragraph summary based on the
    function's code body and its docstring. Focus on its purpose
    and parameters."
    can explain_function(code_body: str, docstr: str) -> str by llm();

    # 4. Diagram Generation Ability
    can generate_call_diagram(func_node: Function) -> str {
        # Query the graph for callers and callees
        callers = [func_node <-- calls];
        callees = [func_node --> calls];
        
        if not callers and not callees {
            return "";
        }

        # Build lists to pass to our Python util
        nodes = [{"id": func_node.name, "label": func_node.name}];
        edges =;
        
        for c in callers {
            nodes.append({"id": c.name, "label": c.name});
            edges.append({"from": c.name, "to": func_node.name});
        }
        for c in callees {
            nodes.append({"id": c.name, "label": c.name});
            edges.append({"from": func_node.name, "to": c.name});
        }
        
        # Call the Python util from utils.py
        mermaid_string = utils.create_mermaid_chart(nodes, edges);
        
        if mermaid_string {
            # Return a markdown-formatted Mermaid block
            return f"**Call Graph**\n\n```mermaid\n{mermaid_string}\n```\n";
        }
        return "";
    }
}


# --- Agent 1: The Supervisor (FINAL VERSION) ---
walker CodeGenius {
    has repo_url: str;
    
    can start with `root entry {
        
        # --- 1. CLONE ---
        temp_dir = utils.clone_repo(self.repo_url);
        if not temp_dir {
            report {"error": "Failed to clone repo.", "status": 500};
            disengage;
        }

        # --- 2. MAP REPO ---
        print("Cloned. Spawning RepoMapper...");
        mapper = RepoMapper(repo_path=temp_dir);
        # Spawn the agent and capture its report(s)
        mapper_report_list = spawn root spawn mapper;
        
        # Store the summary on the root node for DocGenie to find
        if mapper_report_list {
            root.readme_summary = mapper_report_list["readme_summary"];
        } else {
            root.readme_summary = "No README summary available.";
        }

        # --- 3. PLANNING (Find all code files) ---
        # This queries the graph built by RepoMapper
        # The '-->*' operator means "find all descendants"
        py_files =;
        jac_files =;
        all_code_files = py_files + jac_files;
        
        if not all_code_files {
            report {"error": "No.py or.jac files found in repo.", "status": 404};
            disengage;
        }
        print(f"Planning complete. Found {all_code_files.len} code files.");

        # --- 4. ITERATIVE ANALYSIS (Pass 1: Node Creation) ---
        print(f"Starting analysis pass 1: Creating nodes...");
        for file in all_code_files {
            # Spawn one analyzer agent for each file
            analyzer = CodeAnalyzer(file_node=file);
            spawn root spawn analyzer; # "Spawn and forget"
        }
        print("Analysis pass 1 complete.");

        # --- 4b. ITERATIVE ANALYSIS (Pass 2: Edge Linking) ---
        print(f"Starting analysis pass 2: Linking graph...");
        linker = GraphLinker();
        spawn root spawn linker; # Spawn the one linker agent
        print("Analysis pass 2 complete.");

        # --- 5. DOCUMENTATION GENERATION ---
        print("Spawning DocGenie to generate final report...");
        doc_genie = DocGenie();
        # Spawn DocGenie and capture its final report
        doc_reports = spawn root spawn doc_genie;
        
        final_markdown = doc_reports["markdown"];

        # --- 6. SAVE AND REPORT ---
        repo_name = self.repo_url.split("/")[-1];
        save_path = utils.save_markdown(
            repo_name=repo_name,
            content=final_markdown
        );
        
        print(f"Documentation saved to {save_path}");
        
        # This is the final report sent back to the API caller
        report {
            "status": "complete",
            "markdown_file": save_path,
            "markdown_content": final_markdown
        };
    }
}