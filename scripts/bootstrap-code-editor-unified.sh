#!/bin/bash
# DAT409 Workshop - Unified Bootstrap Script (Code Editor + Database)
# This script sets up Code Editor AND automatically loads database from S3
# Usage: Called by CloudFormation UserData with Workshop Studio parameters

set -euo pipefail

# Parameters
CODE_EDITOR_PASSWORD="${1:-defaultPassword}"
CODE_EDITOR_USER="participant"
HOME_FOLDER="/workshop"

# Workshop Studio variables (set by CloudFormation)
ASSETS_BUCKET="${ASSETS_BUCKET:-}"
ASSETS_PREFIX="${ASSETS_PREFIX:-}"

# Database configuration from environment (will be set by CloudFormation)
DB_SECRET_ARN="${DB_SECRET_ARN:-}"
DB_CLUSTER_ENDPOINT="${DB_CLUSTER_ENDPOINT:-}"
DB_CLUSTER_ARN="${DB_CLUSTER_ARN:-}"
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

check_success() {
    if [ $? -eq 0 ]; then
        log "$1 - SUCCESS"
    else
        error "$1 - FAILED"
    fi
}

log "Starting DAT409 Unified Bootstrap (Code Editor + Database)"
log "Password: ${CODE_EDITOR_PASSWORD:0:4}****"
log "Note: Database will be automatically initialized from S3 assets"

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
log "Setting up workspace directory..."
mkdir -p "$HOME_FOLDER"
# Note: workshop and demo-app folders are pre-created in GitHub
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

install_vscode_extension() {
    local EXTENSION_ID=$1
    local EXTENSION_NAME=$2
    
    log "Installing extension: $EXTENSION_NAME ($EXTENSION_ID)..."
    
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
install_vscode_extension "amazonwebservices.aws-toolkit-vscode" "AWS Toolkit"
install_vscode_extension "amazonwebservices.amazon-q-vscode" "Amazon Q"

# Configure VS Code settings
log "Configuring VS Code settings..."
SETTINGS_DIR="/home/$CODE_EDITOR_USER/.code-editor-server"
sudo -u "$CODE_EDITOR_USER" mkdir -p "$SETTINGS_DIR/User"

cat > "$SETTINGS_DIR/User/settings.json" << 'VSCODE_SETTINGS'
{
    "python.defaultInterpreterPath": "/usr/bin/python3.13",
    "jupyter.kernels.filter": [
        {
            "python": "/usr/bin/python3.13",
            "type": "pythonEnvironment"
        }
    ],
    "jupyter.preferredRemoteKernelIdForLocalConnection": "python3",
    "python.terminal.activateEnvironment": true,
    "python.linting.enabled": true,
    "jupyter.jupyterServerType": "local",
    "jupyter.notebookFileRoot": "/workshop",
    "notebook.defaultKernel": "python3",
    "terminal.integrated.defaultProfile.linux": "bash",
    "terminal.integrated.cwd": "/workshop",
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "workbench.startupEditor": "none",
    "git.enabled": false,
    "git.autofetch": false,
    "git.autorefresh": false,
    "git.decorations.enabled": false,
    "scm.diffDecorations": "none",
    "aws.telemetry": false,
    "amazonQ.telemetry": false,
    "extensions.autoUpdate": false,
    "telemetry.telemetryLevel": "off"
}
VSCODE_SETTINGS

chown -R "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$SETTINGS_DIR"

# Create workspace settings to auto-open terminal
log "==================== Configuring Auto-Open Terminal ===================="
log "Creating workspace configuration..."
sudo -u "$CODE_EDITOR_USER" mkdir -p "$HOME_FOLDER/.vscode"
sudo -u "$CODE_EDITOR_USER" mkdir -p "$HOME_FOLDER/scripts"

# 1. Create welcome script that STAYS OPEN
cat > "$HOME_FOLDER/scripts/welcome.sh" << 'WELCOME_EOF'
#!/bin/bash
clear

cat << 'EOF'

═══════════════════════════════════════════════════════════════════
  DAT409 - Hybrid Search with Aurora PostgreSQL for MCP Retrieval
═══════════════════════════════════════════════════════════════════

🚀 Quick Start:
   1. Open Jupyter notebook:
      workshop/notebooks/dat409-hybrid-search-TODO.ipynb
   
   2. Follow TODO blocks to build hybrid search (40 min)
   
   3. Explore the full-stack demo app:
      streamlit run demo-app/streamlit_app.py

🔧 Available Commands:
   workshop  - Navigate to /workshop
   demo      - Navigate to demo-app
   psql      - Connect to PostgreSQL database

📁 Workshop Structure:
   /workshop/notebooks/ - Hands-on lab with TODO blocks
   /demo-app/           - Full-stack reference application
   /solutions/          - Completed notebook for reference

═══════════════════════════════════════════════════════════════════

EOF

# THIS LINE KEEPS TERMINAL OPEN
exec bash
WELCOME_EOF

chmod +x "$HOME_FOLDER/scripts/welcome.sh"

# 2. Create tasks.json to auto-open terminal
cat > "$HOME_FOLDER/.vscode/tasks.json" << 'TASKS_EOF'
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Welcome Terminal",
            "type": "shell",
            "command": "/workshop/scripts/welcome.sh",
            "presentation": {
                "echo": false,
                "reveal": "always",
                "focus": false,
                "panel": "dedicated",
                "showReuseMessage": false,
                "clear": true
            },
            "runOptions": {
                "runOn": "folderOpen"
            },
            "problemMatcher": []
        }
    ]
}
TASKS_EOF

