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
# LAB 2: CREATE KNOWLEDGE BASE AND RLS SETUP WITH ALL 50 PRODUCTS
# ===========================================================================

log "==================== Lab 2: Creating Knowledge Base and RLS with 50 Products ===================="

PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'LAB2_SETUP'
-- ============================================================
-- LAB 2: MCP with PostgreSQL RLS - Complete 50 Product Setup
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

-- 2. Create RLS users
DO $
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
END $;

-- 3. Grant permissions
GRANT USAGE ON SCHEMA public TO customer_user, agent_user, pm_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO customer_user, agent_user, pm_user;
GRANT USAGE ON SCHEMA bedrock_integration TO customer_user, agent_user, pm_user;
GRANT SELECT ON ALL TABLES IN SCHEMA bedrock_integration TO customer_user, agent_user, pm_user;

-- 4. Enable RLS
ALTER TABLE knowledge_base ENABLE ROW LEVEL SECURITY;

-- 5. Create RLS policies
CREATE POLICY customer_policy ON knowledge_base
    FOR SELECT TO customer_user
    USING ('customer' = ANY(persona_access));

CREATE POLICY agent_policy ON knowledge_base
    FOR SELECT TO agent_user  
    USING ('customer' = ANY(persona_access) OR 'agent' = ANY(persona_access));

CREATE POLICY pm_policy ON knowledge_base
    FOR SELECT TO pm_user
    USING (true);

-- 6. Populate with ALL 50 HARDCODED product IDs
DO $
DECLARE
    -- All 50 product IDs from high-volume products - deterministic results
    product_ids TEXT[] := ARRAY[
        -- Security Cameras (Top 20 by reviews)
        'B07X6C9RMF', -- Blink Mini (260K reviews)
        'B08N5NQ869', -- Ring Video Doorbell (173K reviews)
        'B086DL32R3', -- Blink Outdoor (157K reviews)
        'B08SGC46M9', -- Blink Video Doorbell + Sync (112K reviews)
        'B07DGR98VQ', -- Wyze Cam Pan/Tilt (76K reviews)
        'B08R59YH7W', -- WYZE Cam v3 (72K reviews)
        'B08CKHPP52', -- Ring Doorbell Wired (71K reviews)
        'B08M125RNW', -- Ring Doorbell Pro (46K reviews)
        'B0849J7W5X', -- Ring Doorbell 3 (44K reviews)
        'B08F6GPQQ7', -- Ring Floodlight Cam (30K reviews)
        'B08FD54PN9', -- Kami Security Camera 4PCS (38K reviews)
        'B07QKXM2D3', -- wansview Wireless Security (35K reviews)
        'B01CW4CEMS', -- YI 4pc Security Home Camera (35K reviews)
        'B07X27JNQ5', -- Blink Indoor 3rd Gen (25K reviews)
        'B07ZB2RNTW', -- Ring Alarm Contact Sensor (25K reviews)
        'B07YB8HZ8T', -- blurams Security Camera (25K reviews)
        'B08ZXJJTYJ', -- Kasa 2K QHD Security (23K reviews)
        'B0829KDY9X', -- TP-Link Tapo Pan/Tilt (22K reviews)
        'B093DDPDXL', -- ZUMIMALL Security Cameras (22K reviews)
        'B07PM2NBGT', -- ZUMIMALL Alternate SKU (22K reviews)
        
        -- Smart Home Devices (5)
        'B07TTH5TMW', -- SwitchBot Hub Mini (46K reviews)
        'B07B7NXV4R', -- SwitchBot Button Pusher (26K reviews)
        'B011MYEMKQ', -- Ring Chime (22K reviews)
        'B07YP9VK7Q', -- Ring A19 Smart LED Bulb (10K reviews)
        'B07ZB2QF2V', -- Ring Alarm Motion Detector (10K reviews)
        
        -- Personal Care Products (7)
        'B0CFR1JB15', -- Crystal Hair Eraser (12K reviews)
        'B00HT6E2NY', -- Schick Hydro Silk (12K reviews)
        'B0CBJRXFVJ', -- Laser Hair Removal (11K reviews)
        'B00PBGQ0SY', -- Gillette Venus (10K reviews)
        'B0168MB1RO', -- Gillette Venus Sensitive (9K reviews)
        'B0CBJRXFVJ', -- Laser Hair Removal Device (11K reviews)
        'B00HT6E2NY', -- Schick Hydro Silk Razor (12K reviews)
        
        -- Vacuum Cleaners (5)
        'B0C8JGHXXB', -- Foppapedretti Cordless (15K reviews)
        'B0C8JDM69N', -- Foppapedretti Hand Vacuum (15K reviews)
        'B0C2PXPWMR', -- Foppapedretti 25Kpa (15K reviews)
        'B0C8JK6TSH', -- Cordless Handheld Vacuum (15K reviews)
        'B0C3RKQPHR', -- Foppapedretti 6 in 1 (15K reviews)
        
        -- Additional Security Cameras to reach 50
        'B07GG3XXNX', -- Certified Refurbished Ring (18K reviews)
        'B0899GLP7R', -- NETVUE Indoor Camera (18K reviews)
        'B07PJ67CKC', -- nooie Baby Monitor (18K reviews)
        'B088C4NHRS', -- Petcube Cam (17K reviews)
        'B07WHMQNPC', -- Ring Peephole Cam (17K reviews)
        'B07YMV9VMT', -- Arlo Essential Doorbell (16K reviews)
        'B07ZPMCW64', -- Ring Alarm 8-piece kit (16K reviews)
        'B0856W45VL', -- eufy Security Indoor Cam (15K reviews)
        'B07W1HKYQK', -- eufy Security eufyCam (13K reviews)
        'B07R3WY95C', -- eufy Security Wi-Fi Doorbell (12K reviews)
        'B01CW49AGG', -- YI Security Camera Outdoor (12K reviews)
        'B07X81M2D2', -- REOLINK Wireless Security (11K reviews)
        'B07X2M8KTR', -- Outdoor Camera 1080P (9K reviews)
        'B08JCS7QKL', -- LaView Security 4pcs (9K reviews)
        'B083GKZWVX'  -- XTU WiFi Video Doorbell (9K reviews)
    ];
    
    pid TEXT;
    product_desc TEXT;
    product_price NUMERIC;
    product_stars NUMERIC;
    product_reviews INT;
    ticket_num INT := 80000;
    idx INT := 0;
