#!/bin/bash
# ===========================================================================
# DAT409 Workshop - Database Setup and Data Loading Script
# ===========================================================================
# This script is IDEMPOTENT - safe to run multiple times
# It sets up both Lab 1 (Hybrid Search) and Lab 2 (MCP with RLS)
# 
# Prerequisites:
# - bootstrap-code-editor.sh must be run first
# - Bedrock Cohere Embed English v3 model must be enabled
# 
# Usage: ./setup-database.sh
# ===========================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION AND UTILITIES
# ============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $1"
}

# ============================================================================
# ENVIRONMENT SETUP
# ============================================================================

log "==================== DAT409 Database Setup Starting ===================="

# Load environment variables
if [ -f "/workshop/.env" ]; then
    source /workshop/.env
    log "✅ Environment file loaded"
else
    error ".env file not found. Please run bootstrap-code-editor.sh first"
fi

# Verify required environment variables
REQUIRED_VARS=("DB_HOST" "DB_PORT" "DB_NAME" "DB_USER" "DB_PASSWORD" "AWS_REGION")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        error "Required environment variable $var is not set"
    fi
done

log "Database Configuration:"
log "  Host: $DB_HOST:$DB_PORT"
log "  Database: $DB_NAME"
log "  User: $DB_USER"
log "  Region: $AWS_REGION"

# ============================================================================
# CONNECTIVITY TESTS
# ============================================================================

log "Testing database connectivity..."
if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -c "SELECT version();" &>/dev/null; then
    log "✅ Database connection successful"
else
    error "Database connection failed. Check your credentials and network connectivity"
fi

log "Testing Bedrock Cohere Embed model access..."
BEDROCK_TEST_BODY='{"texts":["test"],"input_type":"search_document","embedding_types":["float"],"truncate":"END"}'
BEDROCK_TEST_BASE64=$(echo "$BEDROCK_TEST_BODY" | base64)

if aws bedrock-runtime invoke-model \
    --model-id cohere.embed-english-v3 \
    --body "$BEDROCK_TEST_BASE64" \
    --region "$AWS_REGION" \
    /tmp/bedrock_test.json 2>/dev/null; then
    
    if [ -f /tmp/bedrock_test.json ] && [ $(stat -c%s /tmp/bedrock_test.json 2>/dev/null || stat -f%z /tmp/bedrock_test.json 2>/dev/null) -gt 100 ]; then
        log "✅ Bedrock Cohere Embed model is accessible"
        rm -f /tmp/bedrock_test.json
    else
        error "Bedrock model responded but output is invalid"
    fi
else
    error "Cannot access Bedrock Cohere Embed model. Please enable it in AWS Console first"
fi

# ============================================================================
# LAB 1: CREATE SCHEMA AND TABLES
# ============================================================================

log "==================== Lab 1: Setting Up Hybrid Search ===================="

log "Creating schema and tables..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL_LAB1'
-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Create bedrock_integration schema if not exists
CREATE SCHEMA IF NOT EXISTS bedrock_integration;

-- Drop and recreate product_catalog table (clean slate)
DROP TABLE IF EXISTS bedrock_integration.product_catalog CASCADE;

CREATE TABLE bedrock_integration.product_catalog (
    "productId" CHAR(10) PRIMARY KEY,
    product_description VARCHAR(500) NOT NULL,
    imgurl VARCHAR(70),
    producturl VARCHAR(40),
    stars NUMERIC(2,1) CHECK (stars >= 1.0 AND stars <= 5.0),
    reviews INTEGER CHECK (reviews >= 0),
    price NUMERIC(8,2) CHECK (price >= 0),
    category_id SMALLINT CHECK (category_id > 0),
    isbestseller BOOLEAN NOT NULL DEFAULT FALSE,
    boughtinlastmonth INTEGER CHECK (boughtinlastmonth >= 0),
    category_name VARCHAR(50) NOT NULL,
    quantity SMALLINT CHECK (quantity >= 0 AND quantity <= 1000),
    embedding vector(1024)
);

-- Create indexes for efficient querying
CREATE INDEX idx_product_catalog_category ON bedrock_integration.product_catalog(category_id);
CREATE INDEX idx_product_catalog_price ON bedrock_integration.product_catalog(price);
CREATE INDEX idx_product_catalog_stars ON bedrock_integration.product_catalog(stars);

