#!/usr/bin/env python3
"""
Generate embeddings for amazon-products-sample-clean.csv
Output: amazon-products-sample-with-cohere-embeddings.csv
"""
import os
import json
import boto3
import pandas as pd
import numpy as np
from tqdm import tqdm

# Configuration
AWS_REGION = os.getenv('AWS_REGION', 'us-west-2')
INPUT_FILE = 'amazon-products-sample-clean.csv'
OUTPUT_FILE = 'amazon-products-sample-with-cohere-embeddings.csv'

# Initialize Bedrock client
bedrock_runtime = boto3.client('bedrock-runtime', region_name=AWS_REGION)

def generate_embedding(text):
    """Generate embedding using Cohere Embed English v3"""
    if pd.isna(text) or str(text).strip() == '':
        return np.zeros(1024).tolist()
    
    clean_text = str(text)[:2000].strip()
    
    try:
        body = json.dumps({
            "texts": [clean_text],
            "input_type": "search_document",
            "embedding_types": ["float"],
            "truncate": "END"
        })
        
        response = bedrock_runtime.invoke_model(
            modelId="cohere.embed-english-v3",
            body=body,
            contentType="application/json",
            accept="application/json"
        )
        
        result = json.loads(response['body'].read())
        
        if 'embeddings' in result and 'float' in result['embeddings']:
            return result['embeddings']['float'][0]
    except Exception as e:
        print(f"Error generating embedding: {e}")
    
    return np.zeros(1024).tolist()

# Load CSV
print(f"Loading {INPUT_FILE}...")
df = pd.read_csv(INPUT_FILE)
print(f"Loaded {len(df)} rows")

# Generate embeddings
print("Generating embeddings...")
embeddings = []
for idx, row in tqdm(df.iterrows(), total=len(df)):
    embedding = generate_embedding(row['product_description'])
    embeddings.append(json.dumps(embedding))

# Add embedding column
df['embedding'] = embeddings

# Save to CSV
print(f"Saving to {OUTPUT_FILE}...")
df.to_csv(OUTPUT_FILE, index=False)
print(f"✅ Done! Saved {len(df)} rows with embeddings")
