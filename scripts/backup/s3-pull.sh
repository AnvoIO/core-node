#!/bin/bash
set -euo pipefail

# =============================================================================
# Libre Node — S3 Pull (Download Backup)
# =============================================================================
# Downloads and restores a backup from S3. If no backup name is given, the
# latest available backup is used.
#
# Usage: s3-pull.sh [options] [backup_name] [path/to/node.conf]
#
# Arguments:
#   backup_name       Backup timestamp/name to restore (default: latest)
#
# Options:
#   --snapshots-only  Only download snapshot files, not full data
#   --help            Show this help message
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
    echo "Libre Node — S3 Pull (Download Backup)"
    echo ""
    echo "Downloads and restores a backup from S3."
    echo ""
    echo "Usage: $(basename "$0") [options] [backup_name] [path/to/node.conf]"
    echo ""
    echo "Arguments:"
    echo "  backup_name       Backup timestamp/name to restore (default: latest)"
    echo ""
    echo "Options:"
    echo "  --snapshots-only  Only download snapshot files, not full data"
    echo "  --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")                          # Restore latest backup"
    echo "  $(basename "$0") 20250301_120000          # Restore specific backup"
    echo "  $(basename "$0") --snapshots-only         # Download only snapshots"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local backup_name=""
    local config_path=""
    local SNAPSHOTS_ONLY="false"

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                usage
                exit 0
                ;;
            --snapshots-only)
                SNAPSHOTS_ONLY="true"
                ;;
            *)
                if [[ ! "$arg" =~ ^-- ]]; then
                    if [[ -z "$backup_name" ]]; then
                        backup_name="$arg"
                    elif [[ -z "$config_path" ]]; then
                        config_path="$arg"
                    fi
                fi
                ;;
        esac
    done

    log_header "Libre Node — S3 Pull"

    # Load configuration
    load_config "$(find_config "$config_path")"

    # Read settings
    local S3_REMOTE S3_BUCKET S3_PREFIX STORAGE_PATH

    S3_REMOTE="$(get_config "S3_REMOTE")"
    S3_BUCKET="$(get_config "S3_BUCKET")"
    S3_PREFIX="$(get_config "S3_PREFIX" "")"
    STORAGE_PATH="$(get_config "STORAGE_PATH")"

    validate_not_empty "$S3_REMOTE" "S3_REMOTE"
    validate_not_empty "$S3_BUCKET" "S3_BUCKET"
    validate_not_empty "$STORAGE_PATH" "STORAGE_PATH"

    # Require necessary commands
    require_command "rclone" "Install rclone: https://rclone.org/install/"
    require_command "zstd" "Install zstd: apt-get install zstd"

    # If no backup name given, find the latest
    if [[ -z "$backup_name" ]]; then
        log_info "No backup name specified. Finding latest..."
        local latest
        latest=$(rclone lsf "${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}backups/" --dirs-only 2>/dev/null | sort | tail -1 | tr -d '/')

        if [[ -z "$latest" ]]; then
            log_error "No backups found on ${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}backups/"
            exit 1
        fi

        backup_name="$latest"
        log_info "Latest backup: ${backup_name}"
    fi

    local remote_base="${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}backups/${backup_name}"
    local data_dir="${STORAGE_PATH}/data"

    log_info "Restoring backup '${backup_name}' from ${remote_base}/"
    log_info "Destination: ${STORAGE_PATH}"

    # Ensure destination directories exist
    mkdir -p "${data_dir}"
    mkdir -p "${STORAGE_PATH}/snapshots"

    if [[ "$SNAPSHOTS_ONLY" == "true" ]]; then
        log_info "Downloading snapshots only..."
        rclone copy "${remote_base}/snapshots/" "${STORAGE_PATH}/snapshots/" --progress
        log_success "Snapshots restored to ${STORAGE_PATH}/snapshots/"
    else
        log_info "Downloading full backup..."

        # Download and decompress blocks
        log_info "Restoring blocks..."
        if rclone cat "${remote_base}/blocks.tar.zst" 2>/dev/null | zstd -d | tar -xf - -C "${data_dir}"; then
            log_success "Blocks restored."
        else
            log_warn "No blocks archive found or download failed."
        fi

        # Download and decompress state-history
        log_info "Restoring state-history..."
        if rclone cat "${remote_base}/state-history.tar.zst" 2>/dev/null | zstd -d | tar -xf - -C "${data_dir}"; then
            log_success "State history restored."
        else
            log_warn "No state-history archive found or download failed."
        fi

        # Download and decompress state
        log_info "Restoring state..."
        if rclone cat "${remote_base}/state.tar.zst" 2>/dev/null | zstd -d | tar -xf - -C "${data_dir}"; then
            log_success "State restored."
        else
            log_warn "No state archive found or download failed."
        fi

        # Download snapshots directory
        log_info "Restoring snapshots..."
        rclone copy "${remote_base}/snapshots/" "${STORAGE_PATH}/snapshots/" --progress 2>/dev/null || true
    fi

    # Download manifest for reference
    local manifest
    manifest=$(rclone cat "${remote_base}/manifest.json" 2>/dev/null || echo "")
    if [[ -n "$manifest" ]]; then
        log_info "Backup manifest: ${manifest}"
    fi

    # Summary
    echo ""
    log_success "Restore complete: ${backup_name}"
    echo ""
    echo "  Storage path:  ${STORAGE_PATH}"
    echo "  Data dir:      ${data_dir}"
    echo "  Snapshots:     ${STORAGE_PATH}/snapshots/"
    echo ""
    log_info "You can now start the node with: scripts/node/start.sh"
}

main "$@"
