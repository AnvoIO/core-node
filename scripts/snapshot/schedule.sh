#!/bin/bash

# =============================================================================
# Libre Node — Schedule Recurring Snapshots
# =============================================================================
# Schedules, lists, or cancels recurring snapshots via the Leap producer API.
#
# Usage:
#   schedule.sh [/path/to/node.conf] [OPTIONS]
#
# Options:
#   (no flags)   Schedule recurring snapshots using SNAPSHOT_INTERVAL from node.conf
#   --list       Show currently scheduled snapshot requests
#   --cancel     Cancel the currently scheduled snapshot
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
# build_api_url — derive the curl-friendly URL from config values
# ---------------------------------------------------------------------------
build_api_url() {
    local bind_ip="$1"
    local http_port="$2"

    local api_host="$bind_ip"
    if [[ "$api_host" == "0.0.0.0" ]]; then
        api_host="localhost"
    fi

    echo "http://${api_host}:${http_port}"
}

# ---------------------------------------------------------------------------
# check_node_responding — verify the node API is reachable
# ---------------------------------------------------------------------------
check_node_responding() {
    local api_url="$1"

    if ! curl -sf "${api_url}/v1/chain/get_info" >/dev/null 2>&1; then
        log_error "Node is not responding at ${api_url}. Is the container running?"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# schedule_snapshot — POST to producer/schedule_snapshot
# ---------------------------------------------------------------------------
do_schedule() {
    local api_url="$1"
    local snapshot_interval="$2"

    log_info "Scheduling recurring snapshots every ${snapshot_interval} blocks..."

    local response
    response=$(curl -sf -X POST "${api_url}/v1/producer/schedule_snapshot" \
        -H "Content-Type: application/json" \
        -d "{
            \"block_spacing\": ${snapshot_interval},
            \"start_block_num\": 0,
            \"end_block_num\": 0
        }" 2>&1) || {
        log_error "Failed to schedule snapshot. Is producer_api_plugin enabled?"
        exit 1
    }

    log_success "Snapshot schedule created."
    log_info "Block spacing: ${snapshot_interval}"
    log_info "API response: ${response}"
}

# ---------------------------------------------------------------------------
# list_schedules — GET producer/get_snapshot_requests
# ---------------------------------------------------------------------------
do_list() {
    local api_url="$1"

    log_info "Retrieving scheduled snapshot requests..."

    local response
    response=$(curl -sf "${api_url}/v1/producer/get_snapshot_requests" 2>&1) || {
        log_error "Failed to retrieve snapshot schedules. Is producer_api_plugin enabled?"
        exit 1
    }

    if [[ -z "$response" || "$response" == "[]" || "$response" == "{}" ]]; then
        log_info "No snapshot schedules are currently active."
    else
        log_info "Current snapshot schedules:"
        echo "$response"
    fi
}

# ---------------------------------------------------------------------------
# cancel_schedule — POST to producer/unschedule_snapshot
# ---------------------------------------------------------------------------
do_cancel() {
    local api_url="$1"
    local snapshot_interval="$2"

    log_info "Cancelling snapshot schedule (block_spacing=${snapshot_interval})..."

    local response
    response=$(curl -sf -X POST "${api_url}/v1/producer/unschedule_snapshot" \
        -H "Content-Type: application/json" \
        -d "{
            \"block_spacing\": ${snapshot_interval},
            \"start_block_num\": 0,
            \"end_block_num\": 0
        }" 2>&1) || {
        log_error "Failed to cancel snapshot schedule. Is producer_api_plugin enabled?"
        exit 1
    }

    log_success "Snapshot schedule cancelled."
    log_info "API response: ${response}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local config_path=""
    local action="schedule"   # "schedule", "list", or "cancel"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --list)
                action="list"
                shift
                ;;
            --cancel)
                action="cancel"
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [[ -z "$config_path" ]]; then
                    config_path="$1"
                fi
                shift
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

    local snapshot_interval
    snapshot_interval="$(get_config "SNAPSHOT_INTERVAL" "")"

    local node_role
    node_role="$(get_config "NODE_ROLE" "")"

    local container_name
    container_name="$(get_config "CONTAINER_NAME" "")"
    if [[ -z "$container_name" ]]; then
        log_error "CONTAINER_NAME is not set in ${conf}"
        exit 1
    fi

    # Build API URL
    local api_url
    api_url="$(build_api_url "$bind_ip" "$http_port")"

    # Verify the container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log_error "Container '${container_name}' is not running."
        exit 1
    fi

    # Verify the node is responding
    check_node_responding "$api_url" || exit 1

    case "$action" in
        schedule)
            if [[ -z "$snapshot_interval" ]]; then
                log_error "SNAPSHOT_INTERVAL is not set in ${conf}. Set it to the desired block spacing."
                exit 1
            fi
            if [[ -n "$node_role" ]]; then
                log_info "Node role: ${node_role}"
            fi
            do_schedule "$api_url" "$snapshot_interval"
            ;;
        list)
            do_list "$api_url"
            ;;
        cancel)
            if [[ -z "$snapshot_interval" ]]; then
                log_error "SNAPSHOT_INTERVAL is not set in ${conf}. Needed to identify the schedule to cancel."
                exit 1
            fi
            do_cancel "$api_url" "$snapshot_interval"
            ;;
    esac
}

main "$@"
