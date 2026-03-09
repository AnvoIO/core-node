#!/bin/bash
set -euo pipefail

# =============================================================================
# Libre Node — Log Viewer
# =============================================================================
# Displays logs from the Libre blockchain node container using docker compose.
#
# Usage: logs.sh [path/to/node.conf] [-f] [-n NUM] [--since DURATION]
#        logs.sh --container-name NAME [-f] [-n NUM] [--since DURATION]
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
# usage
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $(basename "$0") [path/to/node.conf] [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f                Follow log output"
    echo "  -n NUM            Number of lines to show from the end (default: 100)"
    echo "  --since DURATION  Show logs since duration (e.g., 10m, 1h, 2024-01-01)"
    echo "  --container-name  Specify container name directly (skip node.conf)"
    echo "  -h, --help        Show this help message"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local config_path=""
    local follow="false"
    local tail_lines="100"
    local since=""
    local explicit_container=""
    local positional_args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f)
                follow="true"
                shift
                ;;
            -n)
                tail_lines="${2:-100}"
                shift 2
                ;;
            --since)
                since="${2:-}"
                shift 2
                ;;
            --container-name)
                explicit_container="${2:-}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                positional_args+=("$1")
                shift
                ;;
        esac
    done

    local CONTAINER_NAME STORAGE_PATH

    if [[ -n "$explicit_container" ]]; then
        # Use explicit container name — query docker for compose file
        CONTAINER_NAME="$explicit_container"
        # Fall back to docker logs directly when no config is loaded
        local docker_flags=()
        if [[ "$follow" == "true" ]]; then
            docker_flags+=("-f")
        fi
        docker_flags+=("--tail" "$tail_lines")
        if [[ -n "$since" ]]; then
            docker_flags+=("--since" "$since")
        fi
        docker logs "${docker_flags[@]}" "$CONTAINER_NAME"
        return
    fi

    # Load configuration
    config_path="$(find_config "${positional_args[0]:-}")"
    load_config "$config_path"

    CONTAINER_NAME="$(get_config "CONTAINER_NAME")"
    STORAGE_PATH="$(get_config "STORAGE_PATH")"

    validate_not_empty "$CONTAINER_NAME" "CONTAINER_NAME"
    validate_not_empty "$STORAGE_PATH" "STORAGE_PATH"

    # Build docker compose log flags
    local compose_flags=()
    if [[ "$follow" == "true" ]]; then
        compose_flags+=("-f")
    fi
    compose_flags+=("--tail" "$tail_lines")
    if [[ -n "$since" ]]; then
        compose_flags+=("--since" "$since")
    fi

    docker compose -f "${STORAGE_PATH}/config/docker-compose.yml" \
        logs "${compose_flags[@]}" "${CONTAINER_NAME}"
}

main "$@"
