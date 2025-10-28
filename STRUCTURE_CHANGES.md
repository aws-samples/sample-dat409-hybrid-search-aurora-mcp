# Repository Structure Changes

## Summary
Flattened the repository structure by moving `data/` and `notebooks/` from `workshop/` subdirectory to the top level, eliminating the confusing nested `workshop/workshop/` pattern.

## Changes Made

### Directory Structure

**Before:**
```
workshop/
├── data/
│   └── amazon-products-sample.csv
├── notebooks/
│   ├── dat409-hybrid-search-TODO.ipynb
│   └── dat409-hybrid-search-SOLUTIONS.ipynb
└── requirements.txt
```

**After:**
```
data/
├── amazon-products-sample.csv
└── generate_embeddings.py
notebooks/
├── dat409-hybrid-search-TODO.ipynb
└── dat409-hybrid-search-SOLUTIONS.ipynb
requirements.txt
```

### Files Updated

1. **README.md**
   - Updated repository structure diagram
   - Changed all path references from `/workshop/notebooks/` to `/notebooks/`
   - Updated Quick Start instructions

2. **scripts/bootstrap-code-editor-unified.sh**
   - Simplified .env file creation (now creates only 2 files instead of 3)
   - Removed `/workshop/workshop/.env` reference
   - Updated welcome message terminal banner

3. **notebooks/*.ipynb**
   - Updated .env path to `/workshop/notebooks/.env` (clearer location)

## Benefits

- ✅ Clearer structure - no more `workshop/workshop/` confusion
- ✅ Simpler paths - `/notebooks/` instead of `/workshop/notebooks/`
- ✅ Easier navigation for participants
- ✅ Consistent with typical repository layouts

## Runtime Environment

The workshop runs in a Code Editor environment where:
- Repository is cloned to `/workshop/`
- Notebooks are at `/workshop/notebooks/`
- Data is at `/workshop/data/`
- .env files:
  - `/workshop/.env` (master copy)
  - `/workshop/notebooks/.env` (for Jupyter notebooks)
  - `/workshop/demo-app/.env` (for Streamlit app)

## .env File Strategy

Bootstrap script creates three .env files:
1. **Master**: `/workshop/.env` - Source of truth
2. **Notebooks**: `/workshop/notebooks/.env` - Used by Jupyter notebooks
3. **Demo App**: `/workshop/demo-app/.env` - Used by Streamlit

This makes it clear which .env each component uses.
