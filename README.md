# Codebase Genius
Codebase Genius is an AI-powered, multi-agent system built with JacLang that automatically generates high-quality markdown documentation for any public software repository.

Given a GitHub URL, the system clones the repository, builds a complete Code Context Graph (CCG) of its files, classes, and functions, and uses AI agents to generate prose, explanations, and diagrams for the entire codebase.

This project is built as a multi-agent system following the Object-Spatial Programming (OSP) paradigm, as specified in the assignment. It features a decoupled architecture with a JacLang backend API and a Streamlit frontend.

## System Architecture
The system is composed of five distinct agents (walkers) that collaborate to perform the analysis:

CodeGenius (Supervisor): The main orchestrator. It receives the GitHub URL from the API, manages the overall workflow, and delegates tasks to subordinate agents. It is responsible for cloning the repo, spawning the RepoMapper, iteratively spawning the CodeAnalyzer, running the GraphLinker, and finally spawning the DocGenie to assemble the final report.

RepoMapper: This agent is responsible for building the physical graph of the repository. It traverses the file system, creating Directory and File nodes, while ignoring specified directories like .git. It also finds the README.md and uses a byLLM ability  to generate an initial project overview.   

CodeAnalyzer: This is the core analytical agent. It is spawned once for each .py or .jac file. It reads the file's content and parses it to build the logical Code Context Graph (CCG).   

For Python files, it uses the tree-sitter library to create a concrete syntax tree.   

For Jac files, it uses the jaclang.compiler.parser's internal API to generate a Jac AST.   

It creates Module, Class, and Function nodes and links them to the corresponding File node.

GraphLinker (Pass 2): This agent runs after all CodeAnalyzer agents are finished. Its job is to traverse the graph and create the relational edges (e.g., calls, imports, inherits) between the nodes created in Pass 1. This two-pass system is necessary to link functions defined in different files.

DocGenie: The final agent. It traverses the fully-linked CCG and generates the final docs.md file. It uses byLLM abilities  to explain the purpose of each function and class. It also generates Mermaid.js call graph diagrams  by querying the graph for calls edges.   

## Features
Git Repository Cloning: Clones any public GitHub repository into a temporary local directory.

File Tree Mapping: Builds a complete graph of all files and directories, ignoring common non-code folders.

AI-Powered Summarization: Automatically reads the README.md and uses a Gemini LLM to generate a concise project overview.

Code Context Graph (CCG): Generates a detailed graph schema with Module, Class, and Function nodes , connected by defines, calls, and imports edges.   

Dual-Language Parsing: Natively parses both Python (.py) files using tree-sitter  and Jac (.jac) files using the jaclang compiler's internal parser.   

AI-Generated Documentation: Uses byLLM abilities  to analyze code blocks and generate human-readable explanations for each function and class.   

Automated Diagram Generation: Automatically generates Mermaid.js  call graph diagrams for functions, showing what they call and what calls them.   

REST API: Exposes the entire workflow as a simple API endpoint via jac serve.   

Streamlit Frontend: Provides a simple web UI to interact with the backend API.   

## Project Structure (Deliverable 1)
agentic_codebase_genius/
├──.env             # Stores API keys (e.g., GEMINI_API_KEY)
├── main.jac         # Core Jac file: contains all agent walkers and graph schema
├── utils.py         # Python helper functions (git, tree-sitter, diagramming)
├── app.py           # Streamlit frontend application
└── requirements.txt # Python dependencies

## Setup and Run Instructions (Deliverable 2)
These instructions are self-contained and reproducible.

### 1. Initial Setup
Clone the Repository:

Bash

git clone <your-repo-url>
cd agentic_codebase_genius
Create API Key File: Create a file named .env in the root of the project directory. Your Gemini API key is required for the byLLM abilities.   

GEMINI_API_KEY="YOUR_API_KEY_HERE"
Create Virtual Environment:

Bash

python3 -m venv venv
source venv/bin/activate
Install Dependencies: Install all required Python packages from requirements.txt.

Bash

pip install -r requirements.txt
#### 2. Running the System
This application runs in a decoupled client-server model, similar to the byLLM Task Manager example. You must run two separate terminals.

Terminal 1: Run the Backend (Jac API Server)

In your first terminal, run the jac serve command to start the backend API:

Bash

#Make sure your virtual environment is active
source venv/bin/activate

#Serve the main.jac file
jac serve main.jac
You will see output indicating the Uvicorn server is running on http://0.0.0.0:8000. This terminal is now your active backend.   

