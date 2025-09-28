#!/bin/bash
# DAT409 Workshop - Database Setup and Data Loading Script
# Run this AFTER enabling Bedrock models (Cohere Embed English v3)
# This script creates all tables and loads data for both Lab 1 and Lab 2
# Usage: ./setup-database.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# Load environment variables
if [ -f "/workshop/.env" ]; then
    source /workshop/.env
else
    error ".env file not found. Please run bootstrap-code-editor.sh first"
fi

# Verify database credentials
if [ -z "$DB_HOST" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ] || [ -z "$DB_NAME" ]; then
    error "Database credentials not configured. Check .env file"
fi

log "==================== DAT409 Database Setup ===================="
log "Database: $DB_HOST:$DB_PORT/$DB_NAME"
log "User: $DB_USER"

# Test database connection
log "Testing database connection..."
if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -c "SELECT 'Connection successful' as status;" &>/dev/null; then
    log "✅ Database connection successful"
else
    error "Database connection failed. Please check credentials"
fi

# Test Bedrock access
log "Testing Bedrock access..."
BODY_JSON='{"texts":["test"],"input_type":"search_document","embedding_types":["float"],"truncate":"END"}'
BODY_BASE64=$(echo "$BODY_JSON" | base64)

if aws bedrock-runtime invoke-model \
    --model-id cohere.embed-english-v3 \
    --body "$BODY_BASE64" \
    --region "$AWS_REGION" \
    /tmp/bedrock_test.json 2>/dev/null; then
    
    # Verify the response contains embeddings
    if [ -f /tmp/bedrock_test.json ] && [ $(stat -c%s /tmp/bedrock_test.json 2>/dev/null || stat -f%z /tmp/bedrock_test.json 2>/dev/null) -gt 100 ]; then
        log "✅ Bedrock Cohere model accessible and working"
        rm -f /tmp/bedrock_test.json
    else
        error "❌ Bedrock model responded but output seems invalid"
    fi
else
    error "❌ Bedrock Cohere model not accessible. Please enable it in the console first!"
    echo "To enable:"
    echo "1. Go to https://console.aws.amazon.com/bedrock"
    echo "2. Click 'Model access' in the left sidebar"
    echo "3. Enable 'Cohere Embed English v3'"
    echo "4. Wait for 'Access granted' status"
    exit 1
fi

# ===========================================================================
# LAB 1: CREATE SCHEMA AND TABLES
# ===========================================================================

log "==================== Lab 1: Creating Schema and Tables ===================="

PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'LAB1_SCHEMA'
-- Create extensions
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Create bedrock_integration schema
CREATE SCHEMA IF NOT EXISTS bedrock_integration;

-- Drop and recreate product_catalog table
DROP TABLE IF EXISTS bedrock_integration.product_catalog CASCADE;

CREATE TABLE bedrock_integration.product_catalog (
    "productId" VARCHAR(255) PRIMARY KEY,
    product_description TEXT,
    stars DOUBLE PRECISION,
    price DOUBLE PRECISION,
    category_id INTEGER,
    embedding vector(1024),
    metadata JSONB DEFAULT '{}'
);

-- Create indexes (will be populated after data load)
CREATE INDEX idx_product_stars ON bedrock_integration.product_catalog(stars DESC);
CREATE INDEX idx_product_price ON bedrock_integration.product_catalog(price);
CREATE INDEX idx_product_category ON bedrock_integration.product_catalog(category_id);
CREATE INDEX idx_product_description_fts 
    ON bedrock_integration.product_catalog 
    USING gin(to_tsvector('english', product_description));

SELECT 'Lab 1 schema created successfully' as status;
LAB1_SCHEMA

if [ $? -eq 0 ]; then
    log "✅ Lab 1 schema and tables created"
else
    error "Failed to create Lab 1 schema"
fi

# ===========================================================================
# LAB 1: LOAD 21,704 PRODUCTS WITH EMBEDDINGS
# ===========================================================================

log "==================== Lab 1: Loading Product Data ===================="
log "This will load 21,704 products with Cohere embeddings"
log "Expected duration: 5-8 minutes"

# Create Python data loader script
cat > /tmp/load_products.py << 'LOADER_EOF'
#!/usr/bin/env python3
import sys
import os
import time
import json
import boto3
import psycopg
from pathlib import Path
import pandas as pd
import numpy as np
from pgvector.psycopg import register_vector
from pandarallel import pandarallel
from tqdm import tqdm
import warnings
warnings.filterwarnings('ignore')

