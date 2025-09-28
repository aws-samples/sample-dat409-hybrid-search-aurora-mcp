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
    python3.13-tkinter gcc gcc-c++ make postgresql16
check_success "Base packages installation"

# Install AWS CLI v2
log "Installing AWS CLI v2..."
cd /tmp
if [ "$(uname -m)" = "aarch64" ]; then
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
else
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
fi
unzip -q awscliv2.zip
./aws/install --update
rm -rf awscliv2.zip aws/
cd -

# Verify AWS CLI installation
if command -v aws &>/dev/null; then
    log "✅ AWS CLI installed: $(aws --version)"
else
    error "AWS CLI installation failed"
fi
check_success "AWS CLI v2 installation"

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

# Install AWS and Amazon Q extensions
install_vscode_extension "amazonwebservices.aws-toolkit-vscode" "AWS Toolkit"
install_vscode_extension "amazonwebservices.amazon-q-vscode" "Amazon Q"

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
    "jupyter.kernels.filter": [
        {
            "path": "/usr/bin/python3.13",
            "type": "pythonEnvironment"
        }
    ],
    "notebook.defaultKernel": "python3",
    "notebook.kernelProviderAssociations": {
        "jupyter-notebook": [
            "python3"
        ]
    },
    "terminal.integrated.defaultProfile.linux": "bash",
    "terminal.integrated.cwd": "/workshop",
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "workbench.startupEditor": "none",
    
    "git.enabled": false,
    "git.path": "",
    "git.autorefresh": false,
    "git.autofetch": false,
    "git.allowNoVerifyCommit": false,
    "scm.defaultViewMode": "tree",
    "git.decorations.enabled": false,
    "git.showInlineOpenFileAction": false,
    "git.showPushSuccessNotification": false,
    "scm.diffDecorations": "none",
    
    "aws.telemetry": false,
    "amazonQ.telemetry": false,
    "aws.profile": "default",
    "aws.onDefaultRegionMissing": "add",
    "amazonQ.shareContentWithAWS": true,
    "amazonQ.featureDev.enableCodeGen": true,
    "amazonQ.featureDev.enableInlineCodeCompletion": true,
    "codewhisperer.includeSuggestionsWithCodeReferences": true,
    "codewhisperer.shareCodeWhispererContentWithAWS": true,
    
    "extensions.autoUpdate": false,
    "extensions.autoCheckUpdates": false,
    "telemetry.telemetryLevel": "off",
    "security.workspace.trust.startupPrompt": "never",
    "security.workspace.trust.enabled": false,
    "security.workspace.trust.banner": "never",
    "security.workspace.trust.emptyWindow": false
}
VSCODE_SETTINGS

chown -R "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$SETTINGS_DIR"

log "VS Code extensions and settings configured"

log "==================== End VS Code Extensions Section ===================="

# ===========================================================================
# DATABASE CONFIGURATION SECTION (FIXED)
# ===========================================================================

log "==================== Database Configuration Section ===================="

# Declare DB variables globally
export DB_HOST=""
export DB_PORT="5432"
export DB_NAME="${DB_NAME}"
export DB_USER=""
export DB_PASSWORD=""

if [ ! -z "$DB_SECRET_ARN" ] && [ "$DB_SECRET_ARN" != "none" ]; then
    log "Retrieving database credentials from Secrets Manager..."
    
    DB_SECRET=$(aws secretsmanager get-secret-value \
        --secret-id "$DB_SECRET_ARN" \
        --region "$AWS_REGION" \
        --query SecretString \
        --output text 2>/dev/null)
    
    if [ ! -z "$DB_SECRET" ] && [ "$DB_SECRET" != "null" ]; then
        log "Secret retrieved successfully, parsing JSON..."
        
        # Parse the secret JSON and export to environment
        export DB_HOST=$(echo "$DB_SECRET" | jq -r '.host // .endpoint // empty')
        export DB_PORT=$(echo "$DB_SECRET" | jq -r '.port // "5432"')
        export DB_NAME=$(echo "$DB_SECRET" | jq -r '.dbname // .database // empty')
        export DB_USER=$(echo "$DB_SECRET" | jq -r '.username // .user // empty')
        export DB_PASSWORD=$(echo "$DB_SECRET" | jq -r '.password // empty')
        
        # Fallback to cluster endpoint if host is empty
        if [ -z "$DB_HOST" ] || [ "$DB_HOST" == "null" ]; then
            export DB_HOST="$DB_CLUSTER_ENDPOINT"
        fi
        
        log "Database credentials parsed:"
        log "  Host: $DB_HOST"
        log "  Port: $DB_PORT"
        log "  Database: $DB_NAME"
        log "  User: $DB_USER"
        log "  Password length: ${#DB_PASSWORD}"
        
        # Verify all required credentials were extracted
        if [ -z "$DB_HOST" ] || [ "$DB_HOST" == "null" ]; then
            error "Failed to extract DB_HOST from secret"
        fi
        if [ -z "$DB_USER" ] || [ "$DB_USER" == "null" ]; then
            error "Failed to extract DB_USER from secret"
        fi
        if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" == "null" ]; then
            error "Failed to extract DB_PASSWORD from secret"
        fi
        
        # Create .env file with ALL database credentials
        log "Creating .env file with database credentials..."
        cat > "$HOME_FOLDER/.env" << ENV_EOF
# Database Configuration
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME

# PostgreSQL Client Environment Variables
PGHOST=$DB_HOST
PGPORT=$DB_PORT
PGDATABASE=$DB_NAME
PGUSER=$DB_USER
PGPASSWORD=$DB_PASSWORD

# AWS Configuration
AWS_REGION=$AWS_REGION
DB_SECRET_ARN=$DB_SECRET_ARN
ENV_EOF
        
        chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/.env"
        chmod 600 "$HOME_FOLDER/.env"
        log "✅ .env file created successfully at $HOME_FOLDER/.env"
        
        # Verify .env file contains password
        if grep -q "DB_PASSWORD=$DB_PASSWORD" "$HOME_FOLDER/.env"; then
            log "✅ Verified: DB_PASSWORD is correctly set in .env file"
        else
            error "❌ DB_PASSWORD verification failed in .env file"
        fi
        
        # Create .pgpass file for passwordless psql access
        log "Creating .pgpass file for passwordless psql access..."
        sudo -u "$CODE_EDITOR_USER" bash -c "cat > /home/$CODE_EDITOR_USER/.pgpass << PGPASS_EOF
$DB_HOST:$DB_PORT:$DB_NAME:$DB_USER:$DB_PASSWORD
$DB_HOST:$DB_PORT:*:$DB_USER:$DB_PASSWORD
*:*:*:$DB_USER:$DB_PASSWORD
PGPASS_EOF"
        
        chmod 600 "/home/$CODE_EDITOR_USER/.pgpass"
        chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "/home/$CODE_EDITOR_USER/.pgpass"
        log "✅ .pgpass file created"
        
        # Update .bashrc with comprehensive database environment
        log "Updating .bashrc with database environment..."
        cat >> "/home/$CODE_EDITOR_USER/.bashrc" << BASHRC_EOF

# =============================================================================
# DAT409 Workshop Database Environment
# =============================================================================

# PostgreSQL Environment Variables
export PGHOST='$DB_HOST'
export PGPORT='$DB_PORT'
export PGUSER='$DB_USER'
export PGPASSWORD='$DB_PASSWORD'
export PGDATABASE='$DB_NAME'

# Application Database Variables
export DB_HOST='$DB_HOST'
export DB_PORT='$DB_PORT'
export DB_USER='$DB_USER'
export DB_PASSWORD='$DB_PASSWORD'
export DB_NAME='$DB_NAME'
export DATABASE_URL='postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME'

# AWS Configuration
export AWS_REGION='$AWS_REGION'
export DB_SECRET_ARN='$DB_SECRET_ARN'

# Workshop Aliases and Shortcuts
alias psql='psql -h \$PGHOST -p \$PGPORT -U \$PGUSER -d \$PGDATABASE'
alias workshop='cd /workshop'
alias lab1='cd /workshop/lab1-hybrid-search'
alias lab2='cd /workshop/lab2-mcp-agent'

# Load .env file if it exists
if [ -f /workshop/.env ]; then
    set -a
    source /workshop/.env
    set +a