Terminal 2: Run the Frontend (Streamlit UI)

In a new, separate terminal, run the streamlit command to start the frontend:

Bash

# Make sure your virtual environment is active
source venv/bin/activate

# Run the app.py script
streamlit run app.py
Streamlit will automatically open your web browser to the application's UI (usually http://localhost:8501).   

## How to Use (Deliverable 3)
Open the Streamlit application in your browser (e.g., http://localhost:8501).

Enter the URL of a public GitHub repository (e.g., https://github.com/jaseci-labs/jaclang).

Click the "Generate Documentation" button.

The Streamlit app will send a POST request to the jac serve backend at http://localhost:8000/walker/CodeGenius.   

You can observe the progress in your Terminal 1 (Backend) window as the agents log their actions (cloning, mapping, analyzing, etc.).

When complete, the final markdown documentation will be displayed on the Streamlit page. A "Download" button will also appear.

The generated documentation is also saved locally in the ./outputs/<repo_name>/docs.md directory.

## Sample Output (Deliverable 4)
Below is a sample of the documentation generated for a hypothetical repository.

### Project Documentation
### Project Overview
(AI-Generated) This repository contains a web application toolkit. The system is designed to provide backend services for user management and data processing, with a clear separation between the core API logic and utility functions. It appears to be built using Python, leveraging FastAPI for the API and various helper modules for tasks like string and data manipulation.

## API Reference
Module: main.py
create_user
Code snippet

def create_user(user: UserCreate, db: Session) -> User:
(AI-Generated) This function is responsible for creating a new user in the database. It takes a UserCreate Pydantic model and a database session, hashes the user's password, creates a new User database object, and commits the transaction. It returns the newly created user object.

Call Graph

Code snippet

graph TD;
    validate_email[validate_email] --> create_user;
    create_user --> hash_password[hash_password];
    create_user --> db_save_user[db_save_user];
    
### Design Report (Deliverable 5)
Design Decisions
Multi-Agent (OSP) Architecture: The core design uses Jac's Object-Spatial Programming (OSP) model. A supervisor (CodeGenius)  manages a team of specialized agents (RepoMapper, CodeAnalyzer, DocGenie). This follows the assignment's recommendation and creates a clear, maintainable separation of concerns.   

Decoupled Frontend/Backend: The system is split into a jac serve backend API and a Streamlit frontend. This pattern, borrowed from the byLLM Task Manager example, is robust. The frontend only needs to know the API endpoint (/walker/CodeGenius)  and the JSON contract, allowing either side to be developed independently.   

Polymorphic Parsing: To meet the requirement of parsing both Python and Jac, a polymorphic CodeAnalyzer was designed. It uses tree-sitter  for Python, which is the industry standard for robustly parsing source code. For Jac, it leverages the compiler's internal parsing API (jaclang.compiler.parser)  to generate a Jac AST, as no public tree-sitter grammar for Jac exists.   

Two-Pass Analysis: A single-pass analysis is insufficient to link function calls across different files. This design uses a two-pass system:

Pass 1 (CodeAnalyzer): Creates all Module, Class, and Function nodes.

Pass 2 (GraphLinker): Traverses the completed node graph to connect calls and imports edges.

Challenges Encountered
Jac Syntax: As Jac is a new language, finding documentation for advanced syntax (like capturing spawn reports  or complex graph queries ) was a significant challenge that required deep study of the official reference.   

Parsing Jac Code: The decision to parse Jac code itself was complex. With no official tree-sitter grammar , the only viable solution was to "hook into" the compiler's internal parser.py. This is powerful but relies on non-public APIs that could change.   

Graph Linking Logic: The most complex part of the design is the GraphLinker. Correctly resolving an import (e.g., from.utils import my_func) and linking it to the correct Function node in the graph requires building a complete import resolution system, which is a non-trivial compiler-level task.   

External Libraries Used (Submission Guideline)
jaclang: The core Jac language runtime.   

byllm: Jac plugin for AI abilities (Gemini).   

jac-cloud: Jac plugin for jac serve functionality.   

streamlit: For building the Python web frontend.   

requests: Used by the Streamlit frontend to call the Jac backend API.   

gitpython: For cloning git repositories in utils.py.

tree-sitter & tree-sitter-python: For parsing Python source code in utils.py.   

networkx & networkx-mermaid: For generating graph diagrams from the CCG in utils.py.