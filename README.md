# DAT409 | Implement hybrid search with Aurora PostgreSQL for MCP retrieval

🚀 **AWS re:Invent 2025 Builder's Session**

Build a production-ready hybrid search system that combines PostgreSQL trigram search, pgvector semantic search, and Cohere reranking to enable Model Context Protocol (MCP) style retrieval patterns.

**GitHub Repository**: https://github.com/aws-samples/sample-dat409-hybrid-search-workshop

## 🎯 The Black Friday Playbook

Transform a year of engineering observations into actionable intelligence for peak events. Learn how different engineering teams (DBAs, SREs, Developers, Data Engineers) describe the same incidents differently, and build a search system that connects these perspectives.

## 📚 What You'll Learn

- **PostgreSQL Full-Text Search with pg_trgm**: Handle typos, abbreviations, and partial matches
- **Semantic Search with pgvector**: Find conceptually similar incidents across teams
- **Hybrid Search Strategies**: Combine multiple search methods with intelligent weighting
- **Cohere Reranking via Amazon Bedrock**: Improve result relevance by 20-30%
- **MCP-style Structured Retrieval**: Build context-aware search with persona and temporal filters
- **Performance Optimization**: Choose the right search strategy for different query types

## 🏗️ Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│                 │     │                  │     │                 │
│  Jupyter        │────▶│  Aurora          │────▶│  Amazon         │
│  Notebook       │     │  PostgreSQL      │     │  Bedrock        │
│                 │     │  (pgvector +     │     │  (Cohere)       │
└─────────────────┘     │   pg_trgm)       │     └─────────────────┘
                        └──────────────────┘
```

## 🚦 Prerequisites

- AWS Account with Amazon Bedrock access (Cohere models enabled)
- Basic knowledge of PostgreSQL and Python
- Familiarity with vector databases (helpful but not required)

## 📂 Workshop Studio Structure vs GitHub Repository

### Workshop Studio Assets (S3):
```
static/
├── dat409-hybrid-search.yaml        # Unified CFN template
└── iam_policy.json                  # IAM policy for participants
```

### GitHub Repository (Public):
```
sample-dat409-hybrid-search-workshop/
├── README.md                         # This file
├── LICENSE                          # MIT-0 License
├── notebooks/
│   ├── workshop_notebook.ipynb      # Main workshop notebook (enhanced version)
│   └── requirements.txt              # Python dependencies
├── code/
│   ├── search_utils.py              # Reusable search functions
│   ├── mcp_patterns.py              # MCP implementation patterns
│   └── streamlit_app.py             # Interactive dashboard (bonus module)
├── data/
│   ├── incident_logs.json           # Sample engineering logs (1 year of data)
│   └── sample_queries.json          # Example search queries for testing
├── scripts/
│   ├── setup_database.sql           # Database initialization
│   ├── create_indexes.sql           # Index creation scripts
│   └── load_sample_data.py          # Data loading utility
├── solutions/
│   └── complete_notebook.ipynb      # Full solution reference
└── .env.example                      # Environment variables template
```

## 🚀 Quick Start (Workshop Participants)

If you're attending the workshop at re:Invent, your environment is pre-configured with our automated bootstrap! 

### What's Already Done For You:
✅ Aurora PostgreSQL 17.5 with pgvector and pg_trgm extensions  
✅ Jupyter Lab running on port 8888  
✅ All Python packages installed  
✅ GitHub repository cloned to `/workshop`  
✅ Database credentials configured  
✅ Environment variables set  

### Just Three Steps:
1. Open the Code Editor URL provided by your instructor
2. Navigate to the Jupyter interface (port 8888)
3. Open `/workshop/notebooks/workshop_notebook.ipynb` and follow along!

## 💻 Self-Paced Setup

Want to run this workshop on your own? Follow these steps:

### 1. Clone the Repository
```bash
git clone https://github.com/aws-samples/sample-dat409-hybrid-search-workshop.git
cd sample-dat409-hybrid-search-workshop
```

### 2. Deploy Infrastructure
Deploy the complete workshop stack with automated bootstrap:

```bash
aws cloudformation create-stack \
  --stack-name dat409-workshop \
  --template-url https://workshop-assets-url/static/dat409-hybrid-search.yaml \
  --parameters \
    ParameterKey=AssetsBucketName,ParameterValue=your-bucket \
    ParameterKey=AssetsBucketPrefix,ParameterValue=your-prefix/ \
  --capabilities CAPABILITY_NAMED_IAM

