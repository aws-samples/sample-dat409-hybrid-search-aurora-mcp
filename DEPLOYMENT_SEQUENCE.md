# DAT409 Workshop - Deployment Sequence

## Overview
This workshop uses a **two-phase deployment** approach:
1. **Phase 1**: Infrastructure setup (automated via CloudFormation)
2. **Phase 2**: Database setup and data loading (manual, run by instructors)

---

## Phase 1: Infrastructure Setup (Automated)

### CloudFormation Stack Deployment

**Main Template**: `cfn/dat409-hybrid-search.yml`

**Nested Stacks**:
1. `cfn/dat409-vpc.yml` - Network infrastructure
2. `cfn/dat409-rds-version.yml` - RDS version helper
3. `cfn/dat409-database.yml` - Aurora PostgreSQL cluster
4. `cfn/dat409-code-editor.yml` - Code Editor EC2 instance

### Bootstrap Script Execution

**Script**: `scripts/bootstrap-code-editor.sh`

**Triggered by**: CloudFormation UserData via SSM Document

**What it does**:
- ✅ Installs Python 3.13, AWS CLI v2, PostgreSQL client
- ✅ Sets up Code Editor with VS Code extensions
- ✅ Configures Nginx reverse proxy
- ✅ Installs Python packages (pandas, boto3, psycopg, pgvector, etc.)
- ✅ Installs uv/uvx for MCP
- ✅ Retrieves database credentials from Secrets Manager
- ✅ Creates `.env` file with all environment variables
- ✅ Creates `.pgpass` for passwordless PostgreSQL access
- ✅ Creates MCP config file for Lab 2
- ✅ Clones workshop repository
- ✅ Sets up bash environment with shortcuts

**What it does NOT do**:
- ❌ Does NOT create database tables
- ❌ Does NOT load product data
- ❌ Does NOT generate embeddings

**Duration**: ~5-7 minutes

**Output**: Code Editor accessible via CloudFront URL

---

## Phase 2: Database Setup (Manual)

### Prerequisites
1. ✅ Phase 1 completed successfully
2. ✅ Code Editor accessible
3. ✅ Aurora cluster available
4. ⚠️ **CRITICAL**: Bedrock Cohere Embed English v3 model enabled in AWS Console

### Enable Bedrock Models (Required)

**Before running setup-database.sh**, instructors must:

1. Open AWS Console → Bedrock → Model access
2. Click "Modify model access"
3. Enable: **Cohere Embed English v3** (required for embeddings)
4. Optional: Enable Amazon Titan Text Embeddings V2 (backup)
5. Wait for "Access granted" status (~30 seconds)

### Database Setup Script

**Script**: `scripts/setup-database.sh`

**How to run**:
```bash
# SSH into Code Editor instance or use SSM Session Manager
cd /workshop
source .env
./scripts/setup-database.sh
```

**What it does**:

#### Lab 1 Setup (Hybrid Search)
- ✅ Tests database connectivity
- ✅ Tests Bedrock Cohere model access
- ✅ Creates `bedrock_integration` schema
- ✅ Creates `product_catalog` table with vector column
- ✅ Loads 21,704 products from CSV
- ✅ Generates embeddings using Cohere (parallel processing, 10 workers)
- ✅ Creates HNSW vector index for similarity search
- ✅ Creates GIN indexes for full-text and trigram search

#### Lab 2 Setup (MCP with RLS)
- ✅ Creates `knowledge_base` table
- ✅ Creates RLS users (customer_user, agent_user, pm_user)
- ✅ Creates RLS policies for persona-based access
- ✅ Inserts sample knowledge base data (FAQs, tickets, analytics)
- ✅ Creates test script for RLS verification

**Duration**: ~6-9 minutes
- Embedding generation: 5-8 minutes (21,704 products)
- Schema/indexes: 1 minute
- RLS setup: 20 seconds

**Output**:
```
📊 LAB 1 - Hybrid Search:
   ✅ Products loaded: 21,704
   ✅ Products with embeddings: 21,704

🔒 LAB 2 - MCP with RLS:
   ✅ Knowledge base entries: 103
   ✅ RLS policies created: 3
```

---

## Deployment Sequence Summary

