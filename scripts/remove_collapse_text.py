#!/usr/bin/env python3
"""Remove all references to collapsed cells from markdown."""
import json
from pathlib import Path

def remove_collapse_references(notebook_path: Path):
    with open(notebook_path, 'r') as f:
        nb = json.load(f)
    
    for cell in nb['cells']:
        if cell['cell_type'] == 'markdown':
            source = ''.join(cell['source'])
            
            # Remove collapse-related text
            if 'COLLAPSED CELL' in source or 'collapsed cells' in source:
                lines = []
                skip_next = False
                
                for line in cell['source']:
                    # Skip lines with collapse references
                    if any(x in line for x in [
                        'COLLAPSED CELL BELOW',
                        'collapsed by default',
                        'Click the blue bar',
                        'must still run collapsed cells',
                        'Important:** You must still run collapsed'
                    ]):
                        skip_next = True
                        continue
                    
                    # Skip closing div tags after collapse text
                    if skip_next and '</div>' in line:
                        skip_next = False
                        continue
                    
                    lines.append(line)
                
                cell['source'] = lines
    
    # Also remove from code cells
    for cell in nb['cells']:
        if cell['cell_type'] == 'code':
            source = ''.join(cell['source'])
            if '📦 COLLAPSED CELL:' in source:
                # Remove first line with collapse marker
                cell['source'] = [line for line in cell['source'] 
                                 if '📦 COLLAPSED CELL:' not in line]
    
    with open(notebook_path, 'w') as f:
        json.dump(nb, f, indent=1)

if __name__ == "__main__":
    notebook = Path(__file__).parent.parent / "notebooks" / "01-dat409-hybrid-search-TODO.ipynb"
    
    if notebook.exists():
        remove_collapse_references(notebook)
        print(f'✅ Removed collapse references from {notebook.name}')
    else:
        print(f'❌ Notebook not found: {notebook}')