print("="*60)
print("DAT409 Workshop Data Loader")
print("Loading 21,704 products with embeddings...")
print("="*60)

# Get database credentials from environment
DB_HOST = os.getenv('DB_HOST')
DB_PORT = os.getenv('DB_PORT', '5432')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')
AWS_REGION = os.getenv('AWS_REGION', 'us-west-2')

# Set up paths
WORKSHOP_DIR = Path("/workshop")
DATA_FILE = WORKSHOP_DIR / "lab1-hybrid-search/data/amazon-products.csv"

# Check if data file exists, if not download it
if not DATA_FILE.exists():
    print(f"Data file not found, downloading from GitHub...")
    os.system(f"mkdir -p {DATA_FILE.parent}")
    os.system(f"curl -fsSL https://raw.githubusercontent.com/aws-samples/sample-dat409-hybrid-search-workshop-prod/main/lab1-hybrid-search/data/amazon-products.csv -o {DATA_FILE}")

if not DATA_FILE.exists():
    print("❌ Could not download data file")
    sys.exit(1)

print(f"✅ Data file found: {DATA_FILE}")

start_time = time.time()

# Initialize Bedrock client
bedrock_runtime = boto3.client('bedrock-runtime', region_name=AWS_REGION)

def generate_embedding_cohere(text):
    """Generate Cohere embedding with Titan fallback"""
    if not text or pd.isna(text):
        return np.random.randn(1024).tolist()
    
    try:
        body = json.dumps({
            "texts": [str(text)[:2000]],
            "input_type": "search_document",
            "embedding_types": ["float"],
            "truncate": "END"
        })
        
        response = bedrock_runtime.invoke_model(
            modelId='cohere.embed-english-v3',
            body=body,
            accept='application/json',
            contentType='application/json'
        )
        
        result = json.loads(response['body'].read())
        return result['embeddings']['float'][0]
        
    except Exception as e:
        # Fallback to Titan
        try:
            body = json.dumps({
                "inputText": str(text)[:8000],
                "dimensions": 1024,
                "normalize": True
            })
            
            response = bedrock_runtime.invoke_model(
                modelId='amazon.titan-embed-text-v2:0',
                body=body,
                accept='application/json',
                contentType='application/json'
            )
            
            result = json.loads(response['body'].read())
            return result['embedding']
        except:
            return np.random.randn(1024).tolist()

# Load CSV data
print("📂 Loading CSV data...")
df = pd.read_csv(DATA_FILE, encoding='utf-8', on_bad_lines='skip')
print(f"   Loaded {len(df):,} products")

# Connect to database
conn = psycopg.connect(
    host=DB_HOST,
    port=DB_PORT,
    dbname=DB_NAME,
    user=DB_USER,
    password=DB_PASSWORD,
    autocommit=False
)

# Register pgvector
register_vector(conn)

# Initialize pandarallel for parallel processing
pandarallel.initialize(progress_bar=True, nb_workers=10, verbose=0)

# Process data
print("🔄 Processing product data...")

# Clean and prepare data
df['product_description'] = df['title'].fillna('') + ' ' + df['description'].fillna('')
df['product_description'] = df['product_description'].str[:2000]
df['productId'] = df['parent_asin'].fillna(df.index.astype(str))
df['stars'] = pd.to_numeric(df['average_rating'], errors='coerce').fillna(3.0)
df['price'] = pd.to_numeric(df['price'].astype(str).str.replace('[\$,]', '', regex=True), errors='coerce').fillna(0.0)
df['category_id'] = pd.Categorical(df['main_category']).codes

# Add metadata
df['metadata'] = df.apply(lambda row: json.dumps({
    'reviews': int(row.get('rating_number', 0)) if pd.notna(row.get('rating_number')) else 0,
    'category': row.get('main_category', 'Unknown')
}), axis=1)

# Select columns
df_final = df[['productId', 'product_description', 'stars', 'price', 'category_id', 'metadata']].copy()

# Generate embeddings in parallel
print("🚀 Generating embeddings (parallel processing)...")
print("   This will take 5-8 minutes for 21,704 products...")

