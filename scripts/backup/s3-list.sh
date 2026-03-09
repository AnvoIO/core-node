#!/bin/bash
set -euo pipefail

# =============================================================================
# Libre Node — S3 List Backups
# =============================================================================
# Lists available remote backups stored on S3, including metadata from each
# backup's manifest file.
#
# Usage: s3-list.sh [path/to/node.conf]
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
    echo "Libre Node — S3 List Backups"
    echo ""
    echo "Lists available remote backups stored on S3."
    echo ""
    echo "Usage: $(basename "$0") [options] [path/to/node.conf]"
    echo ""
    echo "Options:"
    echo "  --help    Show this help message"
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

    # Load configuration
    load_config "$(find_config "$config_path")"

    # Read S3 settings
    local S3_REMOTE S3_BUCKET S3_PREFIX

    S3_REMOTE="$(get_config "S3_REMOTE")"
    S3_BUCKET="$(get_config "S3_BUCKET")"
    S3_PREFIX="$(get_config "S3_PREFIX" "")"

    validate_not_empty "$S3_REMOTE" "S3_REMOTE"
    validate_not_empty "$S3_BUCKET" "S3_BUCKET"

    # Require necessary commands
    require_command "rclone" "Install rclone: https://rclone.org/install/"

    log_info "Available backups on ${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}:"
    echo ""

    local backups
    backups=$(rclone lsf "${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}backups/" --dirs-only 2>/dev/null)

    if [[ -z "$backups" ]]; then
        log_warn "No backups found."
        exit 0
    fi

    printf "%-25s %-15s %-15s %s\n" "BACKUP" "NETWORK" "ROLE" "DATE"
    printf "%-25s %-15s %-15s %s\n" "------" "-------" "----" "----"

    while IFS= read -r dir; do
        dir="${dir%/}"
        [[ -z "$dir" ]] && continue

        local manifest
        manifest=$(rclone cat "${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}backups/${dir}/manifest.json" 2>/dev/null || echo '{}')

        local net role date
        net=$(echo "$manifest" | grep -o '"network":"[^"]*"' | cut -d'"' -f4)
        role=$(echo "$manifest" | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
        date=$(echo "$manifest" | grep -o '"date":"[^"]*"' | cut -d'"' -f4)

        printf "%-25s %-15s %-15s %s\n" "$dir" "${net:-unknown}" "${role:-unknown}" "${date:-unknown}"
    done <<< "$backups"

    echo ""
    local count
    count=$(echo "$backups" | grep -c '[^[:space:]]' || true)
    log_info "Total: ${count} backup(s)"
}

main "$@"
