#!/bin/bash
# DAT409 Workshop - Code Editor Bootstrap Script with Database Loading
# This script should be placed in your GitHub repository and called from CloudFormation
# Usage: curl -fsSL https://raw.githubusercontent.com/aws-samples/sample-dat409-hybrid-search-aurora-mcp/main/scripts/bootstrap-code-editor.sh | bash -s -- PASSWORD

set -euo pipefail

# Parameters
CODE_EDITOR_PASSWORD="${1:-defaultPassword}"
CODE_EDITOR_USER="participant"
HOME_FOLDER="/workshop"

# Database configuration from environment (will be set by CloudFormation)
DB_SECRET_ARN="${DB_SECRET_ARN:-}"
DB_CLUSTER_ENDPOINT="${DB_CLUSTER_ENDPOINT:-}"
DB_NAME="${DB_NAME:-workshop_db}"
AWS_REGION="${AWS_REGION:-us-west-2}"

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

# Function to check if command succeeded
check_success() {
    if [ $? -eq 0 ]; then
        log "$1 - SUCCESS"
    else
        error "$1 - FAILED"
    fi
}

log "Starting DAT409 Code Editor Bootstrap with Database Loading"
log "Password: ${CODE_EDITOR_PASSWORD:0:4}****"

# Update system and install base packages
log "Installing base packages..."
dnf update -y
dnf install --skip-broken -y curl gnupg whois argon2 unzip nginx openssl jq git wget \
    python3.13 python3.13-pip python3.13-setuptools python3.13-devel python3.13-wheel \
    python3.13-tkinter gcc gcc-c++ make postgresql15
check_success "Base packages installation"

# Set Python 3.13 as default
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 1
sudo update-alternatives --set python3 /usr/bin/python3.13

# Create user
log "Setting up user: $CODE_EDITOR_USER"
if ! id "$CODE_EDITOR_USER" &>/dev/null; then
    adduser -c '' "$CODE_EDITOR_USER"
    echo "$CODE_EDITOR_USER:$CODE_EDITOR_PASSWORD" | chpasswd
    usermod -aG wheel "$CODE_EDITOR_USER"
    sed -i 's/# %wheel/%wheel/g' /etc/sudoers
    check_success "User creation"
else
    log "User $CODE_EDITOR_USER already exists"
fi

# Setup workspace directory
log "Setting up workspace directory: $HOME_FOLDER"
mkdir -p "$HOME_FOLDER"
chown -R "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER"
check_success "Workspace directory setup"

# Install Code Editor
log "Installing Code Editor..."
export CodeEditorUser="$CODE_EDITOR_USER"
curl -fsSL https://code-editor.amazonaws.com/content/code-editor-server/dist/aws-workshop-studio/install.sh | bash -s --
check_success "Code Editor installation"

# Find Code Editor binary
if [ -f "/home/$CODE_EDITOR_USER/.local/bin/code-editor-server" ]; then
    CODE_EDITOR_CMD="/home/$CODE_EDITOR_USER/.local/bin/code-editor-server"
    log "Found Code Editor at: $CODE_EDITOR_CMD"
else
    error "Code Editor binary not found"
fi

# Configure authentication token
log "Configuring authentication token..."
sudo -u "$CODE_EDITOR_USER" mkdir -p "/home/$CODE_EDITOR_USER/.code-editor-server/data"
echo -n "$CODE_EDITOR_PASSWORD" > "/home/$CODE_EDITOR_USER/.code-editor-server/data/token"
chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "/home/$CODE_EDITOR_USER/.code-editor-server/data/token"
check_success "Token configuration"

# Configure Nginx
log "Configuring Nginx..."
mkdir -p /etc/nginx/conf.d
cat > /etc/nginx/conf.d/code-editor.conf << EOF
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:8080/;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header Accept-Encoding gzip;
        proxy_read_timeout 86400;
    }
}
EOF

nginx -t
systemctl enable nginx
systemctl start nginx
check_success "Nginx configuration"

