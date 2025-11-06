# app.py
import streamlit as st
import requests
import json
import time

# This is the API endpoint for your 'CodeGenius' walker
# It's exposed by the 'jac serve main.jac' command
JAC_API_URL = "http://localhost:8000/walker/CodeGenius"

st.set_page_config(layout="wide")
st.title("Codebase Genius 🤖")
st.caption("An AI-powered, multi-agent system for code documentation, built with JacLang.")

repo_url = st.text_input(
    "Enter a public GitHub repository URL:",
    "https://github.com/jaseci-labs/jaclang"
)

if st.button("Generate Documentation"):
    if not repo_url:
        st.error("Please enter a URL")
    else:
        try:
            payload = {"repo_url": repo_url}
            
            with st.spinner("🚀 Spawning agents... This may take several minutes..."):
                st.write(f"1. Calling `CodeGenius` supervisor at `{JAC_API_URL}`...")
                start_time = time.time()
                
                # This single API call runs the entire agentic pipeline
                response = requests.post(JAC_API_URL, json=payload, timeout=600)
                
                end_time = time.time()
                st.write(f"✅ Pipeline complete in {end_time - start_time:.2f} seconds.")

            if response.status_code == 200:
                st.success("Documentation Generated!")
                
                response_data = response.json()
                
                # Jac server wraps reports in a list
                report = response_data.get("reports", [{}])
                
                if report.get("status") == "complete":
                    markdown_content = report.get("markdown_content", "No content.")
                    
                    st.download_button(
                        label="Download docs.md",
                        data=markdown_content,
                        file_name="docs.md",
                        mime="text/markdown"
                    )
                    
                    st.markdown("---")
                    # Display the generated docs, including Mermaid diagrams
                    st.markdown(markdown_content, unsafe_allow_html=True)
                
                else:
                    st.error(f"Agent reported an error: {report.get('error', 'Unknown')}")

            else:
                st.error(f"Error from Jac Server (Status {response.status_code}):")
                st.json(response.text)
        
        except requests.exceptions.RequestException as e:
            st.error(f"Failed to connect to Jac server. Is it running? (jac serve main.jac)")
            st.error(f"Error: {e}")