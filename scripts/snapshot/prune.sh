#!/bin/bash

# =============================================================================
# Libre Node — Prune Old Snapshots
# =============================================================================
# Removes old local snapshots beyond the configured retention count.
#
# Usage:
#   prune.sh [/path/to/node.conf] [OPTIONS]
#
# Options:
#   --keep N     Override retention count (default: SNAPSHOT_RETENTION from node.conf, or 5)
#   --dry-run    Show what would be deleted without actually deleting
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Source library files
# ---------------------------------------------------------------------------
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/config-utils.sh
source "${SCRIPT_DIR}/../lib/config-utils.sh"

# ---------------------------------------------------------------------------
# find_config — locate node.conf from argument, $PWD, or $PROJECT_DIR
# ---------------------------------------------------------------------------
find_config() {
    local config_arg="${1:-}"

    if [[ -n "$config_arg" && -f "$config_arg" ]]; then
        echo "$config_arg"
        return 0
    fi

    if [[ -f "${PWD}/node.conf" ]]; then
        echo "${PWD}/node.conf"
        return 0
    fi

    if [[ -f "${PROJECT_DIR}/node.conf" ]]; then
        echo "${PROJECT_DIR}/node.conf"
        return 0
    fi

    log_error "Cannot find node.conf. Provide it as an argument, or ensure it exists in \$PWD or ${PROJECT_DIR}."
    return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local config_path=""
    local keep_override=""
    local dry_run=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --keep)
                keep_override="${2:-}"
                if [[ -z "$keep_override" || ! "$keep_override" =~ ^[0-9]+$ ]]; then
                    log_error "--keep requires a positive integer argument."
                    exit 1
                fi
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [[ -z "$config_path" ]]; then
                    config_path="$1"
                fi
                shift
                ;;
        esac
    done

    # Locate and load configuration
    local conf
    conf="$(find_config "$config_path")"
    load_config "$conf"

    local storage_path
    storage_path="$(get_config "STORAGE_PATH" "")"
    if [[ -z "$storage_path" ]]; then
        log_error "STORAGE_PATH is not set in ${conf}"
        exit 1
    fi

    local snapshot_retention
    snapshot_retention="$(get_config "SNAPSHOT_RETENTION" "5")"

    # Allow --keep to override the config value
    local keep="${keep_override:-$snapshot_retention}"

    local snapshots_dir="${storage_path}/snapshots"

    if [[ ! -d "$snapshots_dir" ]]; then
        log_info "Snapshots directory does not exist: ${snapshots_dir}"
        log_info "Nothing to prune."
        return 0
    fi

    # Build sorted list of snapshots (newest first by modification time)
    local snapshots=()
    while IFS= read -r f; do
        snapshots+=("$f")
    done < <(ls -1t "${snapshots_dir}"/*.bin 2>/dev/null)

    local count=${#snapshots[@]}

    if [[ $count -eq 0 ]]; then
        log_info "No snapshots found in ${snapshots_dir}"
        return 0
    fi

    if [[ $count -le $keep ]]; then
        log_info "Only ${count} snapshot(s) found, nothing to prune (keeping ${keep})"
        return 0
    fi

    local to_remove=$((count - keep))
    if [[ "$dry_run" == "true" ]]; then
        log_info "[dry-run] Would prune ${to_remove} old snapshot(s) (keeping latest ${keep})..."
    else
        log_info "Pruning ${to_remove} old snapshot(s) (keeping latest ${keep})..."
    fi

    local freed_bytes=0
    local deleted_count=0

    for (( i = keep; i < count; i++ )); do
        local snap="${snapshots[$i]}"
        local snap_name
        snap_name="$(basename "$snap")"

        if [[ "$dry_run" == "true" ]]; then
            local snap_size
            snap_size="$(du -h "$snap" | cut -f1)"
            log_info "[dry-run] Would delete: ${snap_name} (${snap_size})"
        else
            # Track size before deletion
            local snap_bytes
            snap_bytes="$(stat -c %s "$snap" 2>/dev/null || echo 0)"
            freed_bytes=$((freed_bytes + snap_bytes))

            rm -f "$snap"
            log_info "Deleted: ${snap_name}"
            deleted_count=$((deleted_count + 1))
        fi
    done

    # Summary
    if [[ "$dry_run" == "true" ]]; then
        log_info "[dry-run] ${to_remove} snapshot(s) would be removed. ${keep} would be kept."
    else
        local remaining=$((count - deleted_count))
        local freed_human
        if [[ $freed_bytes -ge $((1024 * 1024 * 1024)) ]]; then
            freed_human="$(awk "BEGIN {printf \"%.1fG\", ${freed_bytes}/1024/1024/1024}")"
        elif [[ $freed_bytes -ge $((1024 * 1024)) ]]; then
            freed_human="$(awk "BEGIN {printf \"%.1fM\", ${freed_bytes}/1024/1024}")"
        elif [[ $freed_bytes -ge 1024 ]]; then
            freed_human="$(awk "BEGIN {printf \"%.1fK\", ${freed_bytes}/1024}")"
        else
            freed_human="${freed_bytes}B"
        fi

        log_success "Pruned ${deleted_count} snapshot(s), freed ${freed_human}. ${remaining} snapshot(s) remaining."
    fi
}

main "$@"