```
┌─────────────────────────────────────────────────────────────┐
│ 1. CloudFormation Stack Creation (10-15 min)               │
│    - VPC, Subnets, Security Groups                         │
│    - Aurora PostgreSQL cluster                             │
│    - EC2 instance for Code Editor                          │
│    - Secrets Manager for credentials                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. bootstrap-code-editor.sh (5-7 min)                      │
│    - Runs automatically via SSM Document                   │
│    - Sets up Code Editor infrastructure                    │
│    - Configures environment variables                      │
│    - Does NOT load data                                    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Enable Bedrock Models (1 min) - MANUAL                  │
│    - Instructor enables Cohere Embed English v3            │
│    - Required before data loading                          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. setup-database.sh (6-9 min) - MANUAL                    │
│    - Instructor runs from Code Editor                      │
│    - Creates all database tables                           │
│    - Loads 21,704 products with embeddings                 │
│    - Sets up Lab 2 RLS                                     │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Workshop Ready! (Total: 22-32 min)                      │
│    - Participants access Code Editor                       │
│    - Lab 1 notebook ready with data                        │
│    - Lab 2 MCP agent ready with RLS                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Files

### CloudFormation Templates
- `cfn/dat409-hybrid-search.yml` - Main stack (entry point)
- `cfn/dat409-vpc.yml` - Network infrastructure
- `cfn/dat409-database.yml` - Aurora PostgreSQL
- `cfn/dat409-code-editor.yml` - Code Editor setup
- `cfn/dat409-rds-version.yml` - RDS version helper
- `cfn/iam_policy.json` - Workshop Studio IAM policy

### Setup Scripts
- `scripts/bootstrap-code-editor.sh` - Infrastructure setup (automated)
- `scripts/setup-database.sh` - Database and data loading (manual)
- `scripts/setup-database.sh.backup` - Backup of setup script

### Helper Scripts
- `scripts/setup/parallel-fast-loader.py` - Fast data loader (reference)
- `scripts/setup/test_connection.py` - Database connection test

### Configuration Files
- `.gitignore` - Protects sensitive files
- `env_example` - Environment variable template
- `lab1-hybrid-search/requirements.txt` - Lab 1 dependencies
- `lab2-mcp-agent/requirements.txt` - Lab 2 dependencies

---

## Verification Commands

### After Phase 1 (bootstrap-code-editor.sh)
```bash
# Check services
systemctl status code-editor@participant
systemctl status nginx

# Check environment
source /workshop/.env
echo $DB_HOST
echo $DB_USER

# Test database connection (should work)
psql -c "SELECT version();"
```

### After Phase 2 (setup-database.sh)
```bash
# Check Lab 1 data
psql -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog;"
psql -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL;"

# Check Lab 2 RLS
psql -c "SELECT COUNT(*) FROM knowledge_base;"
psql -c "SELECT COUNT(*) FROM pg_policies WHERE tablename='knowledge_base';"

# Test RLS personas
/workshop/lab2-mcp-agent/test_personas.sh
```

---

## Troubleshooting

### Issue: bootstrap-code-editor.sh fails
- Check CloudWatch Logs: `/aws/ssm/dat409-hybrid-search-bootstrap`
- Verify EC2 instance has internet access
- Check IAM role has required permissions

### Issue: setup-database.sh fails on Bedrock
- Verify Cohere Embed English v3 is enabled in Bedrock console
- Check IAM role has `bedrock:InvokeModel` permission
- Test: `aws bedrock-runtime list-foundation-models --region us-west-2`

### Issue: Database connection fails
- Verify Aurora cluster is available
- Check security group allows EC2 → Aurora on port 5432
- Verify `.env` file has correct credentials
- Test: `psql -c "SELECT 1;"`

### Issue: Embedding generation is slow
- Expected: 5-8 minutes for 21,704 products
- Uses 10 parallel workers
- Rate: ~50-70 products/second
- If slower, check Bedrock throttling limits

---

## Workshop Studio Configuration

### CloudFormation Parameters
```yaml
WorkshopName: dat409-hybrid-search
GitHubRepo: https://github.com/aws-samples/sample-dat409-hybrid-search-aurora-mcp.git
DBVersion: '17'
DBInstanceClass: db.r8g.2xlarge
CodeEditorInstanceType: t4g.large
CodeEditorVolumeSize: 50
```

### Environment Variables (Passed to bootstrap)
```bash
DB_SECRET_ARN=${SecretArn}
DB_CLUSTER_ENDPOINT=${ClusterEndpoint}
DB_CLUSTER_ARN=${ClusterArn}
DB_NAME=workshop_db
AWS_REGION=${AWS::Region}
```

### IAM Permissions Required
- SecretsManager: GetSecretValue
- Bedrock: InvokeModel
- RDS: DescribeDBClusters
- RDS-Data: ExecuteStatement (for MCP)
- S3: GetObject, PutObject
- CloudWatch: PutMetricData, CreateLogGroup

---

## Success Criteria

### Infrastructure (Phase 1)
- ✅ Code Editor accessible via CloudFront
- ✅ Nginx and Code Editor services running
- ✅ Python 3.13 and all packages installed
- ✅ Database credentials configured in `.env`
- ✅ Workshop repository cloned

### Database (Phase 2)
- ✅ 21,704 products loaded
- ✅ All products have embeddings
- ✅ HNSW, GIN indexes created
- ✅ Lab 2 RLS users and policies created
- ✅ Knowledge base populated

### Workshop Delivery
- ✅ Lab 1 notebook runs successfully
- ✅ Hybrid search queries work (vector + text + trigram)
- ✅ Lab 2 MCP agent connects to database
- ✅ RLS policies show different results per persona
- ✅ All dependencies pre-installed
- ✅ Total setup time: 22-32 minutes

---

## Notes

- **Two-phase approach** separates infrastructure from data loading
- **Bedrock enablement** must be done manually before data loading
- **setup-database.sh** is idempotent - safe to run multiple times
- **Parallel processing** uses 10 workers for fast embedding generation
- **RLS testing** script provided for Lab 2 verification
- **CloudWatch logs** available for troubleshooting
- **Backup script** kept for reference (setup-database.sh.backup)
