#!/usr/bin/env python3
"""
Test connection to AWS Aurora PostgreSQL from local machine
"""
import boto3
import json
import psycopg
from pgvector.psycopg import register_vector

def get_database_credentials():
    """Retrieve database credentials from AWS Secrets Manager"""
    try:
        # Create a Secrets Manager client
        session = boto3.session.Session(region_name='us-west-2')
        client = session.client(service_name='secretsmanager')
        
        # Retrieve the secret
        secret_name = 'apgpg-pgvector-secret'
        print(f"📡 Retrieving secret: {secret_name}")
        
        response = client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])
        
        print(f"✅ Secret retrieved successfully")
        print(f"🔗 Host: {secret.get('host', 'Not found')}")
        print(f"👤 User: {secret.get('username', 'Not found')}")
        print(f"🔌 Port: {secret.get('port', 5432)}")
        
        return secret
    
    except Exception as e:
        print(f"❌ Error retrieving secret: {e}")
        raise

def test_connection():
    """Test connection to Aurora PostgreSQL"""
    try:
        # Get credentials
        credentials = get_database_credentials()
        
        # Connect to database
        print(f"\n🔄 Connecting to Aurora PostgreSQL...")
        conn = psycopg.connect(
            host=credentials['host'],
            port=credentials.get('port', 5432),
            user=credentials['username'],
            password=credentials['password'],
            dbname=credentials.get('dbname', 'postgres'),
            connect_timeout=10
        )
        
        print(f"✅ Connected successfully!")
        
        # Register pgvector
        register_vector(conn)
        
        # Test query
        cursor = conn.cursor()
        
        # Check PostgreSQL version
        cursor.execute("SELECT version();")
        version = cursor.fetchone()[0]
        print(f"📊 PostgreSQL Version: {version.split(',')[0]}")
        
        # Check for pgvector extension
        cursor.execute("""
            SELECT extname, extversion 
            FROM pg_extension 
            WHERE extname = 'vector';
        """)
        result = cursor.fetchone()
        if result:
            print(f"✅ pgvector extension: v{result[1]}")
        
        # Check if product catalog exists
        cursor.execute("""
            SELECT COUNT(*) 
            FROM information_schema.tables 
            WHERE table_schema = 'bedrock_integration' 
            AND table_name = 'product_catalog';
        """)
        exists = cursor.fetchone()[0]
        
        if exists:
            cursor.execute("""
                SELECT COUNT(*) 
                FROM bedrock_integration.product_catalog;
            """)
            count = cursor.fetchone()[0]
            print(f"✅ Product catalog found: {count:,} products")
        else:
            print("⚠️ Product catalog table not found")
        
        cursor.close()
        conn.close()
        
        print("\n🎉 All tests passed!")
        return True
        
    except Exception as e:
        print(f"\n❌ Connection failed: {e}")
        print("\n🔍 Troubleshooting tips:")
        print("1. Check your AWS credentials: aws sts get-caller-identity")
        print("2. Verify secret name is correct")
        print("3. Check if your IP is whitelisted in the RDS security group")
        print("4. Ensure the database is publicly accessible or you're using VPN/bastion")
        return False

if __name__ == "__main__":
    test_connection()