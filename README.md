# DAT409 - Hybrid Search with Aurora PostgreSQL for MCP Retrieval

[![AWS](https://img.shields.io/badge/AWS-Aurora_PostgreSQL-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/rds/aurora/)
[![Python](https://img.shields.io/badge/Python-3.13-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17.5-316192?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Bedrock](https://img.shields.io/badge/Amazon_Bedrock-Cohere-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/bedrock/)
[![License](https://img.shields.io/badge/License-MIT--0-green?style=for-the-badge)](LICENSE)

> **⚠️ Important Notice**: The examples in this repository are for demonstration and educational purposes only. They demonstrate concepts and techniques but are not intended for direct use in production. Always apply proper security and testing procedures before using in production environments.

## 🚀 Quick Start

### Workshop Structure (60 minutes)
- **Presentation** (10 min): Introduction to hybrid search and MCP
- **Lab 1** (25 min): Build hybrid search with pgvector + pg_trgm
- **Lab 2** (20 min): Natural language queries with MCP & Strands
- **Q&A** (5 min): Wrap-up and questions

## 📁 Repository Structure

```
├── lab1-hybrid-search/
│   ├── notebook/
│   │   └── dat409-hybrid-search-notebook.ipynb  # Main lab notebook
│   ├── data/
│   │   └── amazon-products.csv                  # 21,704 products
│   └── requirements.txt                         # Lab 1 dependencies
├── lab2-mcp-agent/
│   ├── streamlit_app.py                         # Streamlit demo app
│   ├── test_personas.sh                         # RLS testing script
│   ├── mcp_config.json                          # MCP configuration
│   └── requirements.txt                         # Lab 2 dependencies
├── scripts/
│   ├── bootstrap-code-editor.sh                 # Infrastructure setup
│   ├── setup-database.sh                        # Database & data loading
│   └── setup/                                   # Helper scripts
├── cfn/                                         # CloudFormation templates
├── env_example                                  # Environment template
└── README.md                                    # This file
```

## 🎯 Learning Path

### Lab 1: Hybrid Search Fundamentals (25 minutes)
Build a production-ready search system combining semantic and lexical search with Aurora PostgreSQL and pgvector.

**What you'll learn:**
- Vector similarity search with pgvector and HNSW indexes
- Full-text search with PostgreSQL's built-in capabilities
- Fuzzy matching with pg_trgm for typo tolerance
- Combining multiple search techniques for optimal results
- Working with 21,704 products and Cohere embeddings

**How to access:**
```bash
# Open Jupyter notebook in Code Editor
cd /workshop/lab1-hybrid-search/notebook
# Open dat409-hybrid-search-notebook.ipynb
```

### Lab 2: MCP & Natural Language Queries (20 minutes)
Query your database using natural language with Model Context Protocol (MCP) and Row-Level Security (RLS).

**What you'll learn:**
- Model Context Protocol (MCP) for database access
- Row-Level Security (RLS) for persona-based data access
- Natural language to SQL with AI agents
- Secure multi-tenant data access patterns
- Testing different user personas (customer, support, product manager)

**How to access:**
```bash
# Test RLS personas
cd /workshop/lab2-mcp-agent
./test_personas.sh

# Run Streamlit app (optional)
streamlit run streamlit_app.py
```

## 🛠️ Prerequisites
- AWS Account with Aurora PostgreSQL 17.5
- Amazon Bedrock access (Cohere Embed English v3)
- Python 3.13
- Jupyter Notebook
- 60 minutes of hands-on time

## 📝 Workshop Scenario
**The Black Friday Playbook**: Transform engineering observations into actionable intelligence for peak events.

You'll work with a realistic e-commerce dataset of 21,704 products, implementing:
- **Semantic search** for understanding user intent
- **Lexical search** for exact keyword matching
- **Fuzzy matching** for handling typos and variations
- **Row-Level Security** for multi-tenant data access
- **Natural language queries** with MCP and AI agents

## 🚦 Getting Started

### For Workshop Participants
1. Access your Code Editor via the CloudFront URL provided
2. All dependencies are pre-installed
3. Database is pre-loaded with 21,704 products
4. Start with Lab 1 notebook in `/workshop/lab1-hybrid-search/notebook/`

### For Instructors
See [DEPLOYMENT_SEQUENCE.md](DEPLOYMENT_SEQUENCE.md) for complete setup instructions.

## 🔧 Technical Stack
- **Database**: Aurora PostgreSQL 17.5 with pgvector extension
- **Embeddings**: Cohere Embed English v3 (1024 dimensions)
- **Search**: HNSW vector index + GIN full-text + pg_trgm fuzzy
- **MCP**: Model Context Protocol for database access
- **RLS**: Row-Level Security for persona-based access
- **Python**: 3.13 with pandas, psycopg, boto3, streamlit

## 📚 Additional Resources
- [DEPLOYMENT_SEQUENCE.md](DEPLOYMENT_SEQUENCE.md) - Complete deployment guide
- [WORKSHOP_STUDIO_READY.txt](WORKSHOP_STUDIO_READY.txt) - Verification checklist
- [Aurora PostgreSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/)
- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [Model Context Protocol](https://modelcontextprotocol.io/)

## 🤝 Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License
This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.

## ⚠️ Security
See [CONTRIBUTING.md](CONTRIBUTING.md#security-issue-notifications) for security issue notifications.

---

© 2025 Shayon Sanyal, Principal Solutions Architect, AWS