# 3. Create workspace settings (kernel + terminal config)
cat > "$HOME_FOLDER/.vscode/settings.json" << 'SETTINGS_EOF'
{
    "terminal.integrated.defaultProfile.linux": "bash",
    "terminal.integrated.cwd": "/workshop",
    "python.defaultInterpreterPath": "/usr/bin/python3.13",
    "jupyter.kernels.filter": [
        {
            "path": "/usr/bin/python3.13",
            "type": "pythonEnvironment"
        }
    ],
    "jupyter.preferredRemoteKernelIdForLocalConnection": "python3",
    "notebook.defaultKernel": "python3",
    "task.autoDetect": "on",
    "task.problemMatchers.neverPrompt": true
}
SETTINGS_EOF

chown -R "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/.vscode"
chown -R "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/scripts"

log "✅ Workspace configured - terminal will auto-open with welcome message"

log "==================== End Auto-Open Terminal Configuration ===================="

log "==================== End VS Code Extensions Section ===================="

# ===========================================================================
# PYTHON PACKAGES INSTALLATION
# ===========================================================================

log "==================== Installing Python Packages ===================="

# Note: Requirements will be installed after repository clone
log "Core Python packages will be installed..."
sudo -u "$CODE_EDITOR_USER" PIP_NO_WARN_SCRIPT_LOCATION=1 python3.13 -m pip install --user --upgrade pip setuptools wheel

log "Installing essential packages for both labs..."
sudo -u "$CODE_EDITOR_USER" PIP_NO_WARN_SCRIPT_LOCATION=1 python3.13 -m pip install --user \
    boto3 psycopg psycopg-binary pgvector pandas numpy matplotlib seaborn tqdm \
    jupyterlab jupyter ipywidgets notebook python-dotenv streamlit plotly pillow requests

check_success "Core Python package installation"

log "Lab-specific requirements.txt will be installed after repository clone"

# Install uv/uvx for MCP
log "Installing uv/uvx for MCP..."
if command -v uv &>/dev/null; then
    log "uv already installed"
else
    if command -v curl &>/dev/null; then
        sudo -u "$CODE_EDITOR_USER" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' || {
            log "curl installation failed, trying pip..."
            sudo -u "$CODE_EDITOR_USER" python3 -m pip install --user uv
        }
    else
        sudo -u "$CODE_EDITOR_USER" python3 -m pip install --user uv
    fi
fi

# Add uv to PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> "/home/$CODE_EDITOR_USER/.bashrc"

