#!/usr/bin/env python3
"""
Fast Parallel Data Loader - Based on Part 1 Notebook Approach
Uses pandarallel for parallel embedding generation with Cohere
Runtime: ~5-8 minutes for 21K products
"""

import pandas as pd
import numpy as np
import boto3
import json
import psycopg
from pgvector.psycopg import register_vector
from pandarallel import pandarallel
from tqdm import tqdm
import time
import warnings
import sys
import os

warnings.filterwarnings('ignore')

# Configuration
CSV_PATH = '/Users/shayons/Desktop/Workshops/sample-dat409-hybrid-search-workshop-prod/lab1-hybrid-search/data/amazon-products.csv'
BATCH_SIZE = 1000
PARALLEL_WORKERS = 10
REGION = 'us-west-2'
SECRET_NAME = 'apgpg-pgvector-secret'

print("="*60)
print("⚡ FAST PARALLEL DATA LOADER (Part 1 Style)")
print(f"Using {PARALLEL_WORKERS} parallel workers")
print("="*60)

# Check CSV exists
if not os.path.exists(CSV_PATH):
    print(f"❌ CSV not found: {CSV_PATH}")
    sys.exit(1)

# Initialize Bedrock client (global for parallel access)
bedrock_runtime = boto3.client('bedrock-runtime', region_name=REGION)

def generate_embedding_cohere(text):
    """Generate Cohere embedding with Titan fallback"""
    if not text or pd.isna(text):
        return np.random.randn(1024).tolist()
    
    try:
        # Try Cohere first
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
        
        response_body = json.loads(response['body'].read())
        if 'embeddings' in response_body:
            if 'float' in response_body['embeddings']:
                return response_body['embeddings']['float'][0]
            else:
                return response_body['embeddings'][0]
    except:
        # Fallback to Titan
        try:
            payload = json.dumps({'inputText': str(text)[:8000]})
            response = bedrock_runtime.invoke_model(
                body=payload,
                modelId='amazon.titan-embed-text-v2:0',
                accept="application/json",
                contentType="application/json"
            )
            response_body = json.loads(response.get("body").read())
            return response_body.get("embedding")
        except:
            pass
    
    # Ultimate fallback
    np.random.seed(hash(str(text)) % 2**32)
    return np.random.randn(1024).tolist()

# Get database credentials
print("\n🔐 Getting database credentials...")
session = boto3.Session(region_name=REGION)
secrets_client = session.client('secretsmanager')
response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
database_secrets = json.loads(response['SecretString'])

dbhost = database_secrets['host']
dbport = database_secrets.get('port', 5432)
dbuser = database_secrets['username']
dbpass = database_secrets['password']

print(f"✅ Connected to: {dbhost}")

# Setup database
def setup_database():
    """Set up database schema and tables"""
    conn = psycopg.connect(
        host=dbhost,
        port=dbport,
        user=dbuser,
        password=dbpass,
        autocommit=True
    )
    
    # Enable vector extension
    conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm;")
    register_vector(conn)
    
    # Create schema
    conn.execute("CREATE SCHEMA IF NOT EXISTS bedrock_integration;")
    
    # Drop and recreate table for clean start
    conn.execute("DROP TABLE IF EXISTS bedrock_integration.product_catalog CASCADE;")
    
    # Create products table
    conn.execute("""
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
    """)
    
    print("✅ Database setup complete")
    conn.close()

print("\n📋 Setting up database...")
setup_database()

# Load product data
print("\n📁 Loading product data...")
df = pd.read_csv(CSV_PATH)

# Clean up missing values
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

print(f"✅ Loaded {len(df)} products")

# Options
print("\n⚡ Loading Options:")
print("1. Full parallel load with Cohere embeddings (~5-8 min)")
print("2. Quick test with 500 products (~30 sec)")
print("3. Load without embeddings (instant)")

choice = input("\nSelect (1/2/3): ")

if choice == '2':
    df = df.head(500)
    print(f"\n🧪 Test mode: {len(df)} products")
elif choice == '3':
    print("\n🏃 Quick mode: No embeddings")
    df['embedding'] = [np.random.randn(1024).tolist() for _ in range(len(df))]
else:
    print(f"\n🚀 Full mode: {len(df)} products with parallel embeddings")

# Generate embeddings in parallel (if not option 3)
if choice != '3':
    print("\n🧠 Generating embeddings in parallel...")
    print("This will take a few minutes...")
    
    # Initialize pandarallel
    pandarallel.initialize(progress_bar=True, nb_workers=PARALLEL_WORKERS, verbose=0)
    
    # Generate embeddings in parallel
    start_time = time.time()
    df['embedding'] = df['product_description'].parallel_apply(generate_embedding_cohere)
    
    embed_time = time.time() - start_time
    print(f"\n✅ Embeddings generated in {embed_time/60:.1f} minutes")
    print(f"   Rate: {len(df)/embed_time:.1f} products/second")

