#!/bin/bash

# Setup automatic snapshot management via cron
# Creates snapshots every 6 hours and prunes old ones daily

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Setting up automatic snapshot management..."

# Create cron entries
SNAPSHOT_CREATE_JOB="0 */6 * * * cd $PROJECT_ROOT && ./scripts/manage-snapshots.sh create >/dev/null 2>&1"
SNAPSHOT_PRUNE_JOB="0 2 * * * cd $PROJECT_ROOT && ./scripts/manage-snapshots.sh prune --keep 5 >/dev/null 2>&1"

# Check if cron entries already exist
if crontab -l 2>/dev/null | grep -q "manage-snapshots.sh"; then
    echo "Snapshot cron jobs already exist. Updating..."
    # Remove existing entries
    crontab -l 2>/dev/null | grep -v "manage-snapshots.sh" | crontab -
fi

# Add new entries
echo "Adding snapshot management to crontab..."
(crontab -l 2>/dev/null; echo "# Libre snapshot management"; echo "$SNAPSHOT_CREATE_JOB"; echo "$SNAPSHOT_PRUNE_JOB") | crontab -

echo "✅ Automatic snapshot management configured:"
echo "   - Creates snapshots every 6 hours"
echo "   - Prunes old snapshots daily at 2 AM (keeps latest 5)"
echo ""
echo "To view current cron jobs: crontab -l"
echo "To remove snapshot automation: crontab -e"
echo ""
echo "Manual commands:"
echo "  Create snapshot: ./scripts/manage-snapshots.sh create [mainnet|testnet]"
echo "  View snapshots:  ./scripts/manage-snapshots.sh status"
echo "  Prune snapshots: ./scripts/manage-snapshots.sh prune --keep 3"