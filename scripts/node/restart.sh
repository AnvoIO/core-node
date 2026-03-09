#!/bin/bash
set -euo pipefail

# =============================================================================
# Libre Node — Restart Node
# =============================================================================
# Gracefully stops and then starts the Libre blockchain node.
#
# Usage: restart.sh [path/to/node.conf]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# ---------------------------------------------------------------------------
# find_config — locate node.conf
# ---------------------------------------------------------------------------
find_config() {
    local explicit_path="${1:-}"

    if [[ -n "$explicit_path" ]]; then
        if [[ -f "$explicit_path" ]]; then
            echo "$explicit_path"
            return 0
        fi
        log_error "Specified config not found: ${explicit_path}"
        return 1
    fi

    if [[ -f "${PWD}/node.conf" ]]; then
        echo "${PWD}/node.conf"
        return 0
    fi

    if [[ -f "${PROJECT_DIR}/node.conf" ]]; then
        echo "${PROJECT_DIR}/node.conf"
        return 0
    fi

    log_error "No node.conf found. Provide a path or run from a directory containing node.conf."
    return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_header "Libre Node — Restart"

    # Resolve config path once and pass it to both scripts
    local config_path
    config_path="$(find_config "${1:-}")"

    log_info "Stopping node..."
    "${SCRIPT_DIR}/stop.sh" "$config_path"

    log_info "Starting node..."
    "${SCRIPT_DIR}/start.sh" "$config_path"
}

main "$@"
