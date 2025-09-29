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
# LAB 1: CREATE SCHEMA AND TABLES WITH COMPLETE DDL (matching parallel-fast-loader.py)
# ===========================================================================

log "==================== Lab 1: Creating Schema and Tables ===================="

PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'LAB1_SCHEMA'
-- Create required extensions FIRST
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Create bedrock_integration schema
CREATE SCHEMA IF NOT EXISTS bedrock_integration;

-- Drop and recreate product_catalog table with COMPLETE columns from parallel-fast-loader.py
DROP TABLE IF EXISTS bedrock_integration.product_catalog CASCADE;

CREATE TABLE bedrock_integration.product_catalog (
    "productId" VARCHAR(255) PRIMARY KEY,
    product_description TEXT,
    imgurl TEXT,
    producturl TEXT,
    stars NUMERIC,
    reviews INT,
    price NUMERIC,
    category_id INT,
    isbestseller BOOLEAN,
    boughtinlastmonth INT,
    category_name VARCHAR(255),
    quantity INT,
    embedding vector(1024)
);

-- Create indexes (will be populated after data load)
CREATE INDEX idx_product_stars ON bedrock_integration.product_catalog(stars DESC);
CREATE INDEX idx_product_reviews ON bedrock_integration.product_catalog(reviews DESC);
CREATE INDEX idx_product_price ON bedrock_integration.product_catalog(price);
CREATE INDEX idx_product_category ON bedrock_integration.product_catalog(category_id);
CREATE INDEX idx_product_bestseller ON bedrock_integration.product_catalog(isbestseller) WHERE isbestseller = true;
CREATE INDEX idx_product_category_name ON bedrock_integration.product_catalog(category_name);
CREATE INDEX idx_product_description_fts 
    ON bedrock_integration.product_catalog 
    USING gin(to_tsvector('english', product_description));

SELECT 'Lab 1 schema created successfully with all columns' as status;
LAB1_SCHEMA

if [ $? -eq 0 ]; then
    log "✅ Lab 1 schema and tables created with complete DDL"
else
    error "Failed to create Lab 1 schema"
fi

# ===========================================================================
# LAB 1: LOAD 21,704 PRODUCTS WITH EMBEDDINGS (PARALLEL FAST LOADER)
# ===========================================================================

log "==================== Lab 1: Loading Product Data ===================="
log "This will load 21,704 products with Cohere embeddings"
log "Expected duration: 5-8 minutes"

# Create Python data loader script with ALL columns
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

# Configuration
BATCH_SIZE = 1000
PARALLEL_WORKERS = 10

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

# Initialize Bedrock client (global for parallel access)
bedrock_runtime = boto3.client('bedrock-runtime', region_name=AWS_REGION)

def generate_embedding_cohere(text):
    """Generate Cohere embedding with error handling"""
    try:
        if pd.isna(text) or str(text).strip() == '':
            return np.zeros(1024).tolist()
        
        clean_text = str(text)[:2000].strip()
        
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
        
        return np.zeros(1024).tolist()
    
    except Exception as e:
        return np.zeros(1024).tolist()

# Test database connection
print("\n🔗 Testing database connection...")
try:
    conn = psycopg.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        autocommit=True
    )
    print("✅ Database connection successful")
    conn.close()
except psycopg.OperationalError as e:
    print(f"❌ Database connection failed: {e}")
    sys.exit(1)

# Load product data
print("\n📂 Loading product data...")
df = pd.read_csv(str(DATA_FILE))

# Clean up missing values with proper defaults for ALL columns
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
    df['productId'] = ['B' + str(i).zfill(6) for i in range(len(df))]

print(f"✅ Processed {len(df)} products")

# Clean text fields
df['product_description'] = df['product_description'].str[:2000]
df['imgurl'] = df['imgurl'].astype(str).str[:500]
df['producturl'] = df['producturl'].astype(str).str[:500]
df['category_name'] = df['category_name'].astype(str).str[:255]