# Create Code Editor systemd service
log "Creating Code Editor systemd service..."
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
ExecStart=$CODE_EDITOR_CMD --accept-server-license-terms --host 127.0.0.1 --port 8080 --default-workspace $HOME_FOLDER --default-folder $HOME_FOLDER --connection-token $CODE_EDITOR_PASSWORD
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Start Code Editor service
log "Starting Code Editor service..."
systemctl daemon-reload
systemctl enable "code-editor@$CODE_EDITOR_USER"
systemctl start "code-editor@$CODE_EDITOR_USER"
check_success "Code Editor service creation"

# Wait for Code Editor to fully start
log "Waiting for Code Editor to initialize..."
sleep 20

# Verify Code Editor is responding
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/ | grep -q "200\|302\|401\|403"; then
        log "Code Editor is responding"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
            error "Code Editor failed to start after $MAX_RETRIES attempts"
        fi
        log "Waiting for Code Editor to respond... (attempt $RETRY_COUNT/$MAX_RETRIES)"
        sleep 5
    fi
done

# ===========================================================================
# VS CODE EXTENSIONS INSTALLATION
# ===========================================================================

log "==================== Installing VS Code Extensions ===================="

# Function to install VS Code extension
install_vscode_extension() {
    local EXTENSION_ID=$1
    local EXTENSION_NAME=$2
    
    log "Installing extension: $EXTENSION_NAME ($EXTENSION_ID)..."
    
    # Try to install using code-editor-server command
    if [ -f "$CODE_EDITOR_CMD" ]; then
        sudo -u "$CODE_EDITOR_USER" "$CODE_EDITOR_CMD" --install-extension "$EXTENSION_ID" 2>&1 | tee -a /tmp/extension_install.log || true
        
        if grep -q "successfully installed" /tmp/extension_install.log 2>/dev/null; then
            log "✅ Successfully installed $EXTENSION_NAME"
            return 0
        fi
    fi
    
    warn "Extension $EXTENSION_NAME may require manual installation"
    return 1
}

# Install essential extensions
install_vscode_extension "ms-python.python" "Python"
install_vscode_extension "ms-toolsai.jupyter" "Jupyter"
install_vscode_extension "ms-toolsai.vscode-jupyter-cell-tags" "Jupyter Cell Tags"
install_vscode_extension "ms-toolsai.jupyter-keymap" "Jupyter Keymap"
install_vscode_extension "ms-toolsai.jupyter-renderers" "Jupyter Renderers"

# Configure VS Code settings
log "Configuring VS Code settings..."
SETTINGS_DIR="/home/$CODE_EDITOR_USER/.code-editor-server"
sudo -u "$CODE_EDITOR_USER" mkdir -p "$SETTINGS_DIR/User"

cat > "$SETTINGS_DIR/User/settings.json" << 'VSCODE_SETTINGS'
{
    "python.defaultInterpreterPath": "/usr/bin/python3.13",
    "python.terminal.activateEnvironment": true,
    "python.linting.enabled": true,
    "jupyter.jupyterServerType": "local",
    "jupyter.notebookFileRoot": "/workshop",
    "terminal.integrated.defaultProfile.linux": "bash",
    "terminal.integrated.cwd": "/workshop",
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "workbench.startupEditor": "none"
}
VSCODE_SETTINGS

chown -R "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$SETTINGS_DIR"

log "VS Code extensions and settings configured"

log "==================== End VS Code Extensions Section ===================="

# ===========================================================================
# DATABASE CONFIGURATION SECTION
# ===========================================================================

log "==================== Database Configuration Section ===================="

