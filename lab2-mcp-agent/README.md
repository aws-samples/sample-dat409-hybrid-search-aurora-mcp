# Lab 2: MCP Server & Strands Agent

## 🎯 Objective
Transform Aurora PostgreSQL into an MCP server and interact using natural language.

## ⏱️ Duration: 20 minutes

## 🚀 Getting Started

### Step 1: Setup (2 min)
```bash
cd setup
python3 lab2_setup_mcp_agent.py
```

### Step 2: Run Agent (15 min)
```bash
cd ../agent
python3 strands_agent.py
```

### Step 3: Optional Dashboard (3 min)
```bash
cd ../dashboard
streamlit run dashboard.py --server.port 8501
```

## 💬 Sample Queries
- "What were the top 3 critical incidents from last Black Friday?"
- "Show me connection pool exhaustion patterns from November"
- "Generate a preparedness checklist for database team"
- "What resources should we scale for this Black Friday?"

## 🏗️ Architecture
```
Natural Language → Strands Agent → MCP Client → Aurora PostgreSQL
```

## 🎓 Key Takeaways
- Use MCP to expose databases to AI
- Convert natural language to SQL automatically
- Build actionable insights from historical data