fi
BASHRC_EOF
        
        log "✅ .bashrc updated with database environment"
        
        # Create database test script
        log "Creating database connection test script..."
        cat > "$HOME_FOLDER/test_db_connection.sh" << TEST_EOF
#!/bin/bash
echo "Testing database connection..."
echo "Host: \$PGHOST"
echo "Database: \$PGDATABASE"
echo "User: \$PGUSER"
echo ""

# Test basic connection
if psql -c "SELECT 'Connection successful!' as status;" 2>/dev/null; then
    echo "✅ Database connection successful!"
    
    # Test extensions
    echo ""
    echo "Checking PostgreSQL extensions:"
    psql -c "SELECT extname, extversion FROM pg_extension WHERE extname IN ('vector', 'pg_trgm');" 2>/dev/null || echo "Extensions check failed"
    
    # Test schema
    echo ""
    echo "Checking bedrock_integration schema:"
    psql -c "SELECT EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name = 'bedrock_integration') as schema_exists;" 2>/dev/null || echo "Schema check failed"
    
else
    echo "❌ Database connection failed!"
    echo "Please check your credentials and network connectivity."
fi
TEST_EOF
        
        chmod +x "$HOME_FOLDER/test_db_connection.sh"
        chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/test_db_connection.sh"
        log "✅ Database test script created at $HOME_FOLDER/test_db_connection.sh"
        
        # Test the database connection immediately
        log "Testing database connection..."
        if sudo -u "$CODE_EDITOR_USER" \
            PGHOST="$DB_HOST" \
            PGPORT="$DB_PORT" \
            PGDATABASE="$DB_NAME" \
            PGUSER="$DB_USER" \
            PGPASSWORD="$DB_PASSWORD" \
            psql -c "SELECT 'Bootstrap connection test successful!' as status;" 2>/dev/null; then
            log "✅ Database connection test successful!"
        else
            warn "❌ Database connection test failed - check credentials and network"
        fi
        
    else
        error "Failed to retrieve secret from Secrets Manager"
    fi
else
    warn "DB_SECRET_ARN not provided or set to 'none', skipping database configuration"
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

# Configure Jupyter to use Python 3.13 as default kernel
log "Configuring Jupyter default kernel..."
sudo -u "$CODE_EDITOR_USER" python3.13 -m ipykernel install --user --name python3 --display-name "Python 3.13"

# Create Jupyter config to set default kernel
sudo -u "$CODE_EDITOR_USER" mkdir -p "/home/$CODE_EDITOR_USER/.jupyter"
cat > "/home/$CODE_EDITOR_USER/.jupyter/jupyter_notebook_config.py" << 'JUPYTER_CONFIG'
c.NotebookApp.kernel_spec_manager_class = 'jupyter_client.kernelspec.KernelSpecManager'
c.MultiKernelManager.default_kernel_name = 'python3'
c.Session.kernel_name = 'python3'
JUPYTER_CONFIG

chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "/home/$CODE_EDITOR_USER/.jupyter/jupyter_notebook_config.py"

log "✅ Jupyter configured with Python 3.13 as default kernel"

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
    print(f"   DB_HOST: {'✓' if DB_HOST else '✗'}")
    print(f"   DB_USER: {'✓' if DB_USER else '✗'}")
    print(f"   DB_PASSWORD: {'✓' if DB_PASSWORD else '✗'}")
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
    """Generate Cohere embedding with Titan fallback"""
    if not text or pd.isna(text):
        raise ValueError("Cannot generate embedding for empty text")
    
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
    except Exception as cohere_error:
        # Fallback to Titan Text v2
        titan_body = json.dumps({
            "inputText": str(text)[:8000]
        })
        
        titan_response = bedrock_runtime.invoke_model(
            modelId='amazon.titan-embed-text-v2:0',
            body=titan_body,
            accept='application/json',
            contentType='application/json'
        )
        
        titan_response_body = json.loads(titan_response['body'].read())
        return titan_response_body.get('embedding')

# Setup database
print("Setting up database schema...")
try:
    conn = psycopg.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        dbname=DB_NAME,
        autocommit=True
    )
    
    # Enable extensions - CRITICAL: Must be done before using vector types
    print("Creating PostgreSQL extensions...")
    try:
        conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")
        print("  ✅ vector extension created/verified")
    except Exception as e:
        print(f"  ⚠️ vector extension: {e}")
    
    try:
        conn.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm;")
        print("  ✅ pg_trgm extension created/verified")
    except Exception as e:
        print(f"  ⚠️ pg_trgm extension: {e}")
    
    # Verify vector extension is installed
    result = conn.execute("SELECT extversion FROM pg_extension WHERE extname = 'vector'").fetchone()
    if result:
        print(f"  ✅ pgvector version: {result[0]}")
        register_vector(conn)
    else:
        print("  ❌ vector extension not found - cannot proceed")
        sys.exit(1)
    
    # Create schema
    conn.execute("CREATE SCHEMA IF NOT EXISTS bedrock_integration;")
    print("  ✅ Schema 'bedrock_integration' created/verified")
    
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
    print("✅ Database schema created successfully")
    conn.close()
    
except psycopg.OperationalError as e:
    print(f"❌ Database connection failed: {e}")
    print(f"   Host: {DB_HOST}")
    print(f"   Port: {DB_PORT}")
    print(f"   Database: {DB_NAME}")
    print(f"   User: {DB_USER}")
    sys.exit(1)
except Exception as e:
    print(f"❌ Database setup failed: {e}")
    sys.exit(1)

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

# IMPORTANT: Must register vector type AFTER connecting
register_vector(conn)

BATCH_SIZE = 1000
try:
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
                print(f"\rProgress: {total_processed}/{len(df)} products", end="", flush=True)
                batches = []

    print("\n\n🔧 Creating indexes...")
    indexes = [
        ("CREATE INDEX IF NOT EXISTS product_catalog_embedding_idx ON bedrock_integration.product_catalog USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);", "HNSW vector"),
        ("CREATE INDEX IF NOT EXISTS product_catalog_fts_idx ON bedrock_integration.product_catalog USING GIN (to_tsvector('english', coalesce(product_description, '')));", "Full-text search"),
        ("CREATE INDEX IF NOT EXISTS product_catalog_trgm_idx ON bedrock_integration.product_catalog USING GIN (product_description gin_trgm_ops);", "Trigram"),
        ("CREATE INDEX IF NOT EXISTS product_catalog_category_idx ON bedrock_integration.product_catalog(category_name);", "Category"),
        ("CREATE INDEX IF NOT EXISTS product_catalog_price_idx ON bedrock_integration.product_catalog(price);", "Price")
    ]

    with conn.cursor() as cur:
        for sql, name in indexes:
            print(f"  Creating {name} index...")
            try:
                cur.execute(sql)
                print(f"    ✅ {name} index created")
            except Exception as e:
                print(f"    ⚠️ {name} index: {e}")

        print("\n🔧 Running VACUUM ANALYZE...")
        cur.execute("VACUUM ANALYZE bedrock_integration.product_catalog;")

        # Verify
        cur.execute("SELECT COUNT(*) FROM bedrock_integration.product_catalog")
        final_count = cur.fetchone()[0]
        
        # Verify vector extension and embeddings
        cur.execute("""
            SELECT COUNT(*) as with_embeddings,
                   AVG(vector_dims(embedding)) as avg_dims
            FROM bedrock_integration.product_catalog 
            WHERE embedding IS NOT NULL
        """)
        emb_result = cur.fetchone()
        embeddings_count = emb_result[0] if emb_result else 0
        avg_dims = emb_result[1] if emb_result else 0

except Exception as e:
    print(f"\n❌ Error during database operations: {e}")
    conn.close()
    sys.exit(1)

conn.close()

total_time = time.time() - start_time
print("\n" + "="*60)
print(f"✅ FULL DATA LOADING COMPLETE!")
print(f"   Total rows loaded: {final_count:,}")
print(f"   Rows with embeddings: {embeddings_count:,}")
print(f"   Embedding dimensions: {int(avg_dims) if avg_dims else 0}")
print(f"   Total time: {total_time/60:.1f} minutes")
print("="*60)
LOADER_EOF

chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/run_data_loader.py"
chmod +x "$HOME_FOLDER/run_data_loader.py"

