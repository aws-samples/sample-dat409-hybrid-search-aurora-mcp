#!/usr/bin/env python3
"""
DAT409 Workshop - Lab 2: Aurora PostgreSQL MCP Server & Strands Agent
Setup script for configuring MCP server with RDS Data API
"""

import os
import json
import subprocess
import sys
from pathlib import Path
from typing import Dict, Any

# Try to find and load .env file
def find_env_file():
    """Find .env file in various locations"""
    possible_locations = [
        Path('.env'),  # Current directory
        Path('../.env'),  # Parent directory
        Path('../../.env'),  # Two levels up
        Path('/workshop/.env'),  # Workshop environment
        Path.home() / '.env',  # Home directory
    ]
    
    for location in possible_locations:
        if location.exists():
            print(f"📁 Found .env file at: {location}")
            return location
    
    return None

# Load environment variables
env_path = find_env_file()
if env_path:
    try:
        from dotenv import load_dotenv
        load_dotenv(env_path)
        print("✅ Environment variables loaded")
    except ImportError:
        print("⚠️ python-dotenv not installed, reading .env manually")
        with open(env_path) as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    os.environ[key] = value
else:
    print("⚠️ No .env file found")
    print("\n🔍 Please provide database connection details:")

class MCPServerSetup:
    """Setup Aurora PostgreSQL as an MCP Server using RDS Data API"""
    
    def __init__(self):
        # Try to get from environment first, then prompt if needed
        self.db_name = os.getenv('DB_NAME')
        self.region = os.getenv('AWS_REGION', 'us-west-2')
        self.secret_arn = os.getenv('DATABASE_SECRET_ARN')
        self.cluster_arn = os.getenv('DATABASE_CLUSTER_ARN')
        
        # For backward compatibility, still get these for testing
        self.db_host = os.getenv('DB_HOST')
        self.db_port = os.getenv('DB_PORT', '5432')
        self.db_user = os.getenv('DB_USER')
        self.db_password = os.getenv('DB_PASSWORD')
        
        # Prompt for missing critical values
        if not self.db_name:
            self.db_name = input("Enter database name [workshop_db]: ").strip() or "workshop_db"
        
        if not self.cluster_arn:
            print("\n⚠️ DATABASE_CLUSTER_ARN not found in environment")
            print("To find your cluster ARN:")
            print("1. Go to RDS Console > Databases")
            print("2. Click on your Aurora cluster")
            print("3. Copy the 'Resource ARN' from Configuration tab")
            print("\nExample format: arn:aws:rds:us-west-2:123456789012:cluster:dat409-workshop-cluster")
            self.cluster_arn = input("\nEnter Aurora Cluster ARN: ").strip()
        
        if not self.secret_arn:
            print("\n⚠️ DATABASE_SECRET_ARN not found in environment")
            print("To find your secret ARN:")
            print("1. Go to Secrets Manager Console")
            print("2. Find your database secret")
            print("3. Copy the Secret ARN")
            print("\nExample format: arn:aws:secretsmanager:us-west-2:123456789012:secret:dat409-db-credentials-AbCdEf")
            self.secret_arn = input("\nEnter Database Secret ARN: ").strip()
    
    def install_dependencies(self):
        """Install required Python packages"""
        print("\n📦 Installing MCP and dependencies...")
        
        # Core packages
        packages = [
            ("psycopg[binary]", "PostgreSQL adapter for testing"),
            ("python-dotenv", "Environment variable management"),
            ("boto3", "AWS SDK"),
        ]
        
        # Try to install uv first (package manager)
        try:
            subprocess.run(["uv", "--version"], capture_output=True, check=True)
            print("  ✔ uv already installed")
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("  Installing uv...")
            subprocess.run([sys.executable, "-m", "pip", "install", "uv"], 
                         capture_output=True, text=True)
        
        # Install other packages
        for package, description in packages:
            print(f"  Installing {package} ({description})...")
            result = subprocess.run([sys.executable, "-m", "pip", "install", package], 
                                  capture_output=True, text=True)
            if result.returncode != 0:
                print(f"    ⚠️ Failed to install {package}: {result.stderr}")
            else:
                print(f"    ✔ {package} installed")
        
        print("✅ Dependencies installed")
    
    def create_mcp_config(self) -> Dict[str, Any]:
        """Create MCP configuration for Aurora PostgreSQL using RDS Data API"""
        
        # Create ~/.aws/amazonq directory if it doesn't exist
        amazonq_dir = Path.home() / ".aws" / "amazonq"
        amazonq_dir.mkdir(parents=True, exist_ok=True)
        
        # MCP configuration for RDS Data API connection
        mcp_config = {
            "mcpServers": {
                "aurora-postgres-mcp": {
                    "command": "uvx",
                    "args": [
                        "awslabs.postgres-mcp-server@latest",
                        "--resource_arn", self.cluster_arn,
                        "--secret_arn", self.secret_arn,
                        "--database", self.db_name,
                        "--region", self.region,
                        "--readonly", "False"  # Allow writes for workshop
                    ],
                    "env": {
                        "AWS_REGION": self.region,
                        "FASTMCP_LOG_LEVEL": "INFO"
                    },
                    "disabled": False,
                    "autoApprove": []
                }
            }
        }
        
        # Save configuration
        config_path = amazonq_dir / "mcp.json"
        with open(config_path, 'w') as f:
            json.dump(mcp_config, f, indent=2)
        
        print(f"✅ MCP configuration saved to {config_path}")
        print(f"\n📋 Configuration details:")
        print(f"   - Using RDS Data API connection")
        print(f"   - Cluster ARN: {self.cluster_arn[:50]}...")
        print(f"   - Secret ARN: {self.secret_arn[:50]}...")
        print(f"   - Database: {self.db_name}")
        print(f"   - Region: {self.region}")
        
        # Also save to VS Code settings location
        self.update_vscode_settings(mcp_config)
        
        return mcp_config
    
    def update_vscode_settings(self, mcp_config: Dict[str, Any]):
        """Update VS Code settings with MCP configuration"""
        # Try multiple VS Code settings locations
        vscode_locations = [
            Path.home() / ".code-editor-server" / "data" / "User" / "settings.json",
            Path.home() / ".vscode-server" / "data" / "User" / "settings.json",
            Path.home() / ".config" / "Code" / "User" / "settings.json",
        ]
        
        for settings_path in vscode_locations:
            if settings_path.parent.exists():
                try:
                    # Read existing settings
                    if settings_path.exists():
                        with open(settings_path, 'r') as f:
                            settings = json.load(f)
                    else:
                        settings = {}
                    
                    # Add MCP configuration
                    settings["amazonQ.mcp"] = mcp_config
                    
                    # Write updated settings
                    settings_path.parent.mkdir(parents=True, exist_ok=True)
                    with open(settings_path, 'w') as f:
                        json.dump(settings, f, indent=2)
                    
                    print(f"✅ Updated VS Code settings at {settings_path}")
                except Exception as e:
                    print(f"⚠️ Could not update VS Code settings at {settings_path}: {e}")
    
    def test_database_connection(self):
        """Test database connection (if direct connection details available)"""
        print("\n🔍 Testing database connection...")
        
        # If we don't have direct connection details, skip this test
        if not all([self.db_host, self.db_user, self.db_password]):
            print("ℹ️ Direct connection details not available")
            print("   RDS Data API connection will be tested when MCP server starts")
            return True
        
        try:
            import psycopg
            
            # Build connection string
            conn_string = f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"
            
            # Test connection
            with psycopg.connect(conn_string) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT version()")
                    version = cur.fetchone()[0]
                    print(f"✅ Connected to PostgreSQL")
                    print(f"   Version: {version.split(',')[0]}")
                    
                    # Check for required extensions
                    cur.execute("SELECT extname FROM pg_extension WHERE extname IN ('vector', 'pg_trgm')")
                    extensions = [row[0] for row in cur.fetchall()]
                    if extensions:
                        print(f"   Extensions: {', '.join(extensions)}")
                    else:
                        print("   ⚠️ Extensions not found (will be created)")
            
            return True
            
        except ImportError:
            print("ℹ️ psycopg not installed - skipping direct connection test")
            return True
        except Exception as e:
            print(f"⚠️ Direct connection failed: {str(e)}")
            print("   This is OK if using RDS Data API exclusively")
            return True
    
    def test_rds_data_api(self):
        """Test RDS Data API connection"""
        print("\n🔍 Testing RDS Data API connection...")
        
        try:
            import boto3
            
            # Create RDS Data API client
            rds_data = boto3.client('rds-data', region_name=self.region)
            
            # Test with a simple query
            response = rds_data.execute_statement(
                resourceArn=self.cluster_arn,
                secretArn=self.secret_arn,
                database=self.db_name,
                sql="SELECT version()"
            )
            
            if response['records']:
                version = response['records'][0][0]['stringValue']
                print(f"✅ RDS Data API connection successful")
                print(f"   Version: {version.split(',')[0]}")
                return True
            
        except Exception as e:
            print(f"❌ RDS Data API test failed: {str(e)}")
            print("\n💡 Troubleshooting tips:")
            print("  1. Verify cluster ARN is correct")
            print("  2. Check secret ARN and permissions")
            print("  3. Ensure RDS Data API is enabled for your cluster")
            print("  4. Verify IAM permissions for rds-data:ExecuteStatement")
            return False
    
    def create_sample_env_file(self):
        """Create a sample .env file with RDS Data API configuration"""
        sample_env = f"""# DAT409 Workshop Environment Variables
# Copy this to .env and fill in your values

# Database Configuration
DB_NAME={self.db_name}
DATABASE_CLUSTER_ARN={self.cluster_arn or 'arn:aws:rds:region:account:cluster:your-cluster-name'}
DATABASE_SECRET_ARN={self.secret_arn or 'arn:aws:secretsmanager:region:account:secret:your-secret-name'}

# AWS Configuration
AWS_REGION={self.region}

# Optional: Direct connection details (for testing)
DB_HOST={self.db_host or 'your-cluster.cluster-xxx.region.rds.amazonaws.com'}
DB_PORT={self.db_port}
DB_USER={self.db_user or 'workshop_admin'}
DB_PASSWORD={self.db_password or 'your-password'}

# Workshop Configuration
WORKSHOP_NAME=dat409-hybrid-search
"""
        
        env_file = Path('.env.sample')
        with open(env_file, 'w') as f:
            f.write(sample_env)
        
        print(f"\n📝 Sample environment file created: {env_file}")
        print("   Copy to .env and update with your values")

def main():
    """Main setup function"""
    print("🚀 DAT409 Lab 2: Setting up Aurora PostgreSQL MCP Server (RDS Data API)")
    print("=" * 60)
    
    setup = MCPServerSetup()
    
    # Step 1: Install dependencies
    setup.install_dependencies()
    
    # Step 2: Test connections
    setup.test_database_connection()  # Optional direct connection test
    setup.test_rds_data_api()  # RDS Data API test
    
    # Step 3: Create MCP configuration
    setup.create_mcp_config()
    
    # Step 4: Create sample env file
    setup.create_sample_env_file()
    
    print("\n" + "=" * 60)
    print("📝 Next steps:")
    print("1. Restart VS Code to load the new MCP configuration")
    print("2. Open Amazon Q chat and test with: 'What tables are in the database?'")
    print("3. If using direct connection, run Lab 1 to populate incident_logs table")
    print("4. Use Amazon Q to analyze your data with natural language queries")
    print("\n💡 Example queries for Amazon Q:")
    print("   - 'Show me all critical incidents from Black Friday'")
    print("   - 'What are the most common database errors?'")
    print("   - 'Create a summary of connection pool issues'")

if __name__ == "__main__":
    main()