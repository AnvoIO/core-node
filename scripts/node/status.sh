#!/bin/bash
set -euo pipefail

# =============================================================================
# Libre Node — Node Status
# =============================================================================
# Displays the current status of the Libre blockchain node, including
# container state, chain info, peer count, and API endpoint.
#
# Usage: status.sh [path/to/node.conf]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/config-utils.sh"
source "${SCRIPT_DIR}/../lib/network-defaults.sh"

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
# format_age — convert seconds to a human-readable age string
# ---------------------------------------------------------------------------
format_age() {
    local seconds="$1"

    if [[ $seconds -lt 0 ]]; then
        seconds=$(( -seconds ))
    fi

    if [[ $seconds -lt 60 ]]; then
        echo "${seconds} seconds ago"
    elif [[ $seconds -lt 3600 ]]; then
        echo "$(( seconds / 60 )) minutes ago"
    elif [[ $seconds -lt 86400 ]]; then
        echo "$(( seconds / 3600 )) hours ago"
    else
        echo "$(( seconds / 86400 )) days ago"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    # Load configuration
    local config_path
    config_path="$(find_config "${1:-}")"
    load_config "$config_path"

    # Read key values
    local NETWORK NODE_ROLE CONTAINER_NAME HTTP_PORT P2P_PORT BIND_IP
    NETWORK="$(get_config "NETWORK")"
    NODE_ROLE="$(get_config "NODE_ROLE")"
    CONTAINER_NAME="$(get_config "CONTAINER_NAME")"
    HTTP_PORT="$(get_config "HTTP_PORT")"
    P2P_PORT="$(get_config "P2P_PORT")"
    BIND_IP="$(get_config "BIND_IP" "0.0.0.0")"

    # Determine container status
    local container_status="stopped"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        container_status="running"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        container_status="exited"
    fi

    # Gather chain info if the node is running and has an HTTP API
    local head_block_num="" head_block_time="" lib="" server_version="" peer_count="" block_age=""

    if [[ "$container_status" == "running" && "$NODE_ROLE" != "seed" ]]; then
        local chain_info
        if chain_info="$(curl -sf "http://localhost:${HTTP_PORT}/v1/chain/get_info" 2>/dev/null)"; then
            head_block_num="$(echo "$chain_info" | grep -o '"head_block_num":[0-9]*' | cut -d: -f2)"
            head_block_time="$(echo "$chain_info" | grep -o '"head_block_time":"[^"]*"' | cut -d'"' -f4)"
            lib="$(echo "$chain_info" | grep -o '"last_irreversible_block_num":[0-9]*' | cut -d: -f2)"
            server_version="$(echo "$chain_info" | grep -o '"server_version_string":"[^"]*"' | cut -d'"' -f4)"

            # Calculate head block age
            if [[ -n "$head_block_time" ]]; then
                local head_epoch now_epoch
                head_epoch="$(date -d "${head_block_time}" +%s 2>/dev/null || echo "")"
                now_epoch="$(date +%s)"
                if [[ -n "$head_epoch" ]]; then
                    block_age="$(format_age $(( now_epoch - head_epoch )))"
                fi
            fi
        fi

        # Query peer count
        local connections
        if connections="$(curl -sf "http://localhost:${HTTP_PORT}/v1/net/connections" 2>/dev/null)"; then
            peer_count="$(echo "$connections" | grep -o '"connecting":false' | wc -l)"
        fi
    fi

    # Display formatted status
    echo ""
    echo "Libre Node Status"
    echo "================="
    echo "  Container:    ${CONTAINER_NAME} (${container_status})"
    echo "  Network:      ${NETWORK}"
    echo "  Role:         ${NODE_ROLE}"

    if [[ -n "$head_block_num" ]]; then
        local block_age_display=""
        if [[ -n "$block_age" ]]; then
            block_age_display=" (${block_age})"
        fi
        echo "  Head Block:   ${head_block_num}${block_age_display}"
    fi

    if [[ -n "$lib" ]]; then
        echo "  LIB:          ${lib}"
    fi

    if [[ -n "$peer_count" ]]; then
        echo "  Peers:        ${peer_count} connected"
    fi

    if [[ -n "$server_version" ]]; then
        echo "  Version:      ${server_version}"
    fi

    if [[ "$NODE_ROLE" != "seed" ]]; then
        echo "  API:          http://${BIND_IP}:${HTTP_PORT}"
    fi

    echo "  P2P:          ${BIND_IP}:${P2P_PORT}"
    echo ""
}

main "$@"
