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
    STATE_FILE="/opt/core/data/state/shared_memory.bin"

    # Dirty-shutdown recovery. chainbase marks shared_memory.bin with a
    # dirty flag (single byte at offset 8, see environment.hpp:106) on
    # startup and clears it on clean shutdown. If the process is SIGKILLed
    # or the host loses power, the flag stays set and chainbase refuses to
    # open the db on next start. For STATE_IN_MEMORY=true (--database-map-mode
    # locked) this is the normal crash path since the in-memory state was
    # lost anyway. Treat dirty state as "no state" so the snapshot-restore
    # branch below handles recovery uniformly.
    if [ -f "$STATE_FILE" ]; then
        DIRTY_BYTE=$(dd if="$STATE_FILE" bs=1 count=1 skip=8 2>/dev/null | od -An -tu1 | tr -d ' \n')
        if [ "$DIRTY_BYTE" != "0" ] && [ -n "$DIRTY_BYTE" ]; then
            echo "Detected dirty chain state (shared_memory.bin dirty byte=${DIRTY_BYTE})."
            echo "Last shutdown did not flush cleanly — clearing state for snapshot-restore recovery."
            rm -f "$STATE_FILE"
            rm -f /opt/core/data/state/chain_head.dat
            rm -rf /opt/core/data/blocks/reversible
        fi
    fi

    # Look for latest snapshot if state directory is empty
    STATE_FILES=$(find /opt/core/data/state -name "shared_memory.bin" 2>/dev/null | head -1)

    if [ -z "$STATE_FILES" ]; then
        # No existing state — try to boot from snapshot
        LATEST_SNAPSHOT=$(find /opt/core/data/snapshots -name "*.bin" -type f 2>/dev/null | sort -r | head -n 1)

        if [ -n "$LATEST_SNAPSHOT" ]; then
            echo "No existing state found. Booting from snapshot: $(basename "$LATEST_SNAPSHOT")"

            # Clean stale head data from prior runs — snapshot boot requires
            # no pre-existing head blocks.log or state-history logs (empty or
            # mismatched files cause crashes). Retained subdirectories
            # (blocks/retained, blocks/archive, state-history/retained) are
            # preserved — they contain valid historical data that the node
            # will continue building on.
            rm -f /opt/core/data/blocks/blocks.log
            rm -f /opt/core/data/blocks/blocks.index
            rm -rf /opt/core/data/blocks/reversible
            # Top-level striped files (blocks-NNN-NNN.log/.index) are written
            # when blocks-log-stride is set without blocks-retained-dir — e.g.
            # the producer role. Chainbase treats them as part of the head
            # block log and refuses to open a snapshot whose head is past the
            # last striped block (block_log_exception: "Block log is provided
            # with snapshot but does not contain the head block from the
            # snapshot nor a block right after it"). Clear them so snapshot
            # restore can rebuild the log cleanly from the snapshot head.
            rm -f /opt/core/data/blocks/blocks-*.log
            rm -f /opt/core/data/blocks/blocks-*.index
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
