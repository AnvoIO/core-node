#!/bin/bash
set -euo pipefail

# =============================================================================
# Libre Node — S3 Prune (Enforce Retention Policy)
# =============================================================================
# Deletes old backups on S3, keeping only the most recent N backups.
# Backups are sorted by name (timestamp-based, so alphabetical = chronological).
#
# Usage: s3-prune.sh [options] [path/to/node.conf]
#
# Options:
#   --keep N     Number of backups to retain (default: BACKUP_RETENTION from
#                node.conf, or 7 if not configured)
#   --dry-run    Show what would be deleted without actually deleting
#   --help       Show this help message
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
    echo "Libre Node — S3 Prune (Enforce Retention Policy)"
    echo ""
    echo "Deletes old backups on S3, keeping the most recent N backups."
    echo ""
    echo "Usage: $(basename "$0") [options] [path/to/node.conf]"
    echo ""
    echo "Options:"
    echo "  --keep N     Number of backups to retain (default: BACKUP_RETENTION"
    echo "               from node.conf, or 7)"
    echo "  --dry-run    Show what would be deleted without actually deleting"
    echo "  --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")                    # Prune using configured retention"
    echo "  $(basename "$0") --keep 5           # Keep last 5 backups"
    echo "  $(basename "$0") --dry-run          # Preview what would be deleted"
    echo "  $(basename "$0") --keep 3 --dry-run # Preview keeping only 3"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local config_path=""
    local keep=""
    local DRY_RUN="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                usage
                exit 0
                ;;
            --keep)
                if [[ -z "${2:-}" ]]; then
                    log_error "--keep requires a numeric argument."
                    exit 1
                fi
                keep="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            *)
                if [[ -z "$config_path" && ! "$1" =~ ^-- ]]; then
                    config_path="$1"
                fi
                shift
                ;;
        esac
    done

    log_header "Libre Node — S3 Prune"

    # Load configuration
    load_config "$(find_config "$config_path")"

    # Read S3 settings
    local S3_REMOTE S3_BUCKET S3_PREFIX BACKUP_RETENTION

    S3_REMOTE="$(get_config "S3_REMOTE")"
    S3_BUCKET="$(get_config "S3_BUCKET")"
    S3_PREFIX="$(get_config "S3_PREFIX" "")"
    BACKUP_RETENTION="$(get_config "BACKUP_RETENTION" "7")"

    validate_not_empty "$S3_REMOTE" "S3_REMOTE"
    validate_not_empty "$S3_BUCKET" "S3_BUCKET"

    # Use --keep value if provided, otherwise fall back to config
    if [[ -z "$keep" ]]; then
        keep="$BACKUP_RETENTION"
    fi

    # Validate keep is a positive integer
    if ! [[ "$keep" =~ ^[1-9][0-9]*$ ]]; then
        log_error "Invalid --keep value: '${keep}'. Must be a positive integer."
        exit 1
    fi

    # Require necessary commands
    require_command "rclone" "Install rclone: https://rclone.org/install/"

    local remote_path="${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}backups/"

    log_info "Retention policy: keep latest ${keep} backup(s)"
    log_info "Remote: ${remote_path}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN mode — no backups will be deleted."
    fi

    # List backups sorted by name (timestamp-based = chronological)
    local -a backups=()
    while IFS= read -r dir; do
        [[ -n "$dir" ]] && backups+=("${dir%/}")
    done < <(rclone lsf "${remote_path}" --dirs-only 2>/dev/null | sort)

    local count=${#backups[@]}

    if [[ $count -eq 0 ]]; then
        log_info "No backups found. Nothing to prune."
        exit 0
    fi

    local to_remove=$((count - keep))

    if [[ $to_remove -le 0 ]]; then
        log_info "Only ${count} backup(s) found, nothing to prune (keeping ${keep})."
        exit 0
    fi

    log_info "Found ${count} backup(s). Pruning ${to_remove} old backup(s)..."

    local deleted=0
    for (( i = 0; i < to_remove; i++ )); do
        local backup="${backups[$i]}"
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[dry-run] Would delete: ${backup}"
        else
            rclone purge "${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}backups/${backup}/" 2>/dev/null
            log_info "Deleted: ${backup}"
            deleted=$((deleted + 1))
        fi
    done

    # Summary
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run complete. ${to_remove} backup(s) would be deleted, ${keep} retained."
    else
        log_success "Pruning complete. Deleted ${deleted} backup(s), ${keep} retained."
    fi
}

main "$@"
