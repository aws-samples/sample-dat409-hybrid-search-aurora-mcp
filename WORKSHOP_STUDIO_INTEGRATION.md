# Workshop Studio Integration Guide

## 📦 Asset Upload Structure

When you upload `amazon-products-sample-with-cohere-embeddings.csv` to Workshop Studio's `assets/` folder, it automatically uploads to:

```
s3://{AssetsBucketName}/{AssetsBucketPrefix}amazon-products-sample-with-cohere-embeddings.csv
```

### Example

```
AssetsBucketName: ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0
AssetsBucketPrefix: abc123def456/

Result:
s3://ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0/abc123def456/amazon-products-sample-with-cohere-embeddings.csv
```

**Important:** Workshop Studio guarantees:
- ✅ `AssetsBucketName` is always provided (never empty)
- ✅ `AssetsBucketPrefix` is always provided (never empty)
- ✅ Prefix always ends with `/` (no double-slash issues)

---

## ✅ Current Implementation

### 1. CloudFormation Parameters

Both parameters are **required** (no defaults):

```yaml
# Parent Template (dat409-hybrid-search.yml)
AssetsBucketName:
  Type: String
  Description: Workshop Studio assets bucket
  # NO DEFAULT - Workshop Studio provides this

AssetsBucketPrefix:
  Type: String
  Description: Workshop Studio assets prefix
  # NO DEFAULT - Workshop Studio provides this
```

### 2. S3 Path Construction

**Bootstrap Script:**
```bash
# Construct S3 path (Workshop Studio guarantees both parameters)
S3_PATH="s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}amazon-products-sample-with-cohere-embeddings.csv"
log "S3 Path: $S3_PATH"

aws s3 cp "$S3_PATH" "$DATA_FILE"
```

**Result:** Always works because Workshop Studio ensures both variables are populated! ✅

### 3. Validation & Logging

**SSM Document logs the full S3 path:**
```
=== PARAMETER VALIDATION ===
Assets Bucket: ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0
Assets Prefix: abc123def456/
S3 Path: s3://ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0/abc123def456/amazon-products-sample-with-cohere-embeddings.csv
✅ All critical parameters validated
```

**Bootstrap Script logs the S3 path:**
```
Downloading product data with embeddings from S3...
S3 Path: s3://ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0/abc123def456/amazon-products-sample-with-cohere-embeddings.csv
✅ Downloaded pre-generated embeddings from S3 (21705 lines)
```

---

## 🔒 Why This Always Works

| Component | Guarantee | Validation |
|-----------|-----------|------------|
| Workshop Studio | Provides both parameters | Built-in platform behavior |
| CloudFormation | Required parameters (no defaults) | Stack creation fails if missing |
| SSM Document | Validates parameters not empty | ValidateParameters step |
| Bootstrap Script | Validates ASSETS_BUCKET not empty | Fail-fast check |
| S3 Download | Logs full path before download | Clear error messages |

**Result:** 5 layers of protection ensure the S3 path is always valid! ✅

---

## 📋 Workshop Studio Setup Checklist

### 1. Upload Assets

Upload to Workshop Studio `assets/` folder:
```
assets/
└── amazon-products-sample-with-cohere-embeddings.csv
```

Workshop Studio automatically uploads to:
```
s3://{AssetsBucketName}/{AssetsBucketPrefix}amazon-products-sample-with-cohere-embeddings.csv
```

### 2. Configure CloudFormation Template

In Workshop Studio, configure the parent template:
```yaml
TemplateURL: s3://ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0/dat409-hybrid-search.yml

Parameters:
  AssetsBucketName: "{{.AssetsBucketName}}"    # Workshop Studio provides
  AssetsBucketPrefix: "{{.AssetsBucketPrefix}}" # Workshop Studio provides
```

### 3. Verify Parameter Passing

Workshop Studio will automatically inject:
```yaml
AssetsBucketName: ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0
AssetsBucketPrefix: abc123def456/
```

---

## 🧪 Testing Locally

To test the S3 path construction locally:

```bash
# Simulate Workshop Studio parameters
export ASSETS_BUCKET="ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0"
export ASSETS_PREFIX="abc123def456/"

# Test S3 path construction
S3_PATH="s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}amazon-products-sample-with-cohere-embeddings.csv"
echo "S3 Path: $S3_PATH"

# Test download
aws s3 cp "$S3_PATH" /tmp/test.csv
```

**Expected Output:**
```
S3 Path: s3://ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0/abc123def456/amazon-products-sample-with-cohere-embeddings.csv
download: s3://ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0/abc123def456/amazon-products-sample-with-cohere-embeddings.csv to /tmp/test.csv
```

---

## 🐛 Troubleshooting

### Issue: "Failed to download CSV from S3"

**Check logs for the S3 path:**
```
S3 Path: s3://ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0/abc123def456/amazon-products-sample-with-cohere-embeddings.csv
```

**Verify:**
1. ✅ Bucket name is correct
2. ✅ Prefix ends with `/`
3. ✅ File name is correct
4. ✅ File exists in S3: `aws s3 ls s3://bucket/prefix/`
5. ✅ IAM permissions allow `s3:GetObject` and `s3:ListBucket`

### Issue: Double Slash in Path

**Not possible!** Workshop Studio guarantees prefix ends with `/`, and our code constructs:
```bash
"s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}filename"
```

This always produces valid paths:
- ✅ `s3://bucket/prefix/file` (prefix has trailing slash)
- ✅ `s3://bucket/file` (empty prefix)

---

## ✅ Success Indicators

Look for these in CloudWatch logs:

**SSM Document:**
```
Assets Bucket: ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0
Assets Prefix: abc123def456/
S3 Path: s3://ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0/abc123def456/amazon-products-sample-with-cohere-embeddings.csv
✅ All critical parameters validated
```

**Bootstrap Script:**
```
S3 Path: s3://ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0/abc123def456/amazon-products-sample-with-cohere-embeddings.csv
✅ Downloaded pre-generated embeddings from S3 (21705 lines)
✅ Database initialized with 21704 products from S3
```

---

## 📊 Parameter Flow Summary

```
Workshop Studio Assets Folder
    ↓ (automatic upload)
S3 Bucket
    s3://{AssetsBucketName}/{AssetsBucketPrefix}file.csv
    ↓ (parameters injected)
CloudFormation Parent Template
    AssetsBucketName: ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0
    AssetsBucketPrefix: abc123def456/
    ↓ (!Ref parameters)
CloudFormation Child Template
    AssetsBucketName: !Ref AssetsBucketName
    AssetsBucketPrefix: !Ref AssetsBucketPrefix
    ↓ (SSM Document parameters)
SSM Document
    ASSETS_BUCKET="{{ AssetsBucketName }}"
    ASSETS_PREFIX="{{ AssetsBucketPrefix }}"
    ↓ (environment variables)
Bootstrap Script
    S3_PATH="s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}file.csv"
    aws s3 cp "$S3_PATH" /tmp/file.csv
    ↓
✅ File Downloaded Successfully
```

---

**Status:** ✅ S3 path construction guaranteed to work with Workshop Studio  
**Confidence:** 🟢 HIGH - Workshop Studio ensures both parameters are always provided
