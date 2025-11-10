#!/usr/bin/env python3
"""
Add color-coded visual hierarchy to notebook cells.
Replaces collapse approach with clear visual markers.
"""
import json
from pathlib import Path

# Color-coded box templates
YELLOW_BOX = """<div style="background: #fff9e6; border-left: 5px solid #ffc107; padding: 12px; margin: 10px 0; border-radius: 4px; color: #000;">
<strong>🟨 SETUP CELL - RUN THIS FIRST</strong><br>
⚠️ Must run: This cell initializes your environment. No changes needed.
</div>"""

BLUE_BOX = """<div style="background: #e3f2fd; border-left: 5px solid #2196f3; padding: 12px; margin: 10px 0; border-radius: 4px; color: #000;">
<strong>🟦 TODO - YOUR CODE HERE</strong><br>
✏️ Complete the marked sections in this cell.
</div>"""

GREEN_BOX = """<div style="background: #e8f5e9; border-left: 5px solid #4caf50; padding: 12px; margin: 10px 0; border-radius: 4px; color: #000;">
<strong>🟩 VERIFICATION - TEST YOUR CODE</strong><br>
✅ Run this cell to verify your implementation works correctly.
</div>"""

def add_visual_markers(notebook_path: Path):
    """Add color-coded boxes before specific cells."""
    with open(notebook_path, 'r') as f:
        nb = json.load(f)
    
    # Map: cell index -> box type
    markers = {
        4: YELLOW_BOX,   # Environment setup
        6: YELLOW_BOX,   # Data verification
        8: BLUE_BOX,     # Fuzzy search TODO
        10: GREEN_BOX,   # Fuzzy test
        14: BLUE_BOX,    # Semantic search TODO
        16: GREEN_BOX,   # Semantic test
        20: BLUE_BOX,    # Hybrid RRF TODO
        22: GREEN_BOX,   # Hybrid test
        25: YELLOW_BOX,  # Interactive UI
        28: YELLOW_BOX,  # Optional benchmarking
    }
    
    # Insert markers before markdown cells
    for idx, box in sorted(markers.items(), reverse=True):
        if idx < len(nb['cells']):
            # Find preceding markdown cell
            for i in range(idx-1, -1, -1):
                if nb['cells'][i]['cell_type'] == 'markdown':
                    # Add box to end of markdown
                    nb['cells'][i]['source'].append('\n\n' + box)
                    print(f'✅ Added marker before cell {idx}')
                    break
    
    with open(notebook_path, 'w') as f:
        json.dump(nb, f, indent=1)

if __name__ == "__main__":
    notebook = Path(__file__).parent.parent / "notebooks" / "01-dat409-hybrid-search-TODO.ipynb"
    
    if notebook.exists():
        add_visual_markers(notebook)
        print(f'\n✅ Added visual hierarchy to {notebook.name}')
    else:
        print(f'❌ Notebook not found: {notebook}')
