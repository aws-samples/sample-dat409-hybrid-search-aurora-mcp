-- DAT409 Workshop - Database Setup Script
-- This script initializes the database with required extensions and tables
-- Note: In Workshop Studio, this is automatically executed by the bootstrap process

-- ==========================================
-- Extensions
-- ==========================================

-- Enable pgvector for semantic search
CREATE EXTENSION IF NOT EXISTS vector;

-- Enable pg_trgm for trigram-based fuzzy text search
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Enable pg_stat_statements for query performance monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- ==========================================
-- Main Table
-- ==========================================

-- Drop existing table if it exists (for clean workshop start)
DROP TABLE IF EXISTS incident_logs CASCADE;

-- Create the main incident logs table
CREATE TABLE incident_logs (
    -- Primary identifier
    doc_id TEXT PRIMARY KEY,
    
    -- Core content for search
    content TEXT NOT NULL,
    
    -- MCP-style structured metadata
    persona TEXT NOT NULL,                    -- Engineering team (dba, sre, developer, data_engineer)
    timestamp TIMESTAMPTZ NOT NULL,           -- When the incident occurred
    task_context TEXT,                        -- What the team was doing
    severity TEXT DEFAULT 'info',             -- Severity level (critical, warning, info)
    
    -- Flexible metric storage
    metrics JSONB,                            -- Team-specific metrics as JSON
    
    -- Relationship tracking
    related_systems TEXT[],                   -- Array of related system names
    temporal_marker TEXT,                     -- Time period marker (morning, afternoon, evening, overnight)
    
    -- Vector embedding for semantic search
    content_embedding vector(1024),           -- Cohere Embed v3 uses 1024 dimensions
    
    -- Audit fields
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==========================================
-- Indexes for Search Performance
-- ==========================================

-- HNSW index for fast vector similarity search
CREATE INDEX IF NOT EXISTS idx_logs_embedding
ON incident_logs
USING hnsw (content_embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- GIN index for trigram-based fuzzy text search
CREATE INDEX IF NOT EXISTS idx_logs_content_trgm
ON incident_logs
USING gin(content gin_trgm_ops);

-- GIN index for PostgreSQL full-text search
CREATE INDEX IF NOT EXISTS idx_logs_fts
ON incident_logs
USING gin(to_tsvector('english', content));

-- B-tree indexes for filtering
CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON incident_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_logs_persona ON incident_logs(persona);
CREATE INDEX IF NOT EXISTS idx_logs_severity ON incident_logs(severity);
CREATE INDEX IF NOT EXISTS idx_logs_task_context ON incident_logs(task_context);

-- GIN index for JSONB metrics queries
CREATE INDEX IF NOT EXISTS idx_logs_metrics ON incident_logs USING gin(metrics);

-- ==========================================
-- Helper Functions
-- ==========================================

-- Function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update updated_at
CREATE TRIGGER update_incident_logs_updated_at
BEFORE UPDATE ON incident_logs
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- ==========================================
-- Search Functions (Optional)
-- ==========================================

-- Function for hybrid search combining all methods
CREATE OR REPLACE FUNCTION hybrid_search(
    query_text TEXT,
    query_embedding vector(1024),
    semantic_weight FLOAT DEFAULT 0.4,
    trigram_weight FLOAT DEFAULT 0.3,
    fulltext_weight FLOAT DEFAULT 0.3,
    result_limit INT DEFAULT 10
)
RETURNS TABLE(
    doc_id TEXT,
    content TEXT,
    persona TEXT,
    timestamp TIMESTAMPTZ,
    severity TEXT,
    combined_score FLOAT
) AS $$
BEGIN
    RETURN QUERY
    WITH semantic_results AS (
        SELECT 
            il.doc_id,
            il.content,
            il.persona,
            il.timestamp,
            il.severity,
            1 - (il.content_embedding <=> query_embedding) as score
        FROM incident_logs il
        WHERE il.content_embedding IS NOT NULL
        ORDER BY il.content_embedding <=> query_embedding
        LIMIT result_limit * 2
    ),
    trigram_results AS (
        SELECT 
            il.doc_id,
            il.content,
            il.persona,
            il.timestamp,
            il.severity,
            similarity(query_text, il.content) as score
        FROM incident_logs il
        WHERE similarity(query_text, il.content) > 0.1
        ORDER BY score DESC
        LIMIT result_limit * 2
    ),
    fulltext_results AS (
        SELECT 
            il.doc_id,
            il.content,
            il.persona,
            il.timestamp,
            il.severity,
            ts_rank_cd(to_tsvector('english', il.content),
                      plainto_tsquery('english', query_text)) as score
        FROM incident_logs il
        WHERE to_tsvector('english', il.content) @@ plainto_tsquery('english', query_text)
        ORDER BY score DESC
        LIMIT result_limit * 2
    ),
    all_results AS (
        SELECT 
            COALESCE(s.doc_id, t.doc_id, f.doc_id) as doc_id,
            COALESCE(s.content, t.content, f.content) as content,
            COALESCE(s.persona, t.persona, f.persona) as persona,
            COALESCE(s.timestamp, t.timestamp, f.timestamp) as timestamp,
            COALESCE(s.severity, t.severity, f.severity) as severity,
            COALESCE(s.score * semantic_weight, 0) + 
            COALESCE(t.score * trigram_weight, 0) + 
            COALESCE(LEAST(f.score, 1.0) * fulltext_weight, 0) as combined_score
        FROM semantic_results s
        FULL OUTER JOIN trigram_results t ON s.doc_id = t.doc_id
        FULL OUTER JOIN fulltext_results f ON s.doc_id = f.doc_id OR t.doc_id = f.doc_id
    )
    SELECT 
        all_results.doc_id,
        all_results.content,
        all_results.persona,
        all_results.timestamp,
        all_results.severity,
        all_results.combined_score
    FROM all_results
    ORDER BY all_results.combined_score DESC
    LIMIT result_limit;
END;
$$ LANGUAGE plpgsql;

-- ==========================================
-- Sample Data Verification
-- ==========================================

-- Query to verify extensions are installed
SELECT 
    extname,
    extversion
FROM pg_extension
WHERE extname IN ('vector', 'pg_trgm', 'pg_stat_statements');

-- Query to check table structure
SELECT 
    column_name,
    data_type,
    character_maximum_length,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'incident_logs'
ORDER BY ordinal_position;

-- Query to verify indexes
SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'incident_logs';

-- ==========================================
-- Useful Queries for Workshop
-- ==========================================

-- Count logs by persona
SELECT 
    persona,
    COUNT(*) as log_count,
    COUNT(DISTINCT DATE_TRUNC('day', timestamp)) as active_days
FROM incident_logs
GROUP BY persona
ORDER BY log_count DESC;

-- Count logs by severity
SELECT 
    severity,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM incident_logs
GROUP BY severity
ORDER BY 
    CASE severity 
        WHEN 'critical' THEN 1
        WHEN 'warning' THEN 2
        WHEN 'info' THEN 3
        ELSE 4
    END;

-- Find peak incident days
SELECT 
    DATE_TRUNC('day', timestamp) as day,
    COUNT(*) as incident_count,
    COUNT(DISTINCT persona) as teams_affected,
    ARRAY_AGG(DISTINCT severity) as severities
FROM incident_logs
GROUP BY DATE_TRUNC('day', timestamp)
ORDER BY incident_count DESC
LIMIT 10;

-- Find multi-team incident patterns
WITH multi_team_days AS (
    SELECT 
        DATE_TRUNC('day', timestamp) as day,
        COUNT(DISTINCT persona) as team_count,
        ARRAY_AGG(DISTINCT persona ORDER BY persona) as teams
    FROM incident_logs
    GROUP BY DATE_TRUNC('day', timestamp)
    HAVING COUNT(DISTINCT persona) > 1
)
SELECT 
    day,
    team_count,
    teams
FROM multi_team_days
ORDER BY team_count DESC, day DESC;

-- ==========================================
-- Cleanup (if needed)
-- ==========================================

-- To reset the workshop environment:
-- DROP TABLE IF EXISTS incident_logs CASCADE;
-- DROP EXTENSION IF EXISTS vector CASCADE;
-- DROP EXTENSION IF EXISTS pg_trgm CASCADE;