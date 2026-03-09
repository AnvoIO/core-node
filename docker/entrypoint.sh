#!/bin/bash
set -e

# Ensure data directories exist and have correct permissions
mkdir -p /opt/eosio/data/state
mkdir -p /opt/eosio/data/state-history
mkdir -p /opt/eosio/data/blocks
mkdir -p /opt/eosio/data/snapshots
mkdir -p /opt/eosio/config/protocol_features
chown -R eosio:eosio /opt/eosio/data
chown -R eosio:eosio /opt/eosio/config

# If the first argument is nodeos, handle snapshot detection
if [ "$1" = "nodeos" ]; then
    # Look for latest snapshot if state directory is empty
    STATE_FILES=$(find /opt/eosio/data/state -name "shared_memory.bin" 2>/dev/null | head -1)

    if [ -z "$STATE_FILES" ]; then
        # No existing state — try to boot from snapshot
        LATEST_SNAPSHOT=$(find /opt/eosio/data/snapshots -name "*.bin" -type f 2>/dev/null | sort -r | head -n 1)

        if [ -n "$LATEST_SNAPSHOT" ]; then
            echo "No existing state found. Booting from snapshot: $(basename "$LATEST_SNAPSHOT")"
            # Add --snapshot flag if not already present
            SNAPSHOT_FOUND=false
            for arg in "$@"; do
                if [ "$arg" = "--snapshot" ]; then
                    SNAPSHOT_FOUND=true
                    break
                fi
            done

            if [ "$SNAPSHOT_FOUND" = "false" ]; then
                set -- "$@" --snapshot "$LATEST_SNAPSHOT"
            fi
        else
            echo "No state or snapshots found. Node will sync from genesis."
        fi
    fi
fi

# Switch to eosio user and execute the command
exec gosu eosio "$@"
