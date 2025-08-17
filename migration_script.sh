#!/bin/bash

# DAT409 Workshop Repository Migration Script
# Run this from the root of your repository

echo "🚀 Starting DAT409 Workshop Structure Migration"
echo "=============================================="

# Step 1: Create new directory structure
echo "📁 Step 1: Creating new directory structure..."

mkdir -p lab1-hybrid-search/{notebook,data,solutions}
mkdir -p lab2-mcp-agent/{setup,agent,dashboard,examples}
mkdir -p scripts/{setup,data-generation,cleanup}

echo "✅ Directory structure created"

# Step 2: Move Lab 1 files
echo "📦 Step 2: Moving Lab 1 files..."

# Move notebook
if [ -f "notebooks/dat409_notebook.ipynb" ]; then
    cp notebooks/dat409_notebook.ipynb lab1-hybrid-search/notebook/
    echo "  ✓ Moved main notebook"
fi

# Move requirements for Lab 1
if [ -f "notebooks/requirements.txt" ]; then
    cp notebooks/requirements.txt lab1-hybrid-search/notebook/
    echo "  ✓ Moved Lab 1 requirements"
fi

# Move data files
if [ -f "data/incident_logs.json" ]; then
    cp data/incident_logs.json lab1-hybrid-search/data/
    echo "  ✓ Moved incident logs data"
fi

# Move solutions if they exist
if [ -d "solutions" ]; then
    cp -r solutions/* lab1-hybrid-search/solutions/ 2>/dev/null || true
    echo "  ✓ Moved solutions"
fi

echo "✅ Lab 1 files moved"

# Step 3: Create Lab 2 files
echo "📝 Step 3: Creating Lab 2 files..."

# Create Lab 2 setup script
cat > lab2-mcp-agent/setup/lab2_setup_mcp_agent.py << 'EOF'
#!/usr/bin/env python3
"""
DAT409 Workshop - Lab 2: Aurora PostgreSQL MCP Server Setup
"""

import os
import json
import subprocess
import sys
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
load_dotenv('/workshop/.env')

def main():
    print("🚀 Setting up Aurora PostgreSQL as MCP Server")
    print("=" * 60)
    
    # Install dependencies
    print("📦 Installing MCP and Strands dependencies...")
    packages = ["uv", "strands", "mcp", "streamlit"]
    for package in packages:
        subprocess.run([sys.executable, "-m", "pip", "install", package], 
                      capture_output=True, text=True)
    
    print("✅ Lab 2 setup complete!")
    print("\nNext: Run 'python3 ../agent/strands_agent.py'")

if __name__ == "__main__":
    main()
EOF

echo "  ✓ Created Lab 2 setup script"

# Create placeholder for Strands agent
cat > lab2-mcp-agent/agent/strands_agent.py << 'EOF'
#!/usr/bin/env python3
"""
DAT409 Workshop - Lab 2: Strands Agent for Black Friday Preparedness
"""

print("🤖 Strands Agent - Implementation in workshop")
EOF

echo "  ✓ Created Strands agent placeholder"

# Move/rename streamlit app if it exists
if [ -f "code/streamlit_app.py" ]; then
    cp code/streamlit_app.py lab2-mcp-agent/dashboard/dashboard.py
    echo "  ✓ Moved Streamlit dashboard"
fi

echo "✅ Lab 2 files created"

# Step 4: Organize scripts
echo "🔧 Step 4: Organizing scripts..."

# Move database setup script
if [ -f "scripts/setup_database.sql" ]; then
    cp scripts/setup_database.sql scripts/setup/
    echo "  ✓ Moved database setup script"
fi

# Move data generator
if [ -f "scripts/incident_logs_generator.py" ]; then
    cp scripts/incident_logs_generator.py scripts/data-generation/
    echo "  ✓ Moved data generator"
fi

echo "✅ Scripts organized"

# Step 5: Create README files
echo "📄 Step 5: Creating README files..."

# Create main README
cat > README.md << 'EOF'
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
Built with ❤️ by AWS Database Specialists for re:Invent 2025
EOF

echo "  ✓ Created main README"

# Create Lab 1 README
cat > lab1-hybrid-search/README.md << 'EOF'
# Lab 1: Hybrid Search Fundamentals

## 🎯 Objective
Build a production-ready hybrid search system that combines:
- **Semantic search** with pgvector (1024-dimensional embeddings)
- **Lexical search** with pg_trgm (handles typos and exact matches)
- **ML reranking** with Cohere models via Amazon Bedrock

## ⏱️ Duration: 25 minutes

## 🚀 Getting Started

1. **Open the notebook**:
   ```bash
   cd notebook
   jupyter lab dat409_notebook.ipynb
   ```

2. **Run through the modules**:
   - Module 1-2: Setup and data loading
   - Module 3-7: Build search components
   - Module 8-10: Implement hybrid search
   - Module 11: Interactive widget

## 📊 What You'll Build
- Process 1,500 incident logs from 365 days
- Create embeddings with Cohere Embed v3
- Implement trigram and semantic search
- Combine with reciprocal rank fusion
- Test with interactive search widget

## 🎓 Key Takeaways
- Understand when to use semantic vs lexical search
- Learn to handle typos AND exact matches
- Implement production optimization techniques
- Apply to real Black Friday scenarios
EOF

echo "  ✓ Created Lab 1 README"

# Create Lab 2 README
cat > lab2-mcp-agent/README.md << 'EOF'
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
EOF

echo "  ✓ Created Lab 2 README"

echo "✅ README files created"

# Step 6: Create environment template
echo "🔐 Step 6: Creating environment template..."

if [ -f "notebooks/.env" ]; then
    # Copy and sanitize .env file
    cp notebooks/.env env_example
    # Remove actual passwords/secrets
    sed -i.bak 's/DB_PASSWORD=.*/DB_PASSWORD=your_password_here/g' env_example
    rm env_example.bak 2>/dev/null || true
    echo "✅ Created env_example from existing .env"
