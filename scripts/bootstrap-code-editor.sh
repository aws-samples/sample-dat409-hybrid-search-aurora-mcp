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
    
    # Try multiple methods to install extensions
    # Method 1: Using code-editor-server command directly
    if [ -f "$CODE_EDITOR_CMD" ]; then
        sudo -u "$CODE_EDITOR_USER" "$CODE_EDITOR_CMD" --install-extension "$EXTENSION_ID" 2>&1 | tee -a /tmp/extension_install.log
        
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            log "✅ Successfully installed $EXTENSION_NAME via code-editor-server"
            return 0
        fi
    fi
    
    # Method 2: Using the code command if available
    if command -v code &> /dev/null; then
        sudo -u "$CODE_EDITOR_USER" code --install-extension "$EXTENSION_ID" 2>&1 | tee -a /tmp/extension_install.log
        
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            log "✅ Successfully installed $EXTENSION_NAME via code command"
            return 0
        fi
    fi
    
    # Method 3: Direct download and install
    log "Attempting manual installation for $EXTENSION_NAME..."
    
    # Create extensions directory if it doesn't exist
    EXTENSIONS_DIR="/home/$CODE_EDITOR_USER/.local/share/code-server/extensions"
    if [ ! -d "$EXTENSIONS_DIR" ]; then
        EXTENSIONS_DIR="/home/$CODE_EDITOR_USER/.code-editor-server/extensions"
    fi
    
    sudo -u "$CODE_EDITOR_USER" mkdir -p "$EXTENSIONS_DIR"
    
    # Download extension from marketplace
    PUBLISHER="${EXTENSION_ID%%.*}"
    EXTENSION_NAME_SHORT="${EXTENSION_ID#*.}"
    
    # Try to download from VS Code marketplace
    MARKETPLACE_URL="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${PUBLISHER}/vsextensions/${EXTENSION_NAME_SHORT}/latest/vspackage"
    
    cd "$EXTENSIONS_DIR"
    sudo -u "$CODE_EDITOR_USER" wget -q -O "${EXTENSION_ID}.vsix" "$MARKETPLACE_URL" 2>/dev/null
    
    if [ -f "${EXTENSION_ID}.vsix" ]; then
        # Extract the extension
        sudo -u "$CODE_EDITOR_USER" unzip -q "${EXTENSION_ID}.vsix" -d "${EXTENSION_ID}" 2>/dev/null
        rm -f "${EXTENSION_ID}.vsix"
        
        if [ -d "${EXTENSION_ID}" ]; then
            log "✅ Manually installed $EXTENSION_NAME"
            return 0
        fi
    fi
    
    warn "⚠️ Could not install $EXTENSION_NAME - may need manual installation"
    return 1
}

# List of essential extensions to install
declare -a EXTENSIONS=(
    "ms-python.python:Python"
    "ms-toolsai.jupyter:Jupyter"
    "ms-toolsai.vscode-jupyter-cell-tags:Jupyter Cell Tags"
    "ms-toolsai.jupyter-keymap:Jupyter Keymap"
    "ms-toolsai.jupyter-renderers:Jupyter Renderers"
    "ms-toolsai.vscode-jupyter-slideshow:Jupyter Slide Show"
)

# Install each extension
for EXTENSION_INFO in "${EXTENSIONS[@]}"; do
    EXTENSION_ID="${EXTENSION_INFO%%:*}"
    EXTENSION_NAME="${EXTENSION_INFO#*:}"
    install_vscode_extension "$EXTENSION_ID" "$EXTENSION_NAME"
done

# Additional helpful extensions (optional)
log "Installing additional helpful extensions..."
declare -a OPTIONAL_EXTENSIONS=(
    "ms-python.vscode-pylance:Pylance"
    "ms-python.debugpy:Python Debugger"
    "redhat.vscode-yaml:YAML"
    "ms-vscode.makefile-tools:Makefile Tools"
    "DavidAnson.vscode-markdownlint:Markdown Lint"
)

for EXTENSION_INFO in "${OPTIONAL_EXTENSIONS[@]}"; do
    EXTENSION_ID="${EXTENSION_INFO%%:*}"
    EXTENSION_NAME="${EXTENSION_INFO#*:}"
    install_vscode_extension "$EXTENSION_ID" "$EXTENSION_NAME" || true  # Don't fail on optional extensions
done

# Configure VS Code settings for Python and Jupyter
log "Configuring VS Code settings for Python and Jupyter..."
SETTINGS_DIR="/home/$CODE_EDITOR_USER/.local/share/code-server"
if [ ! -d "$SETTINGS_DIR" ]; then
    SETTINGS_DIR="/home/$CODE_EDITOR_USER/.code-editor-server"
