"""
DAT409: Aurora PostgreSQL Hybrid Search with MCP
Enhanced Streamlit Application - 400 Level

Features:
- Weighted Hybrid Search (Keyword + Semantic + Fuzzy)
- Persona-Based Access (RLS Policies)
- Time-Based Filtering
- Cohere Reranking
- MCP Context Protocol Integration
- Interactive Search Comparison
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
# Suppress INFO logs from MCP server, only show WARNING and above
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
# DARK THEME STYLING
# ============================================================================

st.markdown("""
<style>
    /* Main background - Pure black */
    .stApp {
        background-color: #000000;
        color: #E0E0E0;
    }
    
    /* Sidebar styling */
    [data-testid="stSidebar"] {
        background: linear-gradient(180deg, #0a0a0a 0%, #1a1a1a 100%);
        border-right: 1px solid #2a2a2a;
    }
    
    /* Headers */
    h1, h2, h3, h4, h5, h6 {
        color: #FFFFFF !important;
        font-weight: 600;
    }
    
    /* Metric cards */
    [data-testid="stMetricValue"] {
        color: #00D9FF !important;
        font-size: 2rem !important;
    }
    
    [data-testid="stMetricLabel"] {
        color: #B0B0B0 !important;
    }
    
    /* Buttons */
    .stButton > button {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        border: none;
        border-radius: 8px;
        padding: 0.6rem 1.5rem;
        font-weight: 600;
        transition: all 0.3s ease;
        box-shadow: 0 4px 12px rgba(102, 126, 234, 0.3);
    }
    
    .stButton > button:hover {
        transform: translateY(-2px);
        box-shadow: 0 6px 20px rgba(102, 126, 234, 0.5);
    }
    
    /* Text inputs and text areas */
    .stTextInput > div > div > input,
    .stTextArea > div > div > textarea {
        background-color: #1a1a1a;
        border: 1px solid #333333;
        border-radius: 8px;
        color: #E0E0E0;
        padding: 0.75rem;
    }
    
    .stTextInput > div > div > input:focus,
    .stTextArea > div > div > textarea:focus {
        border-color: #667eea;
        box-shadow: 0 0 0 2px rgba(102, 126, 234, 0.2);
    }
    
    /* Select boxes */
    .stSelectbox > div > div {
        background-color: #1a1a1a;
        border: 1px solid #333333;
        border-radius: 8px;
    }
    
    /* Sliders */
    .stSlider > div > div > div > div {
        background-color: #667eea;
    }
    
    /* Tabs */
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
    }
    
    .stTabs [aria-selected="true"] {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        border-color: #667eea;
    }
    
    /* Expanders */
    .streamlit-expanderHeader {
        background-color: #1a1a1a;
        border: 1px solid #333333;
        border-radius: 8px;
        color: #E0E0E0;
    }
    
    /* Info/Warning/Success boxes */
    .stAlert {
        background-color: #1a1a1a;
        border: 1px solid #333333;
        border-radius: 8px;
        padding: 1rem;
    }
    
    /* Code blocks */
    .stCodeBlock {
        background-color: #0a0a0a;
        border: 1px solid #333333;
        border-radius: 8px;
    }
    
    /* Result cards */
    .result-card {
        background: linear-gradient(135deg, #1a1a1a 0%, #2a2a2a 100%);
        border: 1px solid #333333;
        border-radius: 12px;
        padding: 1.5rem;
        margin: 1rem 0;
        transition: all 0.3s ease;
    }
    
    .result-card:hover {
        border-color: #667eea;
        box-shadow: 0 8px 24px rgba(102, 126, 234, 0.2);
        transform: translateY(-2px);
    }
    
    /* Method badges */
    .method-badge {
        display: inline-block;
        padding: 0.25rem 0.75rem;
        border-radius: 20px;
        font-size: 0.75rem;
        font-weight: 600;
        text-transform: uppercase;
        margin-right: 0.5rem;
    }
    
    .badge-keyword { background: #3b82f6; color: white; }
    .badge-semantic { background: #10b981; color: white; }
    .badge-fuzzy { background: #f59e0b; color: white; }
    .badge-hybrid { background: #8b5cf6; color: white; }
    
    /* Score bar */
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
        transition: width 0.5s ease;
    }
    
    /* Product cards */
    .product-card {
        background: #1a1a1a;
        border: 1px solid #333333;
        border-radius: 10px;
        padding: 1rem;
        margin: 0.5rem 0;
        display: flex;
        gap: 1rem;
        align-items: start;
    }
    
    .product-image {
        width: 120px;
        height: 120px;
        object-fit: contain;
        border: 1px solid #333333;
        border-radius: 8px;
        padding: 0.5rem;
        background: #0a0a0a;
    }
    
    .product-details {
        flex: 1;
    }
    
    .product-title {
        color: #00D9FF;
        font-weight: 500;
        font-size: 1rem;
        margin-bottom: 0.5rem;
        cursor: pointer;
    }
    
    .product-title:hover {
        text-decoration: underline;
    }
    
    .product-price {
        color: #10b981;
        font-size: 1.25rem;
        font-weight: 600;
        margin: 0.5rem 0;
    }
    
    .product-meta {
        color: #B0B0B0;
        font-size: 0.875rem;
    }
    
    /* Persona indicator */
    .persona-card {
        background: linear-gradient(135deg, #1a1a1a 0%, #2a2a2a 100%);
        border-left: 4px solid #667eea;
        border-radius: 8px;
        padding: 1rem;
        margin: 1rem 0;
    }
    
    /* Comparison grid */
    .comparison-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
        gap: 1rem;
        margin: 1rem 0;
    }
    
    /* Stats panel */
    .stats-panel {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        border-radius: 10px;
        padding: 1.5rem;
        color: white;
        margin: 1rem 0;
    }
    
    /* Markdown styling */
    .stMarkdown {
        color: #E0E0E0;
    }
    
    /* Divider */
    hr {
        border-color: #333333;
        margin: 2rem 0;
    }
</style>
""", unsafe_allow_html=True)

# ============================================================================
# CONFIGURATION & CONSTANTS
# ============================================================================

# Database configuration
DB_CONFIG = {
    'host': os.getenv('DB_HOST'),
    'port': os.getenv('DB_PORT', '5432'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'dbname': os.getenv('DB_NAME', 'workshop_db')
}

# MCP configuration for Aurora PostgreSQL
MCP_CONFIG = {
    'cluster_arn': os.getenv('DATABASE_CLUSTER_ARN'),
    'secret_arn': os.getenv('DATABASE_SECRET_ARN'),
    'database': os.getenv('DB_NAME', 'workshop_db'),
    'region': os.getenv('AWS_REGION', 'us-west-2')
}

AWS_REGION = os.getenv('AWS_REGION', 'us-west-2')

# Persona definitions with access levels
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

# Sample queries for each persona
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
# BEDROCK CLIENT
# ============================================================================

@st.cache_resource
def get_bedrock_client():
    """Initialize Bedrock runtime client"""
    return boto3.client('bedrock-runtime', region_name=AWS_REGION)

bedrock_runtime = get_bedrock_client()

# ============================================================================
# MCP CLIENT
# ============================================================================

@st.cache_resource(ttl=60)
def get_mcp_client():
    """Initialize MCP client for Aurora PostgreSQL"""
    if not MCP_CONFIG['cluster_arn'] or not MCP_CONFIG['secret_arn']:
        logger.warning("MCP configuration incomplete. Cluster ARN and Secret ARN required.")
        return None
    
    # Use uv run instead of uvx to avoid reinstalling packages every time
    # First ensure the package is installed globally
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
                "POSTGRES_DEFAULT_SCHEMA": "bedrock_integration",
                "PYTHONUNBUFFERED": "1"
            }
        )
    ))

# ============================================================================
# DATABASE FUNCTIONS
# ============================================================================

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

# ============================================================================
# EMBEDDING GENERATION
# ============================================================================

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

# ============================================================================
# SEARCH FUNCTIONS
# ============================================================================

def keyword_search(query: str, limit: int = 10, persona: str = None) -> List[Dict]:
    """PostgreSQL Full-Text Search using TSVector"""
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
            'score': float(r[7]) if r[7] else 0,
            'method': 'Keyword'
        } for r in results]
    finally:
        conn.close()

def fuzzy_search(query: str, limit: int = 10, persona: str = None) -> List[Dict]:
    """PostgreSQL Trigram Search for typo tolerance"""
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
            'score': float(r[7]) if r[7] else 0,
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
            'score': float(r[7]) if r[7] else 0,
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
    """Hybrid Search combining semantic and keyword approaches"""
    # Normalize weights
    total = semantic_weight + keyword_weight
    semantic_weight = semantic_weight / total
    keyword_weight = keyword_weight / total
    
    # Get results from both methods
    semantic_results = semantic_search(query, limit * 2, persona)
    keyword_results = keyword_search(query, limit * 2, persona)
    
    # Combine and score
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

def search_with_mcp_context(
    query: str,
    persona: str,
    time_window: Optional[str] = None,
    limit: int = 10
) -> List[Dict]:
    """Search with MCP context and RLS policies"""
    conn = get_db_connection(persona)
    
    try:
        # Get query embedding
        query_embedding = generate_embedding(query, "search_query")
        
        # Build time filter
        time_filter = ""
        if time_window:
            if time_window == "24h":
                time_filter = "AND k.created_at >= NOW() - INTERVAL '24 hours'"
            elif time_window == "7d":
                time_filter = "AND k.created_at >= NOW() - INTERVAL '7 days'"
            elif time_window == "30d":
                time_filter = "AND k.created_at >= NOW() - INTERVAL '30 days'"
        
        # Execute search with RLS automatically applied
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
                FROM knowledge_base k
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
                FROM knowledge_base k
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
    """
    Use Strands Agent with MCP tools for intelligent database querying.
    
    This demonstrates the Model Context Protocol integration where the agent
    can intelligently use PostgreSQL tools to answer questions.
    
    Args:
        query: Natural language question
        persona: Optional persona for RLS (not used with MCP Data API)
        use_mcp: Whether to use MCP or fall back to direct queries
    
    Returns:
        Dict with agent response and metadata
    """
    if not use_mcp:
        # Fallback to direct search
        return {
            'response': 'MCP not available. Using direct search.',
            'method': 'direct',
            'tools_used': [],
            'error': 'MCP client not configured'
        }
    
    mcp_client = get_mcp_client()
    
    if not mcp_client:
        return {
            'response': 'MCP client not configured. Please set DATABASE_CLUSTER_ARN and DATABASE_SECRET_ARN.',
            'method': 'error',
            'tools_used': [],
            'error': 'Missing MCP configuration'
        }
    
    try:
        # Start MCP client if not already started
        try:
            mcp_client.start()
        except:
            pass  # Already started
        
        # Get available tools from MCP server
        tools = mcp_client.list_tools_sync()
            
        # Create agent with MCP tools and schema context
        agent = Agent(
            tools=tools,
            model="us.anthropic.claude-sonnet-4-20250514-v1:0",
            system_prompt=f"""
You are a helpful database assistant with access to an Aurora PostgreSQL database through MCP tools.

IMPORTANT DATABASE SCHEMA:
- Main product table: bedrock_integration.product_catalog
  Columns: "productId", product_description, category_name, price, stars, reviews, imgurl, embedding
- Knowledge base table: public.knowledge_base
  Columns: id, product_id, content, content_type, access_level, severity, created_at

When querying:
1. ALWAYS use bedrock_integration.product_catalog for product data (NOT "products")
2. Use public.knowledge_base for support tickets, FAQs, and internal notes
3. Quote "productId" column name (case-sensitive)
4. Current persona: {persona}

Provide clear, helpful responses based on the database query results.
"""
        )
        
        # Execute query with agent
        start_time = time.time()
        response = agent(query)
        elapsed = time.time() - start_time
        
        # Extract response content
        if hasattr(response, 'message') and isinstance(response.message, dict):
            content = response.message.get('content', [])
            response_text = content[0].get('text', str(content)) if content else str(response)
        else:
            response_text = str(response)
        
        # Get tool usage info if available
        tools_used = []
        if hasattr(response, 'tool_calls'):
            tools_used = [getattr(tool, 'name', str(tool)) for tool in response.tool_calls]
        
        # Extract tool names from MCPAgentTool wrappers
        available_tool_names = []
        if tools:
            for tool in tools:
                # Try multiple ways to get the tool name
                if isinstance(tool, str):
                    available_tool_names.append(tool)
                elif hasattr(tool, 'mcp_tool') and hasattr(tool.mcp_tool, 'name'):
                    # MCPAgentTool wrapper - get the actual MCP tool name
                    available_tool_names.append(tool.mcp_tool.name)
                elif hasattr(tool, 'name'):
                    available_tool_names.append(tool.name)
                elif hasattr(tool, '__name__'):
                    available_tool_names.append(tool.__name__)
                else:
                    # Skip if we can't extract a meaningful name
                    pass
        
        return {
            'response': response_text,
            'method': 'strands_mcp',
            'tools_used': tools_used,
            'elapsed_time': elapsed,
            'available_tools': available_tool_names,
            'error': None
        }
            
    except Exception as e:
        logger.error(f"Strands Agent error: {e}")
        return {
            'response': f"Agent execution failed: {str(e)}",
            'method': 'error',
            'tools_used': [],
            'error': str(e)
        }

# ============================================================================
# COHERE RERANK
# ============================================================================

def rerank_results(query: str, results: List[Dict], top_k: int = 5) -> List[Dict]:
    """Re-rank search results using Cohere Rerank model"""
    if not results:
        return []
    
    try:
        documents = [r.get('description', r.get('content', '')) for r in results]
        
        body = json.dumps({
            "query": query,
            "documents": documents,
            "top_n": min(top_k, len(documents)),
            "return_documents": False
        })
        
        response = bedrock_runtime.invoke_model(
            modelId='cohere.rerank-v3-5:0',
            body=body,
            accept='application/json',
            contentType='application/json'
        )
        
        response_body = json.loads(response['body'].read())
        
        # Reorder results based on rerank scores
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
# UI COMPONENTS
# ============================================================================

def render_product_card(product: Dict, show_score: bool = True):
    """Render a product result card"""
    method = product.get('method', 'Unknown')
    badge_class = f"badge-{method.lower()}"
    
    score = product.get('rerank_score', product.get('score', 0))
    score_percent = min(score * 100, 100)
    
    st.markdown(f"""
    <div class="product-card">
        <img src="{product.get('imgUrl', '')}" class="product-image" alt="Product">
        <div class="product-details">
            <div>
                <span class="method-badge {badge_class}">{method}</span>
                {f'<span style="color: #B0B0B0; font-size: 0.75rem;">Score: {score:.3f}</span>' if show_score else ''}
            </div>
            <div class="product-title">{product.get('description', 'No description')}</div>
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
    """Render a knowledge base item card"""
    content_type = item.get('content_type', 'unknown')
    severity = item.get('severity', 'low')
    
    severity_colors = {
        'low': '#10b981',
        'medium': '#f59e0b',
        'high': '#ef4444',
        'critical': '#dc2626'
    }
    
    severity_descriptions = {
        'low': 'Informational - General FAQs and routine information',
        'medium': 'Moderate - Customer complaints or issues requiring attention',
        'high': 'Urgent - Product defects or warranty claims',
        'critical': 'Critical - Widespread defects requiring immediate action'
    }
    
    # Format content type for display
    content_type_display = content_type.replace('_', ' ').title()
    if content_type == 'product_faq':
        content_type_display = 'Product FAQ'
    elif content_type == 'support_ticket':
        content_type_display = 'Support Ticket'
    elif content_type == 'internal_note':
        content_type_display = 'Internal Note'
    
    # Render header with severity badge
    col1, col2, col3 = st.columns([2, 2, 1])
    with col1:
        st.markdown(f"""
        <span class="method-badge" style="background: {severity_colors.get(severity, '#666')};">
            {severity.upper()}
        </span>
        """, unsafe_allow_html=True)
    with col2:
        st.markdown(f'<span style="color: #B0B0B0; font-size: 0.875rem;">{content_type_display}</span>', unsafe_allow_html=True)
        st.caption(f"ℹ️ {severity_descriptions.get(severity, '')}")
    with col3:
        st.caption(item.get('created_at', 'N/A')[:10] if item.get('created_at') else 'N/A')
    
    # Render content
    st.markdown(f"**{item.get('content', 'No content')}**")
    
    # Render related product if available
    if item.get('product_description'):
        st.markdown("---")
        st.caption("🔗 Related Product")
        st.markdown(f"{item.get('product_description', 'N/A')[:100]}...")
        st.caption(f"${item.get('price', 0):.2f} • ⭐ {item.get('stars', 0):.1f} • {item.get('reviews', 0):,} reviews")
    
    st.markdown("<br>", unsafe_allow_html=True)

# ============================================================================
# SESSION STATE INITIALIZATION
# ============================================================================

if 'search_history' not in st.session_state:
    st.session_state.search_history = []

if 'performance_metrics' not in st.session_state:
    st.session_state.performance_metrics = []

# ============================================================================
# MAIN APPLICATION
# ============================================================================

# Header
st.markdown("""
<div style="text-align: center; padding: 2rem 0;">
    <h1 style="font-size: 2.5rem; margin-bottom: 0.5rem;">🔍 DAT409 | Implement hybrid search with Aurora PostgreSQL for MCP retrieval</h1>
    <p style="color: #B0B0B0; font-size: 1.1rem;">
        Aurora PostgreSQL • pgvector • Cohere • Model Context Protocol
    </p>
</div>
""", unsafe_allow_html=True)

# ============================================================================
# SIDEBAR
# ============================================================================

with st.sidebar:
    st.markdown("## ⚙️ Configuration")
    
    # Persona selection
    st.markdown("### 👤 Persona (RLS)")
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
            {'<br>'.join([f"✅ {level.replace('_', ' ').title().replace('Product Faq', 'Product FAQ').replace('Internal Note', 'Internal Notes').replace('Support Ticket', 'Support Tickets')}" for level in persona_info['access_levels']])}
        </div>
    </div>
    """, unsafe_allow_html=True)
    
    st.info("""
    **ℹ️ Row-Level Security (RLS)**  
    Database policies automatically filter results based on your selected persona. Customers see only public FAQs, Support Agents see tickets and internal notes, Product Managers see everything including analytics.
    """)
    
    st.markdown("---")
    
    # Hybrid search weights
    st.markdown("### ⚖️ Hybrid Weights")
    
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
        st.caption(f"Normalized: {semantic_weight/total_weight:.1%} / {keyword_weight/total_weight:.1%}")
    
    st.markdown("---")
    
    # Search options
    st.markdown("### 🔧 Options")
    
    results_limit = st.slider("Results per method", 1, 20, 5, key='results_limit')
    
    st.markdown("---")
    
    # Database status with retry
    st.markdown("### 📊 Database")
    if 'db_connected' not in st.session_state:
        st.session_state.db_connected = False
    
    try:
        conn = get_db_connection()
        
        # Product count
        result = conn.execute(
            "SELECT COUNT(*) FROM bedrock_integration.product_catalog"
        ).fetchone()
        product_count = result[0]
        
        # Embedding count
        result = conn.execute(
            "SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL"
        ).fetchone()
        embedding_count = result[0]
        
        # Knowledge base count
        result = conn.execute(
            "SELECT COUNT(*) FROM knowledge_base"
        ).fetchone()
        kb_count = result[0]
        
        conn.close()
        st.session_state.db_connected = True
        
        st.success("✅ Connected")
        st.caption(f"📦 {product_count:,} Products | 🧠 {embedding_count:,} Embeddings | 📝 {kb_count:,} KB Items")
    except Exception as e:
        st.session_state.db_connected = False
        st.error("❌ Connection Failed")
        if st.button("🔄 Retry Connection", key="retry_db"):
            st.rerun()
        logger.error(f"Database connection error: {e}")
    
    # Search History
    if st.session_state.search_history:
        st.markdown("---")
        st.markdown("### 🕒 Recent Searches")
        for i, search in enumerate(st.session_state.search_history[-5:][::-1]):
            if st.button(f"🔍 {search['query'][:30]}...", key=f"history_{i}", help=f"Click to rerun: {search['query']}"):
                st.session_state.quick_search = search['query']
                st.rerun()
    


# ============================================================================
# MAIN CONTENT AREA
# ============================================================================

# Tab navigation
tab1, tab2 = st.tabs([
    "🔍 Search Comparison",
    "🎯 MCP Context Search"
])

# ============================================================================
# TAB 1: SEARCH COMPARISON
# ============================================================================

with tab1:
    st.markdown("### Compare Search Methods Side-by-Side")
    st.caption("See how different search algorithms perform on the same query")
    
    # Quick action buttons
    st.markdown("**⚡ Quick Try:**")
    quick_cols = st.columns(4)
    quick_queries = ["wireless headphones", "security camera", "robot vacuum", "smart doorbell"]
    for idx, q in enumerate(quick_queries):
        with quick_cols[idx]:
            if st.button(f"👉 {q}", key=f"quick_{idx}"):
                st.session_state.quick_search = q
                st.rerun()
    
    # Options row
    col1, col2 = st.columns([3, 1])
    with col1:
        use_rerank = st.checkbox(
            "✨ Use Cohere Rerank", 
            value=False, 
            key='use_rerank',
            help="**Checked**: Applies Cohere's reranking model after initial search to re-order results by relevance. Improves accuracy but adds latency and cost.\n\n**Unchecked**: Shows raw search results ranked by each method's native scoring."
        )
    with col2:
        show_all = st.checkbox("📊 Show All", value=False, key='show_all', help="Show all results instead of top 3")
    
    # Search query with quick search support
    if 'quick_search' in st.session_state:
        st.session_state.comparison_query = st.session_state.quick_search
        del st.session_state.quick_search
    
    search_query = st.selectbox(
        "Search Query",
        options=["", "wireless headphones", "security camera", "robot vacuum", "smart doorbell", "bluetooth speaker", "laptop", "gaming mouse"],
        key='comparison_query'
    )
    
    search_button = st.button("🔍 Search All Methods", type="primary")
    
    if search_button and not search_query:
        st.warning("⚠️ Please enter a search query")
    
    if search_button and search_query:
        with st.spinner("Running all search methods..."):
            # Track performance
            results_data = {}
            
            methods = [
                ('Keyword', lambda q: keyword_search(q, results_limit, selected_persona)),
                ('Fuzzy', lambda q: fuzzy_search(q, results_limit, selected_persona)),
                ('Semantic', lambda q: semantic_search(q, results_limit, selected_persona)),
                ('Hybrid', lambda q: hybrid_search(q, semantic_weight, keyword_weight, results_limit, selected_persona))
            ]
            
            # Display results in columns
            cols = st.columns(len(methods))
            
            for idx, (method_name, method_func) in enumerate(methods):
                with cols[idx]:
                    st.markdown(f"#### {method_name}")
                    
                    start_time = time.time()
                    try:
                        results = method_func(search_query)
                        elapsed = time.time() - start_time
                        
                        # Apply reranking if enabled
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
                            
                            # Show results based on toggle
                            display_count = len(results) if show_all else 3
                            for result in results[:display_count]:
                                with st.container():
                                    render_product_card(result, show_score=True)
                            
                            # Store all results for export
                            if method_name not in st.session_state:
                                st.session_state[f'results_{method_name}'] = results
                        else:
                            st.info("No results found")
                        
                        # Store metrics
                        results_data[method_name] = {
                            'count': len(results),
                            'time': total_time,
                            'avg_score': sum(r.get('score', 0) for r in results) / len(results) if results else 0
                        }
                        
                    except Exception as e:
                        st.error(f"Error: {str(e)}")
                        logger.error(f"{method_name} search error: {e}")
            
            # Add to search history
            if search_query:
                st.session_state.search_history.append({
                    'query': search_query,
                    'timestamp': datetime.now().isoformat(),
                    'persona': selected_persona
                })
                # Keep only last 10
                st.session_state.search_history = st.session_state.search_history[-10:]
            
            # Export results
            if results_data:
                st.markdown("---")
                col1, col2 = st.columns([3, 1])
                with col1:
                    st.markdown("### 📊 Performance Metrics")
                with col2:
                    # Prepare export data
                    export_data = []
                    for method in ['Keyword', 'Fuzzy', 'Semantic', 'Hybrid']:
                        if f'results_{method}' in st.session_state:
                            for r in st.session_state[f'results_{method}']:
                                export_data.append({
                                    'method': method,
                                    'query': search_query,
                                    **r
                                })
                    if export_data:
                        df_export = pd.DataFrame(export_data)
                        csv = df_export.to_csv(index=False)
                        st.download_button(
                            "💾 Export CSV",
                            csv,
                            f"search_results_{search_query[:20]}.csv",
                            "text/csv",
                            key='export_csv'
                        )
            
            # Performance comparison chart
            if results_data:
                
                col1, col2 = st.columns(2)
                
                with col1:
                    # Response time chart
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
                    # Average score chart
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

# ============================================================================
# TAB 2: MCP CONTEXT SEARCH
# ============================================================================

with tab2:
    st.markdown("### MCP Context Search with RLS Policies")
    st.caption(f"Currently viewing as: **{PERSONAS[selected_persona]['name']}** {PERSONAS[selected_persona]['icon']}")
    
    st.info("""
    **🔒 About RLS**: Row-Level Security policies in PostgreSQL automatically filter query results based on your persona. 
    This ensures users only see data they're authorized to access - no application-level filtering needed.
    """)
    
    # Quick action buttons for MCP - persona-specific
    st.markdown("**⚡ Quick Try:**")
    mcp_quick_queries_by_persona = {
        'customer': [
            ("light", "✅ FAQ Access"),
            ("cable", "✅ FAQ Access"),
            ("stylus", "✅ FAQ Access"),
            ("ticket", "🔒 Restricted")
        ],
        'support_agent': [
            ("complaint", "✅ Ticket Access"),
            ("flickering", "✅ Ticket Access"),
            ("defect", "✅ Internal Access"),
            ("analytics", "🔒 Restricted")
        ],
        'product_manager': [
            ("sales", "✅ Analytics Access"),
            ("revenue", "✅ Analytics Access"),
            ("retention", "✅ Analytics Access"),
            ("light", "✅ All Access")
        ]
    }
    mcp_quick_queries = mcp_quick_queries_by_persona.get(selected_persona, [])
    mcp_quick_cols = st.columns(4)
    for idx, (q, status) in enumerate(mcp_quick_queries):
        with mcp_quick_cols[idx]:
            is_restricted = "🔒" in status
            if st.button(f"{'🔒' if is_restricted else '👉'} {q}", key=f"mcp_quick_{idx}", type="secondary" if is_restricted else "primary"):
                st.session_state.mcp_quick_search = q
                st.rerun()
    
    # Explanation for RLS demo
    rls_explanations = {
        'customer': "💡 RLS Test: Uncheck 'Strands Agent', try 'light'/'cable'/'stylus' (✅ see FAQs) vs 'ticket' (🔒 no results)",
        'support_agent': "💡 RLS Test: Uncheck 'Strands Agent', try 'complaint'/'defect' (✅ see tickets/notes) vs 'analytics' (🔒 no results)",
        'product_manager': "💡 Product Managers see everything: Try any query to see FAQs, tickets, internal notes, and analytics."
    }
    st.caption(rls_explanations.get(selected_persona, ""))
    
    st.info("""
    **🔒 RLS Testing**: Uncheck "Use Strands Agent" to test RLS. 
    MCP agent = admin access (bypasses RLS) | Direct search = persona-specific users (enforces RLS)
    """)
    
    # MCP Method selection and Time filter
    col1, col2, col3 = st.columns([2, 1, 1])
    with col1:
        use_strands_agent = st.checkbox(
            "🤖 Use Strands Agent with MCP Tools", 
            value=False,
            help="**Checked**: AI agent uses MCP tools to intelligently query the database and synthesize natural language responses. ⚠️ Note: MCP uses Aurora Data API with admin credentials, so RLS policies are NOT enforced.\n\n**Unchecked**: Direct hybrid search on knowledge base with RLS policies applied. ✅ RLS policies ARE enforced based on selected persona."
        )
        if use_strands_agent:
            st.caption("⚠️ MCP Agent uses admin access - RLS policies not enforced. Uncheck to test RLS.")
    
    with col2:
        time_filter = st.selectbox(
            "📅 Time Window",
            options=['All Time', 'Last 24 Hours', 'Last 7 Days', 'Last 30 Days'],
            key='time_filter'
        )
    
    with col3:
        st.empty()  # Placeholder for alignment
    
    time_window_map = {
        'All Time': None,
        'Last 24 Hours': '24h',
        'Last 7 Days': '7d',
        'Last 30 Days': '30d'
    }
    
    # Search input with sample queries in selectbox
    if 'mcp_quick_search' in st.session_state:
        st.session_state.mcp_query = st.session_state.mcp_quick_search
        del st.session_state.mcp_quick_search
    
    mcp_query = st.selectbox(
        "Search Query",
        options=["", "What are the top products?", "Show customer complaints", "List all product categories", "Recent support tickets", "Products with high ratings"],
        key='mcp_query'
    )
    
    mcp_search_button = st.button("🔍 Search MCP Context", type="primary")
    
    if mcp_search_button and not mcp_query:
        st.warning("⚠️ Please enter a search query")
    
    if mcp_search_button and mcp_query:
        if use_strands_agent:
            # Use Strands Agent with MCP tools
            st.markdown("#### 🤖 Strands Agent Response")
            st.caption("Using Model Context Protocol to intelligently query the database")
            
            with st.spinner("Agent is thinking and using MCP tools..."):
                try:
                    start_time = time.time()
                    agent_result = strands_agent_search(mcp_query, selected_persona, use_mcp=True)
                    elapsed = time.time() - start_time
                    
                    if agent_result['error']:
                        st.error(f"❌ {agent_result['error']}")
                        st.info("💡 Make sure to set DATABASE_CLUSTER_ARN and DATABASE_SECRET_ARN in your .env file")
                    else:
                        # Display agent stats
                        st.markdown(f"""
                        <div class="stats-panel">
                            <div style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 1rem;">
                                <div>
                                    <div style="font-size: 1.5rem; font-weight: 600;">Strands Agent</div>
                                    <div style="font-size: 0.875rem; opacity: 0.9;">Powered by Claude + MCP</div>
                                </div>
                                <div>
                                    <div style="font-size: 1.5rem; font-weight: 600;">{elapsed*1000:.0f}ms</div>
                                    <div style="font-size: 0.875rem; opacity: 0.9;">Response Time</div>
                                </div>
                                <div>
                                    <div style="font-size: 1.5rem; font-weight: 600;">{len(agent_result.get('tools_used', []))}</div>
                                    <div style="font-size: 0.875rem; opacity: 0.9;">Tools Used</div>
                                </div>
                                <div>
                                    <div style="font-size: 1.5rem; font-weight: 600;">{len(agent_result.get('available_tools', []))}</div>
                                    <div style="font-size: 0.875rem; opacity: 0.9;">Tools Available</div>
                                </div>
                            </div>
                        </div>
                        """, unsafe_allow_html=True)
                        
                        # Show available MCP tools
                        if agent_result.get('available_tools'):
                            with st.expander("🔗 MCP Tools Available from Aurora PostgreSQL Server", expanded=False):
                                st.markdown("**Database tools exposed via Model Context Protocol:**")
                                for tool in agent_result['available_tools']:
                                    tool_name = tool if isinstance(tool, str) else getattr(tool, 'name', str(tool))
                                    st.markdown(f"- `{tool_name}`")
                                st.caption("These tools allow the AI agent to query tables, describe schemas, and execute SQL.")
                        
                        # Show tools used
                        if agent_result.get('tools_used'):
                            st.markdown("**🔧 Tools Used in This Query:**")
                            for tool in agent_result['tools_used']:
                                st.code(tool, language="text")
                        
                        # Display agent response
                        st.markdown("---")
                        st.markdown("#### 💬 Agent Response")
                        st.markdown(agent_result['response'])
                        
                        # Show explanation
                        st.info("""
                        **🎯 How MCP Works:**
                        1. Agent receives your natural language query
                        2. Aurora PostgreSQL MCP Server exposes database tools
                        3. Agent decides which tools to use (query_database, list_tables, etc.)
                        4. Tools execute with proper permissions and RLS policies
                        5. Agent synthesizes results into natural language response
                        """)
                        
                except Exception as e:
                    st.error(f"Agent error: {str(e)}")
                    logger.error(f"Strands Agent error: {e}")
        else:
            # Use direct MCP context search (original approach)
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
                        <div style="display: flex; justify-content: space-between; align-items: center;">
                            <div>
                                <div style="font-size: 2rem; font-weight: 600;">{len(results)}</div>
                                <div style="font-size: 0.875rem; opacity: 0.9;">Results Found</div>
                            </div>
                            <div>
                                <div style="font-size: 2rem; font-weight: 600;">{elapsed*1000:.0f}ms</div>
                                <div style="font-size: 0.875rem; opacity: 0.9;">Response Time</div>
                            </div>
                            <div>
                                <div style="font-size: 2rem; font-weight: 600;">{PERSONAS[selected_persona]['icon']}</div>
                                <div style="font-size: 0.875rem; opacity: 0.9;">{PERSONAS[selected_persona]['name']}</div>
                            </div>
                        </div>
                    </div>
                    """, unsafe_allow_html=True)
                    
                    if results:
                        # Group by content type
                        by_type = {}
                        for r in results:
                            content_type = r.get('content_type', 'unknown')
                            if content_type not in by_type:
                                by_type[content_type] = []
                            by_type[content_type].append(r)
                        
                        # Display grouped results
                        for content_type, items in by_type.items():
                            with st.expander(f"📁 {content_type.replace('_', ' ').title()} ({len(items)})", expanded=True):
                                for item in items:
                                    render_knowledge_card(item, show_persona=True)
                    else:
                        st.info(f"No results found for '{mcp_query}' with {selected_persona} access level")
                        
                except Exception as e:
                    st.error(f"Search error: {str(e)}")
                    logger.error(f"MCP search error: {e}")



# ============================================================================
# FOOTER
# ============================================================================

st.markdown("---")
st.markdown("""
<div style="text-align: center; color: #666; padding: 2rem 0;">
    <p>DAT409: Hybrid Search with Aurora PostgreSQL • Built with Streamlit, pgvector, Cohere, and MCP</p>
    <p style="font-size: 0.875rem;">Amazon Web Services • re:Invent 2025</p>
</div>
""", unsafe_allow_html=True)