"""
DAT409 - Hybrid Search Workshop
Interactive Streamlit Dashboard for Search Exploration

This dashboard allows participants to:
- Experiment with different search methods
- Adjust search weights in real-time
- Visualize search results and scores
- Analyze persona-based patterns
- Explore temporal patterns in incidents
"""

import streamlit as st
import pandas as pd
import numpy as np
import psycopg
from pgvector.psycopg import register_vector
import boto3
import json
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime, timedelta
import os
from dotenv import load_dotenv
import time

# Load environment variables
load_dotenv()

# Page configuration
st.set_page_config(
    page_title="DAT409 - Hybrid Search Dashboard",
    page_icon="🔍",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS for better styling
st.markdown("""
<style>
    .main > div {
        padding-top: 2rem;
    }
    .stMetric {
        background-color: #f0f2f6;
        padding: 10px;
        border-radius: 5px;
        margin: 5px;
    }
    .search-result {
        padding: 15px;
        border-left: 4px solid #1f77b4;
        margin: 10px 0;
        background: #f9f9f9;
    }
</style>
""", unsafe_allow_html=True)

# ==========================================
# Database Connection
# ==========================================

@st.cache_resource
def get_db_connection():
    """Create a cached database connection"""
    try:
        conn = psycopg.connect(
            host=os.getenv('DB_HOST'),
            dbname=os.getenv('DB_NAME', 'workshop_db'),
            user=os.getenv('DB_USER', 'workshop_admin'),
            password=os.getenv('DB_PASSWORD'),
            port=os.getenv('DB_PORT', 5432),
            autocommit=True
        )
        register_vector(conn)
        return conn
    except Exception as e:
        st.error(f"Database connection failed: {e}")
        st.stop()

@st.cache_resource
def init_bedrock_client():
    """Initialize Bedrock client for embeddings"""
    return boto3.client(
        service_name='bedrock-runtime',
        region_name=os.getenv('AWS_REGION', 'us-west-2')
    )

# ==========================================
# Search Functions
# ==========================================

def generate_embedding(text, bedrock_client, input_type='search_query'):
    """Generate embeddings using Cohere via Bedrock"""
    if len(text) > 2048:
        text = text[:2048]
    
    try:
        request_body = {
            'texts': [text],
            'input_type': input_type
        }
        
        response = bedrock_client.invoke_model(
            modelId='cohere.embed-english-v3',
            contentType='application/json',
            accept='application/json',
            body=json.dumps(request_body)
        )
        
        response_body = json.loads(response['body'].read())
        return response_body['embeddings'][0]
    except Exception as e:
        st.error(f"Embedding generation failed: {e}")
        # Return mock embedding for demo
        np.random.seed(hash(text) % 2**32)
        return np.random.randn(1024).tolist()

def trigram_search(query, conn, limit=10, threshold=0.1):
    """Perform trigram-based fuzzy text search"""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT
                doc_id,
                content,
                persona,
                timestamp,
                severity,
                similarity(%s, content) as score
            FROM incident_logs
            WHERE similarity(%s, content) > %s
            ORDER BY score DESC
            LIMIT %s;
        """, (query, query, threshold, limit))
        
        return cur.fetchall()

def semantic_search(query, conn, bedrock_client, limit=10):
    """Perform semantic search using vector similarity"""
    query_embedding = generate_embedding(query, bedrock_client, 'search_query')
    
    with conn.cursor() as cur:
        cur.execute("""
            SELECT
                doc_id,
                content,
                persona,
                timestamp,
                severity,
                1 - (content_embedding <=> %s::vector) as score
            FROM incident_logs
            WHERE content_embedding IS NOT NULL
            ORDER BY content_embedding <=> %s::vector
            LIMIT %s;
        """, (query_embedding, query_embedding, limit))
        
        return cur.fetchall()

def fulltext_search(query, conn, limit=10):
    """Perform PostgreSQL full-text search"""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT
                doc_id,
                content,
                persona,
                timestamp,
                severity,
                ts_rank_cd(to_tsvector('english', content),
                          plainto_tsquery('english', %s)) as score
            FROM incident_logs
            WHERE to_tsvector('english', content) @@ plainto_tsquery('english', %s)
            ORDER BY score DESC
            LIMIT %s;
        """, (query, query, limit))
        
        return cur.fetchall()

