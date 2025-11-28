#!/bin/bash
clear

cat << 'EOF'

═══════════════════════════════════════════════════════════════════
  DAT409 - Hybrid Search with Aurora PostgreSQL for MCP Retrieval
═══════════════════════════════════════════════════════════════════

🚀 Quick Start:
   1. Open Jupyter notebook:
      notebooks/01-dat409-hybrid-search-TODO.ipynb
   
   2. Follow TODO blocks to build hybrid search (40 min)
   
   3. Explore the full-stack demo app:
      streamlit run demo-app/streamlit_app.py

🔧 Available Commands:
   workshop  - Navigate to /workshop
   demo      - Navigate to demo-app
   psql      - Connect to PostgreSQL database

📁 Workshop Structure:
   /workshop/notebooks/ - Hands-on lab with TODO blocks
   /workshop/demo-app/  - Full-stack reference application
   /workshop/data/      - Product dataset

═══════════════════════════════════════════════════════════════════

EOF

# Open TODO notebook
code /workshop/notebooks/01-dat409-hybrid-search-TODO.ipynb

exec bash
