# Comprehensive DAT409 Setup Script

## Overview

The `comprehensive_dat409_setup.sh` script combines **all setup steps** into a single automated process:

1. ✅ Infrastructure setup (Code Editor, Python, dependencies)
2. ✅ Database credential retrieval
3. ✅ Wait for Aurora cluster availability
4. ✅ Wait for Bedrock model access
5. ✅ Lab 1 setup (21,704 products with embeddings)
6. ✅ Lab 2 setup (RLS and knowledge base)

## Key Features

### Intelligent Waiting
- **Database Availability**: Waits up to 20 minutes for Aurora cluster
- **Bedrock Access**: Waits up to 10 minutes for model enablement
- Checks every 30 seconds with progress updates

### Automatic Dependency Handling
- Installs all required packages
- Configures Code Editor
- Retrieves credentials from Secrets Manager
- Creates .env and .pgpass files

### Complete Database Setup
- Creates schemas and tables
- Loads 21,704 products
- Generates embeddings (5-8 minutes)
- Sets up RLS with proper role grants
- Inserts 17 knowledge base records

## CloudFormation Integration

### UserData Configuration

```yaml
Resources:
  WorkshopInstance:
    Type: AWS::EC2::Instance
    Properties:
      UserData:
        Fn::Base64: !Sub |
          #!/bin/bash
          export DB_SECRET_ARN=${DBSecret}
          export DB_CLUSTER_ENDPOINT=${DBCluster.Endpoint.Address}
          export DB_CLUSTER_ARN=arn:aws:rds:${AWS::Region}:${AWS::AccountId}:cluster:${DBCluster}
          export DB_NAME=workshop_db
          export AWS_REGION=${AWS::Region}
          
          # Download and run comprehensive setup
          curl -fsSL https://raw.githubusercontent.com/[YOUR-REPO]/scripts/comprehensive_dat409_setup.sh \
            | bash -s -- ${CodeEditorPassword}
```

### Required CloudFormation Outputs

The script expects these environment variables from CloudFormation:

- `DB_SECRET_ARN` - Secrets Manager ARN for database credentials
- `DB_CLUSTER_ENDPOINT` - Aurora cluster endpoint
- `DB_CLUSTER_ARN` - Aurora cluster ARN (for MCP)
- `DB_NAME` - Database name (default: workshop_db)
- `AWS_REGION` - AWS region

## Timeline

### Total Setup Time: ~15-25 minutes

| Phase | Duration | Description |
|-------|----------|-------------|
| Phase 1 | 3-5 min | Infrastructure (Code Editor, Python, packages) |
| Phase 2 | 10 sec | Retrieve database credentials |
| Phase 3 | 0-10 min | Wait for Aurora cluster availability |
| Phase 4 | 0-10 min | Wait for Bedrock model access |
| Phase 5 | 5-8 min | Load products and generate embeddings |
| Phase 6 | 30 sec | Setup RLS and knowledge base |

**Note**: Phases 3 and 4 run in parallel with CloudFormation resource creation, so actual wait time depends on when the script starts relative to Aurora cluster creation.

## What Gets Installed

### System Packages
- Python 3.13
- PostgreSQL 16 client
- AWS CLI v2
- Nginx
- gcc, make, git, jq, curl, wget

### Python Packages
- pandas, numpy, boto3
- psycopg, pgvector
- streamlit, plotly
- jupyterlab, jupyter
- tqdm, pandarallel
- python-dotenv
- uv (for MCP)

### Services
- Code Editor (systemd service)
- Nginx (reverse proxy)

## Database Schema Created

### Lab 1: bedrock_integration.product_catalog
- 21,704 products
- 1024-dimensional embeddings
- HNSW, GIN (FTS), GIN (trigram) indexes

### Lab 2: public.knowledge_base
- 17 sample records
- RLS policies for 3 personas
- Role membership grants (CRITICAL FIX)

## Verification

After setup completes, verify:

```bash
# Check product count
psql -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog;"
# Expected: 21704

# Check embeddings
psql -c "SELECT COUNT(*) FROM bedrock_integration.product_catalog WHERE embedding IS NOT NULL;"
# Expected: ~21700 (99%+)

# Check knowledge base
psql -c "SELECT COUNT(*) FROM knowledge_base;"
# Expected: 17

# Check RLS role membership
psql -c "SELECT u.rolname, r.rolname FROM pg_roles u 
JOIN pg_auth_members m ON u.oid = m.member 
JOIN pg_roles r ON r.oid = m.roleid 
WHERE u.rolname IN ('customer_user', 'agent_user', 'pm_user');"
# Expected: 3 rows

# Test RLS access
psql -U customer_user -c "SELECT COUNT(*) FROM knowledge_base;"
# Expected: 6
```

## Advantages Over Separate Scripts

### Single Script Approach
✅ One command to rule them all  
✅ Automatic dependency handling  
✅ Intelligent waiting for resources  
✅ No manual intervention needed  
✅ Consistent timing and ordering  
✅ Better error handling  
✅ Complete logging  

### Separate Scripts Approach
❌ Requires manual timing  
❌ Need to check when Aurora is ready  
❌ Need to check when Bedrock is enabled  
❌ Multiple commands to run  
❌ Easy to miss steps  
❌ Harder to troubleshoot  

