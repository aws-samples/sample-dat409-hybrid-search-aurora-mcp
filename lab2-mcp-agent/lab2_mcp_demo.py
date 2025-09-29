#!/usr/bin/env python3
"""
DAT409 Workshop - Lab 1: Hybrid Search with Aurora PostgreSQL
This Streamlit app demonstrates:
1. Keyword search (TSVector & pg_trgm)
2. Semantic search (Cohere Embeddings via Bedrock)
3. Hybrid search with configurable weights
4. Cohere Rerank for result optimization
5. Performance comparison and analytics

Run with: streamlit run lab1_hybrid_search_demo.py --server.port 8502 --theme.base dark
"""

import streamlit as st
import psycopg
import pandas as pd
import numpy as np
import json
import boto3
from pgvector.psycopg import register_vector
import time
from datetime import datetime
import plotly.express as px
import plotly.graph_objects as go
from pathlib import Path
import os

# Force dark theme configuration
st.set_page_config(
    page_title="DAT409 Lab 1: Hybrid Search Demo",
    page_icon="🔍",
    layout="wide",
    initial_sidebar_state="expanded",
    menu_items={
        'About': "DAT409 Workshop - Hybrid Search with PostgreSQL and Cohere"
    }
)

# Custom dark theme CSS
st.markdown("""
<style>
    /* Dark theme overrides */
    .stApp {
        background-color: #0E1117;
        color: #FAFAFA;
    }
    
    /* Metrics styling */
    [data-testid="metric-container"] {
        background-color: #1E2127;
        border: 1px solid #2E3138;
        padding: 1rem;
        border-radius: 0.5rem;
        box-shadow: 0 2px 4px rgba(0,0,0,0.2);
    }
    
    /* Expander styling */
    .streamlit-expanderHeader {
        background-color: #1E2127;
        border: 1px solid #2E3138;
        border-radius: 0.5rem;
    }
    
    /* Product cards */
    .product-card {
        background-color: #1E2127;
        border: 1px solid #2E3138;
        border-radius: 0.5rem;
        padding: 1.5rem;
        margin-bottom: 1rem;
        transition: all 0.3s ease;
    }
    
    .product-card:hover {
        border-color: #FF9900;
        box-shadow: 0 4px 8px rgba(255, 153, 0, 0.2);
    }
    
    /* Search method badges */
    .method-keyword { background: #1565C0; }
    .method-fuzzy { background: #C2185B; }
    .method-semantic { background: #2E7D32; }
    .method-hybrid { background: #E65100; }
    .method-reranked { background: #7B1FA2; }
    
    /* Score bars */
    .score-bar {
        height: 8px;
        background: #2E3138;
        border-radius: 4px;
        overflow: hidden;
        margin-top: 0.5rem;
    }
    
    .score-fill {
        height: 100%;
        background: linear-gradient(90deg, #FF9900, #FF6600);
    }
    
    /* Custom tabs */
    .stTabs [data-baseweb="tab-list"] {
        background-color: #1E2127;
        border-radius: 0.5rem;
    }
    
    .stTabs [data-baseweb="tab"] {
        color: #FAFAFA;
        background-color: transparent;
    }
    
    .stTabs [aria-selected="true"] {
        background-color: #2E3138;
    }
</style>
""", unsafe_allow_html=True)

# Load environment variables
def load_env():
    """Load environment variables from .env file"""
    env_path = Path("/workshop/.env")
    if env_path.exists():
        with open(env_path) as f:
            for line in f:
                if line.strip() and not line.startswith('#'):
                    if '=' in line:
                        key, value = line.strip().split('=', 1)
                        os.environ[key] = value.strip('"').strip("'")

load_env()

# Database configuration
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': os.getenv('DB_PORT', '5432'),
    'dbname': os.getenv('DB_NAME', 'postgres'),
    'user': os.getenv('DB_USER', 'postgres'),
    'password': os.getenv('DB_PASSWORD', '')
}

