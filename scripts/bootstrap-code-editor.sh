#!/bin/bash
# DAT409 Workshop - Code Editor Bootstrap Script (Infrastructure Only)
# This script sets up Code Editor and dependencies but NO database tables/data
# Usage: curl -fsSL https://raw.githubusercontent.com/.../bootstrap-code-editor.sh | bash -s -- PASSWORD

set -euo pipefail

# Parameters
CODE_EDITOR_PASSWORD="${1:-defaultPassword}"
CODE_EDITOR_USER="participant"
HOME_FOLDER="/workshop"

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

log "Starting DAT409 Code Editor Bootstrap (Infrastructure Only)"
log "Password: ${CODE_EDITOR_PASSWORD:0:4}****"
log "Note: Database tables/data will be set up separately by instructors"

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
# Note: lab1-hybrid-search and lab2-mcp-agent folders are pre-created in GitHub
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
log "Creating workspace settings for auto-open terminal..."
sudo -u "$CODE_EDITOR_USER" mkdir -p "$HOME_FOLDER/.vscode"
cat > "$HOME_FOLDER/.vscode/settings.json" << 'WORKSPACE_SETTINGS'
{
    "terminal.integrated.defaultProfile.linux": "bash",
    "terminal.integrated.cwd": "/workshop"
}
WORKSPACE_SETTINGS

chown -R "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/.vscode"

log "==================== End VS Code Extensions Section ===================="

# ===========================================================================
# PYTHON PACKAGES INSTALLATION
# ===========================================================================

log "==================== Installing Python Packages ===================="

# Note: Requirements will be installed after repository clone
log "Core Python packages will be installed..."
sudo -u "$CODE_EDITOR_USER" python3.13 -m pip install --user --upgrade pip setuptools wheel

log "Installing essential packages for both labs..."
sudo -u "$CODE_EDITOR_USER" python3.13 -m pip install --user \
    boto3 psycopg pgvector pandas numpy matplotlib seaborn tqdm \
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
    cat > "$HOME_FOLDER/.env" << ENV_EOF
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
LAB1_DIR='$HOME_FOLDER/lab1-hybrid-search'
LAB2_DIR='$HOME_FOLDER/lab2-mcp-agent'
ENV_EOF

    chown "$CODE_EDITOR_USER:$CODE_EDITOR_USER" "$HOME_FOLDER/.env"
    chmod 600 "$HOME_FOLDER/.env"
    
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
alias lab1='cd /workshop/lab1-hybrid-search'
alias lab2='cd /workshop/lab2-mcp-agent'

# Load .env file if it exists
if [ -f /workshop/.env ]; then
    set -a
    source /workshop/.env
    set +a
fi

# Welcome message (show once per session)
if [ -z "\$DAT409_WELCOME_SHOWN" ]; then
    export DAT409_WELCOME_SHOWN=1
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  DAT409 - Hybrid Search with Aurora PostgreSQL for MCP Retrieval"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo "🔧 Available Commands:"
    echo "   lab1      - Navigate to Lab 1 (Hybrid Search)"
    echo "   lab2      - Navigate to Lab 2 (MCP Agent)"
    echo "   workshop  - Navigate to /workshop"
    echo "   psql      - Connect to PostgreSQL database"
    echo ""
    echo "📁 Workshop Structure:"
    echo "   /workshop/lab1-hybrid-search/notebook/  - Lab 1 Jupyter notebook"
    echo "   /workshop/lab2-mcp-agent/               - Lab 2 Streamlit app"
    echo "   /workshop/scripts/                      - Setup scripts"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
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

log "==================== Bootstrap Summary ===================="
echo "✅ INFRASTRUCTURE SETUP COMPLETE"
echo ""
echo "Services Running:"
echo "  Nginx: $(systemctl is-active nginx)"
echo "  Code Editor: $(systemctl is-active code-editor@$CODE_EDITOR_USER)"
echo ""
echo "Next Steps (after repository clone):"
echo "  1. Run: cd /workshop && bash scripts/setup-database.sh"
echo "  2. This will load 21,704 products with embeddings (6-9 min)"
echo ""
echo "Access Code Editor via CloudFront with token: $CODE_EDITOR_PASSWORD"
log "============================================================"