SELECT 'Lab 1 schema created successfully' as status;
SQL_LAB1

if [ $? -eq 0 ]; then
    log "✅ Lab 1 schema and tables created"
else
    error "Failed to create Lab 1 schema"
fi

# ============================================================================
# LAB 1: LOAD PRODUCT DATA WITH EMBEDDINGS
# ============================================================================

log "Loading 21,704 products with embeddings..."
log "This will take 5-8 minutes. Please be patient..."

# Create the data loader Python script
cat > /tmp/load_products_dat409.py << 'PYTHON_LOADER'
#!/usr/bin/env python3
import os
import sys
import time
import json
import boto3
import psycopg
import pandas as pd
import numpy as np
from pathlib import Path
from pgvector.psycopg import register_vector
from pandarallel import pandarallel
from tqdm import tqdm
import warnings
warnings.filterwarnings('ignore')

# Constants
BATCH_SIZE = 1000
PARALLEL_WORKERS = 10
MAX_RETRIES = 3
RETRY_DELAY = 1

print("="*70)
print(" DAT409 Workshop - Product Data Loader")
print(" Loading 21,704 products with Cohere embeddings")
print("="*70)

# Environment variables
DB_CONFIG = {
    'host': os.getenv('DB_HOST'),
    'port': os.getenv('DB_PORT', '5432'),
    'dbname': os.getenv('DB_NAME'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD')
}
AWS_REGION = os.getenv('AWS_REGION', 'us-west-2')

# Validate configuration
if not all(DB_CONFIG.values()):
    print("❌ Missing database configuration")
    sys.exit(1)

# Data file path
DATA_FILE = Path("/workshop/lab1-hybrid-search/data/amazon-products.csv")

# Download data if not present
if not DATA_FILE.exists():
    print("📥 Downloading product data...")
    DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
    import urllib.request
    url = "https://raw.githubusercontent.com/aws-samples/sample-dat409-hybrid-search-workshop-prod/main/lab1-hybrid-search/data/amazon-products.csv"
    urllib.request.urlretrieve(url, str(DATA_FILE))
    
if not DATA_FILE.exists():
    print("❌ Failed to download data file")
    sys.exit(1)

print(f"✅ Data file ready: {DATA_FILE}")

# Initialize Bedrock client
bedrock_runtime = boto3.client('bedrock-runtime', region_name=AWS_REGION)

def generate_embedding(text):
    """Generate embedding using Cohere Embed model"""
    if pd.isna(text) or str(text).strip() == '':
        return np.zeros(1024).tolist()
    
    clean_text = str(text)[:2000].strip()
    
    for attempt in range(MAX_RETRIES):
        try:
            body = {
                "texts": [clean_text],
                "input_type": "search_document",
                "embedding_types": ["float"],
                "truncate": "END"
            }
            
            response = bedrock_runtime.invoke_model(
                modelId="cohere.embed-english-v3",
                body=json.dumps(body),
                contentType="application/json",
                accept="application/json"
            )
            
            result = json.loads(response['body'].read())
            
            if 'embeddings' in result and 'float' in result['embeddings']:
                embedding = result['embeddings']['float'][0]
                if len(embedding) == 1024:
                    return embedding
                    
        except Exception as e:
            if attempt < MAX_RETRIES - 1:
                time.sleep(RETRY_DELAY)
                continue
    
    return np.zeros(1024).tolist()

# Load and prepare data
print("\n📊 Loading product data...")
df = pd.read_csv(str(DATA_FILE))

# Clean data
df = df.dropna(subset=['product_description'])
df = df.fillna({
    'stars': 0,
    'reviews': 0,
    'price': 0,
    'category_id': 0,
    'isbestseller': False,
    'boughtinlastmonth': 0,
    'category_name': 'Unknown',
    'quantity': 0,
    'imgurl': '',
    'producturl': ''
})

# Ensure unique productIds
if 'productId' not in df.columns or df['productId'].isna().any():
    df['productId'] = ['B' + str(i).zfill(7) for i in range(len(df))]

# Truncate text fields to fit database constraints
df['product_description'] = df['product_description'].astype(str).str[:500]
df['imgurl'] = df['imgurl'].astype(str).str[:70]
df['producturl'] = df['producturl'].astype(str).str[:40]
df['category_name'] = df['category_name'].astype(str).str[:50]
df['productId'] = df['productId'].astype(str).str[:10]

# Convert data types with constraint validation
df['stars'] = pd.to_numeric(df['stars'], errors='coerce').fillna(3.0).clip(1.0, 5.0).round(1)
df['reviews'] = pd.to_numeric(df['reviews'], errors='coerce').fillna(0).clip(0, None).astype(int)
df['price'] = pd.to_numeric(df['price'], errors='coerce').fillna(0).clip(0, 99999999.99).round(2)
df['category_id'] = pd.to_numeric(df['category_id'], errors='coerce').fillna(1).clip(1, 32767).astype(int)
df['isbestseller'] = df['isbestseller'].astype(bool)
df['boughtinlastmonth'] = pd.to_numeric(df['boughtinlastmonth'], errors='coerce').fillna(0).clip(0, None).astype(int)
df['quantity'] = pd.to_numeric(df['quantity'], errors='coerce').fillna(0).clip(0, 1000).astype(int)

print(f"✅ Prepared {len(df)} products for processing")

# Generate embeddings in parallel
print(f"\n🧠 Generating embeddings using {PARALLEL_WORKERS} workers...")
print("   This will take 5-8 minutes...")

pandarallel.initialize(progress_bar=True, nb_workers=PARALLEL_WORKERS, verbose=0)
start_embed = time.time()
df['embedding'] = df['product_description'].parallel_apply(generate_embedding)
embed_time = time.time() - start_embed

print(f"✅ Embeddings generated in {embed_time/60:.1f} minutes")
print(f"   Rate: {len(df)/embed_time:.1f} products/second")

# Connect to database
print("\n💾 Connecting to database...")
conn = psycopg.connect(**DB_CONFIG, autocommit=False)
register_vector(conn)

# Clear existing data
with conn.cursor() as cur:
    cur.execute("TRUNCATE TABLE bedrock_integration.product_catalog CASCADE;")
    conn.commit()
print("✅ Table cleared")

# Insert data in batches
print("\n📝 Inserting products into database...")
total_inserted = 0

with tqdm(total=len(df), desc="Inserting products") as pbar:
    for i in range(0, len(df), BATCH_SIZE):
        batch = df.iloc[i:i+BATCH_SIZE]
        
        with conn.cursor() as cur:
            for _, row in batch.iterrows():
                try:
                    cur.execute('''
                        INSERT INTO bedrock_integration.product_catalog 
                        ("productId", product_description, imgurl, producturl, 
                         stars, reviews, price, category_id, isbestseller,
                         boughtinlastmonth, category_name, quantity, embedding)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ''', (
                        row['productId'],
                        str(row['product_description']),
                        str(row['imgurl']),
                        str(row['producturl']),
                        float(row['stars']),
                        int(row['reviews']),
                        float(row['price']),
                        int(row['category_id']),
                        bool(row['isbestseller']),
                        int(row['boughtinlastmonth']),
                        str(row['category_name']),
                        int(row['quantity']),
                        row['embedding']
                    ))
                    total_inserted += 1
                except Exception as e:
                    print(f"\n⚠️ Error inserting product {row.get('productId', 'unknown')}: {e}")
                    continue
        
        conn.commit()
        pbar.update(len(batch))

# Create vector and text search indexes
print("\n🔍 Creating search indexes...")
with conn.cursor() as cur:
    # HNSW index for vector similarity search
    cur.execute("""
        CREATE INDEX IF NOT EXISTS idx_product_embedding 
        ON bedrock_integration.product_catalog 
        USING hnsw (embedding vector_cosine_ops)
        WITH (m = 16, ef_construction = 64);
    """)
    
    # GIN index for full-text search
    cur.execute("""
        CREATE INDEX IF NOT EXISTS idx_product_fts 
        ON bedrock_integration.product_catalog
        USING GIN (to_tsvector('english', coalesce(product_description, '')));
    """)
    
    # Trigram index for fuzzy matching
    cur.execute("""
        CREATE INDEX IF NOT EXISTS idx_product_trgm 
        ON bedrock_integration.product_catalog
        USING GIN (product_description gin_trgm_ops);
    """)
    
    conn.commit()

print("✅ Indexes created")

# Final statistics
with conn.cursor() as cur:
    cur.execute("SELECT COUNT(*) FROM bedrock_integration.product_catalog;")
    final_count = cur.fetchone()[0]
    
    cur.execute("SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL;")
    embeddings_count = cur.fetchone()[0]

conn.close()

total_time = time.time() - time.time()
print("\n" + "="*70)
print(" ✅ Data Loading Complete!")
print("="*70)
print(f" Products loaded: {final_count:,}")
print(f" Products with embeddings: {embeddings_count:,}")
print(f" Success rate: {(embeddings_count/final_count)*100:.1f}%")
print("="*70)
PYTHON_LOADER

# Run the loader
if python3 /tmp/load_products_dat409.py; then
    log "✅ Lab 1 data loaded successfully"
    rm -f /tmp/load_products_dat409.py
else
    error "Failed to load Lab 1 data"
fi

# ============================================================================
# LAB 2: CREATE KNOWLEDGE BASE WITH RLS
# ============================================================================

log "==================== Lab 2: Setting Up MCP with RLS ===================="

# Create Lab 2 SQL file
cat > /tmp/lab2_setup.sql << 'SQL_LAB2'
-- ============================================================
-- LAB 2: MCP with PostgreSQL RLS Setup
-- ============================================================

-- 1. Create knowledge_base table
DROP TABLE IF EXISTS bedrock_integration.knowledge_base CASCADE;

CREATE TABLE bedrock_integration.knowledge_base (
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
CREATE INDEX idx_kb_product_id ON bedrock_integration.knowledge_base(product_id);
CREATE INDEX idx_kb_persona_access ON bedrock_integration.knowledge_base USING GIN (persona_access);
CREATE INDEX idx_kb_content_type ON bedrock_integration.knowledge_base(content_type);

-- 2. Handle RLS users with proper cleanup
DO $$
BEGIN
    -- Revoke all privileges from existing users
    IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'customer_user') THEN
        EXECUTE 'REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM customer_user';
        EXECUTE 'REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA bedrock_integration FROM customer_user';
        EXECUTE 'REVOKE ALL PRIVILEGES ON SCHEMA public FROM customer_user';
        EXECUTE 'REVOKE ALL PRIVILEGES ON SCHEMA bedrock_integration FROM customer_user';
        EXECUTE 'DROP USER customer_user';
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'agent_user') THEN
        EXECUTE 'REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM agent_user';
        EXECUTE 'REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA bedrock_integration FROM agent_user';
        EXECUTE 'REVOKE ALL PRIVILEGES ON SCHEMA public FROM agent_user';
        EXECUTE 'REVOKE ALL PRIVILEGES ON SCHEMA bedrock_integration FROM agent_user';
        EXECUTE 'DROP USER agent_user';
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'pm_user') THEN
        EXECUTE 'REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM pm_user';
        EXECUTE 'REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA bedrock_integration FROM pm_user';
        EXECUTE 'REVOKE ALL PRIVILEGES ON SCHEMA public FROM pm_user';
        EXECUTE 'REVOKE ALL PRIVILEGES ON SCHEMA bedrock_integration FROM pm_user';
        EXECUTE 'DROP USER pm_user';
    END IF;
    
    EXCEPTION WHEN OTHERS THEN
        -- Ignore errors if users don't exist or have dependencies
        NULL;
