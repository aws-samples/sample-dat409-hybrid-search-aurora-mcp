# DAT409 - Hybrid Search with Aurora PostgreSQL for MCP Retrieval

## 🚀 Quick Start

### Workshop Structure (60 minutes)
- **Presentation** (10 min): Introduction to hybrid search and MCP
- **Lab 1** (25 min): Build hybrid search with pgvector + pg_trgm
- **Lab 2** (20 min): Natural language queries with MCP & Strands
- **Q&A** (5 min): Wrap-up and questions

## 📁 Repository Structure

```
├── lab1-hybrid-search/     # Fundamentals of hybrid search
├── lab2-mcp-agent/         # AI agent integration with MCP
├── scripts/                # Utility and setup scripts
├── env_example             # Environment variable template
└── README.md              # This file
```

## 🎯 Learning Path

### Lab 1: Hybrid Search Fundamentals
Build a production-ready search system combining semantic and lexical search.
```bash
cd lab1-hybrid-search/notebook
# Open dat409_notebook.ipynb in Jupyter
```

### Lab 2: MCP & Strands Agent
Query your database using natural language.
```bash
cd lab2-mcp-agent
python3 setup/lab2_setup_mcp_agent.py
python3 agent/strands_agent.py
```

## 🛠️ Prerequisites
- AWS Account with Aurora PostgreSQL
- Python 3.12
- Jupyter Notebook
- 60 minutes of hands-on time

## 📝 Workshop Scenario
**The Black Friday Playbook**: Transform engineering observations into actionable intelligence for peak events.

---
Built with ❤️ by AWS Database Specialists
