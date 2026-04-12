#!/bin/bash
set -e

# Ensure data directories exist and have correct permissions
mkdir -p /opt/core/data/state
mkdir -p /opt/core/data/state-history
mkdir -p /opt/core/data/blocks
mkdir -p /opt/core/data/snapshots
mkdir -p /opt/core/config/protocol_features
chown -R core:core /opt/core/data
chown -R core:core /opt/core/config 2>/dev/null || true

# If the first argument is core_netd, handle snapshot detection
if [ "$1" = "core_netd" ]; then
    # Look for latest snapshot if state directory is empty
    STATE_FILES=$(find /opt/core/data/state -name "shared_memory.bin" 2>/dev/null | head -1)

    if [ -z "$STATE_FILES" ]; then
        # No existing state — try to boot from snapshot
        LATEST_SNAPSHOT=$(find /opt/core/data/snapshots -name "*.bin" -type f 2>/dev/null | sort -r | head -n 1)

        if [ -n "$LATEST_SNAPSHOT" ]; then
            echo "No existing state found. Booting from snapshot: $(basename "$LATEST_SNAPSHOT")"

            # Clean stale head data from prior runs — snapshot boot requires
            # no pre-existing head blocks.log or state-history logs (empty or
            # mismatched files cause crashes). Retained directories (archived
            # block/state-history slices) are preserved — they contain valid
            # historical data that the node will continue building on.
            rm -f /opt/core/data/blocks/blocks.log
            rm -f /opt/core/data/blocks/blocks.index
            rm -rf /opt/core/data/blocks/reversible
            rm -f /opt/core/data/state-history/chain_state_history.log
            rm -f /opt/core/data/state-history/chain_state_history.index
            rm -f /opt/core/data/state-history/trace_history.log
            rm -f /opt/core/data/state-history/trace_history.index
            rm -rf /opt/core/config/protocol_features/*
            # Add --snapshot flag if not already present
            SNAPSHOT_FOUND=false
            for arg in "$@"; do
                if [ "$arg" = "--snapshot" ]; then
                    SNAPSHOT_FOUND=true
                    break
                fi
            done

            if [ "$SNAPSHOT_FOUND" = "false" ]; then
                # --snapshot is incompatible with --genesis-json (snapshot
                # already contains genesis data). Strip --genesis-json and
                # its value from the arguments.
                NEW_ARGS=()
                SKIP_NEXT=false
                for arg in "$@"; do
                    if [ "$SKIP_NEXT" = "true" ]; then
                        SKIP_NEXT=false
                        continue
                    fi
                    if [ "$arg" = "--genesis-json" ]; then
                        SKIP_NEXT=true
                        continue
                    fi
                    NEW_ARGS+=("$arg")
                done
                set -- "${NEW_ARGS[@]}" --snapshot "$LATEST_SNAPSHOT"
            fi
        else
            echo "No state or snapshots found. Node will sync from genesis."
        fi
    fi
fi

# Switch to core user and execute the command
exec gosu core "$@"
