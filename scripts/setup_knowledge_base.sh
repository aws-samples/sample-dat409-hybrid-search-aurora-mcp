#!/bin/bash
# DAT409 - Setup Knowledge Base with RLS
# This script creates the knowledge base table, roles, users, and RLS policies

set -e  # Exit on error

# Database connection details from .env
DB_HOST="apgpg-pgvector.cluster-chygmprofdnr.us-west-2.rds.amazonaws.com"
DB_PORT="5432"
DB_USER="postgres"
DB_PASSWORD="brVJ3SNrNtw9VEnG"
DB_NAME="postgres"

echo "=================================="
echo "DAT409 - Knowledge Base Setup"
echo "=================================="
echo ""

# Set password for psql
export PGPASSWORD=$DB_PASSWORD

echo "1. Enabling extensions..."
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << 'EOF'
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;
\echo '✅ Extensions enabled'
EOF

echo ""
echo "2. Creating roles..."
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << 'EOF'
CREATE ROLE customer_role;
CREATE ROLE support_agent_role;
CREATE ROLE product_manager_role;
\echo '✅ Roles created'
EOF

echo ""
echo "3. Creating users..."
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << 'EOF'
CREATE USER customer_user WITH PASSWORD 'customer123' IN ROLE customer_role;
CREATE USER agent_user WITH PASSWORD 'agent123' IN ROLE support_agent_role;
CREATE USER pm_user WITH PASSWORD 'pm123' IN ROLE product_manager_role;
\echo '✅ Users created'
EOF

echo ""
echo "4. Granting permissions..."
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << 'EOF'
GRANT USAGE ON SCHEMA bedrock_integration TO customer_role, support_agent_role, product_manager_role;
GRANT SELECT ON bedrock_integration.product_catalog TO customer_role, support_agent_role, product_manager_role;
GRANT USAGE ON SCHEMA public TO customer_role, support_agent_role, product_manager_role;
\echo '✅ Permissions granted'
EOF

echo ""
echo "5. Creating knowledge_base table..."
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << 'EOF'
CREATE TABLE public.knowledge_base (
    id SERIAL PRIMARY KEY,
    product_id TEXT REFERENCES bedrock_integration.product_catalog("productId"),
    content TEXT NOT NULL,
    content_type TEXT NOT NULL,
    access_level TEXT[] NOT NULL,
    severity TEXT DEFAULT 'low',
    created_at TIMESTAMP DEFAULT NOW()
);
\echo '✅ knowledge_base table created'
EOF

echo ""
echo "6. Enabling Row Level Security..."
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << 'EOF'
ALTER TABLE public.knowledge_base ENABLE ROW LEVEL SECURITY;
\echo '✅ RLS enabled on knowledge_base'
EOF

echo ""
echo "7. Creating RLS policies..."
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << 'EOF'
CREATE POLICY customer_policy ON public.knowledge_base
    FOR SELECT TO customer_role
    USING ('customer' = ANY(access_level) OR 'product_faq' = content_type);

CREATE POLICY agent_policy ON public.knowledge_base
    FOR SELECT TO support_agent_role
    USING ('customer' = ANY(access_level) OR 'support_agent' = ANY(access_level));

CREATE POLICY pm_policy ON public.knowledge_base
    FOR SELECT TO product_manager_role
    USING (true);
\echo '✅ RLS policies created'
EOF

echo ""
echo "8. Granting SELECT on knowledge_base..."
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << 'EOF'
GRANT SELECT ON public.knowledge_base TO customer_role, support_agent_role, product_manager_role;
\echo '✅ SELECT permission granted'
EOF

echo ""
echo "9. Verifying setup..."
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << 'EOF'
-- Check table exists
SELECT 'knowledge_base table exists' as status 
FROM information_schema.tables 
WHERE table_schema = 'public' AND table_name = 'knowledge_base';

-- Check RLS is enabled
SELECT 'RLS is enabled' as status
FROM pg_tables 
WHERE schemaname = 'public' AND tablename = 'knowledge_base' AND rowsecurity = true;

-- Check policies
SELECT COUNT(*) || ' RLS policies created' as status
FROM pg_policies 
WHERE tablename = 'knowledge_base';

-- Check roles
SELECT COUNT(*) || ' roles created' as status
FROM pg_roles 
WHERE rolname IN ('customer_role', 'support_agent_role', 'product_manager_role');
EOF

echo ""
echo "=================================="
echo "✅ Setup Complete!"
echo "=================================="
echo ""
echo "Next steps:"
echo "1. Populate knowledge_base with sample data"
echo "2. Test with: ./test_rls.sh"
echo ""