#!/bin/bash

# =============================================================================
# Libre Node — Create Snapshot
# =============================================================================
# Creates an EOSIO snapshot from a running node via the Leap producer HTTP API.
#
# Usage:
#   create.sh [/path/to/node.conf] [--prune]
#
# Options:
#   --prune   Run snapshot pruning after creation (uses prune.sh)
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
# shellcheck source=../lib/network-defaults.sh
source "${SCRIPT_DIR}/../lib/network-defaults.sh"

# ---------------------------------------------------------------------------
# find_config — locate node.conf from argument, $PWD, or $PROJECT_DIR
# ---------------------------------------------------------------------------
find_config() {
    local config_arg="${1:-}"

    # 1. Explicit argument
    if [[ -n "$config_arg" && -f "$config_arg" ]]; then
        echo "$config_arg"
        return 0
    fi

    # 2. Current working directory
    if [[ -f "${PWD}/node.conf" ]]; then
        echo "${PWD}/node.conf"
        return 0
    fi

    # 3. Project root
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
    local do_prune=false

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --prune)
                do_prune=true
                ;;
            *)
                # Treat non-flag arguments as potential config path
                if [[ -z "$config_path" && ! "$arg" =~ ^-- ]]; then
                    config_path="$arg"
                fi
                ;;
        esac
    done

    # Locate and load configuration
    local conf
    conf="$(find_config "$config_path")"
    load_config "$conf"

    # Read required settings
    local http_port
    http_port="$(get_config "HTTP_PORT" "")"
    if [[ -z "$http_port" ]]; then
        log_error "HTTP_PORT is not set in ${conf}"
        exit 1
    fi

    local bind_ip
    bind_ip="$(get_config "BIND_IP" "0.0.0.0")"

    local container_name
    container_name="$(get_config "CONTAINER_NAME" "")"
    if [[ -z "$container_name" ]]; then
        log_error "CONTAINER_NAME is not set in ${conf}"
        exit 1
    fi

    local storage_path
    storage_path="$(get_config "STORAGE_PATH" "")"
    if [[ -z "$storage_path" ]]; then
        log_error "STORAGE_PATH is not set in ${conf}"
        exit 1
    fi

    # Verify the container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log_error "Container '${container_name}' is not running."
        exit 1
    fi

    # Determine API host — convert 0.0.0.0 to localhost for curl
    local api_host="$bind_ip"
    if [[ "$api_host" == "0.0.0.0" ]]; then
        api_host="localhost"
    fi

    local api_url="http://${api_host}:${http_port}"

    # Call the create_snapshot producer API
    log_info "Creating snapshot via ${api_url} ..."
    local response
    response=$(curl -sf -X POST "${api_url}/v1/producer/create_snapshot" 2>&1) || {
        log_error "Failed to create snapshot. Is producer_api_plugin enabled?"
        exit 1
    }

    # Parse the response for the snapshot path
    # Expected response: {"head_block_id":"...","snapshot_name":"/path/to/snapshot-....bin"}
    local snapshot_path
    snapshot_path="$(echo "$response" | grep -oP '"snapshot_name"\s*:\s*"\K[^"]+' || true)"

    if [[ -z "$snapshot_path" ]]; then
        log_error "Could not parse snapshot path from API response."
        log_error "Response: ${response}"
        exit 1
    fi

    local snapshot_filename
    snapshot_filename="$(basename "$snapshot_path")"

    # Determine the on-disk file size (the snapshot lives inside the container;
    # map it to the host STORAGE_PATH if possible).
    local snapshots_dir="${storage_path}/snapshots"
    local host_snapshot="${snapshots_dir}/${snapshot_filename}"

    if [[ -f "$host_snapshot" ]]; then
        local file_size
        file_size="$(du -h "$host_snapshot" | cut -f1)"
        log_success "Snapshot created: ${snapshot_filename} (${file_size})"
    else
        log_success "Snapshot created: ${snapshot_filename}"
        log_info "Container path: ${snapshot_path}"
    fi

    log_info "API response: ${response}"

    # Optionally trigger pruning
    if [[ "$do_prune" == "true" ]]; then
        log_info "Running post-creation snapshot prune..."
        if [[ -x "${SCRIPT_DIR}/prune.sh" ]]; then
            "${SCRIPT_DIR}/prune.sh" "$conf"
        else
            log_warn "prune.sh not found or not executable at ${SCRIPT_DIR}/prune.sh"
        fi
    fi
}

main "$@"