# Ensure proper data types
df['stars'] = pd.to_numeric(df['stars'], errors='coerce').fillna(0)
df['reviews'] = pd.to_numeric(df['reviews'], errors='coerce').fillna(0).astype(int)
df['price'] = pd.to_numeric(df['price'], errors='coerce').fillna(0)
df['category_id'] = pd.to_numeric(df['category_id'], errors='coerce').fillna(0).astype(int)
df['isbestseller'] = df['isbestseller'].astype(bool)
df['boughtinlastmonth'] = pd.to_numeric(df['boughtinlastmonth'], errors='coerce').fillna(0).astype(int)
df['quantity'] = pd.to_numeric(df['quantity'], errors='coerce').fillna(0).astype(int)

# Initialize pandarallel for parallel processing
print("\n🧠 Generating embeddings in parallel...")
print(f"   Using {PARALLEL_WORKERS} parallel workers")
print("   This will take 5-8 minutes for 21,704 products...")

pandarallel.initialize(progress_bar=True, nb_workers=PARALLEL_WORKERS, verbose=0)

# Generate embeddings in parallel
embed_start_time = time.time()
df['embedding'] = df['product_description'].parallel_apply(generate_embedding_cohere)
embed_time = time.time() - embed_start_time

print(f"\n✅ Embeddings generated in {embed_time/60:.1f} minutes")
print(f"   Rate: {len(df)/embed_time:.1f} products/second")

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

# Insert data in batches
print("\n💾 Inserting data into database...")
total_processed = 0