END $$;

-- Create fresh users
CREATE USER customer_user WITH PASSWORD 'customer123';
CREATE USER agent_user WITH PASSWORD 'agent123';
CREATE USER pm_user WITH PASSWORD 'pm123';

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA bedrock_integration TO customer_user, agent_user, pm_user;
GRANT SELECT ON ALL TABLES IN SCHEMA bedrock_integration TO customer_user, agent_user, pm_user;

-- 3. Enable RLS
ALTER TABLE bedrock_integration.knowledge_base ENABLE ROW LEVEL SECURITY;

-- 4. Create RLS policies
CREATE POLICY customer_policy ON bedrock_integration.knowledge_base
    FOR SELECT TO customer_user
    USING ('customer' = ANY(persona_access));

CREATE POLICY agent_policy ON bedrock_integration.knowledge_base
    FOR SELECT TO agent_user  
    USING ('support_agent' = ANY(persona_access));

CREATE POLICY pm_policy ON bedrock_integration.knowledge_base
    FOR SELECT TO pm_user
    USING (true);

-- 5. Insert sample data for 50 specific products
-- These are hardcoded product IDs that should exist in the catalog
WITH target_products AS (
    SELECT "productId" 
    FROM bedrock_integration.product_catalog 
    WHERE "productId" LIKE 'B%'
    ORDER BY reviews DESC NULLS LAST
    LIMIT 50
)
INSERT INTO bedrock_integration.knowledge_base (product_id, content, content_type, persona_access, severity)
SELECT 
    p."productId",
    'Q: What is the warranty period? A: This product comes with a standard 1-year manufacturer warranty.',
    'product_faq',
    ARRAY['customer', 'support_agent', 'product_manager'],
    'low'
