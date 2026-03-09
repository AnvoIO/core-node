#!/bin/bash
set -euo pipefail

# =============================================================================
# Libre Node — S3 Push (Upload Backup)
# =============================================================================
# Stream-compresses and uploads data from a BTRFS snapshot (or any source
# directory) to S3 using rclone.
#
# Usage: s3-push.sh <source_path> <backup_name> [path/to/node.conf]
#
# Arguments:
#   source_path    Path to the BTRFS snapshot or data directory to upload
#   backup_name    Backup timestamp/name used as the remote directory name
#
# Options:
#   --help         Show this help message
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
    echo "Libre Node — S3 Push (Upload Backup)"
    echo ""
    echo "Stream-compresses and uploads data to S3 using rclone."
    echo ""
    echo "Usage: $(basename "$0") [options] <source_path> <backup_name> [path/to/node.conf]"
    echo ""
    echo "Arguments:"
    echo "  source_path    Path to the BTRFS snapshot or data directory"
    echo "  backup_name    Backup timestamp/name for the remote directory"
    echo ""
    echo "Options:"
    echo "  --help         Show this help message"
    echo ""
    echo "Uploads the following directories (if present):"
    echo "  blocks/          -> blocks.tar.zst (stream-compressed)"
    echo "  state-history/   -> state-history.tar.zst (stream-compressed)"
    echo "  state/           -> state.tar.zst (stream-compressed)"
    echo "  snapshots/       -> snapshots/ (direct copy)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local source_path=""
    local backup_name=""
    local config_path=""

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                usage
                exit 0
                ;;
            *)
                if [[ ! "$arg" =~ ^-- ]]; then
                    if [[ -z "$source_path" ]]; then
                        source_path="$arg"
                    elif [[ -z "$backup_name" ]]; then
                        backup_name="$arg"
                    elif [[ -z "$config_path" ]]; then
                        config_path="$arg"
                    fi
                fi
                ;;
        esac
    done

    # Validate arguments
    if [[ -z "$source_path" || -z "$backup_name" ]]; then
        log_error "Missing required arguments."
        echo ""
        usage
        exit 1
    fi

    if [[ ! -d "$source_path" ]]; then
        log_error "Source path does not exist or is not a directory: ${source_path}"
        exit 1
    fi

    # Load configuration
    load_config "$(find_config "$config_path")"

    # Read S3 settings
    local S3_REMOTE S3_BUCKET S3_PREFIX NETWORK NODE_ROLE

    S3_REMOTE="$(get_config "S3_REMOTE")"
    S3_BUCKET="$(get_config "S3_BUCKET")"
    S3_PREFIX="$(get_config "S3_PREFIX" "")"
    NETWORK="$(get_config "NETWORK" "unknown")"
    NODE_ROLE="$(get_config "NODE_ROLE" "unknown")"

    validate_not_empty "$S3_REMOTE" "S3_REMOTE"
    validate_not_empty "$S3_BUCKET" "S3_BUCKET"

    # Require necessary commands
    require_command "rclone" "Install rclone: https://rclone.org/install/"
    require_command "zstd" "Install zstd: apt-get install zstd"

    local remote_base="${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}backups/${backup_name}"

    log_info "Uploading backup '${backup_name}' to ${remote_base}/"
    log_info "Source: ${source_path}"

    local upload_count=0

    # Upload blocks directory
    if [[ -d "${source_path}/blocks" ]]; then
        log_info "Uploading blocks..."
        tar -cf - -C "${source_path}" blocks | zstd -T0 -3 | \
            rclone rcat "${remote_base}/blocks.tar.zst"
        log_success "Blocks uploaded."
        upload_count=$((upload_count + 1))
    fi

    # Upload state-history directory
    if [[ -d "${source_path}/state-history" ]]; then
        log_info "Uploading state-history..."
        tar -cf - -C "${source_path}" state-history | zstd -T0 -3 | \
            rclone rcat "${remote_base}/state-history.tar.zst"
        log_success "State history uploaded."
        upload_count=$((upload_count + 1))
    fi

    # Upload state directory
    if [[ -d "${source_path}/state" ]]; then
        log_info "Uploading state..."
        tar -cf - -C "${source_path}" state | zstd -T0 -3 | \
            rclone rcat "${remote_base}/state.tar.zst"
        log_success "State uploaded."
        upload_count=$((upload_count + 1))
    fi

    # Upload snapshots directory (no compression — already binary snapshots)
    if [[ -d "${source_path}/snapshots" ]]; then
        log_info "Uploading snapshots..."
        rclone copy "${source_path}/snapshots/" "${remote_base}/snapshots/" --progress
        log_success "Snapshots uploaded."
        upload_count=$((upload_count + 1))
    fi

    # Write a manifest file
    log_info "Writing manifest..."
    echo "{\"timestamp\":\"${backup_name}\",\"network\":\"${NETWORK}\",\"role\":\"${NODE_ROLE}\",\"date\":\"$(date -Iseconds)\"}" | \
        rclone rcat "${remote_base}/manifest.json"

    # Summary
    echo ""
    log_success "Upload complete: ${upload_count} archive(s) pushed to ${remote_base}/"
}

main "$@"