def hybrid_search(query, conn, bedrock_client, weights, limit=10):
    """Combine all search methods with configurable weights"""
    # Normalize weights
    total = sum(weights.values())
    weights = {k: v/total for k, v in weights.items()}
    
    # Get results from all methods
    semantic_results = semantic_search(query, conn, bedrock_client, limit=20)
    trigram_results = trigram_search(query, conn, limit=20)
    fulltext_results = fulltext_search(query, conn, limit=20)
    
    # Combine scores
    combined_scores = {}
    
    # Process each result set
    for results, weight_key in [
        (semantic_results, 'semantic'),
        (trigram_results, 'trigram'),
        (fulltext_results, 'fulltext')
    ]:
        for doc_id, content, persona, timestamp, severity, score in results:
            if doc_id not in combined_scores:
                combined_scores[doc_id] = {
                    'content': content,
                    'persona': persona,
                    'timestamp': timestamp,
                    'severity': severity,
                    'scores': {'semantic': 0, 'trigram': 0, 'fulltext': 0},
                    'combined_score': 0
                }
            
            # Normalize fulltext scores
            if weight_key == 'fulltext':
                score = min(score, 1.0) if score else 0
            
            combined_scores[doc_id]['scores'][weight_key] = score
            combined_scores[doc_id]['combined_score'] += score * weights[weight_key]
    
    # Sort by combined score
    sorted_results = sorted(
        combined_scores.items(),
        key=lambda x: x[1]['combined_score'],
        reverse=True
    )[:limit]
    
    return sorted_results

# ==========================================
# Streamlit UI
# ==========================================

def main():
    st.title("🔍 DAT409 - Hybrid Search Explorer")
    st.markdown("**The Black Friday Playbook**: Mine engineering wisdom from past incidents")
    
    # Initialize connections
    conn = get_db_connection()
    bedrock_client = init_bedrock_client()
    
    # Sidebar configuration
    with st.sidebar:
        st.header("⚙️ Search Configuration")
        
        search_mode = st.radio(
            "Search Mode",
            ["Hybrid Search", "Compare Methods", "Pattern Analysis"],
            help="Choose how you want to explore the search capabilities"
        )
        
        if search_mode == "Hybrid Search":
            st.subheader("Weight Configuration")
            
            # Preset configurations
            preset = st.selectbox(
                "Preset Configurations",
                ["Custom", "Balanced", "Semantic-Heavy", "Keyword-Heavy", "Fuzzy-Heavy"]
            )
            
            if preset == "Balanced":
                weights = {'semantic': 0.4, 'trigram': 0.3, 'fulltext': 0.3}
            elif preset == "Semantic-Heavy":
                weights = {'semantic': 0.7, 'trigram': 0.2, 'fulltext': 0.1}
            elif preset == "Keyword-Heavy":
                weights = {'semantic': 0.2, 'trigram': 0.1, 'fulltext': 0.7}
            elif preset == "Fuzzy-Heavy":
                weights = {'semantic': 0.2, 'trigram': 0.7, 'fulltext': 0.1}
            else:  # Custom
                col1, col2 = st.columns(2)
                with col1:
                    semantic_weight = st.slider("Semantic", 0.0, 1.0, 0.4, 0.1)
                    trigram_weight = st.slider("Trigram", 0.0, 1.0, 0.3, 0.1)
                with col2:
                    fulltext_weight = st.slider("Full-text", 0.0, 1.0, 0.3, 0.1)
                    st.metric("Total", f"{semantic_weight + trigram_weight + fulltext_weight:.1f}")
                
                weights = {
                    'semantic': semantic_weight,
                    'trigram': trigram_weight,
                    'fulltext': fulltext_weight
                }
            
            # Display current weights
            st.write("**Active Weights:**")
            for method, weight in weights.items():
                st.progress(weight, text=f"{method.capitalize()}: {weight:.1%}")
        
        st.divider()
        
        # Filters
        st.subheader("🎯 Filters")
        
        # Get available personas
        with conn.cursor() as cur:
            cur.execute("SELECT DISTINCT persona FROM incident_logs ORDER BY persona")
            personas = [row[0] for row in cur.fetchall()]
        
        selected_personas = st.multiselect(
            "Engineering Teams",
            personas,
            default=personas,
            help="Filter by engineering team"
        )
        
        # Severity filter
        severity_filter = st.multiselect(
            "Severity Levels",
            ["critical", "warning", "info"],
            default=["critical", "warning", "info"]
        )
        
        # Results limit
        result_limit = st.slider("Maximum Results", 5, 50, 10, 5)
    
    # Main content area
    if search_mode == "Hybrid Search":
        hybrid_search_ui(conn, bedrock_client, weights, selected_personas, severity_filter, result_limit)
    elif search_mode == "Compare Methods":
        compare_methods_ui(conn, bedrock_client, selected_personas, severity_filter, result_limit)
    else:  # Pattern Analysis
        pattern_analysis_ui(conn, selected_personas, severity_filter)

