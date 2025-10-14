# DAT409 - Hybrid Search with Aurora PostgreSQL for MCP Retrieval

[![AWS](https://img.shields.io/badge/AWS-Aurora_PostgreSQL-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/rds/aurora/)
[![Python](https://img.shields.io/badge/Python-3.13-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17.5-316192?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Bedrock](https://img.shields.io/badge/Amazon_Bedrock-Cohere-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/bedrock/)
[![License](https://img.shields.io/badge/License-MIT--0-green?style=for-the-badge)](LICENSE)

> **⚠️ Important Notice**: For demonstration and educational purposes only. Not intended for production use.

## 🚀 Quick Start

**Workshop Duration**: 60 minutes | **Lab 1**: 25 min | **Lab 2**: 20 min

Build hybrid search with Aurora PostgreSQL, pgvector, and MCP for natural language database queries.

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

## 🎯 Labs

### Lab 1: Hybrid Search (25 min)
Combine vector similarity (pgvector + HNSW), full-text search, and fuzzy matching (pg_trgm) with 21,704 products.

```bash
cd /workshop/lab1-hybrid-search/notebook
# Open dat409-hybrid-search-notebook.ipynb
```

### Lab 2: MCP & RLS (20 min)
Natural language queries with Model Context Protocol and Row-Level Security for multi-tenant access.

```bash
cd /workshop/lab2-mcp-agent
./test_personas.sh  # Test customer, support, product manager personas
streamlit run streamlit_app.py  # Optional demo
```

## 🛠️ Prerequisites
- AWS Account with Aurora PostgreSQL 17.5 + Amazon Bedrock (Cohere Embed English v3)
- Python 3.13 + Jupyter Notebook

## 🚦 Getting Started

**Participants**: Access Code Editor via CloudFront URL → Open Lab 1 notebook in `/workshop/lab1-hybrid-search/notebook/`

**Instructors**: See [DEPLOYMENT_SEQUENCE.md](DEPLOYMENT_SEQUENCE.md) for setup.

## 🔧 Technical Stack
- **Database**: Aurora PostgreSQL 17.5 with pgvector extension
- **Embeddings**: Cohere Embed English v3 (1024 dimensions)
- **Search**: HNSW vector index + GIN full-text + pg_trgm fuzzy
- **MCP**: Model Context Protocol for database access
- **AI Agent**: Strands Agent with Claude Sonnet 4 + MCP tools
- **RLS**: Row-Level Security for persona-based access
- **Python**: 3.13 with pandas, psycopg, boto3, streamlit

## 🤖 MCP Agent Architecture

The workshop demonstrates natural language database queries using a **Strands Agent** with **MCP tools**:

```
User Query → Strands Agent (Claude Sonnet 4) → MCP Client → Aurora PostgreSQL (Data API)
```

**Key Components:**
- **Strands Agent**: AI agent framework with tool-calling capabilities
- **MCP Client**: Provides standardized database access tools via `awslabs.postgres-mcp-server`
- **Claude Sonnet 4**: Interprets queries and decides which MCP tools to call
- **Aurora Data API**: Serverless database access using cluster ARN + secret ARN

**Why This Pattern?**
- Agent uses admin access via Data API for intelligent cross-schema queries
- Application-level authorization handles security (typical production pattern for AI agents)
- MCP provides standardized, reusable database tools
- Enables natural language → SQL translation with context awareness

## 📚 Resources
[Aurora PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/) | [pgvector](https://github.com/pgvector/pgvector) | [MCP](https://modelcontextprotocol.io/)

## ⭐ Like This Workshop?

If you find this workshop helpful, please consider:
- ⭐ **Star this repository** to show your support!
- 🍴 **Fork it** to customize for your own use cases
- 🐛 **Report issues** to help us improve
- 💡 **Submit pull requests** with enhancements or fixes
- 📢 **Share it** with your colleagues and community

Your feedback and contributions help make this workshop better for everyone!

## 🤝 Contributing

Contributions welcome! Documentation, bug fixes, features, tests, or feedback. See [CONTRIBUTING.md](CONTRIBUTING.md).

## 📄 License & Security
MIT-0 License. See [LICENSE](LICENSE) | Security: [CONTRIBUTING.md](CONTRIBUTING.md#security-issue-notifications)

---

© 2025 Shayon Sanyal, Principal Solutions Architect, AWS
