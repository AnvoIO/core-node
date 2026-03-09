#!/bin/bash
set -euo pipefail

# =============================================================================
# Libre Node — Full Backup
# =============================================================================
# Orchestrates a complete node backup using BTRFS snapshots and S3 upload.
# Stops the node briefly to create a consistent filesystem snapshot, then
# restarts and uploads the snapshot to S3 in the background.
#
# Usage: full-backup.sh [path/to/node.conf]
#
# Options:
#   --help    Show this help message
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/config-utils.sh"

# ---------------------------------------------------------------------------
# find_config — locate node.conf
# ---------------------------------------------------------------------------
find_config() {
    local config_path="${1:-}"
    if [[ -n "$config_path" && -f "$config_path" ]]; then echo "$config_path"; return 0; fi
    if [[ -f "${PWD}/node.conf" ]]; then echo "./node.conf"; return 0; fi
    if [[ -f "${PROJECT_DIR}/node.conf" ]]; then echo "${PROJECT_DIR}/node.conf"; return 0; fi
    log_error "No node.conf found. Specify path as argument."
    return 1
}

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    echo "Libre Node — Full Backup"
    echo ""
    echo "Orchestrates a complete node backup using BTRFS snapshots and S3 upload."
    echo ""
    echo "Usage: $(basename "$0") [options] [path/to/node.conf]"
    echo ""
    echo "Options:"
    echo "  --help    Show this help message"
    echo ""
    echo "The backup sequence:"
    echo "  1. Create an EOSIO snapshot via producer API"
    echo "  2. Wait for blocks to finalize"
    echo "  3. Stop the node container"
    echo "  4. Create a read-only BTRFS snapshot"
    echo "  5. Restart the node container"
    echo "  6. Upload the BTRFS snapshot to S3"
    echo "  7. Clean up the BTRFS snapshot"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local config_path=""

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                usage
                exit 0
                ;;
            *)
                if [[ -z "$config_path" && ! "$arg" =~ ^-- ]]; then
                    config_path="$arg"
                fi
                ;;
        esac
    done

    log_header "Libre Node — Full Backup"

    # Load configuration
    load_config "$(find_config "$config_path")"

    # Read required settings
    local STORAGE_PATH CONTAINER_NAME NETWORK NODE_ROLE HTTP_PORT BIND_IP
    local S3_ENABLED S3_REMOTE S3_BUCKET S3_PREFIX

    STORAGE_PATH="$(get_config "STORAGE_PATH")"
    CONTAINER_NAME="$(get_config "CONTAINER_NAME")"
    NETWORK="$(get_config "NETWORK")"
    NODE_ROLE="$(get_config "NODE_ROLE")"
    HTTP_PORT="$(get_config "HTTP_PORT")"
    BIND_IP="$(get_config "BIND_IP" "0.0.0.0")"
    S3_ENABLED="$(get_config "S3_ENABLED" "false")"
    S3_REMOTE="$(get_config "S3_REMOTE")"
    S3_BUCKET="$(get_config "S3_BUCKET")"
    S3_PREFIX="$(get_config "S3_PREFIX" "")"

    # Validate required fields
    validate_not_empty "$STORAGE_PATH" "STORAGE_PATH"
    validate_not_empty "$CONTAINER_NAME" "CONTAINER_NAME"
    validate_not_empty "$NETWORK" "NETWORK"
    validate_not_empty "$HTTP_PORT" "HTTP_PORT"

    # Verify S3 is configured
    if [[ "$S3_ENABLED" != "true" ]]; then
        log_error "S3 is not enabled. Set S3_ENABLED=true in node.conf to use backups."
        exit 1
    fi

    validate_not_empty "$S3_REMOTE" "S3_REMOTE"
    validate_not_empty "$S3_BUCKET" "S3_BUCKET"

    # Verify BTRFS filesystem
    if ! validate_btrfs "$STORAGE_PATH"; then
        log_error "STORAGE_PATH (${STORAGE_PATH}) is not on a BTRFS filesystem. BTRFS is required for snapshots."
        exit 1
    fi

    # Require necessary commands
    require_command "rclone" "Install rclone: https://rclone.org/install/"
    require_command "btrfs" "Install btrfs-progs: apt-get install btrfs-progs"
    require_command "zstd" "Install zstd: apt-get install zstd"
    require_command "curl"

    # Set API host — convert 0.0.0.0 to localhost for curl
    local api_host="$BIND_IP"
    if [[ "$api_host" == "0.0.0.0" ]]; then
        api_host="localhost"
    fi

    # Generate timestamp for this backup
    local BACKUP_TS
    BACKUP_TS=$(date +%Y%m%d_%H%M%S)

    # Define BTRFS snapshot path
    local BTRFS_SNAP="${STORAGE_PATH}/.backup-${BACKUP_TS}"

    log_info "Starting full backup: ${BACKUP_TS}"
    log_info "Network: ${NETWORK} | Role: ${NODE_ROLE:-unknown} | Storage: ${STORAGE_PATH}"

    # Step 1: Create EOSIO snapshot
    log_info "Step 1/6: Creating EOSIO snapshot..."
    curl -sf -X POST "http://${api_host}:${HTTP_PORT}/v1/producer/create_snapshot" || {
        log_warn "Could not create EOSIO snapshot (producer_api_plugin may not be enabled). Continuing..."
    }

    # Step 2: Wait for blocks to finalize
    log_info "Step 2/6: Waiting 30 seconds for block finalization..."
    sleep 30

    # Step 3: Stop nodeos
    log_info "Step 3/6: Stopping node..."
    docker compose -f "${STORAGE_PATH}/config/docker-compose.yml" stop

    # Step 4: Create BTRFS snapshot
    log_info "Step 4/6: Creating filesystem snapshot..."
    btrfs subvolume snapshot -r "${STORAGE_PATH}/data" "${BTRFS_SNAP}" || {
        log_error "BTRFS snapshot failed. Starting node back up."
        docker compose -f "${STORAGE_PATH}/config/docker-compose.yml" up -d
        exit 1
    }

    # Step 5: Start nodeos back up immediately
    log_info "Step 5/6: Starting node..."
    docker compose -f "${STORAGE_PATH}/config/docker-compose.yml" up -d
    log_success "Node restarted. Downtime was minimal."

    # Step 6: Upload to S3 from BTRFS snapshot
    log_info "Step 6/6: Uploading backup to S3..."
    "${SCRIPT_DIR}/s3-push.sh" "${BTRFS_SNAP}" "${BACKUP_TS}"

    # Cleanup: destroy BTRFS snapshot
    log_info "Cleaning up filesystem snapshot..."
    btrfs subvolume delete "${BTRFS_SNAP}" || log_warn "Could not delete BTRFS snapshot at ${BTRFS_SNAP}"

    log_success "Full backup complete: ${BACKUP_TS}"
}

main "$@"
