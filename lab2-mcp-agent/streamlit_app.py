"""
DAT409: Aurora PostgreSQL Hybrid Search with MCP
Enhanced Streamlit Application - 400 Level (UI ENHANCED VERSION)

NEW UI FEATURES:
- Animated gradient backgrounds with floating particles
- Skeleton loading states for better UX
- Enhanced product cards with smooth animations
- Search bar with auto-suggestions
- Animated metrics with count-up effects
- Better empty states with actionable suggestions
- Toast notifications for user actions
- Collapsible sidebar sections
- Quick view modals for products
- Enhanced result cards with expand/collapse
"""

import streamlit as st
import os
import json
import time
import logging
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any
import psycopg
from pgvector.psycopg import register_vector
import boto3
from dotenv import load_dotenv
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px

# MCP and Strands imports
from mcp import stdio_client, StdioServerParameters
from strands import Agent
from strands.tools.mcp import MCPClient

# Load environment
load_dotenv()
logging.basicConfig(level=logging.WARNING)
logger = logging.getLogger("dat409_app")
logger.setLevel(logging.INFO)
logging.getLogger("awslabs.postgres_mcp_server.server").setLevel(logging.WARNING)

# ============================================================================
# PAGE CONFIGURATION
# ============================================================================

st.set_page_config(
    page_title="DAT409: Hybrid Search with MCP",
    page_icon="🔍",
    layout="wide",
    initial_sidebar_state="expanded"
)

# ============================================================================
# ENHANCED DARK THEME STYLING
# ============================================================================

st.markdown("""
<style>
    /* Main background with animated gradient */
    .stApp {
        background: linear-gradient(135deg, #000000 0%, #0a0a0a 50%, #000000 100%);
        background-size: 200% 200%;
        animation: gradientShift 15s ease infinite;
        color: #E0E0E0;
    }
    
    @keyframes gradientShift {
        0% { background-position: 0% 50%; }
        50% { background-position: 100% 50%; }
        100% { background-position: 0% 50%; }
    }
    
    /* Floating particles effect */
    .stApp::before {
        content: "";
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background-image: 
            radial-gradient(circle at 20% 80%, rgba(102, 126, 234, 0.03) 0%, transparent 50%),
            radial-gradient(circle at 80% 20%, rgba(118, 75, 162, 0.03) 0%, transparent 50%),
            radial-gradient(circle at 40% 40%, rgba(0, 217, 255, 0.02) 0%, transparent 50%);
        pointer-events: none;
        z-index: 0;
    }
    
    /* Sidebar styling with glass effect */
    [data-testid="stSidebar"] {
        background: linear-gradient(180deg, rgba(10, 10, 10, 0.95) 0%, rgba(26, 26, 26, 0.95) 100%);
        backdrop-filter: blur(10px);
        border-right: 1px solid rgba(102, 126, 234, 0.2);
    }
    
    /* Headers with glow effect */
    h1, h2, h3, h4, h5, h6 {
        color: #FFFFFF !important;
        font-weight: 600;
        text-shadow: 0 0 20px rgba(102, 126, 234, 0.3);
    }
    
    /* Animated Metric cards */
    [data-testid="stMetricValue"] {
        color: #00D9FF !important;
        font-size: 2rem !important;
        animation: metricPulse 2s ease-in-out infinite;
    }
    
    @keyframes metricPulse {
        0%, 100% { transform: scale(1); }
        50% { transform: scale(1.05); }
    }
    
    [data-testid="stMetricLabel"] {
        color: #B0B0B0 !important;
    }
    
    /* Enhanced Buttons with ripple effect */
    .stButton > button {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        border: none;
        border-radius: 8px;
        padding: 0.6rem 1.5rem;
        font-weight: 600;
        transition: all 0.3s ease;
        box-shadow: 0 4px 12px rgba(102, 126, 234, 0.3);
        position: relative;
        overflow: hidden;
    }
    
    .stButton > button:hover {
        transform: translateY(-2px);
        box-shadow: 0 6px 20px rgba(102, 126, 234, 0.5);
    }
    
    .stButton > button:active {
        transform: translateY(0px);
    }
    
    /* Text inputs with glow on focus */
    .stTextInput > div > div > input,
    .stTextArea > div > div > textarea {
        background-color: #1a1a1a;
        border: 1px solid #333333;
        border-radius: 8px;
        color: #E0E0E0;
        padding: 0.75rem;
        transition: all 0.3s ease;
    }
    
    .stTextInput > div > div > input:focus,
    .stTextArea > div > div > textarea:focus {
        border-color: #667eea;
        box-shadow: 0 0 0 2px rgba(102, 126, 234, 0.2), 0 0 20px rgba(102, 126, 234, 0.1);
    }
    
    /* Select boxes with better styling */
    .stSelectbox > div > div {
        background-color: #1a1a1a;
        border: 1px solid #333333;
        border-radius: 8px;
    }
    
    /* Enhanced Tabs with icons */
    .stTabs [data-baseweb="tab-list"] {
        gap: 8px;
        background-color: #0a0a0a;
        padding: 0.5rem;
        border-radius: 8px;
    }
    
    .stTabs [data-baseweb="tab"] {
        background-color: #1a1a1a;
        border: 1px solid #333333;
        border-radius: 6px;
        color: #B0B0B0;
        padding: 0.5rem 1rem;
        transition: all 0.3s ease;
    }
    
    .stTabs [data-baseweb="tab"]:hover {
        border-color: #667eea;
        transform: translateY(-2px);
    }
    
    .stTabs [aria-selected="true"] {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        border-color: #667eea;
        box-shadow: 0 4px 12px rgba(102, 126, 234, 0.3);
    }
    
    /* Enhanced Product cards with better animations */
    .product-card {
        background: linear-gradient(135deg, #1a1a1a 0%, #2a2a2a 100%);
        border: 1px solid #333333;
        border-radius: 12px;
        padding: 1.5rem;
        margin: 0.5rem 0;
        display: flex;
        gap: 1rem;
        align-items: start;
        transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        position: relative;
        overflow: hidden;
        min-height: 150px;
    }
    
    .product-details {
        flex: 1;
        min-width: 0;
    }
    
    .product-card::before {
        content: "";
        position: absolute;
        top: 0;
        left: -100%;
        width: 100%;
        height: 100%;
        background: linear-gradient(90deg, transparent, rgba(102, 126, 234, 0.1), transparent);
        transition: left 0.5s ease;
    }
    
    .product-card:hover::before {
        left: 100%;
    }
    
    .product-card:hover {
        border-color: #667eea;
        box-shadow: 0 8px 24px rgba(102, 126, 234, 0.2);
        transform: translateY(-4px) scale(1.01);
    }
    
    .product-image {
        width: 120px;
        height: 120px;
        object-fit: contain;
        border: 1px solid #333333;
        border-radius: 8px;
        padding: 0.5rem;
        background: #0a0a0a;
        transition: transform 0.3s ease;
        flex-shrink: 0;
        display: block;
    }
    
    .product-image img {
        width: 100%;
        height: 100%;
        object-fit: contain;
    }
    
    .product-card:hover .product-image {
        transform: scale(1.05) rotate(2deg);
    }
    
    .product-title {
        color: #00D9FF;
        font-weight: 500;
        font-size: 1rem;
        margin-bottom: 0.5rem;
        cursor: pointer;
        transition: color 0.3s ease;
    }
    
    .product-title:hover {
        color: #667eea;
        text-decoration: underline;
    }
    
    .product-price {
        color: #10b981;
        font-size: 1.25rem;
        font-weight: 600;
        margin: 0.5rem 0;
    }
    
    /* Enhanced method badges */
    .method-badge {
        display: inline-block;
        padding: 0.25rem 0.75rem;
        border-radius: 20px;
        font-size: 0.75rem;
        font-weight: 600;
        text-transform: uppercase;
        margin-right: 0.5rem;
        animation: badgeSlideIn 0.5s ease;
    }
    
    @keyframes badgeSlideIn {
        from {
            opacity: 0;
            transform: translateX(-20px);
        }
        to {
            opacity: 1;
            transform: translateX(0);
        }
    }
    
    .badge-keyword { 
        background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%); 
        color: white; 
        box-shadow: 0 2px 8px rgba(59, 130, 246, 0.3);
    }
    .badge-semantic { 
        background: linear-gradient(135deg, #10b981 0%, #059669 100%); 
        color: white; 
        box-shadow: 0 2px 8px rgba(16, 185, 129, 0.3);
    }
    .badge-fuzzy { 
        background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); 
        color: white; 
        box-shadow: 0 2px 8px rgba(245, 158, 11, 0.3);
    }
    .badge-hybrid { 
        background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%); 
        color: white; 
        box-shadow: 0 2px 8px rgba(139, 92, 246, 0.3);
    }
    
    /* Animated score bar */
    .score-bar {
        height: 8px;
        background: #2a2a2a;
        border-radius: 4px;
        overflow: hidden;
        margin: 0.5rem 0;
    }
    
    .score-fill {
        height: 100%;
        background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
        transition: width 1s cubic-bezier(0.4, 0, 0.2, 1);
        animation: scoreFill 1s ease-out;
    }
    
    @keyframes scoreFill {
        from { width: 0 !important; }
    }
    
    /* Enhanced persona card */
    .persona-card {
        background: linear-gradient(135deg, #1a1a1a 0%, #2a2a2a 100%);
        border-left: 4px solid #667eea;
        border-radius: 8px;
        padding: 1rem;
        margin: 1rem 0;
        transition: all 0.3s ease;
    }
    
    .persona-card:hover {
        transform: translateX(5px);
        box-shadow: 0 4px 12px rgba(102, 126, 234, 0.2);
    }
    
    /* Stats panel with glassmorphism */
    .stats-panel {
        background: linear-gradient(135deg, rgba(102, 126, 234, 0.9) 0%, rgba(118, 75, 162, 0.9) 100%);
        backdrop-filter: blur(10px);
        border-radius: 10px;
        padding: 1.5rem;
        color: white;
        margin: 1rem 0;
        box-shadow: 0 8px 32px rgba(102, 126, 234, 0.3);
        animation: statsSlideUp 0.5s ease-out;
    }
    
    @keyframes statsSlideUp {
        from {
            opacity: 0;
            transform: translateY(20px);
        }
        to {
            opacity: 1;
            transform: translateY(0);
        }
    }
    
    /* Skeleton loader for loading states */
    .skeleton {
        background: linear-gradient(90deg, #1a1a1a 25%, #2a2a2a 50%, #1a1a1a 75%);
        background-size: 200% 100%;
        animation: shimmer 1.5s infinite;
        border-radius: 8px;
    }
    
    @keyframes shimmer {
        0% { background-position: 200% 0; }
        100% { background-position: -200% 0; }
    }
    
    .skeleton-card {
        height: 150px;
        margin: 0.5rem 0;
    }
    
    .skeleton-text {
        height: 20px;
        margin: 0.5rem 0;
    }
    
    /* Toast notification */
    .toast {
        position: fixed;
        bottom: 20px;
        right: 20px;
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        padding: 1rem 1.5rem;
        border-radius: 8px;
        box-shadow: 0 4px 20px rgba(102, 126, 234, 0.4);
        animation: toastSlideIn 0.3s ease-out;
        z-index: 1000;
    }
    
    @keyframes toastSlideIn {
        from {
            opacity: 0;
            transform: translateX(100px);
        }
        to {
            opacity: 1;
            transform: translateX(0);
        }
    }
    
    /* Empty state with better styling */
    .empty-state {
        text-align: center;
        padding: 3rem 2rem;
        background: linear-gradient(135deg, #1a1a1a 0%, #2a2a2a 100%);
        border: 2px dashed #333333;
        border-radius: 12px;
        margin: 2rem 0;
    }
    
    .empty-state-icon {
        font-size: 4rem;
        margin-bottom: 1rem;
        opacity: 0.5;
    }
    
    /* Scrollbar styling */
    ::-webkit-scrollbar {
        width: 10px;
        height: 10px;
    }
    
    ::-webkit-scrollbar-track {
        background: #0a0a0a;
    }
    
    ::-webkit-scrollbar-thumb {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        border-radius: 5px;
    }
    
    ::-webkit-scrollbar-thumb:hover {
        background: linear-gradient(135deg, #764ba2 0%, #667eea 100%);
    }
    
    /* Divider with gradient */
    hr {
        border: none;
        height: 1px;
        background: linear-gradient(90deg, transparent, #667eea, transparent);
        margin: 2rem 0;
    }
    
    /* Expander with better animation */
    .streamlit-expanderHeader {
        background-color: #1a1a1a;
        border: 1px solid #333333;
        border-radius: 8px;
        color: #E0E0E0;
        transition: all 0.3s ease;
    }
    
    .streamlit-expanderHeader:hover {
        border-color: #667eea;
        background: linear-gradient(135deg, #1a1a1a 0%, #2a2a2a 100%);
    }
    
    /* Alert boxes with icons */
    .stAlert {
        background-color: #1a1a1a;
        border: 1px solid #333333;
        border-radius: 8px;
        padding: 1rem;
        animation: alertSlideIn 0.3s ease-out;
    }
    
    @keyframes alertSlideIn {
        from {
            opacity: 0;
            transform: translateY(-10px);
        }
        to {
            opacity: 1;
            transform: translateY(0);
        }
    }
</style>
""", unsafe_allow_html=True)

