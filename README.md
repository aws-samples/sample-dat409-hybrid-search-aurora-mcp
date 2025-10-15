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

> ⚠️ **WARNING**: For demonstration and educational purposes only. Not intended for production use.

## 🚀 Quick Start

**Workshop Duration**: 60 minutes | **Lab 1**: 25 min | **Lab 2**: 20 min

Build enterprise-grade hybrid search combining semantic similarity, lexical matching, and fuzzy search with Aurora PostgreSQL. Integrate Model Context Protocol (MCP) for natural language database queries with enterprise-grade Row-Level Security (RLS).

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

### Lab 1: Foundational Hybrid Search Architecture (25 min)

Build a multi-modal retrieval system combining three complementary search techniques over 21,704 products:

**Technical Implementation:**
- **Vector Similarity**: pgvector with HNSW index (M=16, ef_construction=64) for 1024-dim Cohere embeddings
- **Full-Text Search**: PostgreSQL native `tsvector` with GIN index for lexical matching and ranking
- **Fuzzy Matching**: pg_trgm trigram similarity with GIN index for typo tolerance and partial matches

**Key Concepts:**
- Parallel embedding generation (10 workers) with `pandarallel` for batch processing
- Cohere Rerank for combining heterogeneous ranking signals from multiple search methods into a unified relevance score
- Index tuning: HNSW vs IVFFlat trade-offs, GIN vs GiST for text search
- Distance metrics: cosine distance (`<=>`) 

```bash
cd /workshop/lab1-hybrid-search/notebook
# Open dat409-hybrid-search-notebook.ipynb
```

**Learning Outcomes:**
- Understand when semantic vs keyword search excels (conceptual vs exact match)
- Implement enterprise-grade index strategies for large scale vector workloads
- Optimize query latency through index parameter tuning and result fusion

---

### Lab 2: MCP Agent with Multi-Tenant RLS (20 min)

Implement natural language database queries using Model Context Protocol with PostgreSQL Row-Level Security for persona-based access control.

**Architecture Pattern:**
```
User Query → Strands Agent (Claude Sonnet 4) → MCP Client → Aurora Data API → PostgreSQL
```

**Technical Implementation:**
- **MCP Integration**: `awslabs.postgres-mcp-server` providing standardized database tools via Data API
- **RLS Policies**: Declarative row filtering based on `persona_access[]` array columns
- **Agent Framework**: Strands Agent with tool-calling for intelligent cross-schema queries
- **Serverless Access**: Aurora Data API using cluster ARN + Secrets Manager for credential management

**Key Concepts:**
- **Application-Level Authorization**: Agent uses admin access; security enforced via RLS (standard AI agent pattern)
- **RLS Policy Design**: `customer_role` sees public content, `support_agent_role` sees public+internal, `product_manager_role` sees all
- **MCP Tool Calling**: Claude translates natural language → appropriate MCP tool → SQL execution
- **Context-Aware Retrieval**: `get_mcp_context()` function combines semantic search + RLS filtering

```bash
cd /workshop/lab2-mcp-agent
./test_personas.sh  # Test customer, support, product manager personas
streamlit run streamlit_app.py  # Optional demo UI
```

**Learning Outcomes:**
- Design secure multi-tenant systems with PostgreSQL RLS
- Implement AI agents with MCP for standardized database access
- Understand admin-access-with-RLS pattern for agentic applications
- Build natural language interfaces over structured data

---

## Prerequisites

- AWS Account with:
  - Aurora PostgreSQL 17.5 (Serverless v2 or Provisioned)
  - Amazon Bedrock access (Cohere Embed English v3)
  - IAM permissions for RDS Data API and Secrets Manager
- Python 3.13 + Jupyter Notebook
- Basic understanding of vector databases and semantic search

## Getting Started

**Participants**: Access Code Editor via CloudFront URL → Open Lab 1 notebook in `/workshop/lab1-hybrid-search/notebook/`

## Technology Stack

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

## MCP Agent Architecture

The workshop demonstrates natural language database queries using a **Strands Agent** with **MCP tools**:

```
User Query → Strands Agent (Claude Sonnet 4) → MCP Client → Aurora PostgreSQL (Data API)
              ↓                                ↓                ↓
        Tool Selection                  MCP Protocol       RLS-Filtered Results
```

**Key Components:**
- **Strands Agent**: AI agent framework with tool-calling capabilities and memory management
- **MCP Client**: Provides standardized database access tools via `awslabs.postgres-mcp-server`
- **Claude Sonnet 4**: Interprets queries, decides which MCP tools to call, and synthesizes results
- **Aurora Data API**: Serverless database access using cluster ARN + secret ARN (no VPC required)

**Why This Pattern?**
- **Standard Practice**: Agent uses admin access via Data API for intelligent cross-schema queries
- **Security**: Application-level authorization handles access control (typical production pattern for AI agents)
- **Portability**: MCP provides standardized, reusable database tools across different agents/frameworks
- **Intelligence**: Enables natural language â†' SQL translation with context awareness and multi-step reasoning

**Trade-offs:**
- RLS provides database-level isolation but agent still requires admin credentials
- Data API adds ~10ms latency vs direct connection, acceptable for agentic workflows
- MCP abstraction enables tool reuse but reduces fine-grained query control

## 📚 Resources

- [Aurora PostgreSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/)
- [pgvector Documentation](https://github.com/pgvector/pgvector) - Vector similarity search
- [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) - Standardized context exchange
- [PostgreSQL RLS](https://www.postgresql.org/docs/current/ddl-rowsecurity.html) - Row-Level Security

## ⭐ Like This Workshop?

If you find this workshop helpful, please consider:
- **Star this repository** to show your support!
- **Fork it** to customize for your own use cases
- **Report issues** to help us improve
- **Submit pull requests** with enhancements or fixes
- **Share it** with your colleagues and community

Your feedback and contributions help make this workshop better for everyone!

## Contributing

Contributions welcome! Documentation, bug fixes, features, tests, or feedback. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License & Security

MIT-0 License. See [LICENSE](LICENSE) | Security: [CONTRIBUTING.md](CONTRIBUTING.md#security-issue-notifications)

---

**© 2025 Shayon Sanyal | AWS re:Invent 2025 | DAT409 Builder's Session**
