#!/usr/bin/env python3
"""
Update paths in the Jupyter notebook after migration
"""

import json
import sys
from pathlib import Path

def update_notebook_paths(notebook_path):
    """Update file paths in the notebook after migration"""
    
    print(f"📝 Updating paths in {notebook_path}")
    
    # Read notebook
    with open(notebook_path, 'r') as f:
        notebook = json.load(f)
    
    # Path replacements
    replacements = {
        '../data/incident_logs.json': '../data/incident_logs.json',  # Already correct
        '../../data/incident_logs.json': '../data/incident_logs.json',  # Fix if needed
        '/workshop/data/incident_logs.json': '/workshop/lab1-hybrid-search/data/incident_logs.json',
        '../.env': '../../.env',  # Now needs to go up two levels
        '/workshop/.env': '/workshop/.env',  # Keep absolute path as is
    }
    
    # Update cells
    modified = False
    for cell in notebook.get('cells', []):
        if cell.get('cell_type') == 'code':
            source = cell.get('source', [])
            if isinstance(source, str):
                source = [source]
            
            new_source = []
            for line in source:
                original_line = line
                for old_path, new_path in replacements.items():
                    if old_path in line:
                        line = line.replace(old_path, new_path)
                        if line != original_line:
                            print(f"  ✓ Updated: {old_path} → {new_path}")
                            modified = True
                new_source.append(line)
            
            cell['source'] = new_source
    
    # Save if modified
    if modified:
        with open(notebook_path, 'w') as f:
            json.dump(notebook, f, indent=1)
        print(f"✅ Notebook paths updated")
    else:
        print(f"ℹ️  No path updates needed")

if __name__ == "__main__":
    # Update Lab 1 notebook
    lab1_notebook = Path("lab1-hybrid-search/notebook/dat409_notebook.ipynb")
    
    if lab1_notebook.exists():
        update_notebook_paths(lab1_notebook)
    else:
        print(f"❌ Notebook not found at {lab1_notebook}")
        print("   Run migrate_workshop_structure.sh first")