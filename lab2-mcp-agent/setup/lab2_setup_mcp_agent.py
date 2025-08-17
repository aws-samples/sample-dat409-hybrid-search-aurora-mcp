#!/usr/bin/env python3
"""
DAT409 Workshop - Lab 2: Aurora PostgreSQL MCP Server & Strands Agent
Setup script for configuring MCP server and Strands agent
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
            print(f"📍 Found .env file at: {location}")
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
    print("\n📝 Please provide database connection details:")

class MCPServerSetup:
    """Setup Aurora PostgreSQL as an MCP Server"""
    
    def __init__(self):
        # Try to get from environment first, then prompt if needed
        self.db_host = os.getenv('DB_HOST')
        self.db_port = os.getenv('DB_PORT', '5432')
        self.db_name = os.getenv('DB_NAME')
        self.db_user = os.getenv('DB_USER')
        self.db_password = os.getenv('DB_PASSWORD')
        self.region = os.getenv('AWS_REGION', 'us-west-2')
        self.secret_arn = os.getenv('DATABASE_SECRET_ARN')
        
        # Prompt for missing values
        if not self.db_host:
            self.db_host = input("Enter Aurora PostgreSQL endpoint: ").strip()
        if not self.db_name:
            self.db_name = input("Enter database name [workshop_db]: ").strip() or "workshop_db"
        if not self.db_user:
            self.db_user = input("Enter database username [workshop_admin]: ").strip() or "workshop_admin"
        if not self.db_password:
            self.db_password = input("Enter database password: ").strip()
        if not self.secret_arn:
            print("ℹ️ Secret ARN not provided (optional for local testing)")
            self.secret_arn = "arn:aws:secretsmanager:us-west-2:123456789:secret:placeholder"
    
    def install_dependencies(self):
        """Install required Python packages"""
        print("\n📦 Installing MCP and Strands dependencies...")
        
        # Core packages
        packages = [
            ("psycopg[binary]", "PostgreSQL adapter"),
            ("python-dotenv", "Environment variable management"),
            ("boto3", "AWS SDK"),
        ]
        
        # Try to install uv first (package manager)
        try:
            subprocess.run(["uv", "--version"], capture_output=True, check=True)
            print("  ✓ uv already installed")
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
                print(f"    ✓ {package} installed")
        
        # MCP and Strands packages (may not be available yet)
        optional_packages = [
            ("mcp", "Model Context Protocol"),
            ("strands", "Strands Agent framework"),
            ("streamlit", "Dashboard framework"),
            ("plotly", "Visualization library"),
        ]
        
        for package, description in optional_packages:
            print(f"  Installing {package} ({description})...")
            result = subprocess.run([sys.executable, "-m", "pip", "install", package], 
                                  capture_output=True, text=True)
            if result.returncode != 0:
                print(f"    ℹ️ {package} not available (optional)")
        
        print("✅ Dependencies installed")
    
    def create_mcp_config(self) -> Dict[str, Any]:
        """Create MCP configuration for Aurora PostgreSQL"""
        
        # Create ~/.aws/amazonq directory if it doesn't exist
        amazonq_dir = Path.home() / ".aws" / "amazonq"
        amazonq_dir.mkdir(parents=True, exist_ok=True)
        
        # MCP configuration for direct PostgreSQL connection
        mcp_config = {
            "mcpServers": {
                "aurora-postgres-mcp": {
                    "command": "uvx",
                    "args": [
                        "awslabs.postgres-mcp-server@latest",
                        "--hostname", self.db_host,
                        "--port", self.db_port,
                        "--database", self.db_name,
                        "--secret_arn", self.secret_arn,
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
        return mcp_config
    
    def test_database_connection(self):
        """Test basic database connection"""
        print("\n🔍 Testing database connection...")
        
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
            print("❌ psycopg not installed - run: pip install psycopg[binary]")
            return False
        except Exception as e:
            print(f"❌ Connection failed: {str(e)}")
            print("\n💡 Troubleshooting tips:")
            print("  1. Check your database endpoint is correct")
            print("  2. Verify username and password")
            print("  3. Ensure database is publicly accessible or you're on the correct network")
            print("  4. Check security group allows connections from your IP")
            return False
    
    def create_analysis_tables(self):
        """Create specialized tables for Black Friday analysis"""
        print("\n📊 Creating analysis tables...")
        
        try:
            import psycopg
            
            conn_string = f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"
            
            with psycopg.connect(conn_string) as conn:
                with conn.cursor() as cur:
                    # Check if incident_logs table exists first
                    cur.execute("""
                        SELECT EXISTS (
                            SELECT FROM information_schema.tables 
                            WHERE table_name = 'incident_logs'
                        )
                    """)
                    incident_logs_exists = cur.fetchone()[0]
                    
                    if not incident_logs_exists:
                        print("  ⚠️ incident_logs table not found (run Lab 1 first)")
                    else:
                        print("  ✓ incident_logs table found")
                    
                    # Create performance metrics table
                    cur.execute("""
                        CREATE TABLE IF NOT EXISTS black_friday_metrics (
                            id SERIAL PRIMARY KEY,
                            metric_name TEXT NOT NULL,
                            metric_value NUMERIC,
                            threshold_value NUMERIC,
                            severity TEXT,
                            timestamp TIMESTAMPTZ,
                            year INTEGER,
                            created_at TIMESTAMPTZ DEFAULT NOW()
                        );
                    """)
                    print("  ✓ Created black_friday_metrics table")
                    
                    # Create preparedness checklist table
                    cur.execute("""
                        CREATE TABLE IF NOT EXISTS preparedness_checklist (
                            id SERIAL PRIMARY KEY,
                            category TEXT NOT NULL,
                            item TEXT NOT NULL,
                            priority INTEGER,
                            status TEXT DEFAULT 'pending',
                            owner TEXT,
                            due_date DATE,
                            notes TEXT
                        );
                    """)
                    print("  ✓ Created preparedness_checklist table")
                    
                    # Insert sample preparedness items
                    cur.execute("""
                        INSERT INTO preparedness_checklist (category, item, priority, owner)
                        VALUES 
                            ('Database', 'Increase connection pool size', 1, 'DBA'),
                            ('Database', 'Schedule vacuum before peak', 1, 'DBA'),
                            ('Monitoring', 'Set up connection exhaustion alerts', 1, 'SRE'),
                            ('Application', 'Implement circuit breakers', 2, 'Developer'),
                            ('Infrastructure', 'Scale read replicas', 1, 'DevOps')
                        ON CONFLICT DO NOTHING;
                    """)
                    print("  ✓ Added sample checklist items")
                    
                    conn.commit()
                    print("✅ Analysis tables created successfully")
                    
        except ImportError:
            print("❌ psycopg not installed")
        except Exception as e:
            print(f"⚠️ Could not create tables: {str(e)}")
            print("   Tables may already exist or database connection issue")
    
    def create_sample_env_file(self):
        """Create a sample .env file if none exists"""
        if not env_path:
            sample_env = f"""# DAT409 Workshop Environment Variables