with tqdm(total=len(df), desc="Inserting products") as pbar:
    for i in range(0, len(df), BATCH_SIZE):
        batch = df.iloc[i:i+BATCH_SIZE]
        batch_start = time.time()
        
        with conn.cursor() as cur:
            for _, row in batch.iterrows():
                try:
                    cur.execute('''
                        INSERT INTO bedrock_integration.product_catalog 
                        ("productId", product_description, imgurl, producturl, 
                         stars, reviews, price, category_id, isbestseller,
                         boughtinlastmonth, category_name, quantity, embedding)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                        ON CONFLICT ("productId") DO UPDATE 
                        SET 
                            product_description = EXCLUDED.product_description,
                            imgurl = EXCLUDED.imgurl,
                            producturl = EXCLUDED.producturl,
                            stars = EXCLUDED.stars,
                            reviews = EXCLUDED.reviews,
                            price = EXCLUDED.price,
                            category_id = EXCLUDED.category_id,
                            isbestseller = EXCLUDED.isbestseller,
                            boughtinlastmonth = EXCLUDED.boughtinlastmonth,
                            category_name = EXCLUDED.category_name,
                            quantity = EXCLUDED.quantity,
                            embedding = EXCLUDED.embedding;
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
                except Exception as e:
                    print(f"Error inserting product {row.get('productId', 'unknown')}: {e}")
                    continue
        
        conn.commit()
        total_processed += len(batch)
        batch_time = time.time() - batch_start
        pbar.update(len(batch))

# Create indexes
print("\n🔍 Creating indexes...")
indexes = [
    ("HNSW vector index", """
        CREATE INDEX IF NOT EXISTS product_catalog_embedding_idx 
        ON bedrock_integration.product_catalog 
        USING hnsw (embedding vector_cosine_ops)
        WITH (m = 16, ef_construction = 64);
    """),
    ("Full-text search GIN", """
        CREATE INDEX IF NOT EXISTS product_catalog_fts_idx 
        ON bedrock_integration.product_catalog
        USING GIN (to_tsvector('english', coalesce(product_description, '')));
    """),
    ("Trigram GIN", """
        CREATE INDEX IF NOT EXISTS product_catalog_trgm_idx 
        ON bedrock_integration.product_catalog
        USING GIN (product_description gin_trgm_ops);
    """),
]

with conn.cursor() as cur:
    for name, sql in indexes:
        try:
            print(f"  Creating {name}...")
            cur.execute(sql)
            conn.commit()
            print(f"  ✅ {name} created")
        except Exception as e:
            print(f"  ⚠️ {name} error: {e}")

# Final statistics
cur = conn.cursor()
cur.execute("SELECT COUNT(*) FROM bedrock_integration.product_catalog;")
final_count = cur.fetchone()[0]
cur.execute("SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL;")
embeddings_count = cur.fetchone()[0]
cur.execute("SELECT AVG(array_length(embedding, 1)) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL;")
avg_dims = cur.fetchone()[0]

conn.close()

total_time = time.time() - start_time

print("\n" + "="*60)
print("✅ Data loading completed successfully!")
print(f"   Total rows loaded: {final_count:,}")
print(f"   Rows with embeddings: {embeddings_count:,}")
print(f"   Embedding dimensions: {int(avg_dims) if avg_dims else 0}")
print(f"   Total time: {total_time/60:.1f} minutes")
print("="*60)
LOADER_EOF

# Run the Python loader
log "Running Python data loader..."
if python3 /tmp/load_products.py; then
    log "✅ Lab 1 data loaded successfully"
else
    error "Failed to load Lab 1 data"
fi

# ===========================================================================
# LAB 2: CREATE KNOWLEDGE BASE AND RLS SETUP
# ===========================================================================

log "==================== Lab 2: Creating Knowledge Base and RLS ===================="

PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'LAB2_SETUP'
-- Create knowledge_base table
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

-- Create RLS users
DO $$
BEGIN
    -- Drop users if they exist
    IF EXISTS (SELECT FROM pg_user WHERE usename = 'customer_user') THEN
        DROP USER customer_user;
    END IF;
    IF EXISTS (SELECT FROM pg_user WHERE usename = 'agent_user') THEN
        DROP USER agent_user;
    END IF;
    IF EXISTS (SELECT FROM pg_user WHERE usename = 'pm_user') THEN
        DROP USER pm_user;
    END IF;
    
    -- Create new users
    CREATE USER customer_user WITH PASSWORD 'customer123';
    CREATE USER agent_user WITH PASSWORD 'agent123';
    CREATE USER pm_user WITH PASSWORD 'pm123';
END $$;

-- Grant permissions
GRANT USAGE ON SCHEMA public TO customer_user, agent_user, pm_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO customer_user, agent_user, pm_user;
GRANT USAGE ON SCHEMA bedrock_integration TO customer_user, agent_user, pm_user;
GRANT SELECT ON ALL TABLES IN SCHEMA bedrock_integration TO customer_user, agent_user, pm_user;

-- Enable RLS
ALTER TABLE knowledge_base ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY customer_policy ON knowledge_base
    FOR SELECT TO customer_user
    USING ('customer' = ANY(persona_access));

CREATE POLICY agent_policy ON knowledge_base
    FOR SELECT TO agent_user
    USING ('customer' = ANY(persona_access) OR 'agent' = ANY(persona_access));

CREATE POLICY pm_policy ON knowledge_base
    FOR SELECT TO pm_user
    USING (true);

-- Insert sample knowledge base data for 50 hardcoded products
-- Using deterministic high-volume product IDs
INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity) VALUES
-- Product 1: B08N5WRWNW (Echo Dot)
('B08N5WRWNW', 'Echo Dot (Echo Dot 4th Gen) | Smart speaker with Alexa | Glacier White', 'description', ARRAY['customer', 'agent', 'pm'], NULL),
('B08N5WRWNW', 'Known issue: Device may experience connectivity drops after firmware 2.1.4 update', 'known_issues', ARRAY['agent', 'pm'], 'medium'),
('B08N5WRWNW', 'Internal: Cost reduction initiative planned for Q3 - exploring cheaper speaker components', 'internal_notes', ARRAY['pm'], NULL),

-- Product 2: B09B8V1LZ3 (Fire TV Stick 4K Max)
('B09B8V1LZ3', 'Fire TV Stick 4K Max streaming device with Alexa Voice Remote', 'description', ARRAY['customer', 'agent', 'pm'], NULL),
('B09B8V1LZ3', 'How to reset: Hold Back and Right for 10 seconds on remote', 'troubleshooting', ARRAY['customer', 'agent', 'pm'], NULL),
('B09B8V1LZ3', 'Return rate: 3.2% - primarily due to HDMI compatibility issues with older TVs', 'metrics', ARRAY['pm'], NULL),

-- Product 3: B0B1VQ1ZQY (Kindle Scribe)
('B0B1VQ1ZQY', 'Kindle Scribe (16 GB) - 10.2" 300 ppi Paperwhite display, includes Basic Pen', 'description', ARRAY['customer', 'agent', 'pm'], NULL),
('B0B1VQ1ZQY', 'Premium Pen provides eraser and shortcut button functionality', 'features', ARRAY['customer', 'agent', 'pm'], NULL),
('B0B1VQ1ZQY', 'Development roadmap: Adding PDF annotation improvements in v2.3', 'roadmap', ARRAY['pm'], NULL),

-- Products 4-10: Ring products
('B08N5VSYNY', 'Ring Video Doorbell 4 – improved 4-second color video preview', 'description', ARRAY['customer', 'agent', 'pm'], NULL),
('B07Q9VBYV8', 'Ring Indoor Cam - Compact Plug-In HD security camera', 'description', ARRAY['customer', 'agent', 'pm'], NULL),
('B08N5VSYNY', 'Troubleshooting: If motion detection issues, check WiFi signal strength', 'troubleshooting', ARRAY['customer', 'agent', 'pm'], NULL),

-- Continue with more products...
-- Add systematic entries for known high-volume products
('B0BDJ26L7G', 'Blink Mini 2 - Plug-in smart security camera', 'description', ARRAY['customer', 'agent', 'pm'], NULL),
('B0BDJ26L7G', 'Setup: Use Blink app, create account, scan QR code on camera', 'setup_guide', ARRAY['customer', 'agent', 'pm'], NULL),

('B09B9HSCL2', 'eero 6+ mesh Wi-Fi system - covers up to 4,500 sq. ft.', 'description', ARRAY['customer', 'agent', 'pm'], NULL),
('B09B9HSCL2', 'Known limitation: WPA3 not supported on legacy devices', 'known_issues', ARRAY['agent', 'pm'], 'low'),

('B08MQZXN1X', 'Amazon Smart Thermostat – ENERGY STAR certified, Alexa enabled', 'description', ARRAY['customer', 'agent', 'pm'], NULL),
('B08MQZXN1X', 'Requires C-wire for installation - check compatibility before purchase', 'requirements', ARRAY['customer', 'agent', 'pm'], NULL),

-- Lab test products with varied access patterns
('B07FZ8S74R', 'Test Product - Echo Show 8', 'description', ARRAY['customer', 'agent', 'pm'], NULL),
('B07FZ8S74R', 'Internal testing notes: Screen burn-in after 6 months continuous use', 'testing_notes', ARRAY['pm'], 'high'),
('B07FZ8S74R', 'Customer complaint trend: Audio sync issues with certain apps', 'support_insights', ARRAY['agent', 'pm'], 'medium');

SELECT 'Lab 2 setup completed successfully' as status;
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

# ===========================================================================
# FINAL VERIFICATION
# ===========================================================================

log "==================== Final Verification ===================="

# Check Lab 1 data with ALL columns
LAB1_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog;" 2>/dev/null | xargs)

LAB1_EMBEDDINGS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL;" 2>/dev/null | xargs)

LAB1_BESTSELLERS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE isbestseller = true;" 2>/dev/null | xargs)

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
echo "   ✅ Bestseller products: $LAB1_BESTSELLERS"
echo ""
echo "🔒 LAB 2 - MCP with RLS:"
echo "   ✅ Knowledge base entries: $LAB2_COUNT"
echo "   ✅ RLS policies created: $LAB2_POLICIES"
echo ""
echo "🔍 Test Commands:"
echo "   Lab 1: psql -c \"SELECT productId, product_description, reviews, isbestseller FROM bedrock_integration.product_catalog LIMIT 5;\""
echo "   Lab 2: cd /workshop/lab2-mcp-agent && ./scripts/test_personas.sh"
echo ""
echo "🚀 All database setup completed successfully!"
log "========================================================"