log "==================== End Python Packages Section ===================="

# ===========================================================================
# Install and register ipykernel
# ===========================================================================

log "==================== ipykernel Installation Section ===================="
log "Installing ipykernel for Python 3.13..."
sudo -u "$CODE_EDITOR_USER" python3.13 -m pip install --user ipykernel

log "Registering Python 3.13.3 kernel..."
sudo -u "$CODE_EDITOR_USER" python3.13 -m ipykernel install --user \
    --name python3 \
    --display-name "Python 3.13.3"

# Verify installation
KERNEL_DIR="/home/$CODE_EDITOR_USER/.local/share/jupyter/kernels/python3"
if [ -d "$KERNEL_DIR" ]; then
    log "✅ Kernel registered successfully"
fi
log "==================== End ipykernel Installation Section ===================="

# ===========================================================================
# DATABASE CONFIGURATION (Credentials Only - No Tables)
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
    
    if [ ! -z "$DB_SECRET" ]; then
        export DB_HOST=$(echo "$DB_SECRET" | jq -r '.host // .Host // empty')
        export DB_PORT=$(echo "$DB_SECRET" | jq -r '.port // .Port // "5432"')
        export DB_NAME=$(echo "$DB_SECRET" | jq -r '.dbname // .dbClusterIdentifier // .database // "workshop_db"')
        export DB_USER=$(echo "$DB_SECRET" | jq -r '.username // .Username // empty')
        export DB_PASSWORD=$(echo "$DB_SECRET" | jq -r '.password // .Password // empty')
        
        log "Database credentials retrieved successfully"
    else
        warn "Could not retrieve secret from Secrets Manager"
    fi
elif [ ! -z "$DB_CLUSTER_ENDPOINT" ] && [ "$DB_CLUSTER_ENDPOINT" != "none" ]; then
    log "Using cluster endpoint directly..."
    export DB_HOST="$DB_CLUSTER_ENDPOINT"
    export DB_USER="workshop_admin"
    warn "Using endpoint directly, but password needs to be set separately"
else
    warn "No database configuration available"
fi

# Create .env file for easy sourcing
if [ ! -z "$DB_HOST" ] && [ ! -z "$DB_USER" ] && [ ! -z "$DB_PASSWORD" ]; then
    log "Creating .env file..."
    cat > "$HOME_FOLDER/workshop/.env" << ENV_EOF
# DAT409 Workshop Environment Variables
DB_HOST='$DB_HOST'
DB_PORT='$DB_PORT'
DB_NAME='$DB_NAME'
DB_USER='$DB_USER'
DB_PASSWORD='$DB_PASSWORD'
DB_SECRET_ARN='$DB_SECRET_ARN'
DB_CLUSTER_ARN='$DB_CLUSTER_ARN'
DATABASE_URL='postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME'

# MCP Configuration (for Streamlit app)
DATABASE_CLUSTER_ARN='$DB_CLUSTER_ARN'
DATABASE_SECRET_ARN='$DB_SECRET_ARN'

# PostgreSQL Standard Variables
PGHOST='$DB_HOST'
PGPORT='$DB_PORT'
PGUSER='$DB_USER'
PGPASSWORD='$DB_PASSWORD'
PGDATABASE='$DB_NAME'

# AWS Configuration
AWS_REGION='$AWS_REGION'
AWS_DEFAULT_REGION='$AWS_REGION'
AWS_ACCOUNTID='$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")'

# Workshop Paths
WORKSHOP_HOME='$HOME_FOLDER'
WORKSHOP_DIR='$HOME_FOLDER/workshop'
DEMO_APP_DIR='$HOME_FOLDER/demo-app'
ENV_EOF

    chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/workshop/.env"
    chmod 600 "$HOME_FOLDER/workshop/.env"
    
    # Create .pgpass file
    cat > "/home/$CODE_EDITOR_USER/.pgpass" << PGPASS_EOF