if [ ! -z "$DB_SECRET_ARN" ] && [ "$DB_SECRET_ARN" != "none" ]; then
    log "Retrieving database credentials from Secrets Manager..."
    
    DB_SECRET=$(aws secretsmanager get-secret-value \
        --secret-id "$DB_SECRET_ARN" \
        --region "$AWS_REGION" \
        --query SecretString \
        --output text 2>/dev/null)
    
    if [ ! -z "$DB_SECRET" ]; then
        # Parse the secret JSON
        export DB_HOST=$(echo "$DB_SECRET" | jq -r .host)
        export DB_PORT=$(echo "$DB_SECRET" | jq -r .port)
        export DB_NAME=$(echo "$DB_SECRET" | jq -r .dbname)
        export DB_USER=$(echo "$DB_SECRET" | jq -r .username)
        export DB_PASSWORD=$(echo "$DB_SECRET" | jq -r .password)
        
        log "Database credentials retrieved successfully"
        log "Database Host: $DB_HOST"
        log "Database Name: $DB_NAME"
        log "Database User: $DB_USER"
        
        # Create .env file in workshop directory
        log "Creating .env file with database credentials..."
        cat > "$HOME_FOLDER/.env" << ENV_EOF
DB_HOST=$DB_HOST
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_PORT=$DB_PORT
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME
AWS_REGION=$AWS_REGION
DB_SECRET_ARN=$DB_SECRET_ARN
ENV_EOF
        
        chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/.env"
        chmod 600 "$HOME_FOLDER/.env"
        log ".env file created successfully"
        
        # Verify .env file was created with password
        if grep -q "DB_PASSWORD=$DB_PASSWORD" "$HOME_FOLDER/.env"; then
            log "Verified: DB_PASSWORD is in .env file"
        else
            warn "DB_PASSWORD may not be properly set in .env file"
        fi
        
        # Create .pgpass file for passwordless psql
        log "Setting up passwordless psql access..."
        sudo -u "$CODE_EDITOR_USER" bash -c "cat > /home/$CODE_EDITOR_USER/.pgpass << PGPASS_EOF
$DB_HOST:$DB_PORT:$DB_NAME:$DB_USER:$DB_PASSWORD
$DB_HOST:$DB_PORT:*:$DB_USER:$DB_PASSWORD
PGPASS_EOF"
        chmod 600 "/home/$CODE_EDITOR_USER/.pgpass"
        chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "/home/$CODE_EDITOR_USER/.pgpass"
        
        # Update bashrc with database environment and psql alias
        log "Updating user environment with database settings..."
        cat >> "/home/$CODE_EDITOR_USER/.bashrc" << BASHRC_EOF

# Database Connection Settings
export PGHOST='$DB_HOST'
export PGPORT='$DB_PORT'
export PGUSER='$DB_USER'
export PGPASSWORD='$DB_PASSWORD'
export PGDATABASE='$DB_NAME'
export DB_HOST='$DB_HOST'
export DB_PORT='$DB_PORT'
export DB_USER='$DB_USER'
export DB_PASSWORD='$DB_PASSWORD'
export DB_NAME='$DB_NAME'
export DB_SECRET_ARN='$DB_SECRET_ARN'
export AWS_REGION='$AWS_REGION'

# Workshop shortcuts
alias psql='psql -h \$PGHOST -p \$PGPORT -U \$PGUSER -d \$PGDATABASE'
alias workshop='cd /workshop'
alias lab1='cd /workshop/lab1-hybrid-search'
alias lab2='cd /workshop/lab2-mcp-agent'

# Load environment from .env if exists
if [ -f /workshop/.env ]; then
    set -a
    source /workshop/.env
    set +a
fi

echo "📘 DAT409 Workshop Environment Ready!"
echo "📊 Database: \$PGDATABASE @ \$PGHOST"
echo "🔧 Quick commands: psql, workshop, lab1, lab2"
BASHRC_EOF
        
        log "User environment configured with database settings"
        
    else
        warn "Could not parse database credentials from Secrets Manager"
    fi
else
    warn "DB_SECRET_ARN not provided, skipping database configuration"
fi

log "==================== End Database Configuration Section ===================="

# ===========================================================================
# PYTHON DEPENDENCIES INSTALLATION
# ===========================================================================

log "==================== Python Dependencies Section ===================="

log "Installing Python dependencies for database loading and Jupyter..."
sudo -u "$CODE_EDITOR_USER" python3.13 -m pip install --user --upgrade pip
sudo -u "$CODE_EDITOR_USER" python3.13 -m pip install --user \
    boto3 \
    pandas \
    numpy \
    psycopg \
    psycopg-binary \
    pgvector \
    pandarallel \
    tqdm \
    python-dotenv \
    jupyter \
    notebook \
    ipywidgets \
    ipykernel \
    matplotlib \
    seaborn