# ============================================================================
# CONFIGURATION & CONSTANTS (Same as original)
# ============================================================================

# Database configuration
DB_CONFIG = {
    'host': os.getenv('DB_HOST'),
    'port': os.getenv('DB_PORT', '5432'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'dbname': os.getenv('DB_NAME', 'workshop_db')
}

# MCP configuration
MCP_CONFIG = {
    'cluster_arn': os.getenv('DATABASE_CLUSTER_ARN'),
    'secret_arn': os.getenv('DATABASE_SECRET_ARN'),
    'database': os.getenv('DB_NAME', 'workshop_db'),
    'region': os.getenv('AWS_REGION', 'us-west-2')
}

AWS_REGION = os.getenv('AWS_REGION', 'us-west-2')

# Persona definitions
PERSONAS = {
    'customer': {
        'icon': '👤',
        'name': 'Customer',
        'description': 'Public content only',
        'access_levels': ['product_faq'],
        'color': '#3b82f6',
        'db_user': 'customer_user',
        'db_password': 'customer123'
    },
    'support_agent': {
        'icon': '🎧',
        'name': 'Support Agent',
        'description': 'Public + Internal content',
        'access_levels': ['product_faq', 'support_ticket', 'internal_note'],
        'color': '#10b981',
        'db_user': 'agent_user',
        'db_password': 'agent123'
    },
    'product_manager': {
        'icon': '👔',
        'name': 'Product Manager',
        'description': 'Full access including analytics',
        'access_levels': ['product_faq', 'support_ticket', 'internal_note', 'analytics'],
        'color': '#8b5cf6',
        'db_user': 'pm_user',
        'db_password': 'pm123'
    }
}

SAMPLE_QUERIES = {
    'customer': [
        'How do I set up my security camera?',
        'Troubleshooting bluetooth headphones',
        'Best robot vacuum for pet hair',
        'Smart doorbell features'
    ],
    'support_agent': [
        'Recent customer complaints about camera',
        'Common issues with vacuum cleaners',
        'Return requests for electronics',
        'Product defect patterns'
    ],
    'product_manager': [
        'Sales performance by category',
        'Customer satisfaction trends',
        'Product line profitability analysis',
        'Market segment analysis'
    ]
}

# ============================================================================
# HELPER FUNCTIONS FOR ALL ORIGINAL FUNCTIONALITY
# (Copy all the functions from original: get_bedrock_client, get_mcp_client, 
# get_db_connection, generate_embedding, all search functions, etc.)
# ============================================================================

@st.cache_resource
def get_bedrock_client():
    """Initialize Bedrock runtime client"""
    return boto3.client('bedrock-runtime', region_name=AWS_REGION)

bedrock_runtime = get_bedrock_client()

@st.cache_resource(ttl=60)
def get_mcp_client():
    """Initialize MCP client for Aurora PostgreSQL"""
    if not MCP_CONFIG['cluster_arn'] or not MCP_CONFIG['secret_arn']:
        logger.warning("MCP configuration incomplete.")
        return None
    
    import subprocess
    try:
        subprocess.run(
            ["uv", "tool", "install", "awslabs.postgres-mcp-server"],
            capture_output=True,
            timeout=30
        )
    except Exception as e:
        logger.warning(f"Could not pre-install MCP server: {e}")
    
    return MCPClient(lambda: stdio_client(
        StdioServerParameters(
            command="uv",
            args=[
                "tool", "run", "awslabs.postgres-mcp-server",
                "--resource_arn", MCP_CONFIG['cluster_arn'],
                "--secret_arn", MCP_CONFIG['secret_arn'],
                "--database", MCP_CONFIG['database'],
                "--region", MCP_CONFIG['region'],
                "--readonly", "True"
            ],
            env={
                "AWS_REGION": MCP_CONFIG['region'],
                "LOGURU_LEVEL": "SUCCESS",
                "LOGURU_FORMAT": "<level>{message}</level>",
                "POSTGRES_DEFAULT_SCHEMA": "bedrock_integration",
                "PYTHONUNBUFFERED": "1",
                "COLUMNS": "200"
            }
        )
    ))

def get_db_connection(persona: str = None):
    """Get database connection with optional persona-based credentials"""
    if persona and persona in PERSONAS:
        config = {
            **DB_CONFIG,
            'user': PERSONAS[persona]['db_user'],
            'password': PERSONAS[persona]['db_password']
        }
    else:
        config = DB_CONFIG
    
    conn = psycopg.connect(**config, autocommit=True)
    register_vector(conn)
    return conn

def generate_embedding(text: str, input_type: str = "search_query") -> Optional[List[float]]:
    """Generate Cohere embeddings via Bedrock"""
    if not text:
        return None
    
    try:
        body = json.dumps({
            "texts": [text],
            "input_type": input_type,
            "embedding_types": ["float"],
            "truncate": "END"
        })
        
        response = bedrock_runtime.invoke_model(
            modelId='cohere.embed-english-v3',
            body=body,
            accept='application/json',
            contentType='application/json'
        )
        
        response_body = json.loads(response['body'].read())
        if 'embeddings' in response_body and 'float' in response_body['embeddings']:
            return response_body['embeddings']['float'][0]
        elif 'embeddings' in response_body:
            return response_body['embeddings'][0]
    except Exception as e:
        logger.error(f"Embedding generation failed: {e}")
    
    return None

def keyword_search(query: str, limit: int = 10, persona: str = None) -> List[Dict]:
    """PostgreSQL Full-Text Search"""
    conn = get_db_connection(persona)
    
    try:
        results = conn.execute("""
            SELECT 
                p."productId",
                p.product_description,
                p.category_name,
                p.price,
                p.stars,
                p.reviews,
                p.imgurl,
                p.producturl,
                ts_rank_cd(
                    to_tsvector('english', p.product_description), 
                    plainto_tsquery('english', %s)
                ) as rank
            FROM bedrock_integration.product_catalog p
            WHERE to_tsvector('english', p.product_description) 
                  @@ plainto_tsquery('english', %s)
            ORDER BY rank DESC
            LIMIT %s;
        """, (query, query, limit)).fetchall()
        
        return [{
            'productId': r[0],
            'description': r[1][:200] + '...' if len(r[1]) > 200 else r[1],
            'category': r[2],
            'price': float(r[3]) if r[3] else 0,
            'stars': float(r[4]) if r[4] else 0,
            'reviews': int(r[5]) if r[5] else 0,
            'imgUrl': r[6],
            'productUrl': r[7],
            'score': float(r[8]) if r[8] else 0,
            'method': 'Keyword'
        } for r in results]
    finally:
        conn.close()

def fuzzy_search(query: str, limit: int = 10, persona: str = None) -> List[Dict]:
    """PostgreSQL Trigram Search"""
    conn = get_db_connection(persona)
    
    try:
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
                producturl,
                similarity(lower(product_description), lower(%s)) as sim
            FROM bedrock_integration.product_catalog
            WHERE lower(product_description) %% lower(%s)
            ORDER BY sim DESC
            LIMIT %s;
        """, (query, query, limit)).fetchall()
        
        return [{
            'productId': r[0],
            'description': r[1][:200] + '...' if len(r[1]) > 200 else r[1],
            'category': r[2],
            'price': float(r[3]) if r[3] else 0,
            'stars': float(r[4]) if r[4] else 0,
            'reviews': int(r[5]) if r[5] else 0,
            'imgUrl': r[6],
            'productUrl': r[7],
            'score': float(r[8]) if r[8] else 0,
            'method': 'Fuzzy'
        } for r in results]
    finally:
        conn.close()

def semantic_search(query: str, limit: int = 10, persona: str = None) -> List[Dict]:
    """Semantic Search using Cohere embeddings"""
    query_embedding = generate_embedding(query, "search_query")
    if not query_embedding:
        return []
    
    conn = get_db_connection(persona)
    
    try:
        results = conn.execute("""
            SELECT 
                "productId",
                product_description,
                category_name,
                price,
                stars,
                reviews,
                imgurl,
                producturl,
                1 - (embedding <=> %s::vector) as similarity
            FROM bedrock_integration.product_catalog
            WHERE embedding IS NOT NULL
            ORDER BY embedding <=> %s::vector
            LIMIT %s;
        """, (query_embedding, query_embedding, limit)).fetchall()
        
        return [{
            'productId': r[0],
            'description': r[1][:200] + '...' if len(r[1]) > 200 else r[1],
            'category': r[2],
            'price': float(r[3]) if r[3] else 0,
            'stars': float(r[4]) if r[4] else 0,
            'reviews': int(r[5]) if r[5] else 0,
            'imgUrl': r[6],
            'productUrl': r[7],
            'score': float(r[8]) if r[8] else 0,
            'method': 'Semantic'
        } for r in results]
    finally:
        conn.close()

def hybrid_search(
    query: str,
    semantic_weight: float = 0.7,
    keyword_weight: float = 0.3,
    limit: int = 10,
    persona: str = None
) -> List[Dict]:
    """Hybrid Search combining semantic and keyword"""
    total = semantic_weight + keyword_weight
    semantic_weight = semantic_weight / total
    keyword_weight = keyword_weight / total
    
    semantic_results = semantic_search(query, limit * 2, persona)
    keyword_results = keyword_search(query, limit * 2, persona)
    
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
    
    sorted_products = sorted(product_scores.items(), key=lambda x: x[1], reverse=True)[:limit]
    
    results = []
    for pid, score in sorted_products:
        product = product_data[pid].copy()
        product['score'] = score
        product['method'] = 'Hybrid'
        results.append(product)
    
    return results

def search_with_mcp_context(
    query: str,
    persona: str,
    time_window: Optional[str] = None,
    limit: int = 10
) -> List[Dict]:
    """Search with MCP context and RLS policies"""
    conn = get_db_connection(persona)
    
    try:
        query_embedding = generate_embedding(query, "search_query")
        
        time_filter = ""
        if time_window:
            if time_window == "24h":
                time_filter = "AND k.created_at >= NOW() - INTERVAL '24 hours'"
            elif time_window == "7d":
                time_filter = "AND k.created_at >= NOW() - INTERVAL '7 days'"
            elif time_window == "30d":
                time_filter = "AND k.created_at >= NOW() - INTERVAL '30 days'"
        
        if query_embedding:
            results = conn.execute(f"""
                SELECT 
                    k.id,
                    k.content,
                    k.content_type,
                    k.severity,
                    k.created_at,
                    k.product_id,
                    p.product_description,
                    p.price,
                    p.stars,
                    p.reviews,
                    p.imgurl,
                    CASE 
                        WHEN p.embedding IS NOT NULL THEN
                            1 - (p.embedding <=> %s::vector)
                        ELSE 0.5
                    END as semantic_score,
                    ts_rank(to_tsvector('english', k.content), plainto_tsquery('english', %s)) as text_score
                FROM bedrock_integration.knowledge_base k
                LEFT JOIN bedrock_integration.product_catalog p ON k.product_id = p."productId"
                WHERE (
                    k.content ILIKE %s
                    OR p.product_description ILIKE %s
                )
                {time_filter}
                ORDER BY semantic_score DESC, text_score DESC
                LIMIT %s;
            """, (query_embedding, query, f'%{query}%', f'%{query}%', limit)).fetchall()
        else:
            results = conn.execute(f"""
                SELECT 
                    k.id,
                    k.content,
                    k.content_type,
                    k.severity,
                    k.created_at,
                    k.product_id,
                    p.product_description,
                    p.price,
                    p.stars,
                    p.reviews,
                    p.imgurl,
                    0.5 as semantic_score,
                    ts_rank(to_tsvector('english', k.content), plainto_tsquery('english', %s)) as text_score
                FROM bedrock_integration.knowledge_base k
                LEFT JOIN bedrock_integration.product_catalog p ON k.product_id = p."productId"
                WHERE (
                    k.content ILIKE %s
                    OR p.product_description ILIKE %s
                )
                {time_filter}
                ORDER BY text_score DESC
                LIMIT %s;
            """, (query, f'%{query}%', f'%{query}%', limit)).fetchall()
        
        return [{
            'id': r[0],
            'content': r[1],
            'content_type': r[2],
            'severity': r[3],
            'created_at': r[4].isoformat() if r[4] else None,
            'product_id': r[5],
            'product_description': r[6],
            'price': float(r[7]) if r[7] else 0,
            'stars': float(r[8]) if r[8] else 0,
            'reviews': int(r[9]) if r[9] else 0,
            'imgUrl': r[10],
            'semantic_score': float(r[11]) if r[11] else 0,
            'text_score': float(r[12]) if r[12] else 0,
            'combined_score': (float(r[11]) if r[11] else 0) * 0.7 + (float(r[12]) if r[12] else 0) * 0.3
        } for r in results]
    finally:
        conn.close()

def strands_agent_search(
    query: str,
    persona: str = None,
    use_mcp: bool = True
) -> Dict[str, Any]:
    """Use Strands Agent with MCP tools"""
    if not use_mcp:
        return {
            'response': 'MCP not available. Using direct search.',
            'method': 'direct',
            'error': 'MCP client not configured'
        }
    
    mcp_client = get_mcp_client()
    
    if not mcp_client:
        return {
            'response': 'MCP client not configured.',
            'method': 'error',
            'error': 'Missing MCP configuration'
        }
    
    try:
        try:
            mcp_client.start()
        except:
            pass
        
        tools = mcp_client.list_tools_sync()
            
        # Calculate denied content types
        all_content_types = ['product_faq', 'support_ticket', 'internal_note', 'analytics']
        denied_types = [ct for ct in all_content_types if ct not in PERSONAS[persona]['access_levels']]
        
        agent = Agent(
            tools=tools,
            model="us.anthropic.claude-sonnet-4-20250514-v1:0",
            system_prompt=f"""You are a helpful database assistant with access to Aurora PostgreSQL through MCP tools.

IMPORTANT SCHEMA:
- Main: bedrock_integration.product_catalog ("productId", product_description, category_name, price, stars, reviews, imgurl, embedding)
- Knowledge: bedrock_integration.knowledge_base (id, product_id, content, content_type, persona_access VARCHAR[], severity, created_at)

Current persona: {persona} (simulating {PERSONAS[persona]['db_user']})

SECURITY RESTRICTIONS:
1. ONLY query knowledge_base table with this filter:
   WHERE '{persona}' = ANY(persona_access) OR persona_access IS NULL
2. ALLOWED content_type: {', '.join(PERSONAS[persona]['access_levels'])}
3. DENIED content_type: {', '.join(denied_types) if denied_types else 'none'}
4. If asked for denied content types, respond: "Access denied. {persona} role cannot access {', '.join(denied_types)} content."
5. Do NOT query product_catalog directly for analytics - only through authorized knowledge_base content

Provide responses only from your authorized knowledge_base content."""
        )
        
        start_time = time.time()
        response = agent(query)
        elapsed = time.time() - start_time
        
        # Extract response text
        if hasattr(response, 'message') and isinstance(response.message, dict):
            content = response.message.get('content', [])
            response_text = content[0].get('text', str(content)) if content else str(response)
        else:
            response_text = str(response)
        
        tools_used = []
        
        # Try multiple ways to extract tool calls
        # Method 1: Check response.tool_calls
        if hasattr(response, 'tool_calls') and response.tool_calls:
            for tool in response.tool_calls:
                tool_name = getattr(tool, 'name', str(tool))
                tools_used.append(tool_name)
                

        
        # Method 2: Check response.message for tool_use blocks
        if hasattr(response, 'message') and isinstance(response.message, dict):
            content = response.message.get('content', [])
            for block in content:
                if isinstance(block, dict):
                    if block.get('type') == 'tool_use':
                        tool_name = block.get('name', 'unknown')
                        tools_used.append(tool_name)
        
        # Method 3: Check response.state (it's a dict)
        if hasattr(response, 'state') and isinstance(response.state, dict):
            # Check for messages in state
            if 'messages' in response.state:
                messages = response.state['messages']
                for msg in messages:
                    if isinstance(msg, dict) and 'content' in msg:
                        content = msg['content']
                        if isinstance(content, list):
                            for block in content:
                                if isinstance(block, dict) and block.get('type') == 'tool_use':
                                    tool_name = block.get('name', 'unknown')
                                    tools_used.append(tool_name)

        
        available_tool_names = []
        if tools:
            for tool in tools:
                if isinstance(tool, str):
                    available_tool_names.append(tool)
                elif hasattr(tool, 'mcp_tool') and hasattr(tool.mcp_tool, 'name'):
                    available_tool_names.append(tool.mcp_tool.name)
                elif hasattr(tool, 'name'):
                    available_tool_names.append(tool.name)
        
        tools_used = list(dict.fromkeys(tools_used))
        
        return {
            'response': response_text,
            'method': 'strands_mcp',
            'elapsed_time': elapsed,
            'available_tools': available_tool_names,
            'error': None
        }
            
    except Exception as e:
        logger.error(f"Strands Agent error: {e}")
        return {
            'response': f"Agent execution failed: {str(e)}",
            'method': 'error',
            'error': str(e)
        }

def rerank_results(query: str, results: List[Dict], top_k: int = 5) -> List[Dict]:
    """Re-rank search results using Cohere"""
    if not results:
        return []
    
    try:
        documents = [r.get('description', r.get('content', '')) for r in results]
        
        body = json.dumps({
            "api_version": 2,
            "query": query,
            "documents": documents,
            "top_n": min(top_k, len(documents))
        })
        
        response = bedrock_runtime.invoke_model(
            modelId='cohere.rerank-v3-5:0',
            body=body,
            accept='application/json',
            contentType='application/json'
        )
        
        response_body = json.loads(response['body'].read())
        
        reranked = []
        for item in response_body.get('results', []):
            idx = item['index']
            result = results[idx].copy()
            result['rerank_score'] = item['relevance_score']
            reranked.append(result)
        
        return reranked
    except Exception as e:
        logger.error(f"Reranking failed: {e}")
        return results[:top_k]

# ============================================================================
# ENHANCED UI COMPONENTS
# ============================================================================

def render_skeleton_card():
    """Render a skeleton loading card"""
    st.markdown("""
    <div class="skeleton skeleton-card"></div>
    """, unsafe_allow_html=True)

def render_product_card(product: Dict, show_score: bool = True):
    """Render an enhanced product card with animations"""
    method = product.get('method', 'Unknown')
    badge_class = f"badge-{method.lower()}"
    
    score = product.get('rerank_score', product.get('score', 0))
    score_percent = min(score * 100, 100)
    
    product_url = product.get('productUrl', '')
    img_url = product.get('imgUrl', '')
    description = product.get('description', 'No description')
    
    # Make title and image clickable if URL exists
    if product_url:
        img_html = f'<a href="{product_url}" target="_blank"><img src="{img_url}" class="product-image" alt="Product" loading="lazy"></a>'
        title_html = f'<a href="{product_url}" target="_blank" class="product-title">{description}</a>'
    else:
        img_html = f'<img src="{img_url}" class="product-image" alt="Product" loading="lazy">'
        title_html = f'<div class="product-title">{description}</div>'
    
    st.markdown(f"""
    <div class="product-card">
        {img_html}
        <div class="product-details">
            <div>
                <span class="method-badge {badge_class}">{method}</span>
                {f'<span style="color: #B0B0B0; font-size: 0.75rem;">Score: {score:.3f}</span>' if show_score else ''}
            </div>
            {title_html}
            <div class="product-price">${product.get('price', 0):.2f}</div>
            <div class="product-meta">
                ⭐ {product.get('stars', 0):.1f} | 
                {product.get('reviews', 0):,} reviews | 
                {product.get('category', 'Unknown')}
            </div>
            {f'<div class="score-bar"><div class="score-fill" style="width: {score_percent}%"></div></div>' if show_score else ''}
        </div>
    </div>
    """, unsafe_allow_html=True)

def render_knowledge_card(item: Dict, show_persona: bool = False):
    """Render a knowledge base card with enhanced styling"""
    content_type = item.get('content_type', 'unknown') or 'unknown'
    severity = item.get('severity', 'low') or 'low'
    
    severity_colors = {
        'low': '#10b981',
        'medium': '#f59e0b',
        'high': '#ef4444',
        'critical': '#dc2626'
    }
    
    severity_descriptions = {
        'low': 'ℹ️ Informational - General FAQs and routine information',
        'medium': '⚠️ Moderate - Customer complaints requiring attention',
        'high': '🚨 Urgent - Product defects or warranty claims',
        'critical': '🔥 Critical - Widespread defects requiring immediate action'
    }
    
    content_type_display = content_type.replace('_', ' ').title()
    if content_type == 'product_faq':
        content_type_display = 'Product FAQ'
    elif content_type == 'support_ticket':
        content_type_display = 'Support Ticket'
    elif content_type == 'internal_note':
        content_type_display = 'Internal Note'
    
    col1, col2, col3 = st.columns([2, 2, 1])
    with col1:
        st.markdown(f"""
        <span class="method-badge" style="background: {severity_colors.get(severity, '#666')};">
            {(severity or 'low').upper()}
        </span>
        """, unsafe_allow_html=True)
    with col2:
        st.markdown(f'<span style="color: #B0B0B0; font-size: 0.875rem;">{content_type_display}</span>', unsafe_allow_html=True)
        st.caption(severity_descriptions.get(severity, ''))
    with col3:
        st.caption(item.get('created_at', 'N/A')[:10] if item.get('created_at') else 'N/A')
    
    st.markdown(f"**{item.get('content', 'No content')}**")
    
    if item.get('product_description'):
        st.markdown("---")
        st.caption("🔗 Related Product")
        st.markdown(f"{item.get('product_description', 'N/A')[:100]}...")
        st.caption(f"${item.get('price', 0):.2f} • ⭐ {item.get('stars', 0):.1f} • {item.get('reviews', 0):,} reviews")
    
    st.markdown("<br>", unsafe_allow_html=True)

def show_empty_state(message: str, icon: str = "🔍"):
    """Show an enhanced empty state"""
    st.markdown(f"""
    <div class="empty-state">
        <div class="empty-state-icon">{icon}</div>
        <h3 style="color: #E0E0E0; margin-bottom: 1rem;">{message}</h3>
        <p style="color: #B0B0B0;">Try adjusting your search query or filters</p>
    </div>
    """, unsafe_allow_html=True)

# ============================================================================
# SESSION STATE
# ============================================================================

if 'search_history' not in st.session_state:
    st.session_state.search_history = []
if 'performance_metrics' not in st.session_state:
    st.session_state.performance_metrics = []

# ============================================================================
# MAIN APPLICATION
# ============================================================================

# Enhanced Header with gradient effect
st.markdown("""
<div style="text-align: center; padding: 2rem 0;">
    <h1 style="font-size: 3rem; margin-bottom: 0.5rem; color: #FFFFFF; font-weight: 600;">
        Hybrid Search with Aurora PostgreSQL for MCP Retrieval
    </h1>
    <p style="color: #00D9FF; font-size: 1.1rem; margin-top: 0.5rem; font-weight: 500;">
        ⚡ Powering AI Agents with Enterprise-Grade Search
    </p>
    <p style="color: #FFFFFF; font-size: 1rem; margin-top: 0.5rem;">
        Aurora PostgreSQL • pgvector • Cohere • Model Context Protocol
    </p>
</div>
""", unsafe_allow_html=True)

# ============================================================================
# SIDEBAR WITH COLLAPSIBLE SECTIONS
# ============================================================================

with st.sidebar:
    st.markdown("## ⚙️ Configuration")
    
    # Persona selection with enhanced styling
    st.markdown("### 👤 Persona (RLS)")
    st.caption("⚠️ Used in MCP Context Search (Tab 1) only")
    selected_persona = st.selectbox(
        "Select Role",
        options=list(PERSONAS.keys()),
        format_func=lambda x: f"{PERSONAS[x]['icon']} {PERSONAS[x]['name']}",
        key='persona'
    )
    
    persona_info = PERSONAS[selected_persona]
    st.markdown(f"""
    <div class="persona-card">
        <div style="font-size: 2rem; margin-bottom: 0.5rem;">{persona_info['icon']}</div>
        <div style="font-weight: 600; margin-bottom: 0.5rem;">{persona_info['name']}</div>
        <div style="color: #B0B0B0; font-size: 0.875rem; margin-bottom: 1rem;">
            {persona_info['description']}
        </div>
        <div style="font-size: 0.75rem; color: #B0B0B0;">
            <strong>Access Levels:</strong><br>
            {'<br>'.join([f"✅ {level.replace('_', ' ').title().replace('Product Faq', 'Product FAQ')}" for level in persona_info['access_levels']])}
        </div>
    </div>
    """, unsafe_allow_html=True)
    
    st.markdown("---")
    
    # Database status with enhanced visuals
    st.markdown("### 📊 Database Status")
    
    if 'db_connected' not in st.session_state:
        st.session_state.db_connected = False
    
    try:
        conn = get_db_connection()
        
        result = conn.execute(
            "SELECT COUNT(*) FROM bedrock_integration.product_catalog"
        ).fetchone()
        product_count = result[0]
        
        result = conn.execute(
            "SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL"
        ).fetchone()
        embedding_count = result[0]
        
        result = conn.execute(
            "SELECT COUNT(*) FROM bedrock_integration.knowledge_base"
        ).fetchone()
        kb_count = result[0]
        
        conn.close()
        st.session_state.db_connected = True
        
        st.success("✅ Connected")
        
        # Show metrics with animation
        col1, col2 = st.columns(2)
        with col1:
            st.metric("Products", f"{product_count:,}")
            st.metric("KB Items", f"{kb_count:,}")
        with col2:
            st.metric("Embeddings", f"{embedding_count:,}")
            st.metric("Status", "🟢 Online")
        
    except Exception as e:
        st.session_state.db_connected = False
        st.error("❌ Connection Failed")
        if st.button("🔄 Retry Connection", key="retry_db"):
            st.rerun()
    
    st.markdown("---")
    
    # Hybrid weights with visual feedback
    with st.expander("⚖️ Hybrid Search Weights", expanded=False):
        semantic_weight = st.slider(
            "Semantic",
            min_value=0.0,
            max_value=1.0,
            value=0.7,
            step=0.1,
            key='semantic_weight'
        )
        
        keyword_weight = st.slider(
            "Keyword",
            min_value=0.0,
            max_value=1.0,
            value=0.3,
            step=0.1,
            key='keyword_weight'
        )
        
        total_weight = semantic_weight + keyword_weight
        if total_weight > 0:
            st.caption(f"📊 Normalized: {semantic_weight/total_weight:.1%} / {keyword_weight/total_weight:.1%}")
    
    # Search options in collapsible section
    with st.expander("🔧 Search Options", expanded=False):
        results_limit = st.slider("Results per method", 1, 20, 5, key='results_limit')
        
        time_filter = st.selectbox(
            "📅 Time Window",
            options=['All Time', 'Last 24 Hours', 'Last 7 Days', 'Last 30 Days'],
            key='time_filter'
        )
    
    # Advanced Index Information (400-level)
    with st.expander("🔧 Index Performance (Advanced)", expanded=False):
        st.caption("PostgreSQL index configuration and performance")
        
        try:
            conn = get_db_connection()
            
            # Get HNSW index info
            st.markdown("**Vector Index (HNSW):**")
            st.code("""CREATE INDEX ON product_catalog 
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);""")
            st.caption("• m=16: Max connections per layer (higher = better recall, more memory)")
            st.caption("• ef_construction=64: Build-time search depth (higher = better quality)")
            
            st.markdown("**Full-Text Index (GIN):**")
            st.code("""CREATE INDEX ON product_catalog 
