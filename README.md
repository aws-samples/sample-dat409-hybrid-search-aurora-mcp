# DAT409 - Hybrid Search with Aurora PostgreSQL for MCP Retrieval

<div align="center">

### Platform & Infrastructure
[![AWS Aurora](https://img.shields.io/badge/Aurora_PostgreSQL-17.5-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/rds/aurora/)
[![pgvector](https://img.shields.io/badge/pgvector-0.8.0-316192?style=for-the-badge&logo=postgresql&logoColor=white)](https://github.com/pgvector/pgvector)
[![Bedrock](https://img.shields.io/badge/Amazon_Bedrock-Cohere_Embed_v3-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/bedrock/)

### Languages & Frameworks
[![Python](https://img.shields.io/badge/Python-3.13-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![MCP](https://img.shields.io/badge/MCP-Model_Context_Protocol-00ADD8?style=for-the-badge)](https://modelcontextprotocol.io/)
[![Streamlit](https://img.shields.io/badge/Streamlit-1.x-FF4B4B?style=for-the-badge&logo=streamlit&logoColor=white)](https://streamlit.io/)

[![License](https://img.shields.io/badge/License-MIT--0-green?style=for-the-badge)](LICENSE)

</div>

> 🎓 **AWS re:Invent 2025 Workshop** | For educational purposes - demonstrates production patterns

## 🚀 Overview

**Duration**: 60 minutes | **Lab 1**: 25 min | **Lab 2**: 20 min

Learn to build enterprise-grade hybrid search combining semantic similarity, lexical matching, and fuzzy search with Aurora PostgreSQL. Integrate Model Context Protocol (MCP) for natural language database queries with Row-Level Security (RLS).

**What You'll Build:**
- Multi-modal search system over 21,704 products
- AI agent with natural language database access
- Secure multi-tenant system with PostgreSQL RLS

## 📁 Repository Structure

```
├── lab1-hybrid-search/
│   ├── notebook/
│   │   └── dat409-hybrid-search-notebook.ipynb  # Lab 1: Hybrid search implementation
│   ├── data/
│   │   └── amazon-products.csv                  # 21,704 product dataset
│   └── requirements.txt
├── lab2-mcp-agent/
│   ├── streamlit_app.py                         # Lab 2: Interactive demo app
│   ├── test_personas.sh                         # RLS testing script
│   └── requirements.txt
├── scripts/
│   ├── bootstrap-code-editor.sh                 # Environment setup
│   ├── setup-database.sh                        # Database initialization
│   └── setup/                                   # Helper utilities
└── solutions/                                   # Reference implementations
```

## 🎯 Workshop Labs

### Lab 1: Hybrid Search Architecture (25 min)

**Build a multi-modal search system combining three complementary techniques:**

| Method | Technology | Use Case |
|--------|-----------|----------|
| **Semantic** | pgvector + HNSW + Cohere | Conceptual queries ("eco-friendly products") |
| **Keyword** | PostgreSQL tsvector + GIN | Exact terms ("iPhone 15 Pro") |
| **Fuzzy** | pg_trgm + GIN | Typo tolerance ("wireles hedphones") |

**What You'll Learn:**
- When to use semantic vs keyword search
- Index strategies for production workloads (HNSW vs IVFFlat)
- Result fusion with Reciprocal Rank Fusion (RRF)
- Cohere Rerank for ML-based result optimization

**Hands-On:**
```bash
cd /workshop/lab1-hybrid-search/notebook
# Open dat409-hybrid-search-notebook.ipynb
```

You'll implement fuzzy search, semantic search, and hybrid RRF queries with TODO blocks guiding you through each step.

---

### Lab 2: MCP Agent with Row-Level Security (20 min)

**Build an AI agent that queries databases using natural language:**

```
User: "Show warranty info for headphones"
  ↓
Strands Agent (Claude Sonnet 4)
  ↓
MCP Tools → SQL Query
  ↓
Aurora PostgreSQL (RLS filtered)
  ↓
Results based on user persona
```

**What You'll Learn:**
- Model Context Protocol (MCP) for standardized database access
- Application-level security with PostgreSQL RLS
- AI agent patterns for database queries
- Multi-tenant data isolation strategies

**Hands-On:**
```bash
cd /workshop/lab2-mcp-agent
./test_personas.sh           # Test RLS policies
streamlit run streamlit_app.py  # Interactive demo
```

Explore how different personas (customer, support agent, product manager) see different data through RLS policies.

---

## 🎓 Workshop Access

**For AWS re:Invent Participants:**
1. Access your Code Editor environment via the provided CloudFront URL
2. Navigate to `/workshop/lab1-hybrid-search/notebook/`
3. Open `dat409-hybrid-search-notebook.ipynb`
4. Follow the guided TODO blocks

**Environment Includes:**
- ✅ Aurora PostgreSQL 17.5 with pgvector
- ✅ 21,704 products pre-loaded with embeddings
- ✅ Python 3.13 + Jupyter + all dependencies
- ✅ Amazon Bedrock access (Cohere models)
- ✅ MCP server pre-configured

## 🛠️ Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Database** | Aurora PostgreSQL 17.5 | Vector storage with pgvector extension |
| **Vector Index** | HNSW (pgvector) | Fast ANN search with 95%+ recall |
| **Embeddings** | Cohere Embed English v3 | 1024-dimensional dense vectors |
| **Full-Text** | PostgreSQL `tsvector` + GIN | Lexical search and BM25-style ranking |
| **Fuzzy Match** | pg_trgm + GIN | Trigram similarity for typo tolerance |
| **MCP Server** | `awslabs.postgres-mcp-server` | Standardized database access tools |
| **AI Agent** | Strands Agent Framework | Tool-calling orchestration layer |
| **LLM** | Claude Sonnet 4 | Natural language → SQL translation |
| **RLS** | PostgreSQL Row-Level Security | Declarative multi-tenancy |
| **Data API** | Aurora Data API | Serverless, IAM-authenticated access |
| **Python** | 3.13 (pandas, psycopg3, boto3) | Data loading and orchestration |

## 🤖 MCP Agent Architecture

**How Natural Language Queries Work:**

```
"Show warranty info" → Strands Agent → MCP Tools → Aurora PostgreSQL → Filtered Results
                           ↓              ↓              ↓
                    Claude Sonnet 4   SQL Query    RLS Policies
```

**Key Components:**

| Component | Role | Technology |
|-----------|------|------------|
| **Strands Agent** | Orchestration & tool calling | Python framework |
| **Claude Sonnet 4** | Natural language → SQL | Amazon Bedrock |
| **MCP Client** | Standardized database tools | `awslabs.postgres-mcp-server` |
| **Aurora Data API** | Serverless database access | IAM authentication |
| **RLS Policies** | Row-level security | PostgreSQL |

**Why This Pattern?**
- ✅ **Standard Practice**: Agent uses admin access; security via application-level filtering
- ✅ **Serverless**: No VPC required with Data API
- ✅ **Portable**: MCP tools work across different AI frameworks
- ✅ **Intelligent**: Multi-step reasoning with context awareness

**Production Considerations:**
- Agent requires admin credentials (standard for AI agents)
- Data API adds ~10ms latency (acceptable for agentic workflows)
- RLS provides database-level isolation per persona

## 📚 Learn More

**Documentation:**
- [Aurora PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/) - Managed PostgreSQL service
- [pgvector](https://github.com/pgvector/pgvector) - Vector similarity search extension
- [Model Context Protocol](https://modelcontextprotocol.io/) - Standardized AI tool protocol
- [PostgreSQL RLS](https://www.postgresql.org/docs/current/ddl-rowsecurity.html) - Row-level security

**Related AWS Services:**
- [Amazon Bedrock](https://aws.amazon.com/bedrock/) - Cohere embeddings & rerank
- [RDS Data API](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/data-api.html) - Serverless database access
- [Secrets Manager](https://aws.amazon.com/secrets-manager/) - Credential management

## 🤝 Contributing

**Found this helpful?**
- ⭐ Star this repository
- 🍴 Fork for your own use cases
- 🐛 Report issues
- 💡 Submit pull requests
- 📢 Share with colleagues

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

MIT-0 License - See [LICENSE](LICENSE)

Security issues: [CONTRIBUTING.md](CONTRIBUTING.md#security-issue-notifications)

---

<div align="center">

**AWS re:Invent 2025 | DAT409 Builder's Session**

*Hybrid Search with Aurora PostgreSQL for MCP Retrieval*

© 2025 Shayon Sanyal

</div>