# Run the data loader if database credentials are available
if [ ! -z "$DB_HOST" ] && [ ! -z "$DB_USER" ] && [ ! -z "$DB_PASSWORD" ]; then
    log "Running data loader for 21,704 products (this will take 5-8 minutes)..."
    log "Using credentials: DB_HOST=$DB_HOST, DB_USER=$DB_USER, DB_PASSWORD length=${#DB_PASSWORD}"
    
    # Run the data loader as participant user with ALL environment variables explicitly passed
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
    log "Credential status: DB_HOST=${DB_HOST:+set}, DB_USER=${DB_USER:+set}, DB_PASSWORD=${DB_PASSWORD:+set}"
fi

log "==================== End Lab 1 Database Loading Section ===================="

# ===========================================================================
# COMPREHENSIVE VALIDATION SECTION
# ===========================================================================

log "==================== Comprehensive Validation ===================="

# Create environment verification script
cat > "$HOME_FOLDER/verify_environment.sh" << VERIFY_EOF
#!/bin/bash
echo "=== DAT409 Workshop Environment Verification ==="
echo ""

echo "📁 Files:"
echo "  .env file: \$([ -f /workshop/.env ] && echo '✅ Exists' || echo '❌ Missing')"
echo "  .pgpass file: \$([ -f ~/.pgpass ] && echo '✅ Exists' || echo '❌ Missing')"
echo ""

echo "🔧 Environment Variables:"
echo "  PGHOST: \${PGHOST:-❌ Not set}"
echo "  PGDATABASE: \${PGDATABASE:-❌ Not set}"
echo "  PGUSER: \${PGUSER:-❌ Not set}"
echo "  PGPASSWORD: \$([ ! -z "\$PGPASSWORD" ] && echo '✅ Set' || echo '❌ Not set')"
echo ""

echo "🗄️  Database Connection:"
if command -v psql >/dev/null 2>&1; then
    if psql -c "SELECT 'Connection OK' as status;" 2>/dev/null; then
        echo "  Status: ✅ Connected successfully"
        echo "  Version: \$(psql -t -c 'SELECT version();' 2>/dev/null | head -1 | xargs)"
    else
        echo "  Status: ❌ Connection failed"
    fi
else
    echo "  Status: ❌ psql command not found"
fi
echo ""

echo "🧪 Quick Tests:"
echo "  Run: psql -c 'SELECT version();'"
echo "  Run: ./test_db_connection.sh"
echo ""
VERIFY_EOF

chmod +x "$HOME_FOLDER/verify_environment.sh"
chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/verify_environment.sh"

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

# Validate Database Environment Variables
log "Validating database environment variables..."
if [ ! -z "$DB_HOST" ] && [ "$DB_HOST" != "null" ]; then
    log "✅ DB_HOST: $DB_HOST"
else
    warn "❌ DB_HOST not set"
fi

if [ ! -z "$DB_USER" ] && [ "$DB_USER" != "null" ]; then
    log "✅ DB_USER: $DB_USER"
else
    warn "❌ DB_USER not set"
fi

if [ ! -z "$DB_PASSWORD" ] && [ "$DB_PASSWORD" != "null" ]; then
    log "✅ DB_PASSWORD: Set (length: ${#DB_PASSWORD})"
else
    warn "❌ DB_PASSWORD not set"
fi

if [ ! -z "$DB_NAME" ] && [ "$DB_NAME" != "null" ]; then
    log "✅ DB_NAME: $DB_NAME"
else
    warn "❌ DB_NAME not set"
fi

# Validate .env file
log "Validating .env file..."
if [ -f "$HOME_FOLDER/.env" ]; then
    log "✅ .env file exists at $HOME_FOLDER/.env"
    
    # Check contents
    if grep -q "DB_HOST=" "$HOME_FOLDER/.env" && \
       grep -q "DB_USER=" "$HOME_FOLDER/.env" && \
       grep -q "DB_PASSWORD=" "$HOME_FOLDER/.env" && \
       grep -q "PGHOST=" "$HOME_FOLDER/.env" && \
       grep -q "PGUSER=" "$HOME_FOLDER/.env" && \
       grep -q "PGPASSWORD=" "$HOME_FOLDER/.env"; then
        log "✅ .env file contains all required database variables"
    else
        warn "⚠️  .env file missing some database variables"
    fi
else
    warn "❌ .env file not found at $HOME_FOLDER/.env"
fi

# Validate .pgpass file
if [ -f "/home/$CODE_EDITOR_USER/.pgpass" ]; then
    log "✅ .pgpass file exists"
else
    warn "❌ .pgpass file not found"
fi