def hybrid_search_ui(conn, bedrock_client, weights, personas, severities, limit):
    """Hybrid search interface"""
    st.header("🔎 Hybrid Search")
    
    # Search input
    col1, col2 = st.columns([3, 1])
    with col1:
        query = st.text_input(
            "Search Query",
            placeholder="e.g., database performance issues, connection pool exhausted, high latency...",
            help="Enter your search query to find relevant incidents"
        )
    with col2:
        search_button = st.button("🔍 Search", type="primary", use_container_width=True)
    
    # Example queries
    with st.expander("💡 Example Queries"):
        example_queries = [
            "database performance degradation",
            "connection pool exhausted",
            "autovacuum taking too long",
            "high CPU usage",
            "query timeout errors",
            "replication lag",
            "disk space issues"
        ]
        
        cols = st.columns(4)
        for idx, example in enumerate(example_queries):
            with cols[idx % 4]:
                if st.button(example, key=f"example_{idx}"):
                    query = example
                    search_button = True
    
    # Perform search
    if search_button and query:
        with st.spinner("Searching..."):
            start_time = time.time()
            results = hybrid_search(query, conn, bedrock_client, weights, limit)
            search_time = time.time() - start_time
        
        # Display metrics
        col1, col2, col3, col4 = st.columns(4)
        with col1:
            st.metric("Results Found", len(results))
        with col2:
            st.metric("Search Time", f"{search_time:.2f}s")
        with col3:
            st.metric("Query Length", len(query.split()))
        with col4:
            st.metric("Search Method", "Hybrid")
        
        # Display results
        st.subheader("📊 Search Results")
        
        for doc_id, result in results:
            # Filter by persona and severity
            if result['persona'] not in personas or result['severity'] not in severities:
                continue
            
            with st.container():
                # Result header
                col1, col2, col3, col4 = st.columns([2, 1, 1, 1])
                with col1:
                    st.markdown(f"**{doc_id}**")
                with col2:
                    persona_color = {
                        'dba': '🔵',
                        'sre': '🟢',
                        'developer': '🟣',
                        'data_engineer': '🟠'
                    }
                    st.markdown(f"{persona_color.get(result['persona'], '⚪')} {result['persona']}")
                with col3:
                    severity_icon = {
                        'critical': '🔴',
                        'warning': '🟡',
                        'info': '🟢'
                    }
                    st.markdown(f"{severity_icon.get(result['severity'], '⚪')} {result['severity']}")
                with col4:
                    st.markdown(f"📅 {result['timestamp'].strftime('%Y-%m-%d %H:%M')}")
                
                # Content
                st.text_area(
                    "Content",
                    result['content'][:500] + "..." if len(result['content']) > 500 else result['content'],
                    height=100,
                    disabled=True,
                    key=f"content_{doc_id}"
                )
                
                # Score breakdown
                with st.expander("📈 Score Breakdown"):
                    score_df = pd.DataFrame({
                        'Method': ['Semantic', 'Trigram', 'Full-text'],
                        'Score': [
                            result['scores']['semantic'],
                            result['scores']['trigram'],
                            result['scores']['fulltext']
                        ],
                        'Weighted': [
                            result['scores']['semantic'] * weights['semantic'],
                            result['scores']['trigram'] * weights['trigram'],
                            result['scores']['fulltext'] * weights['fulltext']
                        ]
                    })
                    
                    col1, col2 = st.columns(2)
                    with col1:
                        fig = px.bar(
                            score_df,
                            x='Method',
                            y='Score',
                            title="Raw Scores",
                            color='Method'
                        )
                        fig.update_layout(height=250, showlegend=False)
                        st.plotly_chart(fig, use_container_width=True)
                    
                    with col2:
                        fig = px.bar(
                            score_df,
                            x='Method',
                            y='Weighted',
                            title="Weighted Contributions",
                            color='Method'
                        )
                        fig.update_layout(height=250, showlegend=False)
                        st.plotly_chart(fig, use_container_width=True)
                    
                    st.metric("Combined Score", f"{result['combined_score']:.3f}")
                
                st.divider()