df_final['embedding'] = df_final['product_description'].parallel_apply(generate_embedding_cohere)

# Insert data in batches
print("💾 Inserting data into database...")
BATCH_SIZE = 1000
total_batches = len(df_final) // BATCH_SIZE + 1

with tqdm(total=len(df_final), desc="Inserting products") as pbar:
    for i in range(0, len(df_final), BATCH_SIZE):
        batch = df_final.iloc[i:i+BATCH_SIZE]
        
        with conn.cursor() as cur:
            for _, row in batch.iterrows():
                try:
                    cur.execute('''
                        INSERT INTO bedrock_integration.product_catalog 
                        ("productId", product_description, stars, price, category_id, embedding, metadata)
                        VALUES (%s, %s, %s, %s, %s, %s, %s::jsonb)
                        ON CONFLICT ("productId") DO UPDATE
                        SET product_description = EXCLUDED.product_description,
                            stars = EXCLUDED.stars,
                            price = EXCLUDED.price,
                            category_id = EXCLUDED.category_id,
                            embedding = EXCLUDED.embedding,
                            metadata = EXCLUDED.metadata;
                    ''', (
                        row['productId'],
                        row['product_description'],
                        float(row['stars']),
                        float(row['price']),
                        int(row['category_id']),
                        row['embedding'],
                        row['metadata']
                    ))
                except Exception as e:
                    print(f"Error inserting {row['productId']}: {e}")
        
        conn.commit()
        pbar.update(len(batch))

# Create vector index
print("📊 Creating vector similarity index...")
with conn.cursor() as cur:
    cur.execute('''
        CREATE INDEX IF NOT EXISTS idx_product_embedding 
        ON bedrock_integration.product_catalog 
        USING ivfflat (embedding vector_cosine_ops) 
        WITH (lists = 100);
    ''')
    conn.commit()

# Verify the data
with conn.cursor() as cur:
    cur.execute("SELECT COUNT(*) FROM bedrock_integration.product_catalog;")
    final_count = cur.fetchone()[0]
    
    cur.execute("SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL;")
    embeddings_count = cur.fetchone()[0]

conn.close()

# Summary
total_time = time.time() - start_time
print("="*60)
print("✅ LAB 1 DATA LOADING COMPLETE!")
print(f"   Total rows loaded: {final_count:,}")
print(f"   Rows with embeddings: {embeddings_count:,}")
print(f"   Total time: {total_time/60:.1f} minutes")
print("="*60)
LOADER_EOF

# Run the data loader
python3 /tmp/load_products.py

if [ $? -eq 0 ]; then
    log "✅ Lab 1 data loading completed successfully"
else
    error "Lab 1 data loading failed"
fi

# ===========================================================================
# LAB 2: CREATE RLS TABLES AND KNOWLEDGE BASE
# ===========================================================================

log "==================== Lab 2: Setting up RLS and Knowledge Base ===================="

# Run the Lab 2 SQL setup (using the complete version with 50 hardcoded products)
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'LAB2_SETUP'
-- ============================================================
-- LAB 2: MCP with PostgreSQL RLS - 50 Product Setup
-- ============================================================

-- 1. Create knowledge_base table (reuses embeddings via JOIN)
DROP TABLE IF EXISTS public.knowledge_base CASCADE;
CREATE TABLE public.knowledge_base (
    id SERIAL PRIMARY KEY,
    product_id VARCHAR(255),
    content TEXT NOT NULL,
    content_type VARCHAR(50) NOT NULL,
    persona_access VARCHAR(50)[] NOT NULL,
    severity VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    metadata JSONB DEFAULT '{}',
    
    CONSTRAINT fk_product 
        FOREIGN KEY (product_id) 
        REFERENCES bedrock_integration.product_catalog("productId")
        ON DELETE CASCADE
);

-- Create indexes
CREATE INDEX idx_kb_product_id ON knowledge_base(product_id);
CREATE INDEX idx_kb_persona_access ON knowledge_base USING GIN (persona_access);
CREATE INDEX idx_kb_content_type ON knowledge_base(content_type);
CREATE INDEX idx_kb_created_at ON knowledge_base(created_at DESC);
CREATE INDEX idx_kb_content_fts ON knowledge_base USING GIN (to_tsvector('english', content));