$DB_HOST:$DB_PORT:$DB_NAME:$DB_USER:$DB_PASSWORD
$DB_HOST:$DB_PORT:*:$DB_USER:$DB_PASSWORD
PGPASS_EOF
    
    chmod 600 "/home/$CODE_EDITOR_USER/.pgpass"
    chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "/home/$CODE_EDITOR_USER/.pgpass"
    
    # Update bashrc
    cat >> "/home/$CODE_EDITOR_USER/.bashrc" << BASHRC_EOF

# DAT409 Workshop Environment
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
export DATABASE_URL='postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME'
export AWS_REGION='$AWS_REGION'
export DB_SECRET_ARN='$DB_SECRET_ARN'

# Workshop shortcuts
alias psql='psql -h \$PGHOST -p \$PGPORT -U \$PGUSER -d \$PGDATABASE'
alias workshop='cd /workshop'
alias demo='cd /workshop/demo-app'

# Load .env file if it exists
if [ -f /workshop/.env ]; then
    set -a
    source /workshop/.env
    set +a
fi

BASHRC_EOF
    
    log "✅ Database credentials configured"
else
    warn "Database credentials incomplete - participants will need to configure manually"
fi

log "==================== End Database Configuration Section ===================="

# ===========================================================================
# MCP CONFIGURATION FOR LAB 2
# ===========================================================================

# MCP configuration will be created after repository is cloned
# The lab2-mcp-agent directory doesn't exist yet during bootstrap
log "MCP configuration will be set up after repository clone"

# Note: Workshop repository will be cloned by CloudFormation after this script
# Scripts will be available in /workshop/scripts/ after clone completes

# ===========================================================================
# AUTOMATED DATABASE SETUP (FROM S3 ASSETS)
# ===========================================================================

log "==================== Automated Database Setup ===================="

# Validate required parameters
if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
    error "Database credentials not available - cannot proceed"
fi

if [ -z "$ASSETS_BUCKET" ]; then
    error "ASSETS_BUCKET not provided - cannot download pre-generated embeddings"
fi

log "Starting automated database initialization..."
log "S3 Source: s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}amazon-products-sample-with-cohere-embeddings.csv"
export PGPASSWORD="$DB_PASSWORD"

# Test connectivity
log "Testing database connectivity..."
if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" &>/dev/null; then
    error "Database connection failed"
fi
log "✅ Database connection successful"

# Create schema and tables
log "Creating schema and tables..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL'
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE SCHEMA IF NOT EXISTS bedrock_integration;

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

CREATE INDEX idx_product_catalog_category ON bedrock_integration.product_catalog(category_id);
CREATE INDEX idx_product_catalog_price ON bedrock_integration.product_catalog(price);
CREATE INDEX idx_product_catalog_stars ON bedrock_integration.product_catalog(stars);
SQL

# Download pre-generated embeddings from S3 (MANDATORY)
DATA_FILE="/tmp/amazon-products-sample-with-cohere-embeddings.csv"

# Construct S3 path (Workshop Studio guarantees both parameters)
S3_PATH="s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}amazon-products-sample-with-cohere-embeddings.csv"
log "Downloading product data with embeddings from S3..."
log "S3 Path: $S3_PATH"

if ! aws s3 cp "$S3_PATH" "$DATA_FILE"; then
    error "Failed to download CSV from S3. Check: 1) ASSETS_BUCKET='$ASSETS_BUCKET' 2) ASSETS_PREFIX='$ASSETS_PREFIX' 3) IAM permissions 4) File exists at: $S3_PATH"
fi

if [ ! -f "$DATA_FILE" ] || [ ! -s "$DATA_FILE" ]; then
    error "Downloaded file is missing or empty: $DATA_FILE"
fi

log "✅ Downloaded pre-generated embeddings from S3 ($(wc -l < $DATA_FILE) lines)"
    
# Load data using Python
log "Loading product data into database (this may take 2-3 minutes)..."
# Install psycopg system-wide for root user (data loading runs as root)
python3.13 -m pip install psycopg psycopg-binary 2>&1 | grep -v "WARNING: Running pip as the 'root' user" || true