AWS_REGION = os.getenv('AWS_REGION', 'us-west-2')

# Initialize Bedrock client
@st.cache_resource
def get_bedrock_client():
    return boto3.client('bedrock-runtime', region_name=AWS_REGION)

# Database connection
@st.cache_resource
def get_db_connection():
    conn = psycopg.connect(**DB_CONFIG, autocommit=True)
    register_vector(conn)
    return conn

# Generate embeddings using Cohere
def generate_embedding(text: str, input_type: str = "search_query") -> list:
    """Generate embedding using Cohere embed-english-v3"""
    if not text:
        return None
    
    bedrock = get_bedrock_client()
    
    body = json.dumps({
        "texts": [text[:2000]],
        "input_type": input_type,
        "embedding_types": ["float"],
        "truncate": "END"
    })
    
    try:
        response = bedrock.invoke_model(
            modelId="cohere.embed-english-v3",
            body=body,
            contentType="application/json",
            accept="application/json"
        )
        
        result = json.loads(response['body'].read())
        if 'embeddings' in result and 'float' in result['embeddings']:
            return result['embeddings']['float'][0]
    except Exception as e:
        st.error(f"Embedding error: {e}")
    
    return None

# Cohere Rerank function
def rerank_results(query: str, results: list, top_k: int = 10) -> list:
    """Rerank search results using Cohere rerank-v3-5:0"""
    if not results:
        return []
    
    bedrock = get_bedrock_client()
    
    # Prepare documents for reranking
    documents = [r['description'] for r in results]
    
    body = json.dumps({
        "query": query,
        "documents": documents,
        "top_n": min(top_k, len(documents)),
        "return_documents": False
    })
    
    try:
        response = bedrock.invoke_model(
            modelId="cohere.rerank-v3-5:0",
            body=body,
            contentType="application/json",
            accept="application/json"
        )
        
        result = json.loads(response['body'].read())
        
        # Reorder results based on rerank scores
        reranked = []
        for item in result.get('results', []):
            idx = item['index']
            res = results[idx].copy()
            res['rerank_score'] = item['relevance_score']
            res['original_rank'] = results.index(results[idx]) + 1
            reranked.append(res)
        
        return reranked
    except Exception as e:
        st.error(f"Reranking error: {e}")
        return results[:top_k]

# Search functions
def keyword_search(query: str, limit: int = 10) -> list:
    """TSVector full-text search"""
    conn = get_db_connection()
    
    results = conn.execute("""
        SELECT 
            "productId",
            product_description,
            category_name,
            price,
            stars,
            reviews,
            imgurl,
            ts_rank_cd(
                to_tsvector('english', product_description), 
                plainto_tsquery('english', %s)
            ) as score
        FROM bedrock_integration.product_catalog
        WHERE to_tsvector('english', product_description) 
              @@ plainto_tsquery('english', %s)
        ORDER BY score DESC
        LIMIT %s;
    """, (query, query, limit)).fetchall()
    
    return [{
        'productId': r[0],
        'description': r[1],
        'category': r[2],
        'price': float(r[3]) if r[3] else 0,
        'stars': float(r[4]) if r[4] else 0,
        'reviews': int(r[5]) if r[5] else 0,
        'imgurl': r[6],
        'score': float(r[7]) if r[7] else 0,
        'method': 'Keyword'
    } for r in results]

def fuzzy_search(query: str, limit: int = 10) -> list:
    """pg_trgm fuzzy search"""
    conn = get_db_connection()
    conn.execute("SET pg_trgm.similarity_threshold = 0.1;")
    
    results = conn.execute("""
        SELECT 
            "productId",
            product_description,
            category_name,
            price,
            stars,
            reviews,
            imgurl,
            similarity(lower(product_description), lower(%s)) as score
        FROM bedrock_integration.product_catalog
        WHERE lower(product_description) %% lower(%s)
        ORDER BY score DESC
        LIMIT %s;
    """, (query, query, limit)).fetchall()
    
    return [{
        'productId': r[0],
        'description': r[1],
        'category': r[2],
        'price': float(r[3]) if r[3] else 0,
        'stars': float(r[4]) if r[4] else 0,
        'reviews': int(r[5]) if r[5] else 0,
        'imgurl': r[6],
        'score': float(r[7]) if r[7] else 0,
        'method': 'Fuzzy'
    } for r in results]