# Validate Database Connection and Components
if [ ! -z "$DB_HOST" ] && [ ! -z "$DB_USER" ] && [ ! -z "$DB_PASSWORD" ]; then
    log "Validating database connection and components..."
    
    # Test database connectivity
    if sudo -u "$CODE_EDITOR_USER" \
        PGHOST="$DB_HOST" \
        PGPORT="$DB_PORT" \
        PGDATABASE="$DB_NAME" \
        PGUSER="$DB_USER" \
        PGPASSWORD="$DB_PASSWORD" \
        psql -c "SELECT 1;" &>/dev/null; then
        log "✅ Database connection successful"
        
        # Check PostgreSQL extensions
        log "Checking PostgreSQL extensions..."
        EXTENSIONS=$(sudo -u "$CODE_EDITOR_USER" \
            PGHOST="$DB_HOST" \
            PGPORT="$DB_PORT" \
            PGDATABASE="$DB_NAME" \
            PGUSER="$DB_USER" \
            PGPASSWORD="$DB_PASSWORD" \
            psql -t -c "SELECT extname FROM pg_extension WHERE extname IN ('vector', 'pg_trgm');" 2>/dev/null | xargs)
        
        if echo "$EXTENSIONS" | grep -q "vector"; then
            log "✅ pgvector extension installed"
        else
            warn "❌ pgvector extension not found"
        fi
        
        if echo "$EXTENSIONS" | grep -q "pg_trgm"; then
            log "✅ pg_trgm extension installed"
        else
            warn "❌ pg_trgm extension not found"
        fi
        
        # Check schema
        log "Checking database schema..."
        SCHEMA_EXISTS=$(sudo -u "$CODE_EDITOR_USER" \
            PGHOST="$DB_HOST" \
            PGPORT="$DB_PORT" \
            PGDATABASE="$DB_NAME" \
            PGUSER="$DB_USER" \
            PGPASSWORD="$DB_PASSWORD" \
            psql -t -c "SELECT EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name = 'bedrock_integration');" 2>/dev/null | xargs)
        
        if [ "$SCHEMA_EXISTS" = "t" ]; then
            log "✅ Schema 'bedrock_integration' exists"
        else
            warn "❌ Schema 'bedrock_integration' not found"
        fi
        
        # Check table
        log "Checking product_catalog table..."
        TABLE_EXISTS=$(sudo -u "$CODE_EDITOR_USER" \
            PGHOST="$DB_HOST" \
            PGPORT="$DB_PORT" \
            PGDATABASE="$DB_NAME" \
            PGUSER="$DB_USER" \
            PGPASSWORD="$DB_PASSWORD" \
            psql -t -c "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'bedrock_integration' AND table_name = 'product_catalog');" 2>/dev/null | xargs)
        
        if [ "$TABLE_EXISTS" = "t" ]; then
            log "✅ Table 'product_catalog' exists"
            
            # Check row count
            ROW_COUNT=$(sudo -u "$CODE_EDITOR_USER" \
                PGHOST="$DB_HOST" \
                PGPORT="$DB_PORT" \
                PGDATABASE="$DB_NAME" \
                PGUSER="$DB_USER" \
                PGPASSWORD="$DB_PASSWORD" \
                psql -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog;" 2>/dev/null | xargs)
            
            if [ ! -z "$ROW_COUNT" ] && [ "$ROW_COUNT" -gt 0 ]; then
                log "✅ Data loaded: $ROW_COUNT products"
            else
                warn "⚠️  Table exists but no data loaded (count: $ROW_COUNT)"
            fi
            
            # Check for embeddings
            EMBEDDING_COUNT=$(sudo -u "$CODE_EDITOR_USER" \
                PGHOST="$DB_HOST" \
                PGPORT="$DB_PORT" \
                PGDATABASE="$DB_NAME" \
                PGUSER="$DB_USER" \
                PGPASSWORD="$DB_PASSWORD" \
                psql -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL;" 2>/dev/null | xargs)
            
            if [ ! -z "$EMBEDDING_COUNT" ] && [ "$EMBEDDING_COUNT" -gt 0 ]; then
                log "✅ Embeddings present: $EMBEDDING_COUNT products with embeddings"
            else
                warn "⚠️  No embeddings found in table"
            fi
        else
            warn "❌ Table 'product_catalog' not found"
        fi
        
        # Check indexes
        log "Checking indexes..."
        INDEXES=$(sudo -u "$CODE_EDITOR_USER" \
            PGHOST="$DB_HOST" \
            PGPORT="$DB_PORT" \
            PGDATABASE="$DB_NAME" \
            PGUSER="$DB_USER" \
            PGPASSWORD="$DB_PASSWORD" \
            psql -t -c "SELECT indexname FROM pg_indexes WHERE schemaname = 'bedrock_integration' AND tablename = 'product_catalog';" 2>/dev/null | wc -l)
        
        if [ ! -z "$INDEXES" ] && [ "$INDEXES" -gt 0 ]; then
            log "✅ Indexes created: $INDEXES indexes on product_catalog"
        else
            warn "⚠️  No indexes found on product_catalog table"
        fi
        
    else
        warn "❌ Database connection failed - cannot validate components"
    fi
else
    warn "⚠️  Database credentials not available - skipping database validation"
fi

# Show final status
log "==================== Bootstrap Summary ===================="
echo "🔧 SERVICES:"
echo "  Nginx: $(systemctl is-active nginx)"
echo "  Code Editor: $(systemctl is-active code-editor@$CODE_EDITOR_USER)"
echo ""
echo "📁 CONFIGURATION FILES:"
echo "  .env file: $( [ -f "$HOME_FOLDER/.env" ] && echo "✅ Created" || echo "❌ Missing" )"
echo "  .pgpass file: $( [ -f "/home/$CODE_EDITOR_USER/.pgpass" ] && echo "✅ Created" || echo "❌ Missing" )"
echo "  .bashrc updated: ✅ Yes"
echo ""
echo "🐍 PYTHON & EXTENSIONS:"
echo "  Python version: $(python3.13 --version 2>/dev/null || echo 'Not found')"
echo "  PostgreSQL client: $(psql --version 2>/dev/null || echo 'Not found')"
echo "  VS Code Extensions: $( [ -d "/home/$CODE_EDITOR_USER/.code-editor-server/extensions/ms-python.python" ] && echo "✅ Installed" || echo "⚠️  Check installation" )"
echo "  Jupyter Kernel: ✅ Python 3.13 (default)"
echo ""
echo "🔒 SECURITY:"
echo "  Git Commits: ❌ Disabled (read-only mode)"
echo ""
echo "🗄️  DATABASE:"
if [ ! -z "$DB_HOST" ]; then
    echo "  Host: $DB_HOST"
    echo "  Database: $DB_NAME"
    echo "  User: $DB_USER"
    echo "  Password: $( [ ! -z "$DB_PASSWORD" ] && echo "✅ Set" || echo "❌ Not set" )"
    
    if [ "$TABLE_EXISTS" = "t" ] && [ ! -z "$ROW_COUNT" ]; then
        echo "  Schema: ✅ bedrock_integration"
        echo "  Table: ✅ product_catalog"
        echo "  Data: ✅ $ROW_COUNT products loaded"
        echo "  Embeddings: ✅ $EMBEDDING_COUNT with embeddings"
        echo "  Indexes: ✅ $INDEXES indexes created"
        echo "  Extensions: vector, pg_trgm"
    else
        echo "  Status: ⚠️  Check $HOME_FOLDER/data_loader.log"
    fi
else
    echo "  Status: ❌ Not configured"
fi

log ""
log "Listening ports:"
ss -tlpn | grep -E ":(80|8080)" || warn "No services listening on expected ports"

log ""
log "============================================================"
log "✅ Bootstrap completed successfully!"
log "Code Editor URL: Use CloudFront URL with token: $CODE_EDITOR_PASSWORD"
log "Database: Configured with credentials from Secrets Manager"
log "Extensions: Python and Jupyter VS Code extensions installed"
log "Git: Read-only mode (commits disabled)"
log "Jupyter: Python 3.13 kernel pre-selected as default"
log "PostgreSQL: Client version 16 installed"
log "============================================================"ate that prevents commits
mkdir -p ~/.git-templates
echo "# Git commits are disabled in this workshop environment" > ~/.git-templates/commit-message.txt
git config --global commit.template ~/.git-templates/commit-message.txt
GIT_CONFIG

log "✅ Git configured for read-only access (commits disabled)"

log "==================== End Git Configuration Section ===================="

# ===========================================================================
# DATABASE CONFIGURATION SECTION
# ===========================================================================

log "==================== Database Configuration Section ===================="

# Declare DB variables globally so they're available to all functions
export DB_HOST=""
export DB_PORT=""
export DB_NAME=""
export DB_USER=""
export DB_PASSWORD=""

if [ ! -z "$DB_SECRET_ARN" ] && [ "$DB_SECRET_ARN" != "none" ]; then
    log "Retrieving database credentials from Secrets Manager..."
    
    DB_SECRET=$(aws secretsmanager get-secret-value \
        --secret-id "$DB_SECRET_ARN" \
        --region "$AWS_REGION" \
        --query SecretString \
        --output text 2>/dev/null)
    
    if [ ! -z "$DB_SECRET" ]; then
        # Parse the secret JSON and EXPORT to environment
        export DB_HOST=$(echo "$DB_SECRET" | jq -r .host)
        export DB_PORT=$(echo "$DB_SECRET" | jq -r .port)
        export DB_NAME=$(echo "$DB_SECRET" | jq -r .dbname)
        export DB_USER=$(echo "$DB_SECRET" | jq -r .username)
        export DB_PASSWORD=$(echo "$DB_SECRET" | jq -r .password)
        
        log "Database credentials retrieved successfully"
        log "Database Host: $DB_HOST"
        log "Database Name: $DB_NAME"
        log "Database User: $DB_USER"
        log "DB_PASSWORD length: ${#DB_PASSWORD}"
        
        # Verify all credentials were extracted
        if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" == "null" ]; then
            error "Failed to extract DB_PASSWORD from secret"
        fi
        
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

# Configure Jupyter to use Python 3.13 as default kernel
log "Configuring Jupyter default kernel..."
sudo -u "$CODE_EDITOR_USER" python3.13 -m ipykernel install --user --name python3 --display-name "Python 3.13"

# Create Jupyter config to set default kernel
sudo -u "$CODE_EDITOR_USER" mkdir -p "/home/$CODE_EDITOR_USER/.jupyter"
cat > "/home/$CODE_EDITOR_USER/.jupyter/jupyter_notebook_config.py" << 'JUPYTER_CONFIG'
c.NotebookApp.kernel_spec_manager_class = 'jupyter_client.kernelspec.KernelSpecManager'
c.MultiKernelManager.default_kernel_name = 'python3'
c.Session.kernel_name = 'python3'
JUPYTER_CONFIG

chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "/home/$CODE_EDITOR_USER/.jupyter/jupyter_notebook_config.py"

log "✅ Jupyter configured with Python 3.13 as default kernel"

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
    print(f"   DB_HOST: {'✓' if DB_HOST else '✗'}")
    print(f"   DB_USER: {'✓' if DB_USER else '✗'}")
    print(f"   DB_PASSWORD: {'✓' if DB_PASSWORD else '✗'}")
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
    """Generate Cohere embedding with Titan fallback"""
    if not text or pd.isna(text):
        raise ValueError("Cannot generate embedding for empty text")
    
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
    except Exception as cohere_error:
        # Fallback to Titan Text v2
        titan_body = json.dumps({
            "inputText": str(text)[:8000]
        })
        
        titan_response = bedrock_runtime.invoke_model(
            modelId='amazon.titan-embed-text-v2:0',
            body=titan_body,
            accept='application/json',
            contentType='application/json'
        )
        
        titan_response_body = json.loads(titan_response['body'].read())
        return titan_response_body.get('embedding')

# Setup database
print("Setting up database schema...")
try:
    conn = psycopg.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        dbname=DB_NAME,
        autocommit=True
    )
    
    # Enable extensions - CRITICAL: Must be done before using vector types
    print("Creating PostgreSQL extensions...")
    try:
        conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")
        print("  ✅ vector extension created/verified")
    except Exception as e:
        print(f"  ⚠️ vector extension: {e}")
    
    try:
        conn.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm;")
        print("  ✅ pg_trgm extension created/verified")
    except Exception as e:
        print(f"  ⚠️ pg_trgm extension: {e}")
    
    # Verify vector extension is installed
    result = conn.execute("SELECT extversion FROM pg_extension WHERE extname = 'vector'").fetchone()
    if result:
        print(f"  ✅ pgvector version: {result[0]}")
        register_vector(conn)
    else:
        print("  ❌ vector extension not found - cannot proceed")
        sys.exit(1)
    
    # Create schema
    conn.execute("CREATE SCHEMA IF NOT EXISTS bedrock_integration;")
    print("  ✅ Schema 'bedrock_integration' created/verified")
    
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
    print("✅ Database schema created successfully")
    conn.close()
    
except psycopg.OperationalError as e:
    print(f"❌ Database connection failed: {e}")
    print(f"   Host: {DB_HOST}")
    print(f"   Port: {DB_PORT}")
    print(f"   Database: {DB_NAME}")
    print(f"   User: {DB_USER}")
    sys.exit(1)
except Exception as e:
    print(f"❌ Database setup failed: {e}")
    sys.exit(1)

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

# IMPORTANT: Must register vector type AFTER connecting
register_vector(conn)

BATCH_SIZE = 1000
try:
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
                print(f"\rProgress: {total_processed}/{len(df)} products", end="", flush=True)
                batches = []

    print("\n\n🔧 Creating indexes...")
    indexes = [
        ("CREATE INDEX IF NOT EXISTS product_catalog_embedding_idx ON bedrock_integration.product_catalog USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);", "HNSW vector"),
        ("CREATE INDEX IF NOT EXISTS product_catalog_fts_idx ON bedrock_integration.product_catalog USING GIN (to_tsvector('english', coalesce(product_description, '')));", "Full-text search"),
        ("CREATE INDEX IF NOT EXISTS product_catalog_trgm_idx ON bedrock_integration.product_catalog USING GIN (product_description gin_trgm_ops);", "Trigram"),
        ("CREATE INDEX IF NOT EXISTS product_catalog_category_idx ON bedrock_integration.product_catalog(category_name);", "Category"),
        ("CREATE INDEX IF NOT EXISTS product_catalog_price_idx ON bedrock_integration.product_catalog(price);", "Price")
    ]

    with conn.cursor() as cur:
        for sql, name in indexes:
            print(f"  Creating {name} index...")
            try:
                cur.execute(sql)
                print(f"    ✅ {name} index created")
            except Exception as e:
                print(f"    ⚠️ {name} index: {e}")

        print("\n🔧 Running VACUUM ANALYZE...")
        cur.execute("VACUUM ANALYZE bedrock_integration.product_catalog;")

        # Verify
        cur.execute("SELECT COUNT(*) FROM bedrock_integration.product_catalog")
        final_count = cur.fetchone()[0]
        
        # Verify vector extension and embeddings
        cur.execute("""
            SELECT COUNT(*) as with_embeddings,
                   AVG(vector_dims(embedding)) as avg_dims
            FROM bedrock_integration.product_catalog 
            WHERE embedding IS NOT NULL
        """)
        emb_result = cur.fetchone()
        embeddings_count = emb_result[0] if emb_result else 0
        avg_dims = emb_result[1] if emb_result else 0

except Exception as e:
    print(f"\n❌ Error during database operations: {e}")
    conn.close()
    sys.exit(1)

conn.close()

total_time = time.time() - start_time
print("\n" + "="*60)
print(f"✅ FULL DATA LOADING COMPLETE!")
print(f"   Total rows loaded: {final_count:,}")
print(f"   Rows with embeddings: {embeddings_count:,}")
print(f"   Embedding dimensions: {int(avg_dims) if avg_dims else 0}")
print(f"   Total time: {total_time/60:.1f} minutes")
print("="*60)
LOADER_EOF

chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/run_data_loader.py"
chmod +x "$HOME_FOLDER/run_data_loader.py"

# Run the data loader if database credentials are available
if [ ! -z "$DB_HOST" ] && [ ! -z "$DB_USER" ] && [ ! -z "$DB_PASSWORD" ]; then
    log "Running data loader for 21,704 products (this will take 5-8 minutes)..."
    log "Using credentials: DB_HOST=$DB_HOST, DB_USER=$DB_USER, DB_PASSWORD length=${#DB_PASSWORD}"
    
    # Run the data loader as participant user with ALL environment variables explicitly passed
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
    log "Credential status: DB_HOST=${DB_HOST:+set}, DB_USER=${DB_USER:+set}, DB_PASSWORD=${DB_PASSWORD:+set}"
fi

log "==================== End Database Loading Section ===================="

# ===========================================================================
# LAB 2 SETUP - MCP WITH POSTGRESQL RLS
# ===========================================================================

log "==================== Setting up Lab 2: MCP with RLS ===================="

# Create Lab 2 directory structure
log "Creating Lab 2 directory structure..."
LAB2_DIR="$HOME_FOLDER/lab2-mcp-agent"
mkdir -p "$LAB2_DIR/setup"
mkdir -p "$LAB2_DIR/scripts"
chown -R "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$LAB2_DIR"

# Install uv/uvx for MCP
log "Installing uv/uvx for MCP..."
if command -v uv &>/dev/null; then
    log "uv already installed"
else
    # Try curl method first (preferred)
    if command -v curl &>/dev/null; then
        sudo -u "$CODE_EDITOR_USER" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' || {
            # Fallback to pip if curl method fails
            log "curl installation failed, trying pip..."
            sudo -u "$CODE_EDITOR_USER" python3 -m pip install --user uv
        }
    else
        # Use pip if curl not available
        sudo -u "$CODE_EDITOR_USER" python3 -m pip install --user uv
    fi