python3.13 << 'PYTHON'
import os, csv, json, sys
import psycopg

conn = psycopg.connect(
    host=os.environ['DB_HOST'],
    port=os.environ['DB_PORT'],
    dbname=os.environ['DB_NAME'],
    user=os.environ['DB_USER'],
    password=os.environ['DB_PASSWORD']
)

count = 0
with open('/tmp/amazon-products-sample-with-cohere-embeddings.csv', 'r') as f:
    reader = csv.DictReader(f)
    with conn.cursor() as cur:
        for row in reader:
            count += 1
            # Validate and clip values to match schema constraints
            product_id = str(row['productId'])[:10]
            description = str(row['product_description'])[:500] if row['product_description'] else 'Product'
            imgurl = str(row.get('imgUrl', ''))[:70]
            producturl = str(row.get('productURL', ''))[:40]
            stars = max(1.0, min(5.0, float(row.get('stars', 3.0))))
            reviews = max(0, int(row.get('reviews', 0)))
            price = max(0, float(row.get('price', 0)))
            category_id = max(1, min(32767, int(row.get('category_id', 1))))
            isbestseller = row.get('isBestSeller', 'False') == 'True'
            boughtinlastmonth = max(0, int(row.get('boughtInLastMonth', 0)))
            category_name = str(row.get('category_name', 'General'))[:50]
            quantity = max(0, min(1000, int(row.get('quantity', 0))))
            embedding = json.loads(row['embedding'])
            
            cur.execute("""
                INSERT INTO bedrock_integration.product_catalog 
                ("productId", product_description, imgurl, producturl, stars, reviews, price, 
                 category_id, isbestseller, boughtinlastmonth, category_name, quantity, embedding)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                product_id, description, imgurl, producturl, stars, reviews, price,
                category_id, isbestseller, boughtinlastmonth, category_name, quantity, embedding
            ))
            
            # Commit every 1000 rows to prevent timeout
            if count % 1000 == 0:
                conn.commit()
                print(f"Loaded {count} products...")

conn.commit()
conn.close()
print(f"✅ Data loaded successfully: {count} products")
PYTHON

if [ $? -ne 0 ]; then
    error "Python data loading failed"
fi
    
    # Create indexes
    log "Creating search indexes..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL'
CREATE INDEX IF NOT EXISTS idx_product_embedding ON bedrock_integration.product_catalog 
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
CREATE INDEX IF NOT EXISTS idx_product_fts ON bedrock_integration.product_catalog
    USING GIN (to_tsvector('english', coalesce(product_description, '')));
CREATE INDEX IF NOT EXISTS idx_product_trgm ON bedrock_integration.product_catalog
    USING GIN (product_description gin_trgm_ops);
SQL
    
    # Demo App: RLS setup
    log "Setting up Demo App RLS policies..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL'
DROP TABLE IF EXISTS bedrock_integration.knowledge_base CASCADE;
CREATE TABLE bedrock_integration.knowledge_base (
    id SERIAL PRIMARY KEY,
    product_id VARCHAR(255),
    content TEXT NOT NULL,
    content_type VARCHAR(50) NOT NULL,
    persona_access VARCHAR(50)[] NOT NULL,
    severity VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT fk_product FOREIGN KEY (product_id) 
        REFERENCES bedrock_integration.product_catalog("productId") ON DELETE CASCADE
);

CREATE INDEX idx_kb_product_id ON bedrock_integration.knowledge_base(product_id);
CREATE INDEX idx_kb_persona_access ON bedrock_integration.knowledge_base USING GIN (persona_access);

-- Create RLS users
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'customer_user') THEN DROP USER customer_user; END IF;
    IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'agent_user') THEN DROP USER agent_user; END IF;
    IF EXISTS (SELECT 1 FROM pg_user WHERE usename = 'pm_user') THEN DROP USER pm_user; END IF;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

CREATE USER customer_user WITH PASSWORD 'customer123';
CREATE USER agent_user WITH PASSWORD 'agent123';
CREATE USER pm_user WITH PASSWORD 'pm123';

GRANT USAGE ON SCHEMA bedrock_integration TO customer_user, agent_user, pm_user;
GRANT SELECT ON ALL TABLES IN SCHEMA bedrock_integration TO customer_user, agent_user, pm_user;

ALTER TABLE bedrock_integration.knowledge_base ENABLE ROW LEVEL SECURITY;

CREATE POLICY customer_policy ON bedrock_integration.knowledge_base
    FOR SELECT TO customer_user USING ('customer' = ANY(persona_access));
CREATE POLICY agent_policy ON bedrock_integration.knowledge_base
    FOR SELECT TO agent_user USING ('support_agent' = ANY(persona_access));
CREATE POLICY pm_policy ON bedrock_integration.knowledge_base
    FOR SELECT TO pm_user USING (true);

-- Insert sample knowledge base data
WITH target_products AS (
    SELECT "productId" FROM bedrock_integration.product_catalog ORDER BY reviews DESC LIMIT 50
)
INSERT INTO bedrock_integration.knowledge_base (product_id, content, content_type, persona_access, severity)
SELECT "productId", 'Q: What is the warranty? A: 1-year manufacturer warranty.', 'product_faq',
       ARRAY['customer', 'support_agent', 'product_manager'], 'low'
FROM target_products;

-- Add support tickets
WITH high_review_products AS (
    SELECT "productId" FROM bedrock_integration.product_catalog WHERE reviews > 10000 LIMIT 25
)
INSERT INTO bedrock_integration.knowledge_base (product_id, content, content_type, persona_access, severity)
SELECT "productId", 'Support Ticket #' || (1000 + row_number() OVER()) || ': Customer reported connectivity issues - Resolved by firmware update',
       'support_ticket', ARRAY['support_agent', 'product_manager'], 'medium'
FROM high_review_products;

-- Add analytics
WITH expensive_products AS (
    SELECT "productId" FROM bedrock_integration.product_catalog WHERE price > 100 LIMIT 25
)
INSERT INTO bedrock_integration.knowledge_base (product_id, content, content_type, persona_access, severity)
SELECT "productId", 'Analytics Report: Product showing 15% month-over-month growth in sales',
       'analytics', ARRAY['product_manager'], NULL
FROM expensive_products;

-- Add general entries
INSERT INTO bedrock_integration.knowledge_base (product_id, content, content_type, persona_access, severity) VALUES
(NULL, 'Holiday return policy has been extended through January 31st', 'product_faq', ARRAY['customer', 'support_agent', 'product_manager'], 'low'),
(NULL, 'System maintenance scheduled for Sunday 2:00 AM - 4:00 AM PST', 'internal_note', ARRAY['support_agent', 'product_manager'], 'medium'),
(NULL, 'New product launch guidelines updated - please review before Q2', 'internal_note', ARRAY['product_manager'], 'high');
SQL
    
PRODUCT_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog" | xargs)

if [ "$PRODUCT_COUNT" -eq 0 ]; then
    error "Data loading failed - product_catalog is empty"
fi

log "✅ Database initialized with $PRODUCT_COUNT products from S3"

log "==================== Bootstrap Summary ===================="
echo "✅ COMPLETE SETUP FINISHED"
echo ""
echo "Services Running:"
echo "  Nginx: $(systemctl is-active nginx)"
echo "  Code Editor: $(systemctl is-active code-editor@$CODE_EDITOR_USER)"
echo ""
if [ ! -z "$PRODUCT_COUNT" ]; then
    echo "Database Status:"
    echo "  Products loaded: $PRODUCT_COUNT"
    echo "  Workshop: Ready for hybrid search"
    echo "  Demo App: RLS policies configured"
    echo ""
    echo "✅ Environment ready - no manual steps required!"
else
    echo "Next Steps:"
    echo "  1. Run: cd /workshop && bash scripts/setup-database.sh"
    echo "  2. This will load products with embeddings"
fi
echo ""
echo "Access Code Editor via CloudFront with token: $CODE_EDITOR_PASSWORD"
log "============================================================"
