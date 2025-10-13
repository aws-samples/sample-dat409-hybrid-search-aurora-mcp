#!/bin/bash
# ===========================================================================
# DAT409 Workshop - Comprehensive Automated Setup
# ===========================================================================
# This script combines infrastructure setup AND database setup in one go
# Designed for CloudFormation UserData to run everything automatically
#
# Usage: curl -fsSL [URL] | bash -s -- PASSWORD
# ===========================================================================

set -euo pipefail

# Parameters
CODE_EDITOR_PASSWORD="${1:-defaultPassword}"
CODE_EDITOR_USER="participant"
HOME_FOLDER="/workshop"

# Database configuration from CloudFormation
DB_SECRET_ARN="${DB_SECRET_ARN:-}"
DB_CLUSTER_ENDPOINT="${DB_CLUSTER_ENDPOINT:-}"
DB_CLUSTER_ARN="${DB_CLUSTER_ARN:-}"
DB_NAME="${DB_NAME:-workshop_db}"
AWS_REGION="${AWS_REGION:-us-west-2}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $1"; }

log "=========================================================================="
log "DAT409 Comprehensive Setup Starting"
log "=========================================================================="

# ===========================================================================
# PHASE 1: INFRASTRUCTURE SETUP
# ===========================================================================

log "PHASE 1: Infrastructure Setup (Code Editor, Python, Dependencies)"

# Install base packages
log "Installing base packages..."
dnf update -y
dnf install --skip-broken -y curl gnupg whois argon2 unzip nginx openssl jq git wget \
    python3.13 python3.13-pip python3.13-devel gcc gcc-c++ make postgresql16

# Install AWS CLI v2
log "Installing AWS CLI v2..."
cd /tmp
if [ "$(uname -m)" = "aarch64" ]; then
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
else
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
fi
unzip -q awscliv2.zip && ./aws/install --update && rm -rf awscliv2.zip aws/
cd -

# Set Python 3.13 as default
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 1
update-alternatives --set python3 /usr/bin/python3.13

# Create user
log "Creating user: $CODE_EDITOR_USER"
if ! id "$CODE_EDITOR_USER" &>/dev/null; then
    adduser -c '' "$CODE_EDITOR_USER"
    echo "$CODE_EDITOR_USER:$CODE_EDITOR_PASSWORD" | chpasswd
    usermod -aG wheel "$CODE_EDITOR_USER"
    sed -i 's/# %wheel/%wheel/g' /etc/sudoers
fi

# Setup workspace
mkdir -p "$HOME_FOLDER"
chown -R "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER"

# Install Code Editor
log "Installing Code Editor..."
export CodeEditorUser="$CODE_EDITOR_USER"
curl -fsSL https://code-editor.amazonaws.com/content/code-editor-server/dist/aws-workshop-studio/install.sh | bash -s --

CODE_EDITOR_CMD="/home/$CODE_EDITOR_USER/.local/bin/code-editor-server"
[ ! -f "$CODE_EDITOR_CMD" ] && error "Code Editor binary not found"

# Configure Code Editor
sudo -u "$CODE_EDITOR_USER" mkdir -p "/home/$CODE_EDITOR_USER/.code-editor-server/data"
echo -n "$CODE_EDITOR_PASSWORD" > "/home/$CODE_EDITOR_USER/.code-editor-server/data/token"
chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "/home/$CODE_EDITOR_USER/.code-editor-server/data/token"

# Configure Nginx
mkdir -p /etc/nginx/conf.d
cat > /etc/nginx/conf.d/code-editor.conf << 'EOF'
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:8080/;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_read_timeout 86400;
    }
}
EOF

nginx -t && systemctl enable nginx && systemctl start nginx

# Create Code Editor systemd service
cat > /etc/systemd/system/code-editor@.service << EOF
[Unit]
Description=AWS Code Editor Server
After=network.target

[Service]
Type=simple
User=%i
Group=%i
WorkingDirectory=$HOME_FOLDER
Environment=PATH=/usr/local/bin:/usr/bin:/bin:/home/$CODE_EDITOR_USER/.local/bin
Environment=HOME=/home/$CODE_EDITOR_USER
ExecStart=$CODE_EDITOR_CMD --accept-server-license-terms --host 127.0.0.1 --port 8080 --default-workspace $HOME_FOLDER --connection-token $CODE_EDITOR_PASSWORD
Restart=always
RestartSec=10

[Install]\nWantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "code-editor@$CODE_EDITOR_USER"
systemctl start "code-editor@$CODE_EDITOR_USER"

