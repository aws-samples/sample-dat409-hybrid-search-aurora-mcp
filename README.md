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

> 🎓 **AWS re:Invent 2025 Workshop** | 400-Level Expert Session

## 🚀 Overview

**Duration**: 60 minutes | **Level**: 400 (Expert)

Build production-grade hybrid search combining pgvector semantic similarity, PostgreSQL full-text search, and trigram fuzzy matching. Implement Model Context Protocol (MCP) for context-aware retrieval with persona-based Row-Level Security—enabling AI agents to query structured data beyond traditional RAG embeddings.

**What You'll Build:**
- Weighted hybrid search with three complementary retrieval methods
- MCP-based agent with intelligent database querying
- Context-aware filtering (persona-based, time-based, operational)

## 📁 Repository Structure

```
├── notebooks/
│   ├── 01-dat409-hybrid-search-TODO.ipynb      # Hands-on lab with TODO blocks
│   └── 02-dat409-hybrid-search-SOLUTIONS.ipynb # Reference implementation
├── data/
│   └── amazon-products-sample.csv           # 21,704 product dataset
├── demo-app/
│   ├── streamlit_app.py                     # Full-stack reference application
│   ├── requirements.txt
│   └── .streamlit/config.toml
├── scripts/
│   ├── bootstrap-code-editor-unified.sh     # Environment setup
│   └── setup/test_connection.py
├── cfn/                                     # CloudFormation templates
└── requirements.txt                         # Workshop dependencies
```

## 🎯 Workshop Structure

### Hands-On Lab: Hybrid Search Implementation (40 min)

**Implement weighted hybrid search with three complementary retrieval methods:**

| Method | Technology | Use Case | MCP Context |
|--------|-----------|----------|-------------|
| **Fuzzy** | pg_trgm + GIN | Typo tolerance ("wireles hedphones") | Handles user input errors without re-prompting |
| **Semantic** | pgvector + HNSW + Cohere | Conceptual queries ("eco-friendly products") | Captures intent beyond keyword matching |
| **Hybrid RRF** | Reciprocal Rank Fusion | Multi-signal fusion | Combines retrieval signals without ML overhead |

**What You'll Implement:**
- **TODO 1**: Fuzzy search with trigram similarity
- **TODO 2**: Semantic search with pgvector and Cohere embeddings
- **TODO 3**: Hybrid RRF combining semantic + keyword + fuzzy

**Hands-On:**
```bash
cd /notebooks
# Open 01-dat409-hybrid-search-TODO.ipynb
# Complete 3 TODO blocks (6 sub-tasks total)
```

**Key Learning:**
- When to use semantic vs keyword vs fuzzy search
- Index strategies for production (HNSW vs IVFFlat)
- RRF vs weighted fusion for heterogeneous score distributions
- Cohere Rerank for ML-based result optimization

---

### Interactive Demo: MCP-Based Retrieval (20 min)

**Explore how MCP shifts from RAG to structured, queryable inputs:**

```
User Query → Strands Agent (Claude Sonnet 4) → MCP Tools → Aurora PostgreSQL
                    ↓                              ↓              ↓
            Tool Selection                    SQL Query      RLS-Filtered Results
```

**What You'll Explore:**
- **Tab 1**: MCP Context Search with persona-based RLS
- **Tab 2**: Search method comparison (side-by-side)
- **Tab 3**: Advanced analysis (optional)
- **Tab 4**: Key takeaways and production decisions

**Hands-On:**
```bash
cd /demo-app
streamlit run streamlit_app.py
```

**Key Learning:**
- MCP enables dynamic retrieval strategy selection
- Application-level RLS for multi-tenant AI agents
- Cohere Rerank vs RRF (ML vs mathematical)
- Production deployment patterns

---

## 🎓 Getting Started

**For AWS re:Invent Participants:**
1. Access Code Editor via provided CloudFront URL
2. Navigate to `/notebooks/`
3. Open `01-dat409-hybrid-search-TODO.ipynb`
4. Complete 3 TODO blocks (guided with hints)
5. Launch demo app: `streamlit run demo-app/streamlit_app.py`

**Pre-Configured Environment:**
- ✅ Aurora PostgreSQL 17.5 with pgvector 0.8.0
- ✅ 21,704 products with pre-generated Cohere embeddings
- ✅ Python 3.13 + Jupyter + all dependencies
- ✅ Amazon Bedrock access (Cohere Embed v3, Rerank v3.5)
- ✅ MCP server (awslabs.postgres-mcp-server)
- ✅ Strands Agent Framework + Claude Sonnet 4

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

## 🤖 Why MCP Matters: Beyond RAG