## Error Handling

The script will:
- Exit immediately on any error (`set -euo pipefail`)
- Wait up to 20 minutes for database
- Wait up to 10 minutes for Bedrock
- Continue with warnings if Bedrock not available
- Log all steps with timestamps
- Provide clear error messages

## Logs

All output is logged to:
- `/var/log/cloud-init-output.log` (CloudFormation UserData)
- Console output (if run manually)

Check logs:
```bash
# View full log
sudo tail -f /var/log/cloud-init-output.log

# Check Code Editor service
sudo journalctl -u code-editor@participant -f

# Check Nginx
sudo systemctl status nginx
```

## Manual Execution

If you need to run manually:

```bash
# Set environment variables
export DB_SECRET_ARN="arn:aws:secretsmanager:..."
export DB_CLUSTER_ARN="arn:aws:rds:..."
export DB_CLUSTER_ENDPOINT="cluster.region.rds.amazonaws.com"
export AWS_REGION="us-west-2"

# Run script
sudo bash comprehensive_dat409_setup.sh myPassword123
```

## Troubleshooting

### Script Hangs at Phase 3 (Database Wait)
**Cause**: Aurora cluster not yet available  
**Solution**: Wait up to 20 minutes, or check CloudFormation stack status

### Script Hangs at Phase 4 (Bedrock Wait)
**Cause**: Bedrock model not enabled  
**Solution**: Enable Cohere Embed English v3 in AWS Console

### Embedding Generation Fails
**Cause**: Bedrock model not accessible  
**Solution**: Verify model is enabled and IAM permissions are correct

### RLS Not Working
**Cause**: Role membership not granted (should not happen with this script)  
**Solution**: Script includes the fix, but verify with:
```sql
SELECT * FROM pg_auth_members WHERE roleid IN (
    SELECT oid FROM pg_roles WHERE rolname LIKE '%_role'
);
```

## Comparison with Original Scripts

| Feature | Comprehensive | Bootstrap + Setup-DB |
|---------|--------------|---------------------|
| Single command | ✅ Yes | ❌ No (2 commands) |
| Auto-wait for Aurora | ✅ Yes | ❌ Manual check |
| Auto-wait for Bedrock | ✅ Yes | ❌ Manual check |
| CloudFormation ready | ✅ Yes | ⚠️ Partial |
| Error handling | ✅ Complete | ⚠️ Partial |
| Progress updates | ✅ Detailed | ⚠️ Basic |
| Total time | 15-25 min | 15-25 min |

## When to Use Which Script

### Use Comprehensive Script When:
- ✅ Deploying via CloudFormation UserData
- ✅ Want fully automated setup
- ✅ Running in AWS Workshop Studio
- ✅ Need hands-off deployment

### Use Separate Scripts When:
- ✅ Testing individual components
- ✅ Debugging specific issues
- ✅ Need to re-run only database setup
- ✅ Developing/modifying setup process

## Files Created

After successful execution:

```
/workshop/
├── .env                          # Environment variables
├── lab1-hybrid-search/
│   └── data/
│       └── amazon-products.csv   # Product data
├── lab2-mcp-agent/
│   ├── streamlit_app.py
│   ├── requirements.txt
│   └── mcp_config.json           # MCP configuration
└── scripts/
    └── setup-rls-knowledge-base.sql

/home/participant/
├── .pgpass                       # PostgreSQL credentials
├── .bashrc                       # Updated with aliases
└── .local/bin/
    └── code-editor-server        # Code Editor binary
```

## Security Notes

- ✅ Credentials retrieved from Secrets Manager
- ✅ .env file has 600 permissions
- ✅ .pgpass file has 600 permissions
- ✅ No hardcoded passwords
- ✅ RLS policies enforce data isolation

## Next Steps After Setup

1. Access Code Editor via CloudFront URL
2. Verify database connection: `psql -c "SELECT 1;"`
3. Test RLS: Run verification queries
4. Launch Streamlit: `cd /workshop/lab2-mcp-agent && streamlit run streamlit_app.py`
5. Test all features in the app

## Support

For issues:
1. Check `/var/log/cloud-init-output.log`
2. Verify CloudFormation stack completed
3. Check Aurora cluster status
4. Verify Bedrock model access
5. Review RLS_DEPLOYMENT_FIX.md for RLS issues

## Updates Required Before Use

1. **Line 467**: Update GitHub URL for RLS script
   ```bash
   curl -fsSL "https://raw.githubusercontent.com/[YOUR-REPO]/scripts/setup-rls-knowledge-base.sql"
   ```

2. **Line 363**: Update GitHub URL for product data (if different)
   ```bash
   curl -fsSL "https://raw.githubusercontent.com/[YOUR-REPO]/data/amazon-products.csv"
   ```

3. **CloudFormation UserData**: Update script URL
   ```bash
   curl -fsSL https://raw.githubusercontent.com/[YOUR-REPO]/scripts/comprehensive_dat409_setup.sh
   ```

---

**Ready for Production**: ✅ YES (after updating GitHub URLs)

**Tested**: ⚠️ Requires testing in fresh AWS Workshop Studio environment

**Recommended**: ✅ YES for CloudFormation deployments