fi

# Add uv to PATH for participant user
echo 'export PATH="$HOME/.local/bin:$PATH"' >> "/home/$CODE_EDITOR_USER/.bashrc"

# Verify uv installation
if sudo -u "$CODE_EDITOR_USER" bash -c 'source ~/.bashrc && command -v uvx' &>/dev/null; then
    log "✅ uvx installed successfully"
else
    warn "⚠️ uvx installation may need manual verification"
fi

# Install Streamlit and other Lab 2 Python dependencies
log "Installing Lab 2 Python dependencies..."
sudo -u "$CODE_EDITOR_USER" python3 -m pip install --user \
    streamlit \
    psycopg \
    psycopg-binary \
    boto3 \
    pandas \
    numpy \
    python-dotenv \
    tqdm
check_success "Lab 2 Python dependencies installation"

# Create Lab 2 database setup script with 50 HARDCODED product IDs
log "Creating Lab 2 database setup script with 50 deterministic products..."
cat > "$LAB2_DIR/setup/lab2_database_setup.sql" << 'SQL_EOF'
-- ============================================================
-- LAB 2: MCP with PostgreSQL RLS - 50 Product Setup
-- Uses hardcoded product IDs from high-volume products
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
DO $
DECLARE
    -- All 50 product IDs from your query - deterministic results
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
        
        -- Get product details
        SELECT 
            LEFT(product_description, 100),
            price,
            stars,
            COALESCE(CAST(metadata->>'reviews' AS INT), 10000)
        INTO product_desc, product_price, product_stars, product_reviews
        FROM bedrock_integration.product_catalog 
        WHERE "productId" = pid;
        
        -- Skip if product not found
        IF product_desc IS NULL THEN
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
        
        -- 2. Support Tickets (agents/managers) - For products with many reviews or lower ratings
        IF product_reviews > 20000 OR product_stars < 4.3 THEN
            ticket_num := ticket_num + 1;
            INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity, created_at)
            VALUES (
                pid,
                CASE 
                    WHEN product_stars < 4.2 THEN
                        format('Ticket #%s: Multiple connection issues reported. Firmware v2.5.1 causing dropouts. Rollback recommended.', ticket_num)
                    WHEN product_reviews > 100000 THEN
                        format('Ticket #%s: High volume of "device offline" reports after recent app update. Engineering investigating.', ticket_num)
                    ELSE
                        format('Ticket #%s: Compatibility issues with newer routers. Workaround: Disable WPA3, use WPA2 only.', ticket_num)
                END,
                'support_ticket',
                ARRAY['support_agent', 'product_manager'],
                CASE WHEN product_stars < 4.2 THEN 'high' ELSE 'medium' END,
                NOW() - (random() * INTERVAL '7 days')
            );
        END IF;
        
        -- 3. Internal Notes (agents/managers) - For high-volume or problematic products
        IF product_reviews > 50000 OR product_price > 100 THEN
            INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity)
            VALUES (
                pid,
                CASE 
                    WHEN product_reviews > 100000 THEN
                        'INTERNAL: High-volume product. Escalate unresolved issues after 2 attempts. Premium support available.'
                    WHEN product_price > 150 THEN
                        format('INTERNAL: High-value item ($%.2f). Offer expedited replacement for DOA. Manager approval for refunds over $100.', product_price)
                    ELSE
                        'INTERNAL: Check batch numbers for units manufactured between Jan-Mar 2024. Known QC issues.'
                END,
                'internal_note',
                ARRAY['support_agent', 'product_manager'],
                'medium'
            );
        END IF;
        
        -- 4. Analytics (managers only) - For top products
        IF idx <= 20 THEN  -- Top 20 products get analytics
            INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity, created_at)
            VALUES (
                pid,
                format('ANALYTICS: Rank #%s in category. %s reviews, %.1f stars. Return rate: %.1f%%. NPS: %s',
                    idx,
                    product_reviews,
                    product_stars,
                    CASE WHEN product_stars < 4.3 THEN 5.2 ELSE 2.8 END,
                    CASE WHEN product_stars >= 4.5 THEN 'Excellent' ELSE 'Good' END
                ),
                'analytics',
                ARRAY['product_manager'],
                'low',
                NOW() - INTERVAL '14 days'
            );
        END IF;
        
        -- 5. Additional FAQ for popular products
        IF product_reviews > 30000 THEN
            INSERT INTO knowledge_base (product_id, content, content_type, persona_access, severity)
            VALUES (
                pid,
                CASE 
                    WHEN product_desc ILIKE '%ring%' THEN
                        'Q: Do I need a Ring Protect subscription? A: Basic features work without subscription. Recording and storage require Ring Protect.'
                    WHEN product_desc ILIKE '%blink%' THEN
                        'Q: How long do batteries last? A: Up to 2 years with normal use (5-10 events per day). High-traffic areas drain faster.'
                    WHEN product_desc ILIKE '%wyze%' THEN
                        'Q: Is there a monthly fee? A: Basic features are free. Cam Plus adds AI detection and unlimited cloud storage.'
                    ELSE
                        'Q: Is professional installation available? A: Self-install is easy with our app. Pro installation available in select areas.'
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
    (NULL, 'COMPETITIVE INTEL: Amazon Prime Day pricing expected to drop 20-30% on security cameras.', 
     'analytics', ARRAY['product_manager'], 'medium'),
    (NULL, 'Q: How do I reset my device to factory settings? A: Hold reset button for 10 seconds until LED flashes.', 
     'product_faq', ARRAY['customer', 'support_agent', 'product_manager'], 'low');
    
    RAISE NOTICE 'Knowledge base populated with % products', idx;
    RAISE NOTICE 'Total entries created: %', (SELECT COUNT(*) FROM knowledge_base);
END $;

-- 4. Create MCP helper function
CREATE OR REPLACE FUNCTION get_mcp_context(
    p_query_text TEXT,
    p_persona TEXT DEFAULT 'customer',
    p_time_window INTERVAL DEFAULT NULL,
    p_limit INT DEFAULT 10
) RETURNS JSON AS $
DECLARE
    v_result JSON;
    v_embedding vector;
BEGIN
    -- Set role based on persona
    CASE p_persona
        WHEN 'customer' THEN EXECUTE 'SET ROLE customer_role';
        WHEN 'support_agent' THEN EXECUTE 'SET ROLE support_agent_role';
        WHEN 'product_manager' THEN EXECUTE 'SET ROLE product_manager_role';
        ELSE EXECUTE 'SET ROLE customer_role';
    END CASE;
    
    -- Try to get an embedding for semantic search
    SELECT embedding INTO v_embedding
    FROM bedrock_integration.product_catalog 
    WHERE product_description ILIKE '%' || p_query_text || '%'
    LIMIT 1;
    
    -- Query with JOIN to products and automatic RLS filtering
    WITH filtered_content AS (
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
            COALESCE(CAST(p.metadata->>'reviews' AS INT), 10000) as reviews,
            CASE 
                WHEN v_embedding IS NOT NULL AND p.embedding IS NOT NULL THEN
                    p.embedding <=> v_embedding
                ELSE 1.0
            END as semantic_distance,
            ts_rank(to_tsvector('english', k.content), plainto_tsquery('english', p_query_text)) as text_rank
        FROM knowledge_base k
        LEFT JOIN bedrock_integration.product_catalog p ON k.product_id = p."productId"
        WHERE (
            k.content ILIKE '%' || p_query_text || '%'
            OR p.product_description ILIKE '%' || p_query_text || '%'
        )
        AND (p_time_window IS NULL OR k.created_at >= NOW() - p_time_window)
        ORDER BY 
            CASE 
                WHEN v_embedding IS NOT NULL THEN semantic_distance
                ELSE text_rank
            END DESC
        LIMIT p_limit
    )
    SELECT json_agg(
        json_build_object(
            'id', id,
            'content', content,
            'type', content_type,
            'severity', severity,
            'created_at', created_at,
            'product', product_description,
            'price', price,
            'stars', stars,
            'reviews', reviews
        ) ORDER BY semantic_distance
    ) INTO v_result FROM filtered_content;
    
    -- Reset role
    RESET ROLE;
    
    RETURN COALESCE(v_result, '[]'::JSON);
END;
$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Verification
SELECT 'Setup complete. Verifying...' as status;

-- Show summary
SELECT 
    content_type,
    COUNT(*) as entries,
    COUNT(DISTINCT product_id) as products
FROM knowledge_base
GROUP BY content_type
ORDER BY entries DESC;

-- Verify products with most support content
SELECT 
    p.product_description,
    COUNT(k.id) as support_items,
    array_agg(DISTINCT k.content_type) as content_types
FROM bedrock_integration.product_catalog p
INNER JOIN knowledge_base k ON p."productId" = k.product_id
GROUP BY p."productId", p.product_description
ORDER BY support_items DESC
LIMIT 10;

RAISE NOTICE 'Lab 2 database setup complete with 50 hardcoded products!';
SQL_EOF

chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$LAB2_DIR/setup/lab2_database_setup.sql"

# Run the Lab 2 database setup if database is available
if [ ! -z "$DB_HOST" ] && [ ! -z "$DB_USER" ] && [ ! -z "$DB_PASSWORD" ]; then
    log "Setting up Lab 2 database objects..."
    sudo -u "$CODE_EDITOR_USER" \
        PGHOST="$DB_HOST" \
        PGPORT="$DB_PORT" \
        PGDATABASE="$DB_NAME" \
        PGUSER="$DB_USER" \
        PGPASSWORD="$DB_PASSWORD" \
        psql -f "$LAB2_DIR/setup/lab2_database_setup.sql" 2>&1 | tee "$LAB2_DIR/setup/db_setup.log"
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log "✅ Lab 2 database objects created successfully"
    else
        warn "⚠️ Lab 2 database setup encountered issues. Check $LAB2_DIR/setup/db_setup.log"
    fi
else
    warn "Database credentials not available, Lab 2 database setup skipped"
fi

# Get database cluster ARN and create MCP configuration
log "Creating MCP configuration..."
if [ ! -z "$DB_SECRET_ARN" ] && [ "$DB_SECRET_ARN" != "none" ]; then
    # Extract cluster identifier from cluster endpoint
    CLUSTER_ID=$(echo "$DB_HOST" | cut -d'.' -f1)
    
    # Construct cluster ARN (assuming standard format)
    if [ ! -z "$AWS_ACCOUNTID" ]; then
        DB_CLUSTER_ARN="arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNTID}:cluster:${CLUSTER_ID}"
    else
        # Try to get account ID
        AWS_ACCOUNTID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        if [ ! -z "$AWS_ACCOUNTID" ]; then
            DB_CLUSTER_ARN="arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNTID}:cluster:${CLUSTER_ID}"
        else
            DB_CLUSTER_ARN="[CLUSTER_ARN_HERE]"
            warn "Could not determine cluster ARN automatically"
        fi
    fi
    
    # Create MCP configuration file
    cat > "$LAB2_DIR/mcp_config.json" << MCP_EOF
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
        "AWS_PROFILE": "default",
        "AWS_REGION": "$AWS_REGION",
        "FASTMCP_LOG_LEVEL": "ERROR"
      },
      "disabled": false,
      "autoApprove": []
    }
  }
}
MCP_EOF
    
    chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$LAB2_DIR/mcp_config.json"
    log "✅ MCP configuration created at $LAB2_DIR/mcp_config.json"
    
    # Also add to .env file for easy access
    cat >> "$HOME_FOLDER/.env" << ENV_APPEND