# Wait for Code Editor
log "Waiting for Code Editor to start..."
sleep 20
for i in {1..30}; do
    if curl -s http://127.0.0.1:8080/ | grep -q "code-editor\|html"; then
        log "✅ Code Editor is running"
        break
    fi
    [ $i -eq 30 ] && error "Code Editor failed to start"
    sleep 5
done

# Install Python packages
log "Installing Python packages..."
sudo -u "$CODE_EDITOR_USER" python3.13 -m pip install --user \
    pandas numpy boto3 psycopg pgvector matplotlib seaborn tqdm pandarallel \
    jupyterlab jupyter streamlit plotly sqlalchemy python-dotenv

# Install uv for MCP
log "Installing uv/uvx..."
sudo -u "$CODE_EDITOR_USER" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' || \
    sudo -u "$CODE_EDITOR_USER" python3 -m pip install --user uv

echo 'export PATH="$HOME/.local/bin:$PATH"' >> "/home/$CODE_EDITOR_USER/.bashrc"

log "✅ Phase 1 Complete: Infrastructure Ready"

# ===========================================================================
# PHASE 2: DATABASE CREDENTIALS
# ===========================================================================

log "PHASE 2: Retrieving Database Credentials"

export DB_HOST=""
export DB_PORT="5432"
export DB_USER=""
export DB_PASSWORD=""

if [ ! -z "$DB_SECRET_ARN" ] && [ "$DB_SECRET_ARN" != "none" ]; then
    log "Retrieving credentials from Secrets Manager..."
    
    DB_SECRET=$(aws secretsmanager get-secret-value \
        --secret-id "$DB_SECRET_ARN" \
        --region "$AWS_REGION" \
        --query SecretString \
        --output text 2>/dev/null)
    
    if [ ! -z "$DB_SECRET" ]; then
        export DB_HOST=$(echo "$DB_SECRET" | jq -r '.host // .Host // empty')
        export DB_PORT=$(echo "$DB_SECRET" | jq -r '.port // .Port // "5432"')
        export DB_NAME=$(echo "$DB_SECRET" | jq -r '.dbname // .database // "workshop_db"')
        export DB_USER=$(echo "$DB_SECRET" | jq -r '.username // .Username // empty')
        export DB_PASSWORD=$(echo "$DB_SECRET" | jq -r '.password // .Password // empty')
        log "✅ Credentials retrieved"
    fi
fi

[ -z "$DB_HOST" ] && error "Database credentials not available"

# Create .env file
cat > "$HOME_FOLDER/.env" << ENV_EOF
DB_HOST='$DB_HOST'
DB_PORT='$DB_PORT'
DB_NAME='$DB_NAME'
DB_USER='$DB_USER'
DB_PASSWORD='$DB_PASSWORD'
DB_SECRET_ARN='$DB_SECRET_ARN'
DB_CLUSTER_ARN='$DB_CLUSTER_ARN'
DATABASE_CLUSTER_ARN='$DB_CLUSTER_ARN'
DATABASE_SECRET_ARN='$DB_SECRET_ARN'
DATABASE_URL='postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME'
PGHOST='$DB_HOST'
PGPORT='$DB_PORT'
PGUSER='$DB_USER'
PGPASSWORD='$DB_PASSWORD'
PGDATABASE='$DB_NAME'
AWS_REGION='$AWS_REGION'
ENV_EOF

chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/.env"
chmod 600 "$HOME_FOLDER/.env"

# Create .pgpass
cat > "/home/$CODE_EDITOR_USER/.pgpass" << PGPASS_EOF
$DB_HOST:$DB_PORT:$DB_NAME:$DB_USER:$DB_PASSWORD
$DB_HOST:$DB_PORT:*:$DB_USER:$DB_PASSWORD
PGPASS_EOF

chmod 600 "/home/$CODE_EDITOR_USER/.pgpass"
chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "/home/$CODE_EDITOR_USER/.pgpass"

log "✅ Phase 2 Complete: Credentials Configured"

# ===========================================================================
# PHASE 3: WAIT FOR DATABASE AVAILABILITY
# ===========================================================================

log "PHASE 3: Waiting for Database to be Available"

info "Aurora cluster may take 5-10 minutes to become available after CloudFormation creates it"
info "Will check every 30 seconds for up to 20 minutes..."

MAX_DB_WAIT=40  # 40 * 30 seconds = 20 minutes
DB_WAIT_COUNT=0

while [ $DB_WAIT_COUNT -lt $MAX_DB_WAIT ]; do
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -c "SELECT 1;" &>/dev/null; then
        log "✅ Database is available and accepting connections"
        break
    fi
    
    DB_WAIT_COUNT=$((DB_WAIT_COUNT + 1))
    if [ $DB_WAIT_COUNT -eq $MAX_DB_WAIT ]; then
        error "Database did not become available after 20 minutes"
    fi
    
    info "Waiting for database... (attempt $DB_WAIT_COUNT/$MAX_DB_WAIT)"
    sleep 30