USING gin(to_tsvector('english', product_description));""")
            st.caption("• GIN index for fast full-text search with stemming")
            
            st.markdown("**Trigram Index (GIN):**")
            st.code("""CREATE INDEX ON product_catalog 
USING gin(product_description gin_trgm_ops);""")
            st.caption("• Trigram index for fuzzy matching (similarity threshold: 0.1)")
            
            conn.close()
        except Exception as e:
            st.caption("Index information unavailable")
    
    # Search History with better formatting
    if st.session_state.search_history:
        st.markdown("---")
        with st.expander("🕒 Recent Searches", expanded=False):
            for i, search in enumerate(st.session_state.search_history[-5:][::-1]):
                if st.button(f"🔍 {search['query'][:25]}...", key=f"history_{i}"):
                    st.session_state.quick_search = search['query']
                    st.rerun()

# ============================================================================
# MAIN TABS
# ============================================================================

tab1, tab2, tab3, tab4 = st.tabs([
    "🎯 MCP Context Search",
    "🔍 Search Comparison",
    "🔬 Advanced Analysis (OPTIONAL)",
    "🎓 Key Takeaways"
])

# TAB 1: MCP Context Search
with tab2:
    st.info("ℹ️ **Lab 1 Reference**: These are the search methods you built in the Jupyter notebook. This tab demonstrates how they work together in a production application.")
    st.markdown("### Compare Search Methods Side-by-Side")
    st.caption("🚀 See how different search algorithms perform on the same query")
    
    with st.expander("🔒 About Row-Level Security (RLS)", expanded=False):
        st.markdown("""
        **What is RLS?**  
        Row-Level Security in PostgreSQL automatically filters results based on your persona.
        
        **Implementation Approaches:**
        - 🧠 **With Strands Agent**: Application-level filtering via system prompt (WHERE '{persona}' = ANY(persona_access))
          - Agent uses admin access via MCP Data API
          - Security enforced through AI agent instructions
          - Standard pattern for AI agents with database access
        - 🔒 **Without Strands Agent**: Database-level RLS with persona-specific users
          - Traditional PostgreSQL RLS policies
          - Enforced at database connection level
        
        **Why Application-Level for MCP?**
        - Data API uses IAM authentication (not database users)
        - MCP server connects as single admin user
        - AI agent intelligently applies filtering based on persona context
        """)
    
    with st.expander("🔍 Search Strategy (Direct Search)", expanded=False):
        st.markdown("""
        **When NOT using Strands Agent, the search uses:**
        
        1. **Hybrid Search Approach**:
           - Semantic search (70%): Vector similarity using Cohere embeddings
           - Keyword search (30%): PostgreSQL full-text search with ts_rank
        
        2. **Multi-Table Query**:
           - Searches `knowledge_base` table (FAQs, tickets, notes, analytics)
           - Joins with `product_catalog` for related product information
        
        3. **RLS Filtering**:
           - Automatically filters results based on your selected persona
           - Uses persona-specific database credentials
        
        4. **Time Window** (if selected):
           - Filters results by `created_at` timestamp
           - Options: 24 hours, 7 days, 30 days, or all time
        
        **Note:** This demonstrates traditional database access patterns with RLS enforcement.
        """)
    
    # Quick queries
    st.markdown("**⚡ Quick Try:**")
    mcp_quick_queries_by_persona = {
        'customer': [
            ("warranty", "✅ FAQ"),
            ("return policy", "✅ FAQ"),
            ("headphones", "✅ FAQ"),
            ("setup guide", "✅ FAQ"),
            ("support ticket", "🔒 Restricted")
        ],
        'support_agent': [
            ("connectivity", "✅ Tickets"),
            ("firmware", "✅ Tickets"),
            ("maintenance", "✅ Internal"),
            ("defect", "✅ Tickets"),
            ("analytics", "🔒 Restricted")
        ],
        'product_manager': [
            ("growth", "✅ Analytics"),
            ("sales", "✅ Analytics"),
            ("product launch", "✅ Internal"),
            ("warranty", "✅ All"),
            ("revenue", "✅ Analytics")
        ]
    }
    
    mcp_quick_queries = mcp_quick_queries_by_persona.get(selected_persona, [])
    mcp_quick_cols = st.columns(5)
    for idx, (q, status) in enumerate(mcp_quick_queries):
        with mcp_quick_cols[idx]:
            is_restricted = "🔒" in status
            if st.button(f"{'🔒' if is_restricted else '💡'} {q}", key=f"mcp_quick_{idx}", type="secondary" if is_restricted else "primary"):
                st.session_state.mcp_quick_search = q
                st.rerun()
    
    st.markdown("---")
    
    use_strands_agent = st.checkbox(
        "🧠 Use Strands Agent with MCP Tools",
        value=False,
        help="AI agent with MCP tools for intelligent database querying"
    )
    
    if use_strands_agent:
        st.caption("💡 MCP Agent uses admin access (via Data API) with application-level security filtering enforced through system prompt. This is the standard production pattern for AI agents - security is maintained through intelligent query construction rather than database-level RLS.")
    
    time_window_map = {
        'All Time': None,
        'Last 24 Hours': '24h',
        'Last 7 Days': '7d',
        'Last 30 Days': '30d'
    }
    
    # Initialize mcp_query if needed
    if 'mcp_query' not in st.session_state:
        st.session_state.mcp_query = ''
    
    # Handle quick search button clicks
    if 'mcp_quick_search' in st.session_state:
        st.session_state.mcp_query = st.session_state.mcp_quick_search
        del st.session_state.mcp_quick_search
    
    mcp_query = st.text_input(
        "Search Query",
        placeholder="Enter your search query or question...",
        key='mcp_query'
    )
    
    mcp_search_button = st.button("🔍 Search MCP Context", type="primary")
    
    if mcp_search_button and mcp_query:
        if use_strands_agent:
            st.markdown("#### 🧠 Strands Agent Response")
            
            with st.spinner("Agent is thinking..."):
                try:
                    start_time = time.time()
                    agent_result = strands_agent_search(mcp_query, selected_persona, use_mcp=True)
                    elapsed = time.time() - start_time
                    
                    if agent_result['error']:
                        st.error(f"❌ {agent_result['error']}")
                    else:
                        # Enhanced stats panel
                        st.markdown(f"""
                        <div class="stats-panel">
                            <div style="display: flex; justify-content: space-between; flex-wrap: wrap; gap: 1rem;">
                                <div>
                                    <div style="font-size: 1.5rem; font-weight: 600;">🧠 Strands Agent</div>
                                    <div style="font-size: 0.875rem; opacity: 0.9;">Claude Sonnet 4 + MCP</div>
                                </div>
                                <div>
                                    <div style="font-size: 1.5rem; font-weight: 600;">{elapsed*1000:.0f}ms</div>
                                    <div style="font-size: 0.875rem; opacity: 0.9;">Response Time</div>
                                </div>
                                <div>
                                    <div style="font-size: 1.5rem; font-weight: 600;">✅</div>
                                    <div style="font-size: 0.875rem; opacity: 0.9;">Database Query</div>
                                </div>
                            </div>
                        </div>
                        """, unsafe_allow_html=True)
                        
                        if agent_result.get('available_tools'):
                            with st.expander("🔗 MCP Tools Available", expanded=False):
                                for tool in agent_result['available_tools']:
                                    st.markdown(f"- `{tool}`")
                        
                        # Explain how the agent works
                        with st.expander("🔍 How It Works", expanded=False):
                            st.markdown(f"""
                            **Agent Architecture:**
                            
                            1. 🧠 **Strands Agent** receives your natural language query
                            2. 🤖 **Claude Sonnet 4** analyzes the query and decides which MCP tools to use
                            3. 🔧 **MCP Tools** execute SQL queries against Aurora PostgreSQL via Data API
                            4. 📊 **Agent synthesizes** the database results into a natural language response
                            
                            **Security Enforcement:**
                            - ✅ Allowed: {', '.join(PERSONAS[selected_persona]['access_levels'])}
                            - ❌ Denied: {', '.join([ct for ct in ['product_faq', 'support_ticket', 'internal_note', 'analytics'] if ct not in PERSONAS[selected_persona]['access_levels']]) or 'none'}
                            - 🔒 Filter: WHERE '{selected_persona}' = ANY(persona_access)
                            
                            **Note:** The Strands framework abstracts away tool call details, so SQL queries are not exposed in the response object. However, the agent successfully queries the database to provide accurate answers.
                            """)
                        
                        # Display response
                        st.markdown("**Response:**")
                        st.markdown(agent_result['response'])
                        
                        st.caption("💡 **Note:** This demo shows a single query response. The MCP architecture can be extended to support multi-turn conversations with chat history and follow-up questions (out of scope for this workshop).")
                        
                except Exception as e:
                    st.error(f"Agent error: {str(e)}")
        else:
            # Direct MCP search
            st.caption("💡 Using hybrid search (semantic + keyword) with RLS filtering. See 'Search Strategy' expander above for details.")
            with st.spinner(f"Searching as {selected_persona}..."):
                try:
                    start_time = time.time()
                    results = search_with_mcp_context(
                        mcp_query,
                        selected_persona,
                        time_window_map[time_filter],
                        results_limit * 2
                    )
                    elapsed = time.time() - start_time
                    
                    st.markdown(f"""
                    <div class="stats-panel">
                        <div style="display: flex; justify-content: space-between;">
                            <div>
                                <div style="font-size: 2rem; font-weight: 600;">{len(results)}</div>
                                <div style="font-size: 0.875rem;">Results Found</div>
                            </div>
                            <div>
                                <div style="font-size: 2rem; font-weight: 600;">{elapsed*1000:.0f}ms</div>
                                <div style="font-size: 0.875rem;">Response Time</div>
                            </div>
                            <div>
                                <div style="font-size: 2rem; font-weight: 600;">{PERSONAS[selected_persona]['icon']}</div>
                                <div style="font-size: 0.875rem;">{PERSONAS[selected_persona]['name']}</div>
                            </div>
                        </div>
                    </div>
                    """, unsafe_allow_html=True)
                    
                    if results:
                        by_type = {}
                        for r in results:
                            content_type = r.get('content_type', 'unknown')
                            if content_type not in by_type:
                                by_type[content_type] = []
                            by_type[content_type].append(r)
                        
                        for content_type, items in by_type.items():
                            with st.expander(f"📁 {content_type.replace('_', ' ').title()} ({len(items)})", expanded=True):
                                for item in items:
                                    render_knowledge_card(item, show_persona=True)
                    else:
                        show_empty_state(f"No results found for '{mcp_query}'", "🔍")
                        
                except Exception as e:
                    st.error(f"Search error: {str(e)}")


# TAB 2: Enhanced Search Comparison
with tab1:
    st.markdown("### MCP Context Search with RLS Policies")
    st.caption(f"Currently viewing as: **{PERSONAS[selected_persona]['name']}** {PERSONAS[selected_persona]['icon']}")
    
    st.markdown("---")
    
    # Quick action buttons with better layout
    st.markdown("**⚡ Quick Try:**")
    quick_cols = st.columns(5)
    quick_queries = ["wireless headphones", "security camera", "robot vacuum", "smart doorbell", "laptop"]
    for idx, q in enumerate(quick_queries):
        with quick_cols[idx]:
            if st.button(f"💡 {q}", key=f"quick_{idx}"):
                st.session_state.quick_search = q
                st.rerun()
    
    st.markdown("---")
    
    # Options row
    col1, col2 = st.columns([3, 1])
    with col1:
        use_rerank = st.checkbox(
            "✨ Use Cohere Rerank",
            value=False,
            key='use_rerank',
            help="Apply Cohere's reranking model for better relevance"
        )
    with col2:
        show_all = st.checkbox("📊 Show All", value=False, key='show_all')
    
    # Initialize comparison_query if needed
    if 'comparison_query' not in st.session_state:
        st.session_state.comparison_query = ''
    
    # Handle quick search button clicks
    if 'quick_search' in st.session_state:
        st.session_state.comparison_query = st.session_state.quick_search
        del st.session_state.quick_search
    
    search_query = st.text_input(
        "Search Query",
        placeholder="Enter your search query (e.g., wireless headphones, security camera...)",
        key='comparison_query'
    )
    
    search_button = st.button("🔍 Search All Methods", type="primary")
    
    with st.expander("💡 Understanding Search Scores", expanded=False):
        st.markdown("""
        **Why Semantic Search Often Has Higher Scores:**
        
        - **Semantic (0.0-1.0)**: Cosine similarity between embeddings - naturally produces scores closer to 1.0 for relevant matches
        - **Keyword (0.0-1.0)**: PostgreSQL ts_rank_cd scores - typically lower values even for good matches
        - **Fuzzy (0.0-1.0)**: Trigram similarity - requires very close character matches to score high
        - **Hybrid**: Weighted combination of Semantic + Keyword scores
        
        **Key Insight:** Higher scores don't always mean better results! Each method excels at different query types:
        - Use **Semantic** for conceptual/meaning-based searches
        - Use **Keyword** for exact term matching
        - Use **Fuzzy** for typo-tolerant searches
        - Use **Hybrid** for balanced results
        
        ---
        
        **💡 Understanding Hybrid Search Approaches:**
        
        **Challenge:** Different search methods produce vastly different score ranges (semantic: 0.7-1.0, keyword: 0.01-0.1), causing one method to dominate weighted combinations.
        
        **Solutions Demonstrated:**
        - ✅ **Hybrid (70/30)** - Weighted score fusion (simple but requires tuning)
        - ✅ **Hybrid-RRF** (Tab 3) - Rank-based fusion (robust, no normalization needed) ✨
        - ✅ **Cohere Rerank** (checkbox above) - ML-based re-ranking (most sophisticated)
        
        **Try it:** Enable Cohere Rerank or check out RRF in Tab 3!
        """)
    
    if search_button and search_query:
        # Create columns first
        cols = st.columns(4)
        
        # Perform actual search with spinner
        with st.spinner("🔍 Searching across all methods..."):
            results_data = {}
            methods = [
                ('Keyword', lambda q: keyword_search(q, results_limit, selected_persona)),
                ('Fuzzy', lambda q: fuzzy_search(q, results_limit, selected_persona)),
                ('Semantic', lambda q: semantic_search(q, results_limit, selected_persona)),
                ('Hybrid', lambda q: hybrid_search(q, semantic_weight, keyword_weight, results_limit, selected_persona))
            ]
        
        for idx, (method_name, method_func) in enumerate(methods):
            with cols[idx]:
                st.markdown(f"#### {method_name}")
                
                start_time = time.time()
                try:
                    results = method_func(search_query)
                    elapsed = time.time() - start_time
                    
                    if use_rerank and results:
                        rerank_start = time.time()
                        results = rerank_results(search_query, results, len(results))
                        rerank_time = time.time() - rerank_start
                        total_time = elapsed + rerank_time
                        st.caption(f"⏱️ {elapsed*1000:.0f}ms + {rerank_time*1000:.0f}ms rerank")
                    else:
                        total_time = elapsed
                        st.caption(f"⏱️ {elapsed*1000:.0f}ms")
                    
                    if results:
                        st.caption(f"✅ {len(results)} results")
                        
                        display_count = len(results) if show_all else 3
                        for result in results[:display_count]:
                            with st.container():
                                render_product_card(result, show_score=True)
                        
                        if f'results_{method_name}' not in st.session_state:
                            st.session_state[f'results_{method_name}'] = results
                    else:
                        show_empty_state("No results found", "🔍")
                    
                    results_data[method_name] = {
                        'count': len(results),
                        'time': total_time,
                        'avg_score': sum(r.get('score', 0) for r in results) / len(results) if results else 0
                    }
                    
                except Exception as e:
                    st.error(f"Error: {str(e)}")
        
        # Add to search history
        if search_query:
            st.session_state.search_history.append({
                'query': search_query,
                'timestamp': datetime.now().isoformat(),
                'persona': selected_persona
            })
            st.session_state.search_history = st.session_state.search_history[-10:]
        
        # Performance charts
        if results_data:
            st.markdown("---")
            st.markdown("### 📊 Performance Metrics")
            
            col1, col2 = st.columns(2)
            
            with col1:
                fig_time = go.Figure(data=[
                    go.Bar(
                        x=list(results_data.keys()),
                        y=[v['time'] * 1000 for v in results_data.values()],
                        marker_color=['#3b82f6', '#f59e0b', '#10b981', '#8b5cf6'],
                        text=[f"{v['time']*1000:.0f}ms" for v in results_data.values()],
                        textposition='auto',
                    )
                ])
                fig_time.update_layout(
                    title="Response Time",
                    yaxis_title="Milliseconds",
                    paper_bgcolor='#0a0a0a',
                    plot_bgcolor='#1a1a1a',
                    font=dict(color='#E0E0E0'),
                    height=300
                )
                st.plotly_chart(fig_time, use_container_width=True)
            
            with col2:
                fig_score = go.Figure(data=[
                    go.Bar(
                        x=list(results_data.keys()),
                        y=[v['avg_score'] for v in results_data.values()],
                        marker_color=['#3b82f6', '#f59e0b', '#10b981', '#8b5cf6'],
                        text=[f"{v['avg_score']:.3f}" for v in results_data.values()],
                        textposition='auto',
                    )
                ])
                fig_score.update_layout(
                    title="Average Relevance Score",
                    yaxis_title="Score",
                    paper_bgcolor='#0a0a0a',
                    plot_bgcolor='#1a1a1a',
                    font=dict(color='#E0E0E0'),
                    height=300
                )
                st.plotly_chart(fig_score, use_container_width=True)


# TAB 3: Advanced Analysis
with tab3:
    st.markdown("### 🔬 Advanced Analysis & Optimization")
    st.caption("🎯 Deep dive into query analysis, result overlap, and index configuration")
    
    st.info("ℹ️ **Note:** This tab is optional and not required for completing the workshop labs. It provides additional technical insights for those interested in production optimization and algorithm internals.")
    
    st.markdown("---")
    
    # Section 0: Reranking comparison (moved to top)
    st.markdown("## 🎯 Reranking: Cohere vs Reciprocal Rank Fusion (RRF)")
    st.caption("Understanding different reranking strategies for hybrid search")
    
    col1, col2 = st.columns(2)
    
    with col1:
        st.markdown("### Cohere Rerank (ML-Based)")
        st.markdown("""
        **Approach:**
        - Uses transformer-based neural network
        - Trained on query-document relevance pairs
        - Understands semantic relationships
        
        **Pros:**
        - ✅ Superior relevance accuracy
        - ✅ Handles complex queries well
        - ✅ Cross-lingual capabilities
        - ✅ Continuous model improvements
        
        **Cons:**
        - ❌ API latency (~50-200ms)
        - ❌ Cost per request
        - ❌ External dependency
        
        **Best For:**
        - Production search applications
        - User-facing search experiences
        - When accuracy is critical
        """)
    
    with col2:
        st.markdown("### Reciprocal Rank Fusion (RRF)")
        st.markdown("""
        **Approach:**
        - Mathematical formula: `score = Σ(1/(k + rank))`
        - Combines rankings from multiple methods
        - Pure PostgreSQL implementation
        
        **Pros:**
        - ✅ Zero latency (in-database)
        - ✅ No external dependencies
        - ✅ No additional cost
        - ✅ Deterministic results
        
        **Cons:**
        - ❌ Less accurate than ML models
        - ❌ Doesn't understand semantics
        - ❌ Fixed algorithm (no learning)
        
        **Best For:**
        - Cost-sensitive applications
        - Low-latency requirements
        - Internal tools/dashboards
        """)
    
    st.markdown("### PostgreSQL RRF Implementation Example")
    st.code("""