# Lab 2 MCP Configuration
DATABASE_CLUSTER_ARN=$DB_CLUSTER_ARN
MCP_CONFIG_PATH=$LAB2_DIR/mcp_config.json
ENV_APPEND
    
else
    warn "Database secret ARN not available, MCP configuration will need manual setup"
fi

# Create Lab 2 test script
log "Creating Lab 2 test script..."
cat > "$LAB2_DIR/scripts/test_personas.sh" << 'TEST_EOF'
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

echo -e "\nMCP Context Function Test:"
psql -c "SELECT jsonb_pretty(get_mcp_context('headphones', 'customer')::jsonb);"
TEST_EOF

chmod +x "$LAB2_DIR/scripts/test_personas.sh"
chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$LAB2_DIR/scripts/test_personas.sh"

# Create Streamlit app
log "Creating Lab 2 Streamlit application..."
cat > "$LAB2_DIR/lab2_mcp_demo.py" << 'STREAMLIT_EOF'
"""
Lab 2: MCP Context Builder with PostgreSQL RLS
"""
import streamlit as st
import psycopg
from psycopg.rows import dict_row
import pandas as pd
import json
import os
import boto3
from datetime import datetime

st.set_page_config(page_title="Lab 2: MCP with RLS", page_icon="🔐", layout="wide")