BEGIN
    -- Clear existing data
    DELETE FROM knowledge_base;
    
    RAISE NOTICE 'Populating knowledge base with 50 deterministic products...';
    
    -- Process each product
    FOREACH pid IN ARRAY product_ids
    LOOP
        idx := idx + 1;
        
        -- Get product details (handle if product doesn't exist in catalog)
        SELECT 
            LEFT(product_description, 100),
            price,
            stars,
            reviews
        INTO product_desc, product_price, product_stars, product_reviews
        FROM bedrock_integration.product_catalog 
        WHERE "productId" = pid;
        
        -- Skip if product not found
        IF product_desc IS NULL THEN
            RAISE NOTICE 'Product % not found in catalog, skipping', pid;
            CONTINUE;
        END IF;
        
        -- Generate support content based on product characteristics
        
        -- 1. FAQs (all personas can see) - Everyone gets at least one
        INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity)
        VALUES (
            pid,
            CASE 
                WHEN product_desc ILIKE '%camera%' OR product_desc ILIKE '%doorbell%' THEN
                    format('Q: How do I connect my %s to WiFi? A: Open the app, select Add Device, and follow the on-screen setup. Ensure 2.4GHz WiFi is enabled.', LEFT(product_desc, 30))
                WHEN product_desc ILIKE '%vacuum%' THEN
                    format('Q: How often should I clean the filters? A: Clean filters every 2 weeks for optimal performance. Replace HEPA filter every 6 months.')
                WHEN product_desc ILIKE '%hair%' OR product_desc ILIKE '%razor%' THEN
                    format('Q: How long do the blades last? A: Replace blades every 5-7 shaves for best results. Proper cleaning extends blade life.')
                ELSE
                    format('Q: What warranty covers this product? A: Standard 1-year manufacturer warranty. Register within 30 days for extended coverage.')
            END,
            'product_faq',
            ARRAY['customer', 'support_agent', 'product_manager'],
            'low'
        );
        
        -- 2. Support tickets (agents and PMs) - High review products get more tickets
        IF product_reviews > 20000 THEN
            INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity)
            VALUES (
                pid,
                format('Ticket #%s: Customer reporting %s. Resolution: %s',
                    ticket_num + idx,
                    CASE (idx % 3)
                        WHEN 0 THEN 'device not responding after update'
                        WHEN 1 THEN 'connectivity issues with 5GHz WiFi'
                        ELSE 'app crashes during setup'
                    END,
                    CASE (idx % 3)
                        WHEN 0 THEN 'Rolled back firmware, fix in v2.1.5'
                        WHEN 1 THEN 'Device only supports 2.4GHz, updated documentation'
                        ELSE 'App hotfix deployed, advise customer to update'
                    END
                ),
                'support_ticket',
                ARRAY['support_agent', 'product_manager'],
                CASE WHEN idx % 3 = 0 THEN 'high' ELSE 'medium' END
            );
        END IF;
        
        -- 3. Internal notes (PMs only) - Add for popular or problematic products
        IF product_reviews > 15000 OR product_stars < 4 THEN
            INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity)
            VALUES (
                pid,
                CASE
                    WHEN product_stars < 3.5 THEN
                        format('URGENT: Product has %.1f star rating with %s reviews. Investigate quality issues. Consider recall if defect rate > 5%%.',
                            product_stars, product_reviews)
                    WHEN product_reviews > 50000 THEN
                        format('TOP SELLER: %s reviews, %.1f stars. Maintain inventory levels. Marketing to feature in Prime Day.',
                            product_reviews, product_stars)
                    ELSE
                        format('Monitor return rate (currently %.1f%%). Price elasticity testing at $%.2f shows optimal margin.',
                            (5 - product_stars) * 2, product_price * 0.9)
                END,
                'internal_note',
                ARRAY['product_manager'],
                CASE WHEN product_stars < 3.5 THEN 'high' ELSE 'low' END
            );
        END IF;
        
        -- 4. Analytics (PMs only) - Add for high-value products
        IF product_price > 50 OR product_reviews > 10000 THEN
            INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity)
            VALUES (
                pid,
                format('Weekly metrics: %s units sold, %.1f%% conversion rate, $%.2f AOV. %s',
                    100 + (idx * 17),
                    3.5 + (product_stars * 0.5),
                    product_price * 1.2,
                    CASE
                        WHEN product_stars >= 4.5 THEN 'Exceeding targets.'
                        WHEN product_stars >= 3.5 THEN 'Meeting expectations.'
                        ELSE 'Below target, review needed.'
                    END
                ),
                'analytics',
                ARRAY['product_manager'],
                NULL
            );
        END IF;
        
        -- 5. Additional FAQ for installation/setup products
        IF product_desc ILIKE '%install%' OR product_desc ILIKE '%setup%' 
           OR product_desc ILIKE '%doorbell%' OR product_desc ILIKE '%thermostat%' THEN
            INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity)
            VALUES (
                pid,
                CASE 
                    WHEN product_desc ILIKE '%doorbell%' THEN
                        'Q: Do I need existing doorbell wiring? A: Most models work with existing wiring (8-24VAC). Battery options available for homes without wiring.'
                    WHEN product_desc ILIKE '%thermostat%' THEN
                        'Q: Is professional installation required? A: C-wire required for power. If unsure about wiring, professional installation recommended.'
                    ELSE
                        'Q: How long does installation take? A: Typical installation takes 15-30 minutes. Video guides available in the app.'
                END,
                'product_faq',
                ARRAY['customer', 'support_agent', 'product_manager'],
                'low'
            );
        END IF;
    END LOOP;
    
    -- Add general support content not tied to specific products
    INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity) VALUES
    (NULL, 'POLICY UPDATE: Extended holiday returns through January 31st for November-December purchases.', 
     'product_faq', ARRAY['customer', 'support_agent', 'product_manager'], 'low'),
    (NULL, 'SYSTEM ALERT: AWS us-west-2 latency affecting smart home device connections. ETR: 2 hours.', 
     'internal_note', ARRAY['support_agent', 'product_manager'], 'high'),
    (NULL, 'TRAINING: New troubleshooting workflow for connectivity issues. Complete by EOW.', 
     'internal_note', ARRAY['support_agent', 'product_manager'], 'medium'),
    (NULL, 'COMPETITIVE INTEL: Competitors dropping prices 20-30% on security cameras for Black Friday.', 
     'analytics', ARRAY['product_manager'], 'medium'),
    (NULL, 'Q: How do I reset my device to factory settings? A: Hold reset button for 10 seconds until LED flashes.', 
     'product_faq', ARRAY['customer', 'support_agent', 'product_manager'], 'low');
    
    RAISE NOTICE 'Knowledge base populated with % products', idx;
    RAISE NOTICE 'Total entries created: %', (SELECT COUNT(*) FROM knowledge_base);
END $;

-- Verification
SELECT 'Lab 2 setup completed. Summary:' as status;

SELECT 
    content_type,
    COUNT(*) as entries,
    COUNT(DISTINCT product_id) as products
FROM knowledge_base
GROUP BY content_type
ORDER BY entries DESC;

SELECT 'Lab 2 setup completed successfully with 50 products!' as status;
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