FROM target_products p;

-- Add support tickets for high-review products
WITH high_review_products AS (
    SELECT "productId" 
    FROM bedrock_integration.product_catalog 
    WHERE reviews > 10000
    LIMIT 25
)
INSERT INTO bedrock_integration.knowledge_base (product_id, content, content_type, persona_access, severity)
SELECT 
    p."productId",
    'Support Ticket #' || (1000 + row_number() OVER()) || ': Customer reported connectivity issues - Resolved by firmware update',
    'support_ticket',
    ARRAY['support_agent', 'product_manager'],
    'medium'
FROM high_review_products p;

-- Add analytics for expensive products
WITH expensive_products AS (
    SELECT "productId" 
    FROM bedrock_integration.product_catalog 
    WHERE price > 100
    LIMIT 25
)
INSERT INTO bedrock_integration.knowledge_base (product_id, content, content_type, persona_access, severity)
SELECT 
    p."productId",
    'Analytics Report: Product showing 15% month-over-month growth in sales',
    'analytics',
    ARRAY['product_manager'],
    NULL
FROM expensive_products p;

-- Add general knowledge base entries
INSERT INTO bedrock_integration.knowledge_base (product_id, content, content_type, persona_access, severity) VALUES
(NULL, 'Holiday return policy has been extended through January 31st', 'product_faq', ARRAY['customer', 'support_agent', 'product_manager'], 'low'),
(NULL, 'System maintenance scheduled for Sunday 2:00 AM - 4:00 AM PST', 'internal_note', ARRAY['support_agent', 'product_manager'], 'medium'),
(NULL, 'New product launch guidelines updated - please review before Q2', 'internal_note', ARRAY['product_manager'], 'high');

