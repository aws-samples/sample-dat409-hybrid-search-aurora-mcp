#!/usr/bin/env python3
"""
Collapse specific cells in Jupyter notebooks by adding metadata.
This ensures cells remain collapsed when provisioned in Workshop Studio.
"""

import json
import sys
from pathlib import Path

def collapse_cells_in_notebook(notebook_path: Path, cell_indices: list[int]) -> None:
    """Add collapse metadata to specified cells."""
    with open(notebook_path, 'r') as f:
        notebook = json.load(f)
    
    for idx in cell_indices:
        if idx < len(notebook['cells']):
            cell = notebook['cells'][idx]
            # Only collapse code cells, not markdown
            if cell['cell_type'] != 'code':
                print(f"⚠️  Skipped cell {idx} (not a code cell)")
                continue
            
            if 'metadata' not in cell:
                cell['metadata'] = {}
            
            # Add both metadata fields for compatibility
            if 'jupyter' not in cell['metadata']:
                cell['metadata']['jupyter'] = {}
            cell['metadata']['jupyter']['source_hidden'] = True
            cell['metadata']['collapsed'] = True
            
            print(f"✅ Collapsed cell {idx} in {notebook_path.name}")
    
    with open(notebook_path, 'w') as f:
        json.dump(notebook, f, indent=1)

if __name__ == "__main__":
    notebooks_dir = Path(__file__).parent.parent / "notebooks"
    
    # TODO notebook - only cells with COLLAPSED markers
    todo_notebook = notebooks_dir / "01-dat409-hybrid-search-TODO.ipynb"
    todo_collapse_indices = [4, 6, 25, 28]  # Only cells with 📦 COLLAPSED CELL marker
    
    # SOLUTIONS notebook - only cells with COLLAPSED markers
    solutions_notebook = notebooks_dir / "02-dat409-hybrid-search-SOLUTIONS.ipynb"
    solutions_collapse_indices = []  # No cells have COLLAPSED markers
    
    print("🔧 Collapsing cells in notebooks...\n")
    
    if todo_notebook.exists():
        collapse_cells_in_notebook(todo_notebook, todo_collapse_indices)
    else:
        print(f"⚠️  {todo_notebook} not found")
    
    if solutions_notebook.exists():
        collapse_cells_in_notebook(solutions_notebook, solutions_collapse_indices)
    else:
        print(f"⚠️  {solutions_notebook} not found")
    
    print("\n✅ Done! Cells will remain collapsed in Workshop Studio deployments.")