-- 2. Create RLS roles and policies
DROP ROLE IF EXISTS customer_role CASCADE;
DROP ROLE IF EXISTS support_agent_role CASCADE;
DROP ROLE IF EXISTS product_manager_role CASCADE;
DROP USER IF EXISTS customer_user;
DROP USER IF EXISTS agent_user;
DROP USER IF EXISTS pm_user;

CREATE ROLE customer_role;
CREATE ROLE support_agent_role;
CREATE ROLE product_manager_role;

CREATE USER customer_user WITH PASSWORD 'customer123' IN ROLE customer_role;
CREATE USER agent_user WITH PASSWORD 'agent123' IN ROLE support_agent_role;
CREATE USER pm_user WITH PASSWORD 'pm123' IN ROLE product_manager_role;

GRANT USAGE ON SCHEMA public TO customer_role, support_agent_role, product_manager_role;
GRANT USAGE ON SCHEMA bedrock_integration TO customer_role, support_agent_role, product_manager_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO customer_role, support_agent_role, product_manager_role;
GRANT SELECT ON bedrock_integration.product_catalog TO customer_role, support_agent_role, product_manager_role;

ALTER TABLE knowledge_base ENABLE ROW LEVEL SECURITY;

CREATE POLICY customer_access_policy ON knowledge_base
    FOR SELECT TO customer_role
    USING ('customer' = ANY(persona_access));

CREATE POLICY agent_access_policy ON knowledge_base
    FOR SELECT TO support_agent_role
    USING ('support_agent' = ANY(persona_access) OR 'customer' = ANY(persona_access));

CREATE POLICY pm_access_policy ON knowledge_base
    FOR SELECT TO product_manager_role
    USING (true);

CREATE POLICY app_user_policy ON knowledge_base
    FOR ALL TO workshop_admin
    USING (true) WITH CHECK (true);

-- 3. Populate with 50 HARDCODED product IDs
DO $$
DECLARE
    product_ids TEXT[] := ARRAY[
        'B07X6C9RMF', 'B08N5NQ869', 'B086DL32R3', 'B08SGC46M9', 'B07DGR98VQ',
        'B08R59YH7W', 'B08CKHPP52', 'B08M125RNW', 'B0849J7W5X', 'B08F6GPQQ7',
        'B08FD54PN9', 'B07QKXM2D3', 'B01CW4CEMS', 'B07X27JNQ5', 'B07ZB2RNTW',
        'B07YB8HZ8T', 'B08ZXJJTYJ', 'B0829KDY9X', 'B093DDPDXL', 'B07PM2NBGT',
        'B07TTH5TMW', 'B07B7NXV4R', 'B011MYEMKQ', 'B07YP9VK7Q', 'B07ZB2QF2V',
        'B0CFR1JB15', 'B00HT6E2NY', 'B0CBJRXFVJ', 'B00PBGQ0SY', 'B0168MB1RO',
        'B0C8JGHXXB', 'B0C8JDM69N', 'B0C2PXPWMR', 'B0C8JK6TSH', 'B0C3RKQPHR',
        'B07GG3XXNX', 'B0899GLP7R', 'B07PJ67CKC', 'B088C4NHRS', 'B07WHMQNPC',
        'B07YMV9VMT', 'B07ZPMCW64', 'B0856W45VL', 'B07W1HKYQK', 'B07R3WY95C',
        'B01CW49AGG', 'B07X81M2D2', 'B07X2M8KTR', 'B08JCS7QKL', 'B083GKZWVX'
    ];
    
    pid TEXT;
    product_desc TEXT;
    product_price NUMERIC;
    product_stars NUMERIC;
    product_reviews INT;
    ticket_num INT := 80000;
    idx INT := 0;