def compare_methods_ui(conn, bedrock_client, personas, severities, limit):
    """Compare different search methods side by side"""
    st.header("⚖️ Compare Search Methods")
    
    # Query input
    query = st.text_input(
        "Search Query",
        placeholder="Enter a query to compare search methods...",
        help="See how different search methods handle the same query"
    )
    
    if st.button("🔍 Compare", type="primary") and query:
        with st.spinner("Running comparisons..."):
            # Run all search methods
            semantic_results = semantic_search(query, conn, bedrock_client, limit)
            trigram_results = trigram_search(query, conn, limit)
            fulltext_results = fulltext_search(query, conn, limit)
        
        # Display in columns
        col1, col2, col3 = st.columns(3)
        
        with col1:
            st.subheader("🧠 Semantic Search")
            st.caption("Finds conceptually similar content")
            if semantic_results:
                for doc_id, content, persona, timestamp, severity, score in semantic_results[:5]:
                    if persona in personas and severity in severities:
                        st.markdown(f"**Score: {score:.3f}**")
                        st.text(f"[{persona}] {content[:100]}...")
                        st.divider()
            else:
                st.info("No semantic matches found")
        
        with col2:
            st.subheader("🔤 Trigram Search")
            st.caption("Handles typos and variations")
            if trigram_results:
                for doc_id, content, persona, timestamp, severity, score in trigram_results[:5]:
                    if persona in personas and severity in severities:
                        st.markdown(f"**Score: {score:.3f}**")
                        st.text(f"[{persona}] {content[:100]}...")
                        st.divider()
            else:
                st.info("No trigram matches found")
        
        with col3:
            st.subheader("📝 Full-text Search")
            st.caption("Exact keyword matching")
            if fulltext_results:
                for doc_id, content, persona, timestamp, severity, score in fulltext_results[:5]:
                    if persona in personas and severity in severities:
                        st.markdown(f"**Score: {score:.3f}**")
                        st.text(f"[{persona}] {content[:100]}...")
                        st.divider()
            else:
                st.info("No full-text matches found")
        
        # Performance comparison
        st.subheader("⚡ Performance Metrics")
        
        # Mock performance data (in production, measure actual times)
        perf_data = pd.DataFrame({
            'Method': ['Semantic', 'Trigram', 'Full-text'],
            'Latency (ms)': [150, 5, 10],
            'Results': [len(semantic_results), len(trigram_results), len(fulltext_results)],
            'Avg Score': [
                np.mean([r[5] for r in semantic_results]) if semantic_results else 0,
                np.mean([r[5] for r in trigram_results]) if trigram_results else 0,
                np.mean([r[5] for r in fulltext_results]) if fulltext_results else 0
            ]
        })
        
        col1, col2, col3 = st.columns(3)
        with col1:
            fig = px.bar(perf_data, x='Method', y='Latency (ms)', title="Search Latency")
            st.plotly_chart(fig, use_container_width=True)
        with col2:
            fig = px.bar(perf_data, x='Method', y='Results', title="Results Count")
            st.plotly_chart(fig, use_container_width=True)
        with col3:
            fig = px.bar(perf_data, x='Method', y='Avg Score', title="Average Relevance")
            st.plotly_chart(fig, use_container_width=True)