-- Reciprocal Rank Fusion in PostgreSQL
WITH semantic_results AS (
    SELECT product_id, ROW_NUMBER() OVER (ORDER BY embedding <=> query_vector) as rank
    FROM products
),
keyword_results AS (
    SELECT product_id, ROW_NUMBER() OVER (ORDER BY ts_rank DESC) as rank
    FROM products
)
SELECT 
    COALESCE(s.product_id, k.product_id) as product_id,
    (1.0 / (60 + COALESCE(s.rank, 1000))) + 
    (1.0 / (60 + COALESCE(k.rank, 1000))) as rrf_score
FROM semantic_results s
FULL OUTER JOIN keyword_results k USING (product_id)
ORDER BY rrf_score DESC
LIMIT 10;
""", language="sql")
    
    st.info("💡 **Recommendation:** Use Cohere Rerank for user-facing search (better accuracy), and RRF for internal tools or when latency/cost is a concern.")
    
    # Section 1: Query Analysis (Condensed)
    st.markdown("---")
    st.markdown("## 🧠 Query Analysis")
    
    if 'comparison_query' in st.session_state and st.session_state.comparison_query:
        search_query = st.session_state.comparison_query
        word_count = len(search_query.split())
        
        col1, col2, col3 = st.columns(3)
        with col1:
            st.metric("Words", word_count)
        with col2:
            st.metric("Characters", len(search_query))
        with col3:
            query_type = "Phrase" if word_count > 3 else "Keywords"
            st.metric("Type", query_type)
        
        # Recommended search method
        if word_count == 1:
            recommendation = "**Fuzzy Search** - Single word benefits from typo tolerance"
        elif word_count <= 3:
            recommendation = "**Keyword Search** - Short queries work well with full-text search"
        elif word_count > 3:
            recommendation = "**Semantic Search** - Long phrases capture intent with embeddings"
        else:
            recommendation = "**Hybrid Search** - Balanced approach for mixed queries"
        
        st.info(f"🎯 {recommendation}")
    else:
        st.info("👉 Run a search in Tab 2 to see query analysis")
    
    # Section 2: Result Overlap Analysis (Condensed)
    st.markdown("---")
    st.markdown("## 📊 Result Overlap Analysis")
    
    # Get product IDs from each method
    method_results = {}
    for method_name in ['Keyword', 'Fuzzy', 'Semantic', 'Hybrid']:
        if f'results_{method_name}' in st.session_state:
            method_results[method_name] = set(
                r['productId'] for r in st.session_state[f'results_{method_name}']
            )
    
    if len(method_results) >= 2:
        col1, col2, col3 = st.columns(3)
        
        with col1:
            st.metric("Total Unique", len(set().union(*method_results.values())))
        with col2:
            common_all = set.intersection(*method_results.values()) if method_results else set()
            st.metric("In All Methods", len(common_all))
        with col3:
            overlaps = []
            methods = list(method_results.keys())
            for i in range(len(methods)):
                for j in range(i+1, len(methods)):
                    overlap = len(method_results[methods[i]] & method_results[methods[j]])
                    overlaps.append(overlap)
            avg_overlap = sum(overlaps) / len(overlaps) if overlaps else 0
            st.metric("Avg Overlap", f"{avg_overlap:.1f}")
        
        st.info("💡 High overlap = methods agree on relevance. Low overlap = methods find different aspects.")
    else:
        st.info("👉 Run a search in Tab 2 to see overlap analysis")
    
    # Section 3: Index Configuration (Condensed)
    st.markdown("---")
    st.markdown("## 🔧 Index Configuration Quick Reference")
    
    col1, col2, col3 = st.columns(3)
    
    with col1:
        st.markdown("**Vector (HNSW)**")
        st.code("""CREATE INDEX 