BEGIN
    DELETE FROM knowledge_base;
    
    RAISE NOTICE 'Populating knowledge base with 50 deterministic products...';
    
    FOREACH pid IN ARRAY product_ids
    LOOP
        idx := idx + 1;
        
        SELECT 
            LEFT(product_description, 100),
            price,
            stars,
            COALESCE(CAST(metadata->>'reviews' AS INT), 10000)
        INTO product_desc, product_price, product_stars, product_reviews
        FROM bedrock_integration.product_catalog 
        WHERE "productId" = pid;
        
        IF product_desc IS NULL THEN
            CONTINUE;
        END IF;
        
        -- Generate varied support content
        INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity)
        VALUES (
            pid,
            CASE 
                WHEN product_desc ILIKE '%camera%' OR product_desc ILIKE '%doorbell%' THEN
                    format('Q: How do I connect to WiFi? A: Open app, select Add Device, follow setup. Use 2.4GHz WiFi.')
                WHEN product_desc ILIKE '%vacuum%' THEN
                    'Q: How often should I clean filters? A: Every 2 weeks for optimal performance.'
                ELSE
                    'Q: What warranty applies? A: 1-year manufacturer warranty. Register within 30 days.'
            END,
            'product_faq',
            ARRAY['customer', 'support_agent', 'product_manager'],
            'low'
        );
        
        IF product_reviews > 20000 OR product_stars < 4.3 THEN
            ticket_num := ticket_num + 1;
            INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity)
            VALUES (
                pid,
                format('Ticket #%s: Connection issues reported. Firmware v2.5.1 causing dropouts.', ticket_num),
                'support_ticket',
                ARRAY['support_agent', 'product_manager'],
                CASE WHEN product_stars < 4.2 THEN 'high' ELSE 'medium' END
            );
        END IF;
        
        IF idx <= 20 THEN
            INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity)
            VALUES (
                pid,
                format('ANALYTICS: Rank #%s, %s reviews, %.1f stars', idx, product_reviews, product_stars),
                'analytics',
                ARRAY['product_manager'],
                'low'
            );
        END IF;
    END LOOP;
    
    -- Add general support content
    INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity) VALUES
    (NULL, 'POLICY: Extended holiday returns through January 31st.', 
     'product_faq', ARRAY['customer', 'support_agent', 'product_manager'], 'low'),
    (NULL, 'ALERT: AWS us-west-2 latency affecting connections.', 
     'internal_note', ARRAY['support_agent', 'product_manager'], 'high');
END $$;

-- 4. Create MCP helper function
CREATE OR REPLACE FUNCTION get_mcp_context(
    p_query_text TEXT,
    p_persona TEXT DEFAULT 'customer',
    p_time_window INTERVAL DEFAULT NULL,
    p_limit INT DEFAULT 10
) RETURNS JSON AS $$
DECLARE
    v_result JSON;
BEGIN
    CASE p_persona
        WHEN 'customer' THEN EXECUTE 'SET ROLE customer_role';
        WHEN 'support_agent' THEN EXECUTE 'SET ROLE support_agent_role';
        WHEN 'product_manager' THEN EXECUTE 'SET ROLE product_manager_role';
        ELSE EXECUTE 'SET ROLE customer_role';
    END CASE;
    
    WITH filtered_content AS (
        SELECT k.*, p.product_description, p.price, p.stars
        FROM knowledge_base k
        LEFT JOIN bedrock_integration.product_catalog p ON k.product_id = p."productId"
        WHERE k.content ILIKE '%' || p_query_text || '%'
        AND (p_time_window IS NULL OR k.created_at >= NOW() - p_time_window)
        LIMIT p_limit
    )
    SELECT json_agg(filtered_content) INTO v_result FROM filtered_content;
    
    RESET ROLE;
    RETURN COALESCE(v_result, '[]'::JSON);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Verify setup
SELECT 'Lab 2 setup complete' as status;
SELECT content_type, COUNT(*) as entries FROM knowledge_base GROUP BY content_type;
LAB2_SETUP

if [ $? -eq 0 ]; then
    log "✅ Lab 2 RLS and knowledge base created successfully"
else
    error "Lab 2 setup failed"
fi

# ===========================================================================
# CREATE LAB HELPER FILES
# ===========================================================================

log "Creating Lab helper files..."

# Create scripts directory if it doesn't exist
mkdir -p /workshop/lab2-mcp-agent/scripts
mkdir -p /workshop/lab2-mcp-agent/setup

# Create Lab 2 test script
cat > /workshop/lab2-mcp-agent/scripts/test_personas.sh << 'TEST_EOF'
#!/bin/bash
echo "Testing Lab 2: Persona-Based Access with RLS"
echo "============================================="

source /workshop/.env

echo "Customer View (public only):"
PGPASSWORD=customer123 psql -h $PGHOST -U customer_user -d $PGDATABASE -c \
  "SELECT content_type, COUNT(*) FROM knowledge_base GROUP BY content_type;"

