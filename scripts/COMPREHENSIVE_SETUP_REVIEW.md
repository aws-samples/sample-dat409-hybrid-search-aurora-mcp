# Comprehensive Setup Script Review for CFN Deployment

## Status: ❌ NOT READY - REQUIRES COMPLETION

## Critical Issues

### 1. **Script is Incomplete** 🚨
- **Current**: Cuts off at line 267 during Phase 4
- **Missing**: 
  - Phase 4 completion (Bedrock model wait)
  - Phase 5 (Lab 1: 21,704 products + embeddings)
  - Phase 6 (Lab 2: RLS + knowledge base)
  - Final verification
- **Action**: Complete the remaining ~400-500 lines

### 2. **AWS CLI Installation** ⚠️
```bash
# Line 52-60: Incomplete architecture detection
if [ "$(uname -m)" = "aarch64" ]; then
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
else
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
fi
unzip -q awscliv2.zip && ./aws/install --update && rm -rf awscliv2.zip aws/
```
**Status**: ✅ Actually looks good, just verify it works

### 3. **Environment Variables** ⚠️
```bash
# Missing MCP-compatible aliases
DATABASE_CLUSTER_ARN='$DB_CLUSTER_ARN'
DATABASE_SECRET_ARN='$DB_SECRET_ARN'
```
**Action**: Add these to .env file creation (around line 180)

## Missing Phases

### Phase 4: Bedrock Model Access (INCOMPLETE)
**Needs**:
```bash
log "PHASE 4: Waiting for Bedrock Model Access"

MAX_BEDROCK_WAIT=20  # 20 * 30 seconds = 10 minutes
BEDROCK_WAIT_COUNT=0

while [ $BEDROCK_WAIT_COUNT -lt $MAX_BEDROCK_WAIT ]; do
    if aws bedrock-runtime invoke-model \
        --model-id cohere.embed-english-v3 \
        --body '{"texts":["test"],"input_type":"search_document","embedding_types":["float"]}' \
        --region "$AWS_REGION" \
        /tmp/bedrock_test.json 2>/dev/null; then
        log "✅ Bedrock Cohere model accessible"
        rm -f /tmp/bedrock_test.json
        break
    fi
    
    BEDROCK_WAIT_COUNT=$((BEDROCK_WAIT_COUNT + 1))
    if [ $BEDROCK_WAIT_COUNT -eq $MAX_BEDROCK_WAIT ]; then
        warn "Bedrock model not accessible after 10 minutes - continuing anyway"
        break
    fi
    
    info "Waiting for Bedrock model access... (attempt $BEDROCK_WAIT_COUNT/$MAX_BEDROCK_WAIT)"
    sleep 30
done

log "✅ Phase 4 Complete: Bedrock Check Done"
```

### Phase 5: Lab 1 Setup (MISSING)
**Needs**: 
- Create Python script to load 21,704 products
- Generate embeddings using Cohere
- Use parallel processing (pandarallel)
- Create HNSW, GIN (FTS), GIN (trigram) indexes
- **Reference**: Use logic from `setup-database.sh` lines 200-600

### Phase 6: Lab 2 Setup (MISSING)
**Needs**:
- Create knowledge_base table
- Create RLS users: customer_user, agent_user, pm_user
- **CRITICAL FIX**: Use `GRANT role TO user` not `IN ROLE`
- Create RLS policies
- Insert 50 hardcoded products
- **Reference**: Use logic from `setup-database.sh` lines 700-900

## Specific Code Fixes Needed

### Fix 1: Complete .env File (Line ~180)
```bash
cat > "$HOME_FOLDER/.env" << ENV_EOF
DB_HOST='$DB_HOST'
DB_PORT='$DB_PORT'
DB_NAME='$DB_NAME'
DB_USER='$DB_USER'
DB_PASSWORD='$DB_PASSWORD'
DB_SECRET_ARN='$DB_SECRET_ARN'
DB_CLUSTER_ARN='$DB_CLUSTER_ARN'
DATABASE_CLUSTER_ARN='$DB_CLUSTER_ARN'  # ADD THIS
DATABASE_SECRET_ARN='$DB_SECRET_ARN'    # ADD THIS
DATABASE_URL='postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME'
PGHOST='$DB_HOST'
PGPORT='$DB_PORT'
PGUSER='$DB_USER'
PGPASSWORD='$DB_PASSWORD'
PGDATABASE='$DB_NAME'
AWS_REGION='$AWS_REGION'
ENV_EOF
```

### Fix 2: RLS User Creation (Phase 6)
```sql
-- WRONG (from setup_knowledge_base.sh):
CREATE USER customer_user WITH PASSWORD 'customer123' IN ROLE customer_role;

-- CORRECT:
CREATE ROLE customer_role;
CREATE USER customer_user WITH PASSWORD 'customer123';
GRANT customer_role TO customer_user;
```

### Fix 3: Product IDs for Lab 2 (Phase 6)
Use these 50 product IDs:
```sql
'B07X6C9RMF', 'B08N5NQ869', 'B086DL32R3', 'B08SGC46M9', 'B07DGR98VQ',
'B08R59YH7W', 'B08CKHPP52', 'B08M125RNW', 'B0849J7W5X', 'B08F6GPQQ7',
'B08FD54PN9', 'B07QKXM2D3', 'B01CW4CEMS', 'B07X27JNQ5', 'B07ZB2RNTW',
'B07YB8HZ8T', 'B08ZXJJTYJ', 'B0829KDY9X', 'B093DDPDXL', 'B07PM2NBGT',
'B07TTH5TMW', 'B07B7NXV4R', 'B011MYEMKQ', 'B07YP9VK7Q', 'B07ZB2QF2V',
'B0CFR1JB15', 'B00HT6E2NY', 'B0CBJRXFVJ', 'B00PBGQ0SY', 'B0168MB1RO',
'B0C8JGHXXB', 'B0C8JDM69N', 'B0C2PXPWMR', 'B0C8JK6TSH', 'B0C3RKQPHR',
'B07GG3XXNX', 'B0899GLP7R', 'B07PJ67CKC', 'B088C4NHRS', 'B07WHMQNPC',
'B07YMV9VMT', 'B07ZPMCW64', 'B0856W45VL', 'B07W1HKYQK', 'B07R3WY95C',
'B01CW49AGG', 'B07X81M2D2', 'B07X2M8KTR', 'B08JCS7QKL', 'B083GKZWVX'
```