done

log "✅ Phase 3 Complete: Database Available"

# ===========================================================================
# PHASE 4: WAIT FOR BEDROCK MODEL ACCESS
# ===========================================================================

log "PHASE 4: Checking Bedrock Model Access"

info "Bedrock Cohere Embed model must be enabled for embedding generation"
info "Will check every 30 seconds for up to 10 minutes..."

MAX_BEDROCK_WAIT=20  # 20 * 30 seconds = 10 minutes
BEDROCK_WAIT_COUNT=0

while [ $BEDROCK_WAIT_COUNT -lt $MAX_BEDROCK_WAIT ]; do
    BEDROCK_TEST_BODY='{"texts":["test"],"input_type":"search_document","embedding_types":["float"]}'
    
    if aws bedrock-runtime invoke-model \
        --model-id cohere.embed-english-v3 \
        --body "$BEDROCK_TEST_BODY" \
        --region "$AWS_REGION" \
        /tmp/bedrock_test.json &>/dev/null; then
        
        if [ -f /tmp/bedrock_test.json ] && [ $(stat -c%s /tmp/bedrock_test.json 2>/dev/null || stat -f%z /tmp/bedrock_test.json) -gt 100 ]; then
            log "✅ Bedrock Cohere Embed model is accessible"
            rm -f /tmp/bedrock_test.json
            break
        fi
    fi
    
    BEDROCK_WAIT_COUNT=$((BEDROCK_WAIT_COUNT + 1))
    if [ $BEDROCK_WAIT_COUNT -eq $MAX_BEDROCK_WAIT ]; then
        warn "Bedrock model not accessible after 10 minutes - may need manual enablement"
        warn "Continuing anyway - database setup will fail if model not available"
        break
    fi
    
    info "Waiting for Bedrock model access... (attempt $BEDROCK_WAIT_COUNT/$MAX_BEDROCK_WAIT)"
    sleep 30
done

log "✅ Phase 4 Complete: Bedrock Check Done"

# ===========================================================================
# PHASE 5: DATABASE SETUP (LAB 1 - PRODUCT CATALOG)
# ===========================================================================

log "PHASE 5: Setting Up Lab 1 (Product Catalog with Embeddings)"

# Create schema and tables
log "Creating Lab 1 schema..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL_LAB1'
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE SCHEMA IF NOT EXISTS bedrock_integration;
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

CREATE INDEX idx_product_catalog_category ON bedrock_integration.product_catalog(category_id);
CREATE INDEX idx_product_catalog_price ON bedrock_integration.product_catalog(price);
SQL_LAB1

log "✅ Lab 1 schema created"

# Load products with embeddings
log "Loading 21,704 products with embeddings (this takes 5-8 minutes)..."

# Download data file
DATA_DIR="$HOME_FOLDER/lab1-hybrid-search/data"
mkdir -p "$DATA_DIR"
DATA_FILE="$DATA_DIR/amazon-products.csv"

if [ ! -f "$DATA_FILE" ]; then
    log "Downloading product data..."
    curl -fsSL "https://raw.githubusercontent.com/aws-samples/sample-dat409-hybrid-search-workshop-prod/main/lab1-hybrid-search/data/amazon-products.csv" \
        -o "$DATA_FILE"
fi

# Create Python loader script
cat > /tmp/load_products.py << 'PYTHON_LOADER'
import os, sys, time, json, boto3, psycopg, pandas as pd, numpy as np
from pgvector.psycopg import register_vector
from pandarallel import pandarallel
from tqdm import tqdm

