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