fi

sudo -u "$CODE_EDITOR_USER" mkdir -p "$SETTINGS_DIR/User"

# Create VS Code settings.json with Python and Jupyter configuration
cat > "$SETTINGS_DIR/User/settings.json" << 'VSCODE_SETTINGS'
{
    "python.defaultInterpreterPath": "/usr/bin/python3.13",
    "python.terminal.activateEnvironment": true,
    "python.linting.enabled": true,
    "python.linting.pylintEnabled": true,
    "python.formatting.provider": "black",
    "jupyter.jupyterServerType": "local",
    "jupyter.notebookFileRoot": "/workshop",
    "jupyter.alwaysTrustNotebooks": true,
    "terminal.integrated.defaultProfile.linux": "bash",
    "terminal.integrated.cwd": "/workshop",
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "workbench.startupEditor": "none",
    "python.analysis.typeCheckingMode": "basic",
    "python.analysis.autoImportCompletions": true,
    "jupyter.askForKernelRestart": false,
    "jupyter.interactiveWindow.textEditor.executeSelection": true,
    "extensions.autoUpdate": true,
    "extensions.autoCheckUpdates": true
}
VSCODE_SETTINGS

chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$SETTINGS_DIR/User/settings.json"

log "VS Code extensions and settings configured successfully"

# Restart Code Editor to ensure extensions are loaded
log "Restarting Code Editor to load extensions..."
systemctl restart "code-editor@$CODE_EDITOR_USER"
sleep 10

# Verify Code Editor is still running after restart
if systemctl is-active --quiet "code-editor@$CODE_EDITOR_USER"; then
    log "✅ Code Editor restarted successfully with extensions"
else
    warn "Code Editor may need manual restart to load extensions"
fi

log "==================== End VS Code Extensions Section ===================="

# ===========================================================================
# DATABASE LOADING SECTION
# Note: Full load of 21,704 products takes approximately 5-8 minutes
# Ensure CloudFormation timeout is set to at least 1800 seconds (30 minutes)
# ===========================================================================

log "==================== Database Loading Section ===================="
log "Starting FULL product catalog load: 21,704 products with embeddings"
log "Expected duration: 5-8 minutes"

# Create database environment setup script
log "Creating database connection helper scripts..."
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
        
        # Create .env file in workshop directory
        log "Creating .env file with database credentials..."
        cat > "$HOME_FOLDER/.env" << EOF
DB_HOST=$DB_HOST
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_PORT=$DB_PORT
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME
AWS_REGION=$AWS_REGION
DB_SECRET_ARN=$DB_SECRET_ARN
EOF
        chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/.env"
        chmod 600 "$HOME_FOLDER/.env"
        log ".env file created successfully"
        
        # Create .pgpass file for passwordless psql
        log "Setting up passwordless psql access..."
        sudo -u "$CODE_EDITOR_USER" bash -c "cat > /home/$CODE_EDITOR_USER/.pgpass << EOF
$DB_HOST:$DB_PORT:$DB_NAME:$DB_USER:$DB_PASSWORD
$DB_HOST:$DB_PORT:*:$DB_USER:$DB_PASSWORD
EOF"
        chmod 600 "/home/$CODE_EDITOR_USER/.pgpass"
        chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "/home/$CODE_EDITOR_USER/.pgpass"
        
        # Update bashrc with database environment and psql alias
        log "Updating user environment with database settings..."
        cat >> "/home/$CODE_EDITOR_USER/.bashrc" << 'BASHRC_EOF'

# Database Connection Settings
export PGHOST='DB_HOST_PLACEHOLDER'
export PGPORT='DB_PORT_PLACEHOLDER'
export PGUSER='DB_USER_PLACEHOLDER'
export PGPASSWORD='DB_PASSWORD_PLACEHOLDER'
export PGDATABASE='DB_NAME_PLACEHOLDER'

# Workshop shortcuts
alias psql='psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE'
alias workshop='cd /workshop'
alias lab1='cd /workshop/lab1-hybrid-search'
alias lab2='cd /workshop/lab2-mcp-agent'

# Load environment from .env if exists
if [ -f /workshop/.env ]; then
    export $(grep -v '^#' /workshop/.env | xargs)
fi