echo -e "\nSupport Agent View (public + internal):"
PGPASSWORD=agent123 psql -h $PGHOST -U agent_user -d $PGDATABASE -c \
  "SELECT content_type, COUNT(*) FROM knowledge_base GROUP BY content_type;"

echo -e "\nProduct Manager View (everything):"
PGPASSWORD=pm123 psql -h $PGHOST -U pm_user -d $PGDATABASE -c \
  "SELECT content_type, COUNT(*) FROM knowledge_base GROUP BY content_type;"
TEST_EOF

chmod +x /workshop/lab2-mcp-agent/scripts/test_personas.sh

# Create Lab 2 Streamlit app
log "Creating Lab 2 Streamlit application..."

cat > /workshop/lab2-mcp-agent/lab2_mcp_demo.py << 'STREAMLIT_EOF'
"""
Lab 2: MCP Context Builder with PostgreSQL RLS
"""
import streamlit as st
import psycopg
from psycopg.rows import dict_row
import pandas as pd
import json
import os

st.set_page_config(page_title="Lab 2: MCP with RLS", page_icon="🔐", layout="wide")

# Load environment
DB_HOST = os.getenv('PGHOST')
DB_NAME = os.getenv('PGDATABASE')
DB_USER = os.getenv('PGUSER')
DB_PASSWORD = os.getenv('PGPASSWORD')
DB_SECRET_ARN = os.getenv('DB_SECRET_ARN')
AWS_REGION = os.getenv('AWS_REGION', 'us-west-2')

PERSONAS = {
    "customer": {"user": "customer_user", "password": "customer123", "icon": "👤"},
    "support_agent": {"user": "agent_user", "password": "agent123", "icon": "🛠️"},
    "product_manager": {"user": "pm_user", "password": "pm123", "icon": "📊"}
}

def get_persona_connection(persona):
    config = PERSONAS[persona]
    return psycopg.connect(
        host=DB_HOST, dbname=DB_NAME,
        user=config['user'], password=config['password'],
        row_factory=dict_row
    )

