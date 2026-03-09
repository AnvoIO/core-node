#!/bin/bash
set -euo pipefail

# =============================================================================
# Libre Node — Full Node Reset
# =============================================================================
# Stops the node and removes all blockchain data. Optionally removes snapshots,
# logs, and configuration. Requires confirmation for each destructive step.
#
# Usage: reset.sh [/path/to/node.conf]
# =============================================================================

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
    load_config "$(find_config "${1:-}")"

    local container_name
    container_name="$(get_config "CONTAINER_NAME" "")"
    local storage_path
    storage_path="$(get_config "STORAGE_PATH" "")"

    validate_not_empty "$container_name" "CONTAINER_NAME"
    validate_not_empty "$storage_path" "STORAGE_PATH"

    log_header "Node Reset"

    log_warn "This will delete all node data and require a full resync or snapshot restore."
    echo ""
    echo "  Container: ${container_name}"
    echo "  Data path: ${storage_path}/data/"
    echo ""

    confirm_action "Stop the node and delete all blockchain data"

    # Stop container if running
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
        log_info "Stopping container..."
        docker stop "${container_name}" || true
        docker rm "${container_name}" || true
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
        log_info "Removing stopped container..."
        docker rm "${container_name}" || true
    fi

    # Remove data directories
    log_info "Removing blockchain data..."
    rm -rf "${storage_path}/data/blocks"
    rm -rf "${storage_path}/data/state"
    rm -rf "${storage_path}/data/state-history"
    log_success "Blockchain data removed."

    # Ask about snapshots
    if [[ -d "${storage_path}/snapshots" ]]; then
        local snap_count
        snap_count="$(ls -1 "${storage_path}/snapshots/"*.bin 2>/dev/null | wc -l || echo 0)"
        if [[ $snap_count -gt 0 ]]; then
            local snap_size
            snap_size="$(du -sh "${storage_path}/snapshots" 2>/dev/null | cut -f1)"
            echo ""
            log_info "Found ${snap_count} snapshot(s) (${snap_size})."
        fi
    fi
    if ask_yes_no "Also delete local snapshots?" "n"; then
        rm -rf "${storage_path}/snapshots/"*
        log_info "Snapshots deleted."
    fi

    # Ask about logs
    if ask_yes_no "Also delete logs?" "y"; then
        rm -rf "${storage_path}/logs/"*
        log_info "Logs deleted."
    fi

    # Ask about generated config (default no)
    if ask_yes_no "Also delete generated config files (docker-compose.yml, config.ini, etc.)?" "n"; then
        rm -f "${storage_path}/config/config.ini"
        rm -f "${storage_path}/config/docker-compose.yml"
        rm -f "${storage_path}/config/logging.json"
        rm -f "${storage_path}/config/Caddyfile"
        log_info "Generated config files deleted."
    fi

    echo ""
    log_success "Reset complete."
    echo ""
    echo "  To set up the node again:"
    echo "    1. Run the setup wizard:  scripts/setup/wizard.sh"
    echo "    2. Start the node:        scripts/node/start.sh"
    echo ""
}

main "$@"