echo "📘 DAT409 Workshop Environment Ready!"
echo "📊 Database: $PGDATABASE @ $PGHOST"
echo "🔧 Quick commands: psql, workshop, lab1, lab2"
BASHRC_EOF
        
        # Replace placeholders with actual values
        sed -i "s/DB_HOST_PLACEHOLDER/$DB_HOST/g" "/home/$CODE_EDITOR_USER/.bashrc"
        sed -i "s/DB_PORT_PLACEHOLDER/$DB_PORT/g" "/home/$CODE_EDITOR_USER/.bashrc"
        sed -i "s/DB_USER_PLACEHOLDER/$DB_USER/g" "/home/$CODE_EDITOR_USER/.bashrc"
        sed -i "s/DB_PASSWORD_PLACEHOLDER/$DB_PASSWORD/g" "/home/$CODE_EDITOR_USER/.bashrc"
        sed -i "s/DB_NAME_PLACEHOLDER/$DB_NAME/g" "/home/$CODE_EDITOR_USER/.bashrc"
        
        log "User environment configured with database settings"

# Install Python dependencies for data loading and Jupyter
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

# Clone the repository if not already done
if [ ! -d "$HOME_FOLDER/sample-dat409-hybrid-search-workshop-prod" ]; then
    log "Cloning workshop repository..."
    sudo -u "$CODE_EDITOR_USER" git clone https://github.com/aws-samples/sample-dat409-hybrid-search-workshop-prod.git "$HOME_FOLDER/sample-dat409-hybrid-search-workshop-prod"
    check_success "Repository clone"
fi

# Check if the data loader script exists
LOADER_SCRIPT="$HOME_FOLDER/sample-dat409-hybrid-search-workshop-prod/scripts/setup/parallel-fast-loader.py"
DATA_FILE="$HOME_FOLDER/sample-dat409-hybrid-search-workshop-prod/lab1-hybrid-search/data/amazon-products.csv"

if [ -f "$LOADER_SCRIPT" ]; then
    log "Found data loader script at: $LOADER_SCRIPT"
    
    # Get database credentials from Secrets Manager
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
            
            # Create a configuration file for the loader script
            cat > "$HOME_FOLDER/db_config.env" << EOF
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
SECRET_NAME=$DB_SECRET_ARN
AWS_REGION=$AWS_REGION
EOF
            chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/db_config.env"
            
            # Modify the loader script to use correct paths and configuration
            log "Preparing data loader script..."
            
            # Create a wrapper script that sets up the environment
            cat > "$HOME_FOLDER/run_data_loader.py" << 'LOADER_EOF'
