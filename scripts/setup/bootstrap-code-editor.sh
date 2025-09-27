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

# ===========================================================================
# DATABASE LOADING SECTION
# Note: Full load of 21,704 products takes approximately 5-8 minutes
# Ensure CloudFormation timeout is set to at least 1800 seconds (30 minutes)
# ===========================================================================

log "==================== Database Loading Section ===================="
log "Starting FULL product catalog load: 21,704 products with embeddings"
log "Expected duration: 5-8 minutes"

# Install Python dependencies for data loading
log "Installing Python dependencies for database loading..."
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
    python-dotenv
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
import subprocess
import json
import boto3
import time
from pathlib import Path

# Set up paths
WORKSHOP_DIR = Path("/workshop/sample-dat409-hybrid-search-workshop-prod")
DATA_FILE = WORKSHOP_DIR / "lab1-hybrid-search/data/amazon-products.csv"
sys.path.insert(0, str(WORKSHOP_DIR / "scripts/setup"))

# Get database credentials from environment or Secrets Manager
DB_SECRET_ARN = os.environ.get('DB_SECRET_ARN')
AWS_REGION = os.environ.get('AWS_REGION', 'us-west-2')

if DB_SECRET_ARN:
    print("Retrieving database credentials...")
    secrets_client = boto3.client('secretsmanager', region_name=AWS_REGION)
    response = secrets_client.get_secret_value(SecretId=DB_SECRET_ARN)
    db_secrets = json.loads(response['SecretString'])
    
    # Set environment variables for the loader script
    os.environ['DB_HOST'] = db_secrets['host']
    os.environ['DB_PORT'] = str(db_secrets.get('port', 5432))
    os.environ['DB_NAME'] = db_secrets.get('dbname', 'workshop_db')
    os.environ['DB_USER'] = db_secrets['username']
    os.environ['DB_PASSWORD'] = db_secrets['password']

# Update the CSV path in the environment
os.environ['CSV_PATH'] = str(DATA_FILE)
os.environ['BATCH_SIZE'] = '1000'
os.environ['PARALLEL_WORKERS'] = '6'  # Optimized for t4g.large instance

# Import and run the loader
print("="*60)
print("⚡ FULL DATA LOAD - ALL 21,704 PRODUCTS")
print("="*60)
print(f"Data file: {DATA_FILE}")
print(f"Database: {os.environ.get('DB_HOST')}:{os.environ.get('DB_PORT')}/{os.environ.get('DB_NAME')}")
print("\nThis will take approximately 5-8 minutes...")
print("="*60)

start_time = time.time()

# Execute the loader script in FULL mode
from parallel_fast_loader import *

# Override the interactive choice with option 1 (full load)
print("\n🚀 Automatically selected: FULL LOAD MODE")
print(f"Loading all {len(df)} products with Cohere embeddings")
print("This process will generate embeddings for all products in parallel")

# Generate embeddings in parallel for ALL products
print("\n🧠 Generating embeddings in parallel...")
print(f"Using {os.environ.get('PARALLEL_WORKERS', '6')} parallel workers")
pandarallel.initialize(progress_bar=True, nb_workers=6, verbose=0)

# Generate embeddings for all products
df['embedding'] = df['product_description'].parallel_apply(generate_embedding_cohere)

embed_time = time.time() - start_time
print(f"\n✅ Embeddings generated in {embed_time/60:.1f} minutes")
print(f"   Rate: {len(df)/embed_time:.1f} products/second")

# Store ALL products in database
print("\n💾 Storing all products in database...")
store_products()

total_time = time.time() - start_time
print("\n" + "="*60)
print("🎉 FULL DATA LOADING COMPLETE!")
print("="*60)
print(f"✅ Successfully loaded all {len(df):,} products")
print(f"⏱️ Total time: {total_time/60:.1f} minutes")
print("="*60)
LOADER_EOF
            
            chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/run_data_loader.py"
            chmod +x "$HOME_FOLDER/run_data_loader.py"
            
            # Run the data loader
            log "Running FULL data loader for 21,704 products (this will take 5-8 minutes)..."
            cd "$HOME_FOLDER"
            
            # Export environment variables for the loader
            export DB_SECRET_ARN="$DB_SECRET_ARN"
            export AWS_REGION="$AWS_REGION"
            
            # Run as the participant user
            sudo -u "$CODE_EDITOR_USER" \
                DB_SECRET_ARN="$DB_SECRET_ARN" \
                AWS_REGION="$AWS_REGION" \
                python3.13 "$HOME_FOLDER/run_data_loader.py" 2>&1 | tee "$HOME_FOLDER/data_loader.log"
            
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                log "Database loading completed successfully!"
                log "All 21,704 products loaded with embeddings"
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