# Wait for stack to complete (includes automatic bootstrap)
aws cloudformation wait stack-create-complete --stack-name dat409-workshop
```

The stack automatically:
- Creates Aurora PostgreSQL 17.5 with I/O optimized storage
- Launches Code Editor instance with Jupyter Lab
- Clones the GitHub repository
- Installs all dependencies
- Configures database extensions
- Sets up environment variables

### 3. Set Up Your Environment
```bash
# Install Python dependencies
pip install -r notebooks/requirements.txt

# Set environment variables
export DB_HOST=<your-aurora-endpoint>
export DB_NAME=workshop_db
export AWS_REGION=us-west-2
```

### 4. Run the Notebook
```bash
jupyter lab notebooks/workshop_notebook.ipynb
```

## 📊 Sample Data

The workshop includes a year of simulated engineering logs from four different teams:
- **DBAs**: Database performance metrics, vacuum processes, lock contention
- **SREs**: Service health, response times, availability metrics
- **Developers**: Application exceptions, query patterns, connection issues
- **Data Engineers**: ETL pipeline health, data freshness, processing backlogs

## 🔍 Search Methods Comparison

| Method | Best For | Speed | Example |
|--------|----------|-------|---------|
| **Trigram** | Typos, abbreviations | ~1-5ms | "db perf" → "database performance" |
| **Semantic** | Conceptual similarity | ~50-200ms | "slow queries" → "high latency" |
| **Full-text** | Exact phrases | ~5-10ms | Exact error messages |
| **Hybrid** | Comprehensive search | ~100-300ms | Best of all methods |

## 🎓 Learning Modules

### Module 1: Understanding Your Data
- Explore engineering logs from different personas
- Understand how teams describe issues differently

### Module 2: Database Setup
- Configure Aurora PostgreSQL with pgvector
- Enable pg_trgm for fuzzy matching

### Module 3-6: Search Implementation
- Build trigram, semantic, and full-text search
- Combine into hybrid search with configurable weights

### Module 7-8: Advanced Techniques
- Implement Cohere reranking
- Add MCP-style contextual filters

### Module 9-10: Production Patterns
- Create monitoring queries from historical patterns
- Optimize performance for different use cases

## 🏆 Key Takeaways

After completing this workshop, you'll be able to:
- ✅ Build production-ready hybrid search systems
- ✅ Connect insights across different team perspectives
- ✅ Prevent incidents by finding hidden patterns
- ✅ Implement MCP-compatible retrieval patterns
- ✅ Optimize search strategies for different query types

## 📖 Additional Resources

- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [PostgreSQL Full-Text Search](https://www.postgresql.org/docs/current/textsearch.html)
- [Amazon Bedrock Cohere Models](https://docs.aws.amazon.com/bedrock/latest/userguide/cohere-models.html)
- [Model Context Protocol (MCP)](https://modelcontextprotocol.io/)

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## 📄 License

This sample code is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.

## 🙋 Questions?

- Workshop issues: Open a GitHub issue
- AWS Support: Contact through AWS Console
- Community: Post in AWS Developer Forums

## 🌟 Show Your Support

If you found this workshop helpful:
- ⭐ Star this repository
- 🍴 Fork for your own experiments
- 👁️ Watch for updates
- 📢 Share with your team

---

**Built with ❤️ by AWS Database Specialists**

#reInvent2025 #HybridSearch #AuroraPostgreSQL #MCP