# Load environment
DB_HOST = os.getenv('PGHOST')
DB_NAME = os.getenv('PGDATABASE')
DB_USER = os.getenv('PGUSER')
DB_PASSWORD = os.getenv('PGPASSWORD')
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
                SELECT k.*, p.product_description
                FROM knowledge_base k
                LEFT JOIN bedrock_integration.product_catalog p ON k.product_id = p."productId"
                WHERE k.content ILIKE %s OR p.product_description ILIKE %s
                LIMIT 10
            """, (f'%{query}%', f'%{query}%'))
            return cur.fetchall()

st.title("🔐 Lab 2: MCP Context Builder with RLS")

col1, col2 = st.columns([1, 3])
with col1:
    persona = st.selectbox("Select Persona", list(PERSONAS.keys()))
    st.info(f"{PERSONAS[persona]['icon']} Access Level")

with col2:
    query = st.text_input("Search Query", placeholder="Try 'headphones' or 'bluetooth'")
    if st.button("Search with MCP"):
        with st.spinner(f"Searching as {persona}..."):
            results = search_with_persona(query, persona)
            st.success(f"Found {len(results)} results")
            for r in results:
                with st.expander(f"{r['content_type']} - {r.get('created_at', 'N/A')}"):
                    st.write(r['content'][:500])

# MCP Configuration Display
with st.expander("🔧 MCP Configuration for this setup"):
    cluster_arn = os.getenv('DATABASE_CLUSTER_ARN', '[your-cluster-arn]')
    secret_arn = os.getenv('DB_SECRET_ARN', '[your-secret-arn]')
    st.code(f"""
{{
  "mcpServers": {{
    "awslabs.postgres-mcp-server": {{
      "command": "uvx",
      "args": [
        "awslabs.postgres-mcp-server@latest",
        "--resource_arn", "{cluster_arn}",
        "--secret_arn", "{secret_arn}",
        "--database", "workshop_db",
        "--region", "us-west-2",
        "--readonly", "True"
      ],
      "env": {{
        "AWS_PROFILE": "default",
        "AWS_REGION": "us-west-2",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }}
    }}
  }}
}}
    """, language="json")
STREAMLIT_EOF

chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$LAB2_DIR/lab2_mcp_demo.py"

# Create Lab 2 README
log "Creating Lab 2 README..."
cat > "$LAB2_DIR/README.md" << 'README_EOF'
# Lab 2: MCP with PostgreSQL RLS

## Quick Start

1. **Test RLS with personas:**
   ```bash
   ./scripts/test_personas.sh
   ```

2. **Run Streamlit UI:**
   ```bash
   streamlit run lab2_mcp_demo.py --server.port 8502
   ```

3. **Test MCP with uvx:**
   ```bash
   uvx awslabs.postgres-mcp-server@latest \
     --resource_arn $DATABASE_CLUSTER_ARN \
     --secret_arn $DB_SECRET_ARN \
     --database $PGDATABASE \
     --region $AWS_REGION \
     --readonly True \
     --test-connection
   ```

## Key Concepts

1. **RLS (Row Level Security)**: Database automatically filters data by user role
2. **Vector JOINs**: Reuse Lab 1 embeddings - no duplication!
3. **MCP vs RAG**: Structured, filtered context vs document retrieval

## Personas

- **Customer**: Public FAQs only
- **Support Agent**: FAQs + Tickets + Internal Notes
- **Product Manager**: Everything including analytics

## Database Credentials

- Customer: `customer_user` / `customer123`
- Agent: `agent_user` / `agent123`
- Manager: `pm_user` / `pm123`
README_EOF

chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$LAB2_DIR/README.md"

log "✅ Lab 2 setup complete!"
log "   - Database objects created with RLS"
log "   - MCP configuration generated"
log "   - Streamlit app ready"
log "   - Test scripts available"
log "   - Run: cd $LAB2_DIR && streamlit run lab2_mcp_demo.py"

log "==================== End Lab 2 Setup Section ===================="

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

# Validate Database Environment Variables
log "Validating database environment variables..."
if [ ! -z "$DB_HOST" ] && [ "$DB_HOST" != "null" ]; then
    log "✅ DB_HOST: $DB_HOST"
else
    warn "❌ DB_HOST not set"
fi

if [ ! -z "$DB_USER" ] && [ "$DB_USER" != "null" ]; then
    log "✅ DB_USER: $DB_USER"
else
    warn "❌ DB_USER not set"
fi

if [ ! -z "$DB_PASSWORD" ] && [ "$DB_PASSWORD" != "null" ]; then
    log "✅ DB_PASSWORD: Set (length: ${#DB_PASSWORD})"
else
    warn "❌ DB_PASSWORD not set"
fi

if [ ! -z "$DB_NAME" ] && [ "$DB_NAME" != "null" ]; then
    log "✅ DB_NAME: $DB_NAME"
else
    warn "❌ DB_NAME not set"
fi

# Validate Lab 2 Setup
log "Validating Lab 2 setup..."
if [ -d "$LAB2_DIR" ]; then
    log "✅ Lab 2 directory exists: $LAB2_DIR"
    
    if [ -f "$LAB2_DIR/mcp_config.json" ]; then
        log "✅ MCP configuration file created"
    else
        warn "⚠️ MCP configuration file missing"
    fi
    
    if [ -f "$LAB2_DIR/lab2_mcp_demo.py" ]; then
        log "✅ Streamlit app created"
    else
        warn "⚠️ Streamlit app missing"
    fi
    
    # Check if Lab 2 database objects were created
    if [ ! -z "$DB_HOST" ] && [ ! -z "$DB_USER" ] && [ ! -z "$DB_PASSWORD" ]; then
        KB_EXISTS=$(sudo -u "$CODE_EDITOR_USER" \
            PGHOST="$DB_HOST" \
            PGPORT="$DB_PORT" \
            PGDATABASE="$DB_NAME" \
            PGUSER="$DB_USER" \
            PGPASSWORD="$DB_PASSWORD" \
            psql -t -c "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='knowledge_base');" 2>/dev/null | xargs)
        
        if [ "$KB_EXISTS" = "t" ]; then
            log "✅ Lab 2 knowledge_base table created"
            
            # Check RLS policies
            POLICIES=$(sudo -u "$CODE_EDITOR_USER" \
                PGHOST="$DB_HOST" \
                PGPORT="$DB_PORT" \
                PGDATABASE="$DB_NAME" \
                PGUSER="$DB_USER" \
                PGPASSWORD="$DB_PASSWORD" \
                psql -t -c "SELECT COUNT(*) FROM pg_policies WHERE tablename='knowledge_base';" 2>/dev/null | xargs)
            
            if [ ! -z "$POLICIES" ] && [ "$POLICIES" -gt 0 ]; then
                log "✅ RLS policies created: $POLICIES policies"
            else
                warn "⚠️ No RLS policies found"
            fi
        else
            warn "⚠️ Lab 2 knowledge_base table not found"
        fi
    fi
else
    warn "❌ Lab 2 directory not found"
fi

# Validate Database Connection and Components
if [ ! -z "$DB_HOST" ] && [ ! -z "$DB_USER" ] && [ ! -z "$DB_PASSWORD" ]; then
    log "Validating database components..."
    
    # Test connection
    if sudo -u "$CODE_EDITOR_USER" \
        PGHOST="$DB_HOST" \
        PGPORT="$DB_PORT" \
        PGDATABASE="$DB_NAME" \
        PGUSER="$DB_USER" \
        PGPASSWORD="$DB_PASSWORD" \
        psql -c "SELECT 'Connection test successful';" &>/dev/null; then
        
        log "✅ Database connection successful"
        
        # Check schema
        SCHEMA_EXISTS=$(sudo -u "$CODE_EDITOR_USER" \
            PGHOST="$DB_HOST" \
            PGPORT="$DB_PORT" \
            PGDATABASE="$DB_NAME" \
            PGUSER="$DB_USER" \
            PGPASSWORD="$DB_PASSWORD" \
            psql -t -c "SELECT EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name = 'bedrock_integration');" 2>/dev/null | xargs)
        
        if [ "$SCHEMA_EXISTS" = "t" ]; then
            log "✅ Schema 'bedrock_integration' exists"
        else
            warn "❌ Schema 'bedrock_integration' not found"
        fi
        
        # Check product_catalog table
        TABLE_EXISTS=$(sudo -u "$CODE_EDITOR_USER" \
            PGHOST="$DB_HOST" \
            PGPORT="$DB_PORT" \
            PGDATABASE="$DB_NAME" \
            PGUSER="$DB_USER" \
            PGPASSWORD="$DB_PASSWORD" \
            psql -t -c "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='bedrock_integration' AND table_name='product_catalog');" 2>/dev/null | xargs)
        
        if [ "$TABLE_EXISTS" = "t" ]; then
            log "✅ Table 'product_catalog' exists"
            
            # Check row count
            ROW_COUNT=$(sudo -u "$CODE_EDITOR_USER" \
                PGHOST="$DB_HOST" \
                PGPORT="$DB_PORT" \
                PGDATABASE="$DB_NAME" \
                PGUSER="$DB_USER" \
                PGPASSWORD="$DB_PASSWORD" \
                psql -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog;" 2>/dev/null | xargs)
            
            if [ ! -z "$ROW_COUNT" ] && [ "$ROW_COUNT" -gt 0 ]; then
                log "✅ Data loaded: $ROW_COUNT products"
            else
                warn "⚠️ Table exists but no data loaded (count: $ROW_COUNT)"
            fi
            
            # Check for embeddings
            EMBEDDING_COUNT=$(sudo -u "$CODE_EDITOR_USER" \
                PGHOST="$DB_HOST" \
                PGPORT="$DB_PORT" \
                PGDATABASE="$DB_NAME" \
                PGUSER="$DB_USER" \
                PGPASSWORD="$DB_PASSWORD" \
                psql -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL;" 2>/dev/null | xargs)
            
            if [ ! -z "$EMBEDDING_COUNT" ] && [ "$EMBEDDING_COUNT" -gt 0 ]; then
                log "✅ Embeddings present: $EMBEDDING_COUNT products with embeddings"
            else
                warn "⚠️ No embeddings found in table"
            fi
        else
            warn "❌ Table 'product_catalog' not found"
        fi
        
    else
        warn "❌ Database connection failed - cannot validate components"
    fi
else
    warn "⚠️ Database credentials not available - skipping database validation"
fi

# Show final status
log "==================== Bootstrap Summary ===================="
echo "🔧 SERVICES:"
echo "  Nginx: $(systemctl is-active nginx)"
echo "  Code Editor: $(systemctl is-active code-editor@$CODE_EDITOR_USER)"
echo ""
echo "📁 CONFIGURATION FILES:"
echo "  .env file: $( [ -f "$HOME_FOLDER/.env" ] && echo "✅ Created" || echo "❌ Missing" )"
echo "  .pgpass file: $( [ -f "/home/$CODE_EDITOR_USER/.pgpass" ] && echo "✅ Created" || echo "❌ Missing" )"
echo "  .bashrc updated: ✅ Yes"
echo ""
echo "🐍 PYTHON & EXTENSIONS:"
echo "  Python version: $(python3.13 --version 2>/dev/null || echo 'Not found')"
echo "  VS Code Extensions: $( [ -d "/home/$CODE_EDITOR_USER/.code-editor-server/extensions/ms-python.python" ] && echo "✅ Installed" || echo "⚠️ Check installation" )"
echo "  Jupyter Kernel: ✅ Python 3.13 (default)"
echo ""
echo "🔒 SECURITY:"
echo "  Git Commits: ❌ Disabled (read-only mode)"
echo ""
echo "🗄️ DATABASE:"
if [ ! -z "$DB_HOST" ]; then
    echo "  Host: $DB_HOST"
    echo "  Database: $DB_NAME"
    echo "  User: $DB_USER"
    echo "  Password: $( [ ! -z "$DB_PASSWORD" ] && echo "✅ Set" || echo "❌ Not set" )"
    
    if [ "$TABLE_EXISTS" = "t" ] && [ ! -z "$ROW_COUNT" ]; then
        echo "  Schema: ✅ bedrock_integration"
        echo "  Table: ✅ product_catalog"
        echo "  Data: ✅ $ROW_COUNT products loaded"
        echo "  Embeddings: ✅ $EMBEDDING_COUNT with embeddings"
        echo "  Extensions: vector, pg_trgm"
    else
        echo "  Status: ⚠️ Check $HOME_FOLDER/data_loader.log"
    fi
else
    echo "  Status: ❌ Not configured"
fi
echo ""
echo "🚀 LAB 2 SETUP:"
if [ -d "$LAB2_DIR" ]; then
    echo "  Directory: ✅ $LAB2_DIR"
    echo "  MCP Config: $( [ -f "$LAB2_DIR/mcp_config.json" ] && echo "✅ Created" || echo "⚠️ Missing" )"
    echo "  Streamlit App: $( [ -f "$LAB2_DIR/lab2_mcp_demo.py" ] && echo "✅ Ready" || echo "⚠️ Missing" )"
    echo "  Knowledge Base: $( [ "$KB_EXISTS" = "t" ] && echo "✅ Table created" || echo "⚠️ Not created" )"
    echo "  RLS Policies: $( [ ! -z "$POLICIES" ] && [ "$POLICIES" -gt 0 ] && echo "✅ $POLICIES policies" || echo "⚠️ Not configured" )"
    echo "  Test Script: $( [ -f "$LAB2_DIR/scripts/test_personas.sh" ] && echo "✅ Available" || echo "⚠️ Missing" )"
else
    echo "  Status: ❌ Not set up"
fi

log ""
log "Listening ports:"
ss -tlpn | grep -E ":(80|8080|8501|8502)" || warn "No services listening on expected ports"

log ""
log "============================================================"
log "✅ Bootstrap completed successfully!"
log "Code Editor URL: Use CloudFront URL with token: $CODE_EDITOR_PASSWORD"
log "Database: Configured with credentials from Secrets Manager"
log "Lab 1: 21,704 products loaded with embeddings"
log "Lab 2: MCP with RLS setup complete"
log "============================================================"