## CloudFormation Integration Checklist

### ✅ Ready
- [x] Accepts password as first argument
- [x] Reads environment variables from CFN
- [x] Retrieves credentials from Secrets Manager
- [x] Creates Code Editor service
- [x] Installs Python 3.13 and packages
- [x] Waits for Aurora availability

### ❌ Not Ready
- [ ] Complete Phase 4 (Bedrock wait)
- [ ] Add Phase 5 (Lab 1 data loading)
- [ ] Add Phase 6 (Lab 2 RLS setup)
- [ ] Add final verification
- [ ] Test end-to-end in fresh environment

## Expected CloudFormation UserData

```yaml
UserData:
  Fn::Base64: !Sub |
    #!/bin/bash
    export DB_SECRET_ARN=${DBSecret}
    export DB_CLUSTER_ENDPOINT=${DBCluster.Endpoint.Address}
    export DB_CLUSTER_ARN=arn:aws:rds:${AWS::Region}:${AWS::AccountId}:cluster:${DBCluster}
    export DB_NAME=workshop_db
    export AWS_REGION=${AWS::Region}
    
    curl -fsSL https://raw.githubusercontent.com/aws-samples/sample-dat409-hybrid-search-workshop-prod/main/scripts/comprehensive_dat409_setup.sh \
      | bash -s -- ${CodeEditorPassword}
```

## Timeline Estimate

| Phase | Duration | Status |
|-------|----------|--------|
| Phase 1: Infrastructure | 3-5 min | ✅ Complete |
| Phase 2: Credentials | 10 sec | ✅ Complete |
| Phase 3: Aurora Wait | 0-10 min | ✅ Complete |
| Phase 4: Bedrock Wait | 0-10 min | ⚠️ Incomplete |
| Phase 5: Lab 1 Data | 5-8 min | ❌ Missing |
| Phase 6: Lab 2 RLS | 30 sec | ❌ Missing |
| **Total** | **15-25 min** | **40% Complete** |

## Comparison with Separate Scripts

| Feature | Comprehensive | Bootstrap + Setup-DB |
|---------|--------------|---------------------|
| Lines of code | ~267/700 (38%) | 100% complete |
| Single command | ✅ Yes | ❌ No |
| Auto-wait Aurora | ✅ Yes | ❌ No |
| Auto-wait Bedrock | ⚠️ Partial | ❌ No |
| Data loading | ❌ Missing | ✅ Yes |
| RLS setup | ❌ Missing | ✅ Yes |
| **Production Ready** | ❌ NO | ✅ YES |

## Recommendation

### Option 1: Complete the Comprehensive Script ⭐ RECOMMENDED
**Pros**:
- Single command deployment
- Better for CloudFormation
- Automatic waiting logic
- More robust error handling

**Cons**:
- Requires ~400 more lines of code
- Needs testing
- More complex to debug

**Effort**: 2-3 hours to complete + 1 hour testing

### Option 2: Use Separate Scripts (Current State)
**Pros**:
- Already working and tested
- Easier to debug individual components
- Can re-run specific parts

**Cons**:
- Requires manual timing
- Two commands instead of one
- Less elegant for CFN UserData

**Effort**: 30 minutes to adapt for CFN

## Next Steps

### If Completing Comprehensive Script:
1. Copy Phase 4 completion from this review
2. Copy Phase 5 from `setup-database.sh` lines 200-600
3. Copy Phase 6 from `setup-database.sh` lines 700-900
4. Add final verification section
5. Test in fresh AL2023 environment
6. Update GitHub URLs

### If Using Separate Scripts:
1. Keep `bootstrap-code-editor.sh` as-is
2. Modify `setup-database.sh` to be idempotent
3. Call both from CFN UserData sequentially
4. Add sleep/wait logic between them
5. Test in fresh AL2023 environment

## Files to Update

1. `comprehensive_dat409_setup.sh` - Complete remaining phases
2. `setup_knowledge_base.sh` - Remove hardcoded credentials
3. CloudFormation template - Add proper UserData
4. README.md - Update deployment instructions

## Security Checklist

- [x] No hardcoded passwords in comprehensive script
- [ ] Remove hardcoded credentials from setup_knowledge_base.sh
- [x] Credentials from Secrets Manager
- [x] .env file has 600 permissions
- [x] .pgpass file has 600 permissions
- [x] RLS policies enforce isolation

## Testing Checklist

- [ ] Fresh AL2023 instance
- [ ] Aurora cluster creation timing
- [ ] Bedrock model access
- [ ] All 21,704 products loaded
- [ ] All embeddings generated
- [ ] RLS working for all 3 personas
- [ ] Code Editor accessible
- [ ] Jupyter notebooks work
- [ ] MCP agent works

---

**VERDICT**: ❌ **NOT READY FOR CFN DEPLOYMENT**

**BLOCKING ISSUES**: 
1. Script incomplete (60% missing)
2. No data loading logic
3. No RLS setup logic

**RECOMMENDATION**: Either complete the comprehensive script OR use the proven separate scripts approach with minor CFN adaptations.
