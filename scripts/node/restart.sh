#!/bin/bash
set -euo pipefail

# =============================================================================
# Core Node — Restart Node
# =============================================================================
# Gracefully stops and then starts the Core blockchain node.
#
# Usage: restart.sh [path/to/node.conf]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/config-utils.sh"

# find_config is provided by config-utils.sh

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_header "Core Node — Restart"

    # Resolve config path once and pass it to both scripts
    local config_path
    config_path="$(find_config "${1:-}")"

    log_info "Stopping node..."
    "${SCRIPT_DIR}/stop.sh" "$config_path"

    log_info "Starting node..."
    "${SCRIPT_DIR}/start.sh" "$config_path"
}

main "$@"
