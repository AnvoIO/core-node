#!/bin/bash
set -euo pipefail

# =============================================================================
# Libre Node — Stop Node
# =============================================================================
# Gracefully stops the Libre blockchain node container.
#
# Usage: stop.sh [path/to/node.conf]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/config-utils.sh"

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
    log_header "Libre Node — Stop"

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

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "Container '${CONTAINER_NAME}' is not running."
        exit 0
    fi

    # Graceful stop
    log_info "Stopping ${CONTAINER_NAME}..."
    docker compose -f "${STORAGE_PATH}/config/docker-compose.yml" stop

    # Wait for container to actually stop
    local max_wait=60
    local waited=0
    while docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; do
        sleep 2
        waited=$((waited + 2))
        if [[ $waited -ge $max_wait ]]; then
            log_warn "Container did not stop within ${max_wait} seconds. Forcing removal..."
            break
        fi
    done

    # Remove stopped containers
    docker compose -f "${STORAGE_PATH}/config/docker-compose.yml" down

    log_success "Node stopped."
}

main "$@"
