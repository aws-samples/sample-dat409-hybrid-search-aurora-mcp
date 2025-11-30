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

> ⚠️ **Educational Workshop**: This repository contains demonstration code for AWS re:Invent 2025. Not intended for production deployment without proper security hardening and testing.

## 🚀 Overview

**Duration**: 60 minutes | **Level**: 400 (Expert)

Build production-grade hybrid search combining semantic vectors, full-text search, and fuzzy matching. Implement Model Context Protocol (MCP) for context-aware retrieval with persona-based security—enabling AI agents to query structured data beyond traditional RAG.

**What You'll Build:**
- Hybrid search with fuzzy, semantic, and RRF methods
- MCP-based agent with intelligent database querying
- Context-aware filtering with Row-Level Security

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

**Complete 3 search methods (6 TODO sections total):**

| Method | Technology | Use Case |
|--------|-----------|----------|
| **Fuzzy** | pg_trgm + GIN | Typo tolerance ("wireles hedphones") |
| **Semantic** | pgvector + HNSW + Cohere | Conceptual queries ("eco-friendly products") |
| **Hybrid RRF** | Reciprocal Rank Fusion | Multi-signal fusion without ML overhead |

<div align="center">

![Hybrid Search Architecture](demo-app/architecture/hybrid_search.png)

</div>

**Hands-On:**
```bash
cd /notebooks
# Open 01-dat409-hybrid-search-TODO.ipynb
```

**Key Learning:**
- When to use each search method
- HNSW vs IVFFlat index strategies
- RRF vs weighted fusion
- Cohere Rerank for ML-based optimization

---

### Interactive Demo: MCP-Based Retrieval (10 min)

**Explore MCP-enabled context-aware search:**

```
User Query → Claude Sonnet 4 → MCP Tools → Aurora PostgreSQL
                ↓                  ↓              ↓
         Tool Selection        SQL Query    RLS-Filtered Results
```

**Hands-On:**
```bash
cd /demo-app
streamlit run streamlit_app.py
```

**Key Learning:**
- Dynamic retrieval strategy selection
- Persona-based RLS for multi-tenant agents
- Cohere Rerank vs RRF comparison
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

## 💰 Cost Considerations

**Bedrock Pricing (us-west-2):**
- **Cohere Embed v3**: $0.0001 per 1K tokens
  - Workshop dataset: ~$2.17 for 21,704 products (one-time)
  - Production: Pre-generate embeddings to avoid repeated costs
- **Cohere Rerank v3.5**: $0.002 per search
  - ~$2 per 1,000 searches
  - Use for user-facing search where accuracy is critical

**Cost Optimization Strategies:**
- ✅ **Pre-generate embeddings**: One-time cost vs per-query cost
- ✅ **Cache rerank results**: Redis with 1-hour TTL (reduces 80%+ of rerank calls)
- ✅ **Use RRF for internal tools**: Zero cost, in-database fusion
- ✅ **Batch embedding generation**: Process in batches of 96 texts (Cohere limit)

**When to Use What:**
- **Cohere Rerank**: Customer-facing search, high-value queries (~$0.002/search)
- **RRF**: Internal tools, high-volume, cost-sensitive (~$0/search)
- **Hybrid without rerank**: Balance of accuracy and cost

---

## 🛠️ AWS Services

| Service | Purpose |
|---------|----------|
| **Amazon Aurora PostgreSQL** | Vector storage with pgvector 0.8.0 extension |
| **Amazon Bedrock** | Cohere Embed v3 (embeddings), Rerank v3.5 (ML reranking) |
| **RDS Data API** | Serverless, IAM-authenticated database access |
| **Claude Sonnet 4** | Natural language → SQL translation via Bedrock |

## 🤖 Why MCP Matters: Beyond RAG

**MCP shifts from relevance-based retrieval (RAG) to structured, queryable, context-rich inputs.**

### Traditional RAG vs MCP

| RAG | MCP |
|-----|-----|
| ❌ Fixed retrieval patterns | ✅ Dynamic tool selection |
| ❌ No query-time filtering | ✅ Context-aware filtering |
| ❌ Static embeddings only | ✅ Hybrid retrieval strategies |
| ❌ Limited multi-step reasoning | ✅ Direct structured data access |

### Architecture

```
User Query → Claude Sonnet 4 → MCP Tools → Aurora PostgreSQL
                ↓                  ↓              ↓
         Analyzes Intent      SQL Query    RLS-Filtered Results
         Selects Tools        run_query    WHERE persona = ANY(access)
```

**Key Components:**
- **Strands Agent**: Orchestration & tool calling
- **Claude Sonnet 4**: Natural language → SQL translation
- **MCP Client**: Standardized database tools (`awslabs.postgres-mcp-server`)
- **Aurora Data API**: Serverless, IAM-authenticated access
- **RLS**: Application-level security via system prompt

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

### Key Insight

MCP enables agents to dynamically select retrieval strategies (vector, keyword, SQL filters) based on query intent—enabling time-based, persona-based, and operational context filtering impossible with static embeddings alone.

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

## 🚀 Next Steps

**Extend This Workshop:**
1. Add time-based filtering (`WHERE created_at > NOW() - INTERVAL '7 days'`)
2. Implement query caching (Redis/ElastiCache)
3. Build custom MCP tools for your domain

**Production Checklist:**
- [ ] HNSW indexes on vector columns
- [ ] GIN indexes on tsvector/trigram columns
- [ ] Connection pooling (PgBouncer/RDS Proxy)
- [ ] RLS policies and IAM authentication
- [ ] Audit logging enabled
- [ ] Monitoring and observability (see below)

**Monitoring & Observability:**

For production deployments, monitor search performance and database health:
- **[Database Insights](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_DatabaseInsights.html)**: Track query latency, top SQL statements, and database load in real-time
- **CloudWatch Metrics**: Monitor custom metrics for search method usage (semantic vs keyword vs fuzzy) and result quality
- **Application Logging**: Log search queries, response times, and result counts for analysis and optimization

> 💡 **Note:** Advanced vector optimization techniques (Binary Quantization, Scalar Quantization) are covered in the companion session **DAT406 - Build Agentic AI powered search with Amazon Aurora and Amazon RDS**

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
