#!/bin/bash

# DAT409 Workshop - Cleanup Old Structure
# Run this AFTER verifying the migration was successful

echo "⚠️  WARNING: This will remove old directories!"
echo "Make sure you've verified the new structure works correctly."
echo ""
read -p "Are you sure you want to clean up old directories? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🧹 Cleaning up old structure..."
    
    # Remove old directories
    if [ -d "notebooks" ]; then
        rm -rf notebooks
        echo "  ✓ Removed old notebooks directory"
    fi
    
    if [ -d "data" ]; then
        rm -rf data
        echo "  ✓ Removed old data directory"
    fi
    
    if [ -d "code" ]; then
        rm -rf code
        echo "  ✓ Removed old code directory"
    fi
    
    if [ -d "solutions" ]; then
        rm -rf solutions
        echo "  ✓ Removed old solutions directory"
    fi
    
    # Clean up old scripts that were moved
    if [ -f "scripts/setup_database.sql" ]; then
        rm scripts/setup_database.sql
        echo "  ✓ Removed old database script location"
    fi
    
    if [ -f "scripts/incident_logs_generator.py" ]; then
        rm scripts/incident_logs_generator.py
        echo "  ✓ Removed old generator location"
    fi
    
    echo "✅ Cleanup complete!"
else
    echo "❌ Cleanup cancelled"
fi