USING hnsw (embedding 
vector_cosine_ops)
WITH (m=16, 
ef_construction=64);""")
        st.caption("m=16: connections/layer | ef=64: build quality")
    
    with col2:
        st.markdown("**Full-Text (GIN)**")
        st.code("""CREATE INDEX 
USING gin(
  to_tsvector(
    'english', 
    description)
);""")
        st.caption("Stemming + stop words + ranking")
    
    with col3:
        st.markdown("**Trigram (GIN)**")
        st.code("""CREATE INDEX 
USING gin(
  description 
  gin_trgm_ops
);""")
        st.caption("Fuzzy matching + typo tolerance")
    
    st.markdown("---")
    st.markdown("## 🚀 Quick Tuning Tips")
    
    st.markdown("""
    **Query Optimization:**
    - HNSW is 10-100x faster than IVFFlat for reads
    - Combine vector search with WHERE clauses for filtering
    - Use EXPLAIN ANALYZE to profile slow queries
    - Cache common query results (Redis/ElastiCache)
    
    **Index Maintenance:**
    - VACUUM ANALYZE after bulk updates
    - Monitor index bloat with pg_stat_user_indexes
    - Consider partitioning for >10M rows
    """)

# TAB 4: Key Takeaways
with tab4:
    st.markdown("### 🎓 Workshop Key Takeaways")
    st.caption("💡 Essential concepts and decision frameworks from DAT409")
    
    st.markdown("---")
    
    # Search Method Selection
    st.markdown("## 🎯 When to Use Each Search Method")
    
    col1, col2, col3 = st.columns(3)
    
    with col1:
        st.markdown("""
        ### 🧠 Semantic Search
        **Use When:**
        - Conceptual queries ("eco-friendly products")
        - Cross-language search
        - Synonym/paraphrase matching
        - User intent matters more than exact words
        
        **Avoid When:**
        - Exact SKU/model number lookup
        - Structured data queries
        - Low-latency requirements (<10ms)
        """)
    
    with col2:
        st.markdown("""
        ### 🔑 Keyword Search
        **Use When:**
        - Exact term matching ("iPhone 15 Pro")
        - Boolean queries (AND/OR/NOT)
        - Phrase matching ("wireless charging")
        - Structured field search
        
        **Avoid When:**
        - Typos are common
        - Conceptual/semantic queries
        - Multi-language content
        """)
    
    with col3:
        st.markdown("""
        ### 🎯 Fuzzy Search
        **Use When:**
        - Typo tolerance needed
        - Partial word matching
        - Auto-complete/suggestions
        - User input is unreliable
        
        **Avoid When:**
        - Precision is critical
        - Large result sets (slow)
        - Exact matching required
        """)
    
    st.info("💡 **Best Practice:** Use hybrid search (all three) for production applications, weighted by use case.")
    
    st.markdown("---")
    
    # Index Selection
    st.markdown("## 🛠️ HNSW vs IVFFlat Trade-offs")
    
    comparison_df = pd.DataFrame({
        "Aspect": ["Query Speed", "Build Time", "Memory Usage", "Recall", "Best For"],
        "HNSW": ["⚡ Faster (10-50ms)", "🐢 Slower (hours for 1M+)", "📈 Higher (2-3x data)", "🎯 95-99%", "Production, read-heavy"],
        "IVFFlat": ["🐢 Slower (50-200ms)", "⚡ Faster (minutes)", "📉 Lower (1.5x data)", "🎯 85-95%", "Development, write-heavy"]
    })
    
    st.dataframe(comparison_df, use_container_width=True, hide_index=True)
    
    st.markdown("""
    **Decision Framework:**
    - **HNSW**: Choose for user-facing search, >100K vectors, read-heavy workloads
    - **IVFFlat**: Choose for rapid prototyping, frequent updates, cost optimization
    - **Tuning**: HNSW `m=16, ef_construction=64` balances speed/accuracy for most cases
    """)
    
    st.markdown("---")
    
    # MCP Importance
    st.markdown("## 🤝 Why MCP Matters for AI Agents")
    
    mcp_col1, mcp_col2 = st.columns(2)
    
    with mcp_col1:
        st.markdown("""
        ### Traditional RAG Limitations
        - ❌ Fixed retrieval patterns
        - ❌ No query-time filtering
        - ❌ Limited context awareness
        - ❌ Static embeddings only
        - ❌ No structured data access
        """)
    
    with mcp_col2:
        st.markdown("""
        ### MCP Advantages
        - ✅ Dynamic tool selection
        - ✅ SQL-level filtering (time, persona)
        - ✅ Multi-step reasoning
        - ✅ Hybrid retrieval (vector + keyword)
        - ✅ Direct database queries
        """)
    
    st.success("""
    🎯 **Key Insight:** MCP enables agents to intelligently choose retrieval strategies based on query type, 
    rather than forcing all queries through the same embedding pipeline.
    """)
    
    st.markdown("---")
    
    # RLS Patterns
    st.markdown("## 🔒 RLS Patterns for Multi-Tenant AI Apps")
    
    st.markdown("""
    ### Application-Level Security Pattern (This Workshop)
    
    ```python
    # Agent uses admin credentials + RLS filtering in system prompt
    system_prompt = f\"\"\"Only query WHERE '{persona}' = ANY(persona_access)\"\"\"
    ```
    
    **Why This Pattern:**
    - ✅ Standard for AI agents (single connection pool)
    - ✅ Enables cross-tenant analytics
    - ✅ Works with RDS Data API (no VPC)
    - ✅ Flexible security rules in code
    
    **Trade-offs:**
    - ⚠️ Agent must be trusted (has admin access)
    - ⚠️ Security logic in application layer
    - ⚠️ Requires careful prompt engineering
    """)
    
    st.markdown("""
    ### Alternative: Database-Level RLS (Traditional)
    
    ```sql
    -- Each user gets their own database role
    CREATE POLICY tenant_isolation ON knowledge_base
        USING (tenant_id = current_setting('app.tenant_id'));
    ```
    
    **When to Use:**
    - ✅ Strict compliance requirements (HIPAA, PCI)
    - ✅ Direct user database access
    - ✅ No trusted middleware layer
    
    **Trade-offs:**
    - ⚠️ Connection pooling complexity
    - ⚠️ Doesn't work with Data API
    - ⚠️ Limited cross-tenant queries
    """)
    
    st.markdown("---")
    
    # Production Checklist
    st.markdown("## ✅ Production Deployment Checklist")
    
    checklist_col1, checklist_col2 = st.columns(2)
    
    with checklist_col1:
        st.markdown("""
        ### Performance
        - [ ] HNSW indexes on all vector columns
        - [ ] GIN indexes on tsvector columns
        - [ ] Connection pooling (PgBouncer/RDS Proxy)
        - [ ] Query result caching (Redis/ElastiCache)
        - [ ] Monitor with Performance Insights
        """)
    
    with checklist_col2:
        st.markdown("""
        ### Security
        - [ ] RLS policies for all tables
        - [ ] IAM authentication for Data API
        - [ ] Secrets Manager for credentials
        - [ ] Audit logging enabled
        - [ ] Network isolation (VPC/Security Groups)
        """)
    
    st.markdown("---")
    
    # Next Steps
    st.markdown("## 🚀 Next Steps")
    
    st.markdown("""
    **Extend This Workshop:**
    1. Add more search methods (BM25, ColBERT)
    2. Implement query caching with Redis
    3. Add A/B testing for reranking strategies
    4. Integrate with Amazon Kendra for document search
    5. Build custom MCP tools for your domain
    
    **Resources:**
    - [pgvector GitHub](https://github.com/pgvector/pgvector)
    - [MCP Specification](https://modelcontextprotocol.io/)
    - [Aurora Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.BestPractices.html)
    - [Cohere Rerank API](https://docs.cohere.com/docs/rerank)
    """)

# Footer
st.markdown("---")
st.markdown("""
<div style="text-align: center; color: #FFFFFF; padding: 2rem 0;">
    <p style="font-size: 1.1rem;">DAT409: Hybrid Search with Aurora PostgreSQL</p>
    <p style="font-size: 0.875rem;">Built with Streamlit, pgvector, Cohere, and MCP</p>
    <p style="font-size: 0.75rem; margin-top: 1rem;">Amazon Web Services • re:Invent 2025</p>
</div>
""", unsafe_allow_html=True)