DB_CONFIG = {
    'host': os.getenv('DB_HOST'),
    'port': os.getenv('DB_PORT', '5432'),
    'dbname': os.getenv('DB_NAME'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD')
}
AWS_REGION = os.getenv('AWS_REGION', 'us-west-2')
DATA_FILE = os.getenv('DATA_FILE')

bedrock_runtime = boto3.client('bedrock-runtime', region_name=AWS_REGION)

def generate_embedding(text):
    if pd.isna(text) or str(text).strip() == '':
        return np.zeros(1024).tolist()
    
    try:
        body = json.dumps({
            "texts": [str(text)[:2000]],
            "input_type": "search_document",
            "embedding_types": ["float"]
        })
        response = bedrock_runtime.invoke_model(
            modelId="cohere.embed-english-v3",
            body=body
        )
        result = json.loads(response['body'].read())
        return result['embeddings']['float'][0]
    except:
        return np.zeros(1024).tolist()

print("Loading data...")
df = pd.read_csv(DATA_FILE)
df = df.dropna(subset=['product_description']).fillna({
    'stars': 0, 'reviews': 0, 'price': 0, 'category_id': 0,
    'isbestseller': False, 'boughtinlastmonth': 0,
    'category_name': 'Unknown', 'quantity': 0
})

print(f"Generating embeddings for {len(df)} products...")
pandarallel.initialize(progress_bar=True, nb_workers=10, verbose=0)
df['embedding'] = df['product_description'].parallel_apply(generate_embedding)

print("Inserting into database...")
conn = psycopg.connect(**DB_CONFIG, autocommit=False)
register_vector(conn)

with conn.cursor() as cur:
    cur.execute("TRUNCATE TABLE bedrock_integration.product_catalog CASCADE;")
    conn.commit()

total = 0
for i in tqdm(range(0, len(df), 1000)):
    batch = df.iloc[i:i+1000]
    with conn.cursor() as cur:
        for _, row in batch.iterrows():
            try:
                cur.execute('''
                    INSERT INTO bedrock_integration.product_catalog 
                    ("productId", product_description, imgurl, producturl, stars, reviews, 
                     price, category_id, isbestseller, boughtinlastmonth, category_name, quantity, embedding)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ''', (
                    str(row['productId'])[:255], str(row['product_description'])[:2000],
                    str(row['imgurl'])[:500], str(row['producturl'])[:500],
                    float(row['stars']), int(row['reviews']), float(row['price']),
                    int(row['category_id']), bool(row['isbestseller']),
                    int(row['boughtinlastmonth']), str(row['category_name'])[:255],
                    int(row['quantity']), row['embedding']
                ))
                total += 1
            except:
                continue
    conn.commit()

print(f"✅ Loaded {total} products")
conn.close()
PYTHON_LOADER

# Run loader
export DATA_FILE="$DATA_FILE"
sudo -u "$CODE_EDITOR_USER" -E python3 /tmp/load_products.py

# Create indexes
log "Creating search indexes..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL_INDEXES'
CREATE INDEX IF NOT EXISTS idx_product_embedding 
ON bedrock_integration.product_catalog 
USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

CREATE INDEX IF NOT EXISTS idx_product_fts 
ON bedrock_integration.product_catalog
USING GIN (to_tsvector('english', coalesce(product_description, '')));

CREATE INDEX IF NOT EXISTS idx_product_trgm 
ON bedrock_integration.product_catalog
USING GIN (product_description gin_trgm_ops);
SQL_INDEXES

log "✅ Phase 5 Complete: Lab 1 Data Loaded"

# ===========================================================================
# PHASE 6: DATABASE SETUP (LAB 2 - RLS AND KNOWLEDGE BASE)
# ===========================================================================

log "PHASE 6: Setting Up Lab 2 (RLS and Knowledge Base)"

# Download RLS setup script if not present
RLS_SCRIPT="$HOME_FOLDER/scripts/setup-rls-knowledge-base.sql"
if [ ! -f "$RLS_SCRIPT" ]; then
    mkdir -p "$HOME_FOLDER/scripts"
    curl -fsSL "https://raw.githubusercontent.com/[YOUR-REPO]/scripts/setup-rls-knowledge-base.sql" \
        -o "$RLS_SCRIPT" 2>/dev/null || warn "Could not download RLS script"
fi

if [ -f "$RLS_SCRIPT" ]; then
    log "Running RLS setup script..."
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -f "$RLS_SCRIPT"
    log "✅ Lab 2 RLS and knowledge base configured"
else
    warn "RLS script not found - Lab 2 setup skipped"
fi

log "✅ Phase 6 Complete: Lab 2 Setup Done"

# ===========================================================================
# FINAL VERIFICATION
# ===========================================================================

log "=========================================================================="
log "FINAL VERIFICATION"
log "=========================================================================="

PRODUCT_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog;" 2>/dev/null | xargs || echo "0")

KB_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM knowledge_base;" 2>/dev/null | xargs || echo "0")

echo ""
log "✅ SETUP COMPLETE!"
echo ""
echo "📊 Lab 1 - Hybrid Search:"
echo "   Products loaded: $PRODUCT_COUNT"
echo ""
echo "🔒 Lab 2 - MCP with RLS:"
echo "   Knowledge base entries: $KB_COUNT"
echo ""
echo "🚀 Services:"
echo "   Code Editor: $(systemctl is-active code-editor@$CODE_EDITOR_USER)"
echo "   Nginx: $(systemctl is-active nginx)"
echo ""
echo "🔗 Access:"
echo "   Code Editor via CloudFront with password: $CODE_EDITOR_PASSWORD"
echo ""
log "=========================================================================="