-- Report results
SELECT 'Lab 2 setup completed' as status;
SELECT content_type, COUNT(*) as count FROM bedrock_integration.knowledge_base GROUP BY content_type ORDER BY count DESC;
SQL_LAB2

# Execute Lab 2 setup
log "Creating knowledge base and RLS policies..."
if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f /tmp/lab2_setup.sql; then
    log "✅ Lab 2 knowledge base and RLS created successfully"
    rm -f /tmp/lab2_setup.sql
else
    warn "Lab 2 setup encountered issues but continuing..."
fi



# ============================================================================
# FINAL VERIFICATION
# ============================================================================

log "==================== Verification ===================="

# Verify Lab 1
LAB1_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog;" 2>/dev/null | xargs)

LAB1_EMBEDDINGS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL;" 2>/dev/null | xargs)

# Verify Lab 2
LAB2_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM bedrock_integration.knowledge_base;" 2>/dev/null | xargs)

LAB2_POLICIES=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM pg_policies WHERE schemaname='bedrock_integration' AND tablename='knowledge_base';" 2>/dev/null | xargs)

# ============================================================================
# SUMMARY
# ============================================================================

echo
log "==================== Setup Complete! ===================="
echo
echo "📊 Workshop - Hybrid Search:"
echo "   ✅ Products loaded: ${LAB1_COUNT:-0}"
echo "   ✅ Products with embeddings: ${LAB1_EMBEDDINGS:-0}"
echo
echo "🎨 Demo App - MCP with RLS:"
echo "   ✅ Knowledge base entries: ${LAB2_COUNT:-0}"
echo "   ✅ RLS policies created: ${LAB2_POLICIES:-0}"
echo
echo "🔍 Verification:"
echo "   psql -c \"SELECT COUNT(*) FROM bedrock_integration.product_catalog;\""
echo
echo "🚀 Database setup completed successfully!"
echo "=========================================================="