else
    # Create new template
    cat > env_example << 'EOF'
# Database Configuration
DB_HOST=your_aurora_endpoint_here
DB_PORT=5432
DB_NAME=workshop_db
DB_USER=workshop_admin
DB_PASSWORD=your_password_here
DATABASE_URL=postgresql://workshop_admin:your_password_here@your_aurora_endpoint:5432/workshop_db

# AWS Configuration
AWS_REGION=us-west-2
AWS_ACCOUNT_ID=your_account_id

# Workshop Configuration
WORKSHOP_NAME=dat409-hybrid-search
WORKSHOP_TYPE=DAT409
DATABASE_SECRET_ARN=arn:aws:secretsmanager:region:account:secret:name
EOF
    echo "✅ Created env_example template"
fi

# Step 7: Create .gitignore if it doesn't exist
echo "📝 Step 7: Updating .gitignore..."

if [ ! -f ".gitignore" ]; then
    cat > .gitignore << 'EOF'
# Environment files
.env
*.env
!env_example

# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
venv/
ENV/

# Jupyter
.ipynb_checkpoints
*.ipynb_checkpoints

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Workshop specific
*.log
*.pid
workshop_output/
EOF
    echo "✅ Created .gitignore"
else
    echo "✅ .gitignore already exists"
fi

# Step 8: Clean up old structure (optional - commented out for safety)
echo ""
echo "🔍 Step 8: Review migration"
echo "The new structure has been created alongside the old one."
echo "Old directories are preserved for safety."
echo ""
echo "To remove old directories after verification, run:"
echo "  rm -rf notebooks data code solutions"
echo ""

# Step 9: Summary
echo "✨ Migration Complete!"
echo "====================="
echo ""
echo "New Structure:"
echo "  ├── lab1-hybrid-search/    # Lab 1 materials"
echo "  ├── lab2-mcp-agent/        # Lab 2 materials"
echo "  ├── scripts/               # Organized scripts"
echo "  ├── env_example            # Environment template"
echo "  └── README.md              # Updated documentation"
echo ""
echo "Next Steps:"
echo "1. Review the new structure"
echo "2. Test that notebooks and scripts work with new paths"
echo "3. Update any hardcoded paths in notebooks/scripts"
echo "4. Commit changes to git"
echo "5. Remove old directories when ready"
echo ""
echo "🎉 Ready for workshop!"
EOF

chmod +x migrate_workshop_structure.sh
echo "  ✓ Migration script created and made executable"