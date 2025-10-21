#!/usr/bin/env python3
"""
Script to update Jupyter notebook kernel metadata to ensure Python 3.13 is selected.
This script modifies the notebook's metadata to point to the correct Python 3.13 kernel.
"""

import json
import sys
from pathlib import Path

def update_notebook_kernel(notebook_path):
    """Update notebook kernel metadata to use Python 3.13."""
    
    # Read notebook
    with open(notebook_path, 'r', encoding='utf-8') as f:
        notebook = json.load(f)
    
    # Update kernel metadata
    notebook['metadata']['kernelspec'] = {
        "display_name": "Python 3.13.3",
        "language": "python",
        "name": "python3"
    }
    
    notebook['metadata']['language_info'] = {
        "codemirror_mode": {
            "name": "ipython",
            "version": 3
        },
        "file_extension": ".py",
        "mimetype": "text/x-python",
        "name": "python",
        "nbconvert_exporter": "python",
        "pygments_lexer": "ipython3",
        "version": "3.13.3"  # This ensures VSCode recognizes it as Python 3.13
    }
    
    # Write back
    with open(notebook_path, 'w', encoding='utf-8') as f:
        json.dump(notebook, f, indent=1, ensure_ascii=False)
    
    print(f"✅ Updated kernel metadata in {notebook_path}")
    print(f"   Display name: Python 3.13")
    print(f"   Kernel name: python3")
    print(f"   Version: 3.13.3")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 fix_notebook_kernel.py <notebook_path>")
        sys.exit(1)
    
    notebook_path = Path(sys.argv[1])
    if not notebook_path.exists():
        print(f"❌ Notebook not found: {notebook_path}")
        sys.exit(1)
    
    update_notebook_kernel(notebook_path)