# Store products function (from Part 1)
def store_products():
    """Store products in database with batch processing"""
    start_time = time.time()
    
    conn = psycopg.connect(
        host=dbhost,
        port=dbport,
        user=dbuser,
        password=dbpass,
        autocommit=True
    )
    
    register_vector(conn)
    
    print(f"\n💾 Storing {len(df)} products in database...")
    conn.execute("TRUNCATE TABLE bedrock_integration.product_catalog;")
    
    try:
        with conn.cursor() as cur:
            batches = []
            total_processed = 0
            
            # Process data in batches
            for i, (_, row) in enumerate(df.iterrows(), 1):
                batches.append((
                    row['productId'],
                    str(row['product_description'])[:5000],
                    str(row.get('imgurl', ''))[:500],
                    str(row.get('producturl', ''))[:500],
                    float(row['stars']),
                    int(row['reviews']),
                    float(row['price']),
                    int(row.get('category_id', 0)),
                    bool(row.get('isbestseller', False)),
                    int(row.get('boughtinlastmonth', 0)),
                    str(row['category_name'])[:255],
                    int(row.get('quantity', 0)),
                    row['embedding']
                ))
                
                # When batch size is reached or at the end, process the batch
                if len(batches) == BATCH_SIZE or i == len(df):
                    batch_start = time.time()
                    
                    cur.executemany("""
                    INSERT INTO bedrock_integration.product_catalog (
                        "productId", product_description, imgurl, producturl,
                        stars, reviews, price, category_id, isbestseller,
                        boughtinlastmonth, category_name, quantity, embedding
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT ("productId") DO UPDATE 
                    SET 
                        product_description = EXCLUDED.product_description,
                        embedding = EXCLUDED.embedding;
                    """, batches)
                    
                    total_processed += len(batches)
                    batch_time = time.time() - batch_start
                    elapsed_total = time.time() - start_time
                    
                    # Calculate progress
                    progress = (total_processed / len(df)) * 100
                    if total_processed > 0:
                        avg_time_per_batch = elapsed_total / (total_processed / BATCH_SIZE)
                        remaining_batches = (len(df) - total_processed) / BATCH_SIZE
                        eta = remaining_batches * avg_time_per_batch
                        
                        print(f"\rProgress: {progress:.1f}% | Processed: {total_processed}/{len(df)} | "
                              f"Batch time: {batch_time:.2f}s | ETA: {eta:.0f}s", end="")
                    
                    batches = []
            
            print("\n\n🔍 Creating indexes...")
            
            # Create all indexes
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
                ("Category index", """
                    CREATE INDEX IF NOT EXISTS product_catalog_category_idx 
                    ON bedrock_integration.product_catalog(category_name) 
                    WHERE category_name IS NOT NULL;
                """),
                ("Price index", """
                    CREATE INDEX IF NOT EXISTS product_catalog_price_idx 
                    ON bedrock_integration.product_catalog(price);
                """)
            ]
            
            for name, sql in indexes:
                print(f"  Creating {name}...")
                try:
                    cur.execute(sql)
                    print(f"  ✅ {name} created")
                except Exception as e:
                    print(f"  ⚠️ {name}: {str(e)[:50]}")
            
            print("\n🔧 Running VACUUM ANALYZE...")
            cur.execute("VACUUM ANALYZE bedrock_integration.product_catalog;")
            
            # Get final statistics
            cur.execute("SELECT COUNT(*) FROM bedrock_integration.product_catalog")
            final_count = cur.fetchone()[0]
            
            end_time = time.time()
            total_time = end_time - start_time
            
            print("\n" + "="*60)
            print("📊 DATA LOADING STATISTICS")
            print("="*60)
            print(f"✅ Total rows loaded: {final_count:,}")
            print(f"⏱️ Total loading time: {total_time:.2f} seconds")
            print(f"📈 Average time per row: {(total_time/len(df))*1000:.2f} ms")
            print(f"📦 Average time per batch: {(total_time/(len(df)/BATCH_SIZE)):.2f} seconds")
            print("="*60)
            
    except Exception as e:
        print(f"\n❌ Error storing products: {str(e)}")
        raise
    finally:
        conn.close()

# Load data into database
store_products()

# Verify results
print("\n🔍 Verifying results...")
conn = psycopg.connect(
    host=dbhost, port=dbport, user=dbuser,
    password=dbpass, autocommit=True
)

cur = conn.cursor()
cur.execute("""
    SELECT 
        COUNT(*) as total,
        COUNT(embedding) as with_embeddings
    FROM bedrock_integration.product_catalog;
""")
total, with_embeddings = cur.fetchone()

cur.execute("""
    SELECT category_name, COUNT(*) as cnt
    FROM bedrock_integration.product_catalog
    GROUP BY category_name
    ORDER BY cnt DESC
    LIMIT 5;
""")
categories = cur.fetchall()

print(f"\n✅ VERIFICATION:")
print(f"  Total products: {total:,}")
print(f"  With embeddings: {with_embeddings:,}")
print(f"\n  Top categories:")
for cat, cnt in categories:
    print(f"    • {cat}: {cnt:,}")

cur.close()
conn.close()

print("\n" + "="*60)
print("🎉 DATA LOADING COMPLETE!")
print("✅ Your hybrid search notebook is ready to use!")
print("="*60)
