#!/bin/bash
set -euo pipefail

# =============================================================================
# Core Node — Stop Node
# =============================================================================
# Gracefully stops the Core blockchain node container.
#
# Usage: stop.sh [path/to/node.conf]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/config-utils.sh"

# find_config is provided by config-utils.sh

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_header "Core Node — Stop"

    # Load configuration
    local config_path
    config_path="$(find_config "${1:-}")"
    load_config "$config_path"

    # Read key values
    local CONTAINER_NAME STORAGE_PATH
    CONTAINER_NAME="$(get_config "CONTAINER_NAME")"
    STORAGE_PATH="$(get_config "STORAGE_PATH")"

    validate_not_empty "$CONTAINER_NAME" "CONTAINER_NAME"
    validate_not_empty "$STORAGE_PATH" "STORAGE_PATH"

    require_command "docker"

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "Container '${CONTAINER_NAME}' is not running."
        exit 0
    fi

    # Graceful stop and remove (docker compose down stops then removes)
    log_info "Stopping ${CONTAINER_NAME}..."
    docker compose -f "${STORAGE_PATH}/config/docker-compose.yml" down --timeout 1800

    log_success "Node stopped."
}

main "$@"
