#!/bin/bash
set -euo pipefail

# =============================================================================
# Libre Node — Health Check Monitor
# =============================================================================
# Monitors node health and sends webhook alerts when issues are detected.
#
# Usage:
#   health-check.sh [options] [path/to/node.conf]
#
# Options:
#   --once          Run a single check and exit (for cron usage)
#   --interval N    Check every N seconds (default: 60)
#   --help          Show this help message
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
# Thresholds
# ---------------------------------------------------------------------------
MAX_HEAD_BLOCK_AGE=30   # seconds — if head block is older, node is falling behind
MIN_PEER_COUNT=2        # if fewer peers, warn

# ---------------------------------------------------------------------------
# show_help
# ---------------------------------------------------------------------------
show_help() {
    echo "Libre Node — Health Check Monitor"
    echo ""
    echo "Usage: $(basename "$0") [options] [path/to/node.conf]"
    echo ""
    echo "Options:"
    echo "  --once          Run a single check and exit (for cron usage)"
    echo "  --interval N    Check every N seconds (default: 60)"
    echo "  --help          Show this help message"
}

# ---------------------------------------------------------------------------
# send_alert — send webhook notification
# ---------------------------------------------------------------------------
send_alert() {
    local message="$1"

    if [[ "${WEBHOOK_ENABLED}" != "true" ]]; then
        return 0
    fi

    local payload
    local alert_title="Libre Node Alert: ${CONTAINER_NAME}"

    case "${WEBHOOK_TYPE}" in
        slack)
            payload="{\"text\":\"*${alert_title}*\n${message}\"}"
            ;;
        discord)
            payload="{\"content\":\"**${alert_title}**\n${message}\"}"
            ;;
        pagerduty)
            payload="{\"routing_key\":\"${WEBHOOK_URL}\",\"event_action\":\"trigger\",\"payload\":{\"summary\":\"${alert_title}: ${message}\",\"severity\":\"critical\",\"source\":\"libre-node\"}}"
            ;;
        generic|*)
            payload="{\"title\":\"${alert_title}\",\"message\":\"${message}\",\"severity\":\"critical\",\"timestamp\":\"$(date -Iseconds)\"}"
            ;;
    esac

    curl -sf -X POST "${WEBHOOK_URL}" \
        -H "Content-Type: application/json" \
        -d "$payload" > /dev/null 2>&1 || \
        log_warn "Failed to send alert to webhook"
}

# ---------------------------------------------------------------------------
# check_health — run all health checks
# ---------------------------------------------------------------------------
check_health() {
    local api_host="${BIND_IP}"
    [[ "$api_host" == "0.0.0.0" ]] && api_host="localhost"
    local api_url="http://${api_host}:${HTTP_PORT}"
    local errors=()

    # Check 1: Container running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        errors+=("Container ${CONTAINER_NAME} is not running")
    fi

    # Check 2: API responding (skip for seed nodes)
    if [[ "$NODE_ROLE" != "seed" ]]; then
        local info
        if info=$(curl -sf --max-time 10 "${api_url}/v1/chain/get_info" 2>/dev/null); then
            # Check 3: Head block age
            local head_time
            head_time=$(echo "$info" | grep -o '"head_block_time":"[^"]*"' | cut -d'"' -f4)
            if [[ -n "$head_time" ]]; then
                local head_epoch now_epoch age
                head_epoch=$(date -d "${head_time}" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${head_time%.*}" +%s 2>/dev/null || echo 0)
                now_epoch=$(date +%s)
                age=$((now_epoch - head_epoch))
                if [[ $age -gt $MAX_HEAD_BLOCK_AGE ]]; then
                    errors+=("Head block is ${age} seconds old (threshold: ${MAX_HEAD_BLOCK_AGE}s)")
                fi
            fi

            # Check 4: Peer count
            local connections
            if connections=$(curl -sf --max-time 10 "${api_url}/v1/net/connections" 2>/dev/null); then
                local peer_count
                peer_count=$(echo "$connections" | grep -c '"peer"' || echo "0")
                if [[ $peer_count -lt $MIN_PEER_COUNT ]]; then
                    errors+=("Only ${peer_count} peers connected (minimum: ${MIN_PEER_COUNT})")
                fi
            fi
        else
            errors+=("API not responding at ${api_url}")
        fi
    fi

    # Report results
    if [[ ${#errors[@]} -eq 0 ]]; then
        log_success "Health check passed"
        return 0
    else
        for err in "${errors[@]}"; do
            log_error "$err"
        done
        send_alert "${errors[*]}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    # Parse args
    local mode="loop"
    local interval=60
    local CONFIG_ARG=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --once) mode="once"; shift ;;
            --interval) interval="$2"; shift 2 ;;
            --help) show_help; exit 0 ;;
            *) CONFIG_ARG="$1"; shift ;;
        esac
    done

    # Load config
    load_config "$(find_config "${CONFIG_ARG:-}")"

    # Read all needed values
    NETWORK="$(get_config "NETWORK")"
    NODE_ROLE="$(get_config "NODE_ROLE")"
    CONTAINER_NAME="$(get_config "CONTAINER_NAME")"
    HTTP_PORT="$(get_config "HTTP_PORT")"
    BIND_IP="$(get_config "BIND_IP" "0.0.0.0")"
    WEBHOOK_ENABLED="$(get_config "WEBHOOK_ENABLED" "false")"
    WEBHOOK_TYPE="$(get_config "WEBHOOK_TYPE" "generic")"
    WEBHOOK_URL="$(get_config "WEBHOOK_URL" "")"

    if [[ "$mode" == "once" ]]; then
        check_health
    else
        log_info "Starting health monitor (interval: ${interval}s)..."
        while true; do
            check_health || true
            sleep "$interval"
        done
    fi
}

main "$@"