def pattern_analysis_ui(conn, personas, severities):
    """Analyze patterns in historical data"""
    st.header("📈 Pattern Analysis")
    
    # Get data for analysis
    with conn.cursor() as cur:
        cur.execute("""
            SELECT 
                DATE_TRUNC('day', timestamp) as day,
                persona,
                severity,
                COUNT(*) as count
            FROM incident_logs
            WHERE persona = ANY(%s)
                AND severity = ANY(%s)
            GROUP BY day, persona, severity
            ORDER BY day
        """, (personas, severities))
        
        data = cur.fetchall()
    
    if data:
        df = pd.DataFrame(data, columns=['day', 'persona', 'severity', 'count'])
        
        # Timeline visualization
        st.subheader("📅 Incident Timeline")
        
        fig = px.line(
            df.groupby(['day', 'persona'])['count'].sum().reset_index(),
            x='day',
            y='count',
            color='persona',
            title="Incidents by Team Over Time",
            labels={'count': 'Number of Incidents', 'day': 'Date'}
        )
        st.plotly_chart(fig, use_container_width=True)
        
        # Severity distribution
        col1, col2 = st.columns(2)
        
        with col1:
            st.subheader("🎯 Severity Distribution")
            severity_df = df.groupby('severity')['count'].sum().reset_index()
            fig = px.pie(
                severity_df,
                values='count',
                names='severity',
                title="Incidents by Severity",
                color_discrete_map={
                    'critical': '#FF4444',
                    'warning': '#FFAA00',
                    'info': '#44FF44'
                }
            )
            st.plotly_chart(fig, use_container_width=True)
        
        with col2:
            st.subheader("👥 Team Distribution")
            team_df = df.groupby('persona')['count'].sum().reset_index()
            fig = px.pie(
                team_df,
                values='count',
                names='persona',
                title="Incidents by Team"
            )
            st.plotly_chart(fig, use_container_width=True)
        
        # Peak periods
        st.subheader("⚠️ Peak Incident Periods")
        
        peak_days = df.groupby('day')['count'].sum().nlargest(10).reset_index()
        fig = px.bar(
            peak_days,
            x='day',
            y='count',
            title="Top 10 Days with Most Incidents",
            labels={'count': 'Number of Incidents', 'day': 'Date'}
        )
        st.plotly_chart(fig, use_container_width=True)
        
        # Cross-team correlation
        st.subheader("🔗 Cross-Team Incident Correlation")
        
        # Find days where multiple teams reported issues
        multi_team_days = df.groupby('day')['persona'].nunique()
        correlation_days = multi_team_days[multi_team_days > 1].index
        
        if len(correlation_days) > 0:
            correlation_df = df[df['day'].isin(correlation_days)]
            
            # Create heatmap data
            pivot_df = correlation_df.pivot_table(
                index='day',
                columns='persona',
                values='count',
                fill_value=0
            )
            
            fig = go.Figure(data=go.Heatmap(
                z=pivot_df.values,
                x=pivot_df.columns,
                y=pivot_df.index.strftime('%Y-%m-%d'),
                colorscale='Blues'
            ))
            fig.update_layout(
                title="Multi-Team Incident Days",
                xaxis_title="Team",
                yaxis_title="Date",
                height=400
            )
            st.plotly_chart(fig, use_container_width=True)
            
            st.info(f"Found {len(correlation_days)} days where multiple teams reported issues - potential systemic problems!")
        else:
            st.info("No days found with multi-team incidents")
    else:
        st.warning("No data available for the selected filters")

# ==========================================
# Run the app
# ==========================================

if __name__ == "__main__":
    main()