**MCP shifts from relevance-based retrieval (RAG) to structured, queryable, context-rich inputs.**

### Traditional RAG Limitations
- ❌ Fixed retrieval patterns (always embedding-based)
- ❌ No query-time filtering (time, persona, operational context)
- ❌ Static embeddings only
- ❌ Limited multi-step reasoning

### MCP Advantages
- ✅ Dynamic tool selection (vector, keyword, SQL filters)
- ✅ Context-aware filtering (persona-based, time-based)
- ✅ Hybrid retrieval strategies
- ✅ Direct structured data access

### Architecture

```
User Query → Strands Agent (Claude Sonnet 4) → MCP Tools → Aurora PostgreSQL
                    ↓                              ↓              ↓
            Analyzes Intent                   SQL Query      RLS-Filtered Results
            Selects Tools                     run_query      WHERE persona = ANY(access)
            Synthesizes Response              get_schema     Returns authorized data
```

**Key Components:**

| Component | Role | Technology |
|-----------|------|------------|
| **Strands Agent** | Orchestration & tool calling | Python framework |
| **Claude Sonnet 4** | Natural language → SQL | Amazon Bedrock |
| **MCP Client** | Standardized database tools | `awslabs.postgres-mcp-server` |
| **Aurora Data API** | Serverless database access | IAM authentication |
| **RLS (Application-Level)** | Security via system prompt | PostgreSQL + Agent logic |

**Production Pattern:**
- Agent uses admin credentials (standard for AI agents)
- Security enforced via system prompt filtering
- Data API enables serverless access (no VPC)
- ~10ms latency acceptable for agentic workflows

## 🎯 Key Takeaways

### When to Use Each Search Method

| Method | Best For | Avoid When |
|--------|----------|------------|
| **Semantic** | Conceptual queries, cross-language, intent-based | Exact SKU lookup, low-latency (<10ms) |
| **Keyword** | Exact terms, Boolean queries, structured fields | Typos common, multi-language content |
| **Fuzzy** | Typo tolerance, auto-complete, unreliable input | Precision critical, large result sets |
| **Hybrid** | Production systems, mixed queries | Single-method suffices |

### Production Decisions

**HNSW vs IVFFlat:**
- **HNSW**: User-facing search, >100K vectors, read-heavy (10-50ms queries)
- **IVFFlat**: Rapid prototyping, frequent updates, write-heavy (50-200ms queries)

**Cohere Rerank vs RRF:**
- **Cohere Rerank**: User-facing search, accuracy critical (~50-200ms latency, cost per request)
- **RRF**: Internal tools, cost-sensitive, low-latency (in-database, zero cost)

### MCP for AI Agents

**Key Insight:** MCP enables agents to dynamically select retrieval strategies (vector, keyword, SQL filters) based on query intent—enabling time-based, persona-based, and operational context filtering impossible with static embeddings alone.

---

## 📚 Resources

**Core Technologies:**
- [pgvector](https://github.com/pgvector/pgvector) - Vector similarity search
- [Model Context Protocol](https://modelcontextprotocol.io/) - Standardized AI tool protocol
- [Aurora PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/) - Managed database
- [PostgreSQL RLS](https://www.postgresql.org/docs/current/ddl-rowsecurity.html) - Row-level security

**AWS Services:**
- [Amazon Bedrock](https://aws.amazon.com/bedrock/) - Cohere Embed v3, Rerank v3.5
- [RDS Data API](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/data-api.html) - Serverless access
- [Strands Agent Framework](https://strandsagents.com/) - MCP-compatible agents

## 🚀 Extend This Workshop

**Next Steps:**
1. Add time-based filtering (`WHERE created_at > NOW() - INTERVAL '7 days'`)
2. Implement query caching with Redis/ElastiCache
3. Add A/B testing for reranking strategies
4. Build custom MCP tools for your domain
5. Integrate with Amazon Kendra for document search

**Production Checklist:**
- [ ] HNSW indexes on all vector columns
- [ ] GIN indexes on tsvector and trigram columns
- [ ] Connection pooling (PgBouncer/RDS Proxy)
- [ ] Query result caching
- [ ] RLS policies for all tables
- [ ] IAM authentication for Data API
- [ ] Audit logging enabled

---

## 🤝 Contributing

⭐ Star this repository | 🍴 Fork for your use cases | 🐛 Report issues | 💡 Submit PRs

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

MIT-0 License - See [LICENSE](LICENSE)

---

<div align="center">

**AWS re:Invent 2025 | DAT409 - 400 Level Expert Session**

*Hybrid Search with Aurora PostgreSQL for MCP Retrieval*

© 2025 Shayon Sanyal

</div>