# Copy this to .env and fill in your values

# Database Configuration
DB_HOST={self.db_host}
DB_PORT={self.db_port}
DB_NAME={self.db_name}
DB_USER={self.db_user}
DB_PASSWORD={self.db_password}

# AWS Configuration
AWS_REGION={self.region}
DATABASE_SECRET_ARN={self.secret_arn}

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
    print("🚀 DAT409 Lab 2: Setting up Aurora PostgreSQL MCP Server")
    print("=" * 60)
    
    setup = MCPServerSetup()
    
    # Step 1: Install dependencies
    setup.install_dependencies()
    
    # Step 2: Test database connection
    if setup.test_database_connection():
        # Step 3: Create MCP configuration
        setup.create_mcp_config()
        
        # Step 4: Create analysis tables
        setup.create_analysis_tables()
    else:
        print("\n⚠️ Skipping table creation due to connection issues")
        print("   Fix connection and run again")
        
        # Create sample env file for reference
        setup.create_sample_env_file()
    
    print("\n" + "=" * 60)
    print("📝 Next steps:")
    print("1. Ensure database connection is working")
    print("2. Run Lab 1 to populate incident_logs table")
    print("3. Run the Strands agent: python3 ../agent/strands_agent.py")
    print("4. (Optional) Launch dashboard: streamlit run ../dashboard/dashboard.py")

if __name__ == "__main__":
    main()