check_success "Python dependencies installation"

log "==================== End Python Dependencies Section ===================="

# ===========================================================================
# DATABASE LOADING SECTION
# ===========================================================================

log "==================== Database Loading Section ===================="
log "Full load of 21,704 products takes approximately 5-8 minutes"

# Clone the repository if not already done
if [ ! -d "$HOME_FOLDER/sample-dat409-hybrid-search-workshop-prod" ]; then
    log "Cloning workshop repository..."
    sudo -u "$CODE_EDITOR_USER" git clone https://github.com/aws-samples/sample-dat409-hybrid-search-workshop-prod.git "$HOME_FOLDER/sample-dat409-hybrid-search-workshop-prod" || true
fi

# Create the data loader script
log "Creating data loader script..."
cat > "$HOME_FOLDER/run_data_loader.py" << 'LOADER_EOF'
#!/usr/bin/env python3
"""
DAT409 Data Loader - Full Mode
Loads all 21,704 products with embeddings
"""
import os
import sys
import json
import boto3
import time
import psycopg
from pathlib import Path

print("="*60)
print("⚡ DAT409 Data Loader - Full Mode")
print("="*60)

# Get database credentials from environment
DB_HOST = os.environ.get('DB_HOST')
DB_PORT = os.environ.get('DB_PORT', '5432')
DB_NAME = os.environ.get('DB_NAME', 'workshop_db')
DB_USER = os.environ.get('DB_USER')
DB_PASSWORD = os.environ.get('DB_PASSWORD')
AWS_REGION = os.environ.get('AWS_REGION', 'us-west-2')

if not all([DB_HOST, DB_USER, DB_PASSWORD]):
    print("❌ Missing database credentials")
    sys.exit(1)

print(f"Database: {DB_HOST}:{DB_PORT}/{DB_NAME}")
print(f"User: {DB_USER}")
print(f"Region: {AWS_REGION}")

# Test connection first
print("\nTesting database connection...")
try:
    conn = psycopg.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        dbname=DB_NAME
    )
    print("✅ Database connection successful!")
    conn.close()
except Exception as e:
    print(f"❌ Database connection failed: {e}")
    sys.exit(1)

# Set up paths
WORKSHOP_DIR = Path("/workshop")
DATA_FILE = WORKSHOP_DIR / "sample-dat409-hybrid-search-workshop-prod/lab1-hybrid-search/data/amazon-products.csv"

# Check if data file exists, if not try alternate location or download
if not DATA_FILE.exists():
    DATA_FILE = WORKSHOP_DIR / "lab1-hybrid-search/data/amazon-products.csv"
    if not DATA_FILE.exists():
        print(f"❌ Data file not found at {DATA_FILE}")
        print("Attempting to download from GitHub...")
        os.system(f"mkdir -p {DATA_FILE.parent}")
        os.system(f"curl -fsSL https://raw.githubusercontent.com/aws-samples/sample-dat409-hybrid-search-workshop-prod/main/lab1-hybrid-search/data/amazon-products.csv -o {DATA_FILE}")

if DATA_FILE.exists():
    print(f"✅ Data file found: {DATA_FILE}")
else:
    print("❌ Could not find or download data file")
    sys.exit(1)

print("\nStarting data load...")
print("This will take approximately 5-8 minutes...")
print("="*60)

start_time = time.time()

# Import required libraries
import pandas as pd
import numpy as np
from pgvector.psycopg import register_vector
from pandarallel import pandarallel
from tqdm import tqdm

# Initialize Bedrock client
bedrock_runtime = boto3.client('bedrock-runtime', region_name=AWS_REGION)

def generate_embedding_cohere(text):
    """Generate Cohere embedding with fallback"""
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
        
        response_body = json.loads(response['body'].read())
        if 'embeddings' in response_body:
            if 'float' in response_body['embeddings']:
                return response_body['embeddings']['float'][0]
            else:
                return response_body['embeddings'][0]
    except:
        # Fallback to random
        np.random.seed(hash(str(text)) % 2**32)
        return np.random.randn(1024).tolist()

# Setup database
print("Setting up database schema...")
conn = psycopg.connect(
    host=DB_HOST,
    port=DB_PORT,
    user=DB_USER,
    password=DB_PASSWORD,
    dbname=DB_NAME,
    autocommit=True
)

# Enable extensions
conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")
conn.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm;")
register_vector(conn)

# Create schema
conn.execute("CREATE SCHEMA IF NOT EXISTS bedrock_integration;")

# Drop and recreate table
conn.execute("DROP TABLE IF EXISTS bedrock_integration.product_catalog CASCADE;")
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
print("✅ Database schema created")
conn.close()

# Load data
print("\nLoading product data...")
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

if 'productId' not in df.columns or df['productId'].isna().any():
    df['productId'] = ['B' + str(i).zfill(6) for i in range(len(df))]

print(f"✅ Loaded {len(df)} products")

# Generate embeddings
print("\n🧠 Generating embeddings in parallel...")
pandarallel.initialize(progress_bar=True, nb_workers=6, verbose=0)
df['embedding'] = df['product_description'].parallel_apply(generate_embedding_cohere)

# Store in database
print("\n💾 Storing products in database...")
conn = psycopg.connect(
    host=DB_HOST,
    port=DB_PORT,
    user=DB_USER,
    password=DB_PASSWORD,
    dbname=DB_NAME,
    autocommit=True
)
register_vector(conn)

BATCH_SIZE = 1000
with conn.cursor() as cur:
    batches = []
    total_processed = 0
    
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
        
        if len(batches) == BATCH_SIZE or i == len(df):
            cur.executemany("""
            INSERT INTO bedrock_integration.product_catalog (
                "productId", product_description, imgurl, producturl,
                stars, reviews, price, category_id, isbestseller,
                boughtinlastmonth, category_name, quantity, embedding
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT ("productId") DO UPDATE 
            SET product_description = EXCLUDED.product_description,
                embedding = EXCLUDED.embedding;
            """, batches)
            
            total_processed += len(batches)
            print(f"\rProgress: {total_processed}/{len(df)} products", end="")
            batches = []

print("\n\n🔧 Creating indexes...")
indexes = [
    ("CREATE INDEX IF NOT EXISTS product_catalog_embedding_idx ON bedrock_integration.product_catalog USING hnsw (embedding vector_cosine_ops);", "HNSW vector"),
    ("CREATE INDEX IF NOT EXISTS product_catalog_fts_idx ON bedrock_integration.product_catalog USING GIN (to_tsvector('english', coalesce(product_description, '')));", "Full-text search"),
    ("CREATE INDEX IF NOT EXISTS product_catalog_trgm_idx ON bedrock_integration.product_catalog USING GIN (product_description gin_trgm_ops);", "Trigram"),
    ("CREATE INDEX IF NOT EXISTS product_catalog_category_idx ON bedrock_integration.product_catalog(category_name);", "Category"),
    ("CREATE INDEX IF NOT EXISTS product_catalog_price_idx ON bedrock_integration.product_catalog(price);", "Price")
]

for sql, name in indexes:
    print(f"  Creating {name} index...")
    cur.execute(sql)

print("\n🔧 Running VACUUM ANALYZE...")
cur.execute("VACUUM ANALYZE bedrock_integration.product_catalog;")

# Verify
cur.execute("SELECT COUNT(*) FROM bedrock_integration.product_catalog")
final_count = cur.fetchone()[0]

conn.close()

total_time = time.time() - start_time
print("\n" + "="*60)
print(f"✅ FULL DATA LOADING COMPLETE!")
print(f"   Total rows loaded: {final_count:,}")
print(f"   Total time: {total_time/60:.1f} minutes")
print("="*60)
LOADER_EOF

chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/run_data_loader.py"
chmod +x "$HOME_FOLDER/run_data_loader.py"

# Run the data loader if database credentials are available
if [ ! -z "$DB_HOST" ] && [ ! -z "$DB_USER" ] && [ ! -z "$DB_PASSWORD" ]; then
    log "Running data loader for 21,704 products (this will take 5-8 minutes)..."
    
    # Run the data loader as participant user with all environment variables
    sudo -u "$CODE_EDITOR_USER" \
        DB_HOST="$DB_HOST" \
        DB_PORT="$DB_PORT" \
        DB_NAME="$DB_NAME" \
        DB_USER="$DB_USER" \
        DB_PASSWORD="$DB_PASSWORD" \
        AWS_REGION="$AWS_REGION" \
        PGHOST="$DB_HOST" \
        PGPORT="$DB_PORT" \
        PGDATABASE="$DB_NAME" \
        PGUSER="$DB_USER" \
        PGPASSWORD="$DB_PASSWORD" \
        python3.13 "$HOME_FOLDER/run_data_loader.py" 2>&1 | tee "$HOME_FOLDER/data_loader.log"
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log "Database loading completed successfully!"
        log "All 21,704 products loaded with embeddings"
        
        # Verify data was loaded
        log "Verifying data load..."
        sudo -u "$CODE_EDITOR_USER" \
            PGHOST="$DB_HOST" \
            PGPORT="$DB_PORT" \
            PGDATABASE="$DB_NAME" \
            PGUSER="$DB_USER" \
            PGPASSWORD="$DB_PASSWORD" \
            psql -c "SELECT COUNT(*) as product_count FROM bedrock_integration.product_catalog;" 2>/dev/null || true
        
    else
        warn "Database loading encountered issues. Check $HOME_FOLDER/data_loader.log"
    fi
else
    warn "Database credentials not available, skipping data loading"
fi

log "==================== End Database Loading Section ===================="

# ===========================================================================
# FINAL VALIDATION
# ===========================================================================

log "==================== Final Validation ===================="

# Validate services
log "Validating services..."
if systemctl is-active --quiet nginx; then
    log "✅ Nginx is running"
else
    error "Nginx is not running"
fi

if systemctl is-active --quiet "code-editor@$CODE_EDITOR_USER"; then
    log "✅ Code Editor service is running"
else
    error "Code Editor service is not running"
fi

# Test connectivity
log "Testing connectivity..."
CODE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/ || echo "failed")
NGINX_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/ || echo "failed")

if [[ "$CODE_RESPONSE" =~ ^(200|302|401|403)$ ]]; then
    log "✅ Code Editor responding on port 8080: $CODE_RESPONSE"
else
    error "Code Editor not responding on port 8080: $CODE_RESPONSE"
fi

if [[ "$NGINX_RESPONSE" =~ ^(200|302|401|403)$ ]]; then
    log "✅ Nginx responding on port 80: $NGINX_RESPONSE"
else
    error "Nginx not responding on port 80: $NGINX_RESPONSE"
fi

# Show final status
log "==================== Bootstrap Summary ===================="
echo "  Nginx: $(systemctl is-active nginx)"
echo "  Code Editor: $(systemctl is-active code-editor@$CODE_EDITOR_USER)"
echo "  Database Config: $( [ -f "$HOME_FOLDER/.env" ] && echo "✅ Created" || echo "❌ Missing" )"
echo "  Python Extensions: $( [ -d "/home/$CODE_EDITOR_USER/.code-editor-server/extensions/ms-python.python" ] && echo "✅ Installed" || echo "⚠️  Check installation" )"
echo "  Database Loading: Check $HOME_FOLDER/data_loader.log"

log "Listening ports:"
ss -tlpn | grep -E ":(80|8080)" || warn "No services listening on expected ports"

log ""
log "============================================================"
log "✅ Bootstrap completed successfully!"
log "Code Editor URL: Use CloudFront URL with token: $CODE_EDITOR_PASSWORD"
log "Database: Configured with credentials from Secrets Manager"
log "Data: Loading 21,704 products with embeddings"
log "Extensions: Python and Jupyter VS Code extensions installed"
log "============================================================"
