#!/bin/bash
# Quick verification script to check if workshop setup is complete

source /workshop/.env 2>/dev/null || { echo "❌ .env file not found"; exit 1; }

echo "🔍 DAT409 Workshop Setup Verification"
echo "======================================"
echo ""

# Check database connection
echo "1. Database Connection:"
if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" &>/dev/null; then
    echo "   ✅ Connected to $DB_HOST"
else
    echo "   ❌ Cannot connect to database"
    exit 1
fi

# Check pgvector extension
echo "2. pgvector Extension:"
VECTOR_CHECK=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM pg_extension WHERE extname='vector';" 2>/dev/null | xargs)
if [ "$VECTOR_CHECK" = "1" ]; then
    echo "   ✅ pgvector extension installed"
else
    echo "   ❌ pgvector extension NOT installed"
    echo "   Run: psql -c 'CREATE EXTENSION vector;'"
    exit 1
fi

# Check product catalog
echo "3. Product Catalog:"
PRODUCT_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog;" 2>/dev/null | xargs)
if [ ! -z "$PRODUCT_COUNT" ] && [ "$PRODUCT_COUNT" -gt 0 ]; then
    echo "   ✅ $PRODUCT_COUNT products loaded"
else
    echo "   ⚠️  No products found - run /workshop/setup-database.sh"
fi

# Check embeddings
echo "4. Embeddings:"
EMB_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL;" 2>/dev/null | xargs)
if [ ! -z "$EMB_COUNT" ] && [ "$EMB_COUNT" -gt 0 ]; then
    echo "   ✅ $EMB_COUNT products with embeddings"
else
    echo "   ⚠️  No embeddings found"
fi

# Check Lab 2 RLS
echo "5. Lab 2 RLS:"
RLS_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -c "SELECT COUNT(*) FROM pg_policies WHERE tablename='knowledge_base';" 2>/dev/null | xargs)
if [ ! -z "$RLS_COUNT" ] && [ "$RLS_COUNT" -gt 0 ]; then
    echo "   ✅ $RLS_COUNT RLS policies configured"
else
    echo "   ⚠️  RLS not configured"
fi

echo ""
echo "======================================"
if [ ! -z "$PRODUCT_COUNT" ] && [ "$PRODUCT_COUNT" -gt 20000 ]; then
    echo "✅ Workshop is ready! You can start Lab 1."
else
    echo "⚠️  Setup incomplete. Check /workshop/database-setup.log"
    echo "   Or run: /workshop/setup-database.sh"
fi