def search_with_persona(query, persona):
    with get_persona_connection(persona) as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT k.*, p.product_description, p.price, p.stars
                FROM knowledge_base k
                LEFT JOIN bedrock_integration.product_catalog p ON k.product_id = p."productId"
                WHERE k.content ILIKE %s OR p.product_description ILIKE %s
                LIMIT 10
            """, (f'%{query}%', f'%{query}%'))
            return cur.fetchall()

st.title("🔐 Lab 2: MCP Context Builder with RLS")

# Sidebar with persona selector
with st.sidebar:
    st.header("Configuration")
    persona = st.selectbox("Select Persona", list(PERSONAS.keys()))
    st.info(f"{PERSONAS[persona]['icon']} {persona.replace('_', ' ').title()}")
    
    st.markdown("### Access Levels")
    if persona == "customer":
        st.markdown("- ✅ Product FAQs\n- ❌ Support Tickets\n- ❌ Internal Notes\n- ❌ Analytics")
    elif persona == "support_agent":
        st.markdown("- ✅ Product FAQs\n- ✅ Support Tickets\n- ✅ Internal Notes\n- ❌ Analytics")
    else:
        st.markdown("- ✅ Product FAQs\n- ✅ Support Tickets\n- ✅ Internal Notes\n- ✅ Analytics")

# Main content area
col1, col2 = st.columns([3, 1])
with col1:
    query = st.text_input("Search Query", placeholder="Try 'camera', 'vacuum', 'doorbell', or 'bluetooth'")
    
with col2:
    search_button = st.button("🔍 Search with MCP", type="primary")

if search_button and query:
    with st.spinner(f"Searching as {persona}..."):
        results = search_with_persona(query, persona)
        
        if results:
            st.success(f"Found {len(results)} results visible to {persona}")
            
            # Group results by content type
            by_type = {}
            for r in results:
                content_type = r.get('content_type', 'unknown')
                if content_type not in by_type:
                    by_type[content_type] = []
                by_type[content_type].append(r)
            
            # Display results grouped by type
            for content_type, items in by_type.items():
                st.subheader(f"{content_type.replace('_', ' ').title()} ({len(items)})")
                for item in items:
                    with st.expander(f"{item.get('severity', 'low').upper()} - {item.get('product_description', 'General')[:50]}..."):
                        st.write(f"**Content:** {item['content']}")
                        if item.get('product_description'):
                            st.write(f"**Product:** {item['product_description'][:100]}...")
                            if item.get('price'):
                                st.write(f"**Price:** ${item['price']:.2f} | **Rating:** {item.get('stars', 0):.1f}⭐")
                        st.caption(f"Created: {item.get('created_at', 'N/A')}")
        else:
            st.warning(f"No results found for '{query}' with {persona} access level")

# MCP Configuration Display
with st.expander("🔧 MCP Configuration for this setup"):
    cluster_arn = os.getenv('DATABASE_CLUSTER_ARN', '[your-cluster-arn]')
    
    st.code(f"""
{{
  "mcpServers": {{
    "awslabs.postgres-mcp-server": {{
      "command": "uvx",
      "args": [
        "awslabs.postgres-mcp-server@latest",
        "--resource_arn", "{cluster_arn}",
        "--secret_arn", "{DB_SECRET_ARN or '[your-secret-arn]'}",
        "--database", "{DB_NAME}",
        "--region", "{AWS_REGION}",
        "--readonly", "True"
      ],
      "env": {{
        "AWS_PROFILE": "default",
        "AWS_REGION": "{AWS_REGION}",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }}
    }}
  }}
}}
    """, language="json")

# Instructions
st.markdown("---")
st.markdown("""
### 💡 How to Use
1. **Select a persona** in the sidebar to see different access levels
2. **Search for products** using keywords like 'camera', 'vacuum', 'doorbell'
3. **Observe RLS filtering** - each persona sees different content automatically
4. **Run this app**: `streamlit run lab2_mcp_demo.py --server.port 8502`
""")
STREAMLIT_EOF

chown participant:participant /workshop/lab2-mcp-agent/lab2_mcp_demo.py
log "✅ Streamlit app created at /workshop/lab2-mcp-agent/lab2_mcp_demo.py"

# Create MCP configuration
if [ ! -z "$DB_SECRET_ARN" ] && [ "$DB_SECRET_ARN" != "none" ]; then
    CLUSTER_ID=$(echo "$DB_HOST" | cut -d'.' -f1)
    AWS_ACCOUNTID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    DB_CLUSTER_ARN="arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNTID}:cluster:${CLUSTER_ID}"
    
    cat > /workshop/lab2-mcp-agent/mcp_config.json << MCP_EOF
{
  "mcpServers": {
    "awslabs.postgres-mcp-server": {
      "command": "uvx",
      "args": [
        "awslabs.postgres-mcp-server@latest",
        "--resource_arn", "$DB_CLUSTER_ARN",
        "--secret_arn", "$DB_SECRET_ARN",
        "--database", "$DB_NAME",
        "--region", "$AWS_REGION",
        "--readonly", "True"
      ],
      "env": {
        "AWS_REGION": "$AWS_REGION",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    }
  }
}
MCP_EOF
    log "✅ MCP configuration created"
fi

# ===========================================================================
# FINAL VERIFICATION
# ===========================================================================

log "==================== Final Verification ===================="

# Check Lab 1 data
LAB1_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog;" 2>/dev/null | xargs)

LAB1_EMBEDDINGS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL;" 2>/dev/null | xargs)

# Check Lab 2 data
LAB2_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM public.knowledge_base;" 2>/dev/null | xargs)

LAB2_POLICIES=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM pg_policies WHERE tablename='knowledge_base';" 2>/dev/null | xargs)

log "==================== Setup Complete! ===================="
echo ""
echo "📊 LAB 1 - Hybrid Search:"
echo "   ✅ Products loaded: $LAB1_COUNT"
echo "   ✅ Products with embeddings: $LAB1_EMBEDDINGS"
echo ""
echo "🔐 LAB 2 - MCP with RLS:"
echo "   ✅ Knowledge base entries: $LAB2_COUNT"
echo "   ✅ RLS policies created: $LAB2_POLICIES"
echo ""
echo "📝 Test Commands:"
echo "   Lab 1: psql -c \"SELECT COUNT(*) FROM bedrock_integration.product_catalog;\""
echo "   Lab 2: cd /workshop/lab2-mcp-agent && ./scripts/test_personas.sh"
echo ""
echo "🚀 All database setup completed successfully!"
log "========================================================"