def semantic_search(query: str, limit: int = 10) -> list:
    """Semantic search using Cohere embeddings"""
    query_embedding = generate_embedding(query, "search_query")
    if not query_embedding:
        return []
    
    conn = get_db_connection()
    
    results = conn.execute("""
        SELECT 
            "productId",
            product_description,
            category_name,
            price,
            stars,
            reviews,
            imgurl,
            1 - (embedding <=> %s::vector) as score
        FROM bedrock_integration.product_catalog
        WHERE embedding IS NOT NULL
        ORDER BY embedding <=> %s::vector
        LIMIT %s;
    """, (query_embedding, query_embedding, limit)).fetchall()
    
    return [{
        'productId': r[0],
        'description': r[1],
        'category': r[2],
        'price': float(r[3]) if r[3] else 0,
        'stars': float(r[4]) if r[4] else 0,
        'reviews': int(r[5]) if r[5] else 0,
        'imgurl': r[6],
        'score': float(r[7]) if r[7] else 0,
        'method': 'Semantic'
    } for r in results]

def hybrid_search(query: str, semantic_weight: float = 0.7, keyword_weight: float = 0.3, limit: int = 10) -> list:
    """Hybrid search combining semantic and keyword"""
    # Normalize weights
    total = semantic_weight + keyword_weight
    semantic_weight = semantic_weight / total
    keyword_weight = keyword_weight / total
    
    # Get results from both methods
    semantic_results = semantic_search(query, limit * 2)
    keyword_results = keyword_search(query, limit * 2)
    
    # Combine scores
    product_scores = {}
    product_data = {}
    
    for result in semantic_results:
        pid = result['productId']
        product_scores[pid] = result['score'] * semantic_weight
        product_data[pid] = result
    
    for result in keyword_results:
        pid = result['productId']
        if pid in product_scores:
            product_scores[pid] += result['score'] * keyword_weight
        else:
            product_scores[pid] = result['score'] * keyword_weight
            product_data[pid] = result
    
    # Sort and return top results
    sorted_products = sorted(product_scores.items(), key=lambda x: x[1], reverse=True)[:limit]
    
    results = []
    for pid, score in sorted_products:
        product = product_data[pid].copy()
        product['score'] = score
        product['method'] = 'Hybrid'
        results.append(product)
    
    return results

# Display functions
def display_product_card(product: dict, method_color: str = ""):
    """Display a single product card"""
    score = product.get('rerank_score', product.get('score', 0))
    stars_display = "⭐" * int(product.get('stars', 0))
    
    # Method badge color
    method_colors = {
        'Keyword': '#1565C0',
        'Fuzzy': '#C2185B', 
        'Semantic': '#2E7D32',
        'Hybrid': '#E65100',
        'Reranked': '#7B1FA2'
    }
    badge_color = method_colors.get(product.get('method', ''), '#666666')
    
    # Create columns for product layout
    col1, col2 = st.columns([1, 3])
    
    with col1:
        if product.get('imgurl'):
            st.image(product['imgurl'], use_container_width=True)
        else:
            st.empty()
    
    with col2:
        # Product title and badge
        st.markdown(f"""
        <div style="display: flex; justify-content: space-between; align-items: start;">
            <h4 style="margin: 0;">{product['description'][:100]}...</h4>
            <span style="background: {badge_color}; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px;">
                {product.get('method', '')}
            </span>
        </div>
        """, unsafe_allow_html=True)
        
        # Product details
        col2_1, col2_2, col2_3 = st.columns(3)
        with col2_1:
            st.metric("Price", f"${product.get('price', 0):.2f}")
        with col2_2:
            st.metric("Rating", f"{product.get('stars', 0):.1f} {stars_display}")
        with col2_3:
            st.metric("Reviews", f"{product.get('reviews', 0):,}")
        
        # Score bar
        score_percent = min(score * 100, 100) if score > 0 else 0
        st.markdown(f"""
        <div class="score-bar">
            <div class="score-fill" style="width: {score_percent}%;"></div>
        </div>
        <small>Relevance Score: {score:.4f}</small>
        """, unsafe_allow_html=True)
        
        if product.get('original_rank'):
            st.caption(f"Original Rank: #{product['original_rank']}")

