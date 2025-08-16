# DAT409 | Hybrid Search with Aurora PostgreSQL for MCP Retrieval

## 🎯 The Black Friday Playbook

Transform a year of engineering observations into actionable intelligence for peak events. Build a production-ready hybrid search system that combines semantic understanding with trigram matching, enabling teams to surface critical patterns from historical incidents.

## 🚀 Quick Start for Workshop Participants

### Your Environment is Ready!

If you're attending the workshop at re:Invent, everything is pre-configured:
- ✅ Aurora PostgreSQL with pgvector and pg_trgm extensions
- ✅ Jupyter notebooks with all dependencies
- ✅ 1,500 incident logs from 365 days of operations
- ✅ Amazon Bedrock with Cohere models enabled

**Just three steps:**
1. Open your Workshop Studio URL
2. Navigate to port 8888 (Jupyter)
3. Open `/workshop/notebooks/dat409_notebook.ipynb`

## 📚 What You'll Build

### Production Hybrid Search System (45 min)
Build a comprehensive search system that handles all query patterns:
- **Semantic Search**: Find conceptually similar incidents using Cohere Embed v3
- **Trigram Search**: Match exact terms AND handle typos with pg_trgm
- **Hybrid Fusion**: Combine results with reciprocal rank scoring
- **ML Reranking**: Optimize relevance with Cohere Rerank v3.5

### Interactive Search Widget
Test your hybrid search with a fully-featured widget that includes:
- Real-time weight adjustment (semantic vs trigram)
- Team and severity filters
- Sample queries with typos
- Result interpretation guide for Black Friday preparation

## 🎮 The Scenario

Your e-commerce platform faces Black Friday in 28 days. You have:
- 📊 1,500 logs from 365 days of operations
- 👥 4 engineering teams with different perspectives
- 🔍 Same incidents described differently by each team

**The Challenge**: Different teams describe the same problem differently:
- DBA: "FATAL: remaining connection slots are reserved"
- Developer: "HikariPool-1 - Connection timeout after 30000ms"
- SRE: "CloudWatch: DatabaseConnections crossed 990"

**Your Mission**: Build hybrid search that finds ALL these variations to prevent future incidents.

## 🛠️ Workshop Structure

```
sample-dat409-hybrid-search-workshop/
├── notebooks/
│   └── dat409_notebook.ipynb       # Main workshop notebook
├── data/
│   └── incident_logs.json          # 1,500 engineering logs
├── code/
│   └── incident_logs_generator.py  # Dataset generator
├── scripts/
│   └── setup_database.sql         # Database initialization
└── infrastructure/
    ├── dat409-hybrid-search.yaml  # CloudFormation template
    └── contentspec.yaml           # Workshop Studio config
```

## 💡 Key Learning Points

### Why Hybrid Search Matters

**Pure Trigram Search Limitations:**
```python
Query: "connection exhaustion issues"
Returns: Only exact phrase matches
Misses: "pool saturation", "threading bottleneck"
```

**Pure Semantic Search Limitations:**
```python
Query: "buffer_cache_hit_ratio anomaly"
Returns: Generic "performance issues"
Misses: Exact incident where ratio = 72%
```

**Hybrid Search Success:**
```python
Query: "connection exhaustion issues"
Returns: 
  - Exact matches (trigram)
  - Typos handled (trigram fuzzy)
  - Related concepts (semantic)
  - Both specific metrics AND patterns
```

## 📊 Understanding Your Results

### Relevance Score Interpretation
- **0.8-1.0**: Nearly identical incidents - study these first
- **0.6-0.8**: Highly related patterns - same root cause, different description
- **0.4-0.6**: Conceptually related - may reveal cascade effects

### Action Items by Severity
- 🔴 **Critical**: Create runbooks and automated alerts
- 🟡 **Warning**: Set up proactive monitoring thresholds
- 🔵 **Info**: Understand normal vs abnormal patterns

### Methods Column
- **"trigram, semantic"**: Found by both = highest confidence
- **"trigram only"**: Exact keyword/error code match
- **"semantic only"**: Different terminology, same concept

## 🚦 Prerequisites

- **Required**: AWS Account with Bedrock access
- **Required**: Laptop with modern browser
- **Helpful**: Basic Python and SQL knowledge

## 🔧 Self-Paced Setup

If running independently:

### 1. Deploy Infrastructure
```bash
# Use provided CloudFormation template
aws cloudformation create-stack \
  --stack-name dat409-workshop \
  --template-body file://infrastructure/dat409-hybrid-search.yaml \
  --parameters ParameterKey=DBUsername,ParameterValue=workshop_admin \
  --capabilities CAPABILITY_NAMED_IAM
```

### 2. Connect to Environment
```bash
# Get Jupyter URL from CloudFormation outputs
aws cloudformation describe-stacks \
  --stack-name dat409-workshop \
  --query 'Stacks[0].Outputs[?OutputKey==`JupyterURL`].OutputValue' \
  --output text
```

### 3. Load Sample Data
The notebook automatically loads 1,500 incident logs with:
- Multiple engineering perspectives
- Severity distributions
- Black Friday correlation patterns

## 📈 Performance Optimizations

### Implemented in Workshop
- **Batch embeddings**: 96 texts per API call
- **HNSW indexing**: Fast approximate nearest neighbor search
- **GIN trigram index**: Efficient fuzzy matching
- **Deduplication**: Smart content hashing
- **Single display**: Prevents UI duplication

### Production Considerations
- Use read replicas for search workloads
- Implement query result caching
- Monitor with Performance Insights
- Scale for concurrent users

## 🎯 Learning Outcomes

After completing this workshop:

1. **Build Production Hybrid Search**
   - Combine trigram and semantic effectively
   - Handle typos, exact matches, and concepts
   - Implement smart weight detection

2. **Optimize for Scale**
   - Batch API calls efficiently
   - Create proper indexes
   - Handle metadata filtering

3. **Apply to Black Friday**
   - Identify incident patterns
   - Create preventive playbooks
   - Enable cross-team insights

## 📖 Technologies Used

- **Aurora PostgreSQL 17**: Managed database with extensions
- **pgvector**: Vector similarity search (1024 dimensions)
- **pg_trgm**: Trigram matching for fuzzy search
- **Cohere Embed v3**: State-of-art embeddings
- **Cohere Rerank v3.5**: ML relevance optimization
- **Amazon Bedrock**: Managed model access

## 🤝 Support & Resources

- **Workshop Issues**: [GitHub Issues](https://github.com/aws-samples/sample-dat409-hybrid-search-workshop/issues)
- **Documentation**: [pgvector](https://github.com/pgvector/pgvector) | [Aurora](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/)
- **Model Context Protocol**: [MCP Specification](https://modelcontextprotocol.io/)

## 📄 License

This sample code is licensed under the MIT-0 License.

---

**Built with ❤️ by AWS Database Specialists for re:Invent 2025**