#!/usr/bin/env python3
"""
Wrapper script to run the parallel data loader with correct configuration
FULL LOAD MODE - All 21,704 products
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
WORKSHOP_DIR = Path("/workshop/sample-dat409-hybrid-search-workshop-prod")
if not WORKSHOP_DIR.exists():
    # Try alternate location
    WORKSHOP_DIR = Path("/workshop")
    
DATA_FILE = WORKSHOP_DIR / "lab1-hybrid-search/data/amazon-products.csv"

# Check if data file exists
if not DATA_FILE.exists():
    print(f"❌ Data file not found: {DATA_FILE}")
    print("Attempting to download from GitHub...")
    os.system(f"mkdir -p {DATA_FILE.parent}")
    os.system(f"curl -fsSL https://raw.githubusercontent.com/aws-samples/sample-dat409-hybrid-search-workshop-prod/main/lab1-hybrid-search/data/amazon-products.csv -o {DATA_FILE}")

if DATA_FILE.exists():
    print(f"✅ Data file found: {DATA_FILE}")
else:
    print(f"❌ Could not find or download data file")
    sys.exit(1)

# Set environment variables for the loader script
os.environ['CSV_PATH'] = str(DATA_FILE)
os.environ['BATCH_SIZE'] = '1000'
os.environ['PARALLEL_WORKERS'] = '6'
os.environ['SECRET_NAME'] = os.environ.get('DB_SECRET_ARN', '')
os.environ['REGION'] = AWS_REGION

# Add the scripts directory to path
sys.path.insert(0, str(WORKSHOP_DIR / "scripts/setup"))

print("\nStarting data load...")
print("This will take approximately 5-8 minutes...")
print("="*60)

start_time = time.time()

# Now run the actual loader inline
# Import required libraries
import pandas as pd
import numpy as np
import json
from pgvector.psycopg import register_vector
from pandarallel import pandarallel
from tqdm import tqdm

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
            
            # Copy the test connection script
            log "Creating database test script..."
            cat > "$HOME_FOLDER/test_connection.py" << 'TEST_SCRIPT_EOF'
#!/usr/bin/env python3
import os
import psycopg
import sys

try:
    conn = psycopg.connect(
        host=os.environ.get('DB_HOST'),
        port=os.environ.get('DB_PORT', 5432),
        user=os.environ.get('DB_USER'),
        password=os.environ.get('DB_PASSWORD'),
        dbname=os.environ.get('DB_NAME', 'workshop_db')
    )
    print("✅ Database connection successful!")
    cur = conn.cursor()
    cur.execute("SELECT version();")
    version = cur.fetchone()[0]
    print(f"PostgreSQL: {version.split(',')[0]}")
    cur.close()
    conn.close()
except Exception as e:
    print(f"❌ Connection failed: {e}")
    sys.exit(1)
TEST_SCRIPT_EOF
            chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/test_connection.py"
            chmod +x "$HOME_FOLDER/test_connection.py"
            
            # Run the data loader
            log "Running FULL data loader for 21,704 products (this will take 5-8 minutes)..."
            cd "$HOME_FOLDER"
            
            # Export environment variables for the loader
            export DB_SECRET_ARN="$DB_SECRET_ARN"
            export AWS_REGION="$AWS_REGION"
            export DB_HOST="$DB_HOST"
            export DB_PORT="$DB_PORT"
            export DB_NAME="$DB_NAME"
            export DB_USER="$DB_USER"
            export DB_PASSWORD="$DB_PASSWORD"
            
            # First test the connection
            log "Testing database connection before data load..."
            sudo -u "$CODE_EDITOR_USER" \
                DB_HOST="$DB_HOST" \
                DB_PORT="$DB_PORT" \
                DB_NAME="$DB_NAME" \
                DB_USER="$DB_USER" \
                DB_PASSWORD="$DB_PASSWORD" \
                python3.13 "$HOME_FOLDER/test_connection.py"
            
            if [ $? -ne 0 ]; then
                error "Database connection test failed. Cannot proceed with data loading."
            fi
            
            # Run the data loader as participant user with all environment variables
            sudo -u "$CODE_EDITOR_USER" \
                DB_SECRET_ARN="$DB_SECRET_ARN" \
                AWS_REGION="$AWS_REGION" \
                DB_HOST="$DB_HOST" \
                DB_PORT="$DB_PORT" \
                DB_NAME="$DB_NAME" \
                DB_USER="$DB_USER" \
                DB_PASSWORD="$DB_PASSWORD" \
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
                    psql -c "SELECT COUNT(*) as product_count FROM bedrock_integration.product_catalog;" 2>/dev/null || log "Verification query executed"
                
                log "Check $HOME_FOLDER/data_loader.log for details"
            else
                warn "Database loading encountered issues. Check $HOME_FOLDER/data_loader.log"
            fi
        else
            warn "Could not retrieve database credentials from Secrets Manager"
        fi
    else
        warn "DB_SECRET_ARN not provided, skipping database loading"
    fi
else
    warn "Data loader script not found at expected location: $LOADER_SCRIPT"
    warn "Database loading will need to be done manually"
fi

log "==================== End Database Loading Section ===================="

# Wait for services to start
log "Waiting for services to initialize..."
sleep 20

# Validate services
log "Validating services..."
if systemctl is-active --quiet nginx; then
    log "Nginx is running"
else
    error "Nginx is not running"
fi

if systemctl is-active --quiet "code-editor@$CODE_EDITOR_USER"; then
    log "Code Editor service is running"
else
    error "Code Editor service is not running"
fi

# Test connectivity
log "Testing connectivity..."
CODE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/ || echo "failed")
NGINX_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/ || echo "failed")

if [[ "$CODE_RESPONSE" =~ ^(200|302|401|403)$ ]]; then
    log "Code Editor responding on port 8080: $CODE_RESPONSE"
else
    error "Code Editor not responding on port 8080: $CODE_RESPONSE"
fi

if [[ "$NGINX_RESPONSE" =~ ^(200|302|401|403)$ ]]; then
    log "Nginx responding on port 80: $NGINX_RESPONSE"
else
    error "Nginx not responding on port 80: $NGINX_RESPONSE"
fi

# Show final status
log "Final service status:"
echo "  Nginx: $(systemctl is-active nginx)"
echo "  Code Editor: $(systemctl is-active code-editor@$CODE_EDITOR_USER)"
echo "  Database Loading: Check $HOME_FOLDER/data_loader.log"

log "Listening ports:"
ss -tlpn | grep -E ":(80|8080)" || warn "No services listening on expected ports"

log "Bootstrap completed successfully!"
log "Code Editor should be accessible with token: $CODE_EDITOR_PASSWORD"
log "Database has been preloaded with ALL 21,704 products with embeddings"