def main():
    st.title("🔍 DAT409 Lab 1: Hybrid Search with PostgreSQL")
    
    st.markdown("""
    <div style="background: #1E2127; border-left: 4px solid #FF9900; padding: 1rem; border-radius: 0.5rem; margin-bottom: 2rem;">
        <strong>Features:</strong> TSVector (Keyword) • pg_trgm (Fuzzy) • Cohere Embeddings (Semantic) • Hybrid Search • Cohere Rerank
    </div>
    """, unsafe_allow_html=True)
    
    # Sidebar configuration
    with st.sidebar:
        st.header("⚙️ Search Configuration")
        
        search_method = st.selectbox(
            "Search Method",
            ["Hybrid", "Keyword (TSVector)", "Fuzzy (pg_trgm)", "Semantic (Cohere)", "Compare All"]
        )
        
        st.subheader("Hybrid Weights")
        semantic_weight = st.slider("Semantic Weight", 0.0, 1.0, 0.7, 0.1)
        keyword_weight = st.slider("Keyword Weight", 0.0, 1.0, 0.3, 0.1)
        
        st.subheader("Options")
        use_rerank = st.checkbox("Use Cohere Rerank", value=True)
        results_limit = st.slider("Results Limit", 5, 20, 10)
        
        st.divider()
        
        # Example queries
        st.subheader("📝 Example Queries")
        example_queries = {
            "Sony WH-1000XM4": "Exact product",
            "wireless hedphones": "With typos",
            "gift for coffee lover": "Semantic intent",
            "camera under 500": "Budget constraint",
            "eco-friendly water bottle": "Attributes"
        }
        
        for query, desc in example_queries.items():
            if st.button(f"{desc}: {query}", key=f"ex_{query}"):
                st.session_state.search_query = query
    
    # Main search interface
    search_query = st.text_input(
        "Search Products",
        value=st.session_state.get('search_query', ''),
        placeholder="Try 'wireless headphones' or 'coffee maker'..."
    )
    
    col1, col2, col3 = st.columns([1, 1, 3])
    with col1:
        search_button = st.button("🔍 Search", type="primary", use_container_width=True)
    with col2:
        clear_button = st.button("🔄 Clear", use_container_width=True)
    
    if clear_button:
        st.session_state.search_query = ""
        st.rerun()
    
    if search_button and search_query:
        # Create tabs for results
        if search_method == "Compare All":
            tabs = st.tabs(["🔍 Comparison", "📊 Analytics", "⚡ Performance"])
            
            with tabs[0]:
                st.subheader("Search Method Comparison")
                
                methods = [
                    ("Keyword (TSVector)", keyword_search),
                    ("Fuzzy (pg_trgm)", fuzzy_search),
                    ("Semantic (Cohere)", semantic_search),
                    ("Hybrid", lambda q, l: hybrid_search(q, semantic_weight, keyword_weight, l))
                ]
                
                cols = st.columns(len(methods))
                
                for idx, (method_name, method_func) in enumerate(methods):
                    with cols[idx]:
                        st.markdown(f"### {method_name}")
                        
                        with st.spinner(f"Searching..."):
                            start_time = time.time()
                            results = method_func(search_query, results_limit)
                            elapsed = time.time() - start_time
                            
                            if use_rerank and results:
                                rerank_start = time.time()
                                results = rerank_results(search_query, results, min(5, len(results)))
                                rerank_time = time.time() - rerank_start
                                st.caption(f"Search: {elapsed:.3f}s | Rerank: {rerank_time:.3f}s")
                            else:
                                st.caption(f"Time: {elapsed:.3f}s")
                        
                        if results:
                            st.success(f"Found {len(results)} results")
                            for result in results[:3]:  # Show top 3
                                with st.expander(f"{result['description'][:50]}..."):
                                    display_product_card(result)
                        else:
                            st.warning("No results found")
            
            with tabs[1]:
                st.subheader("Search Analytics")
                
                # Collect all results for analysis
                all_results = {}
                for method_name, method_func in methods:
                    results = method_func(search_query, results_limit)
                    all_results[method_name] = results
                
                # Create comparison metrics
                comparison_data = []
                for method, results in all_results.items():
                    if results:
                        comparison_data.append({
                            'Method': method,
                            'Results': len(results),
                            'Avg Score': np.mean([r['score'] for r in results]),
                            'Max Score': max([r['score'] for r in results]),
                            'Unique Products': len(set([r['productId'] for r in results]))
                        })
                
                if comparison_data:
                    df = pd.DataFrame(comparison_data)
                    
                    # Display metrics
                    col1, col2 = st.columns(2)
                    
                    with col1:
                        fig = px.bar(df, x='Method', y='Avg Score', 
                                   title='Average Relevance Score by Method',
                                   color='Method',
                                   color_discrete_map={
                                       'Keyword (TSVector)': '#1565C0',
                                       'Fuzzy (pg_trgm)': '#C2185B',
                                       'Semantic (Cohere)': '#2E7D32',
                                       'Hybrid': '#E65100'
                                   })
                        fig.update_layout(
                            plot_bgcolor='#0E1117',
                            paper_bgcolor='#0E1117',
                            font_color='#FAFAFA'
                        )
                        st.plotly_chart(fig, use_container_width=True)
                    
                    with col2:
                        fig = px.scatter(df, x='Results', y='Avg Score',
                                       size='Unique Products', color='Method',
                                       title='Results vs Score Trade-off',
                                       color_discrete_map={
                                           'Keyword (TSVector)': '#1565C0',
                                           'Fuzzy (pg_trgm)': '#C2185B',
                                           'Semantic (Cohere)': '#2E7D32',
                                           'Hybrid': '#E65100'
                                       })
                        fig.update_layout(
                            plot_bgcolor='#0E1117',
                            paper_bgcolor='#0E1117',
                            font_color='#FAFAFA'
                        )
                        st.plotly_chart(fig, use_container_width=True)
                    
                    # Product overlap analysis
                    st.subheader("Product Overlap Analysis")
                    
                    # Calculate overlap matrix
                    overlap_matrix = {}
                    for m1 in all_results:
                        overlap_matrix[m1] = {}
                        for m2 in all_results:
                            if all_results[m1] and all_results[m2]:
                                ids1 = set([r['productId'] for r in all_results[m1]])
                                ids2 = set([r['productId'] for r in all_results[m2]])
                                overlap = len(ids1.intersection(ids2)) / len(ids1.union(ids2))
                                overlap_matrix[m1][m2] = overlap
                            else:
                                overlap_matrix[m1][m2] = 0
                    
                    overlap_df = pd.DataFrame(overlap_matrix)
                    fig = px.imshow(overlap_df, title="Method Result Overlap",
                                  color_continuous_scale='RdYlGn',
                                  labels=dict(color="Overlap %"))
                    fig.update_layout(
                        plot_bgcolor='#0E1117',
                        paper_bgcolor='#0E1117',
                        font_color='#FAFAFA'
                    )
                    st.plotly_chart(fig, use_container_width=True)
            
            with tabs[2]:
                st.subheader("Performance Metrics")
                
                # Run performance tests
                perf_data = []
                test_queries = [search_query]  # Add more for comprehensive testing
                
                for query in test_queries:
                    for method_name, method_func in methods:
                        runs = []
                        for _ in range(3):  # Multiple runs for averaging
                            start = time.time()
                            _ = method_func(query, 10)
                            runs.append((time.time() - start) * 1000)
                        
                        perf_data.append({
                            'Method': method_name,
                            'Query': query[:30],
                            'Avg Time (ms)': np.mean(runs),
                            'Min Time (ms)': min(runs),
                            'Max Time (ms)': max(runs)
                        })
                
                perf_df = pd.DataFrame(perf_data)
                
                # Display performance chart
                fig = go.Figure()
                for method in perf_df['Method'].unique():
                    method_data = perf_df[perf_df['Method'] == method]
                    fig.add_trace(go.Bar(
                        name=method,
                        x=method_data['Query'],
                        y=method_data['Avg Time (ms)'],
                        error_y=dict(
                            type='data',
                            array=method_data['Max Time (ms)'] - method_data['Avg Time (ms)'],
                            arrayminus=method_data['Avg Time (ms)'] - method_data['Min Time (ms)']
                        )
                    ))
                
                fig.update_layout(
                    title='Search Performance by Method',
                    xaxis_title='Query',
                    yaxis_title='Response Time (ms)',
                    plot_bgcolor='#0E1117',
                    paper_bgcolor='#0E1117',
                    font_color='#FAFAFA'
                )
                st.plotly_chart(fig, use_container_width=True)
                
                # Display detailed metrics
                st.dataframe(perf_df.style.format({
                    'Avg Time (ms)': '{:.2f}',
                    'Min Time (ms)': '{:.2f}',
                    'Max Time (ms)': '{:.2f}'
                }))
        
        else:
            # Single method search
            st.subheader(f"Results: {search_method}")
            
            with st.spinner("Searching..."):
                start_time = time.time()
                
                if search_method == "Hybrid":
                    results = hybrid_search(search_query, semantic_weight, keyword_weight, results_limit)
                elif search_method == "Keyword (TSVector)":
                    results = keyword_search(search_query, results_limit)
                elif search_method == "Fuzzy (pg_trgm)":
                    results = fuzzy_search(search_query, results_limit)
                elif search_method == "Semantic (Cohere)":
                    results = semantic_search(search_query, results_limit)
                
                search_time = time.time() - start_time
                
                # Apply reranking if enabled
                rerank_time = 0
                if use_rerank and results:
                    rerank_start = time.time()
                    results = rerank_results(search_query, results, len(results))
                    rerank_time = time.time() - rerank_start
            
            # Display metrics
            col1, col2, col3, col4 = st.columns(4)
            with col1:
                st.metric("Results Found", len(results))
            with col2:
                st.metric("Search Time", f"{search_time:.3f}s")
            with col3:
                st.metric("Rerank Time", f"{rerank_time:.3f}s" if use_rerank else "N/A")
            with col4:
                st.metric("Total Time", f"{(search_time + rerank_time):.3f}s")
            
            # Display results
            if results:
                for idx, result in enumerate(results):
                    with st.container():
                        display_product_card(result)
                        st.divider()
            else:
                st.warning("No results found. Try a different search term or method.")
    
    # Footer with information
    st.divider()
    st.markdown("""
    <div style="text-align: center; color: #666; font-size: 14px; margin-top: 2rem;">
        DAT409 Workshop | Hybrid Search with Aurora PostgreSQL | 
        Powered by Cohere (embed-english-v3 & rerank-v3-5:0) via Amazon Bedrock
    </div>
    """, unsafe_allow_html=True)

if __name__ == "__main__":
    main()
