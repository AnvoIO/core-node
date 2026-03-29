#!/bin/bash
set -euo pipefail

# =============================================================================
# Core Node — Prometheus Metrics Exporter
# =============================================================================
# Exposes Prometheus-format metrics for node monitoring.
#
# Usage:
#   metrics.sh [options] [path/to/node.conf]
#
# Options:
#   --once          Print metrics to stdout and exit (for node_exporter
#                   textfile collector)
#   --serve         Start HTTP server on PROMETHEUS_PORT (default mode)
#   --help          Show this help message
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/config-utils.sh"

# find_config is provided by config-utils.sh

# ---------------------------------------------------------------------------
# show_help
# ---------------------------------------------------------------------------
show_help() {
    echo "Core Node — Prometheus Metrics Exporter"
    echo ""
    echo "Usage: $(basename "$0") [options] [path/to/node.conf]"
    echo ""
    echo "Options:"
    echo "  --once          Print metrics to stdout and exit"
    echo "  --serve         Start HTTP server on PROMETHEUS_PORT (default)"
    echo "  --help          Show this help message"
}

# ---------------------------------------------------------------------------
# generate_metrics — query the node and format Prometheus metrics
# ---------------------------------------------------------------------------
generate_metrics() {
    local api_host="${BIND_IP}"
    [[ "$api_host" == "0.0.0.0" ]] && api_host="localhost"
    local api_url="http://${api_host}:${HTTP_PORT}"

    local output=""
    output+="# HELP core_node_up Whether the node is up\n"
    output+="# TYPE core_node_up gauge\n"

    local info
    if info=$(curl -sf --max-time 5 "${api_url}/v1/chain/get_info" 2>/dev/null); then
        output+="core_node_up{network=\"${NETWORK}\",role=\"${NODE_ROLE}\"} 1\n"

        local head_block_num
        head_block_num=$(echo "$info" | grep -o '"head_block_num":[0-9]*' | cut -d: -f2)
        output+="# HELP core_node_head_block_num Current head block number\n"
        output+="# TYPE core_node_head_block_num gauge\n"
        output+="core_node_head_block_num{network=\"${NETWORK}\"} ${head_block_num:-0}\n"

        local lib_num
        lib_num=$(echo "$info" | grep -o '"last_irreversible_block_num":[0-9]*' | cut -d: -f2)
        output+="# HELP core_node_lib_num Last irreversible block number\n"
        output+="# TYPE core_node_lib_num gauge\n"
        output+="core_node_lib_num{network=\"${NETWORK}\"} ${lib_num:-0}\n"

        # Head block age
        local head_time
        head_time=$(echo "$info" | grep -o '"head_block_time":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$head_time" ]]; then
            local head_epoch now_epoch age
            head_epoch=$(date -d "${head_time}" +%s 2>/dev/null || echo 0)
            now_epoch=$(date +%s)
            age=$((now_epoch - head_epoch))
            output+="# HELP core_node_head_block_age_seconds Age of head block in seconds\n"
            output+="# TYPE core_node_head_block_age_seconds gauge\n"
            output+="core_node_head_block_age_seconds{network=\"${NETWORK}\"} ${age}\n"
        fi

        # Peer count
        local connections peer_count=0
        if connections=$(curl -sf --max-time 5 "${api_url}/v1/net/connections" 2>/dev/null); then
            peer_count=$(echo "$connections" | jq 'length' 2>/dev/null || echo 0)
        fi
        output+="# HELP core_node_peer_count Number of connected peers\n"
        output+="# TYPE core_node_peer_count gauge\n"
        output+="core_node_peer_count{network=\"${NETWORK}\"} ${peer_count}\n"
    else
        output+="core_node_up{network=\"${NETWORK}\",role=\"${NODE_ROLE}\"} 0\n"
    fi

    echo -e "$output"
}

# ---------------------------------------------------------------------------
# serve_metrics — serve metrics over HTTP using socat
# ---------------------------------------------------------------------------
serve_metrics() {
    require_command "socat" "apt-get install socat"

    log_info "Serving Prometheus metrics on port ${PROMETHEUS_PORT}..."

    # Each connection forks a handler that regenerates metrics fresh.
    # socat SYSTEM runs a shell for each connection; we call generate_metrics
    # and format a proper HTTP response with correct Content-Length.
    while true; do
        socat TCP-LISTEN:"${PROMETHEUS_PORT}",reuseaddr EXEC:"${BASH_SOURCE[0]} --once-http" 2>/dev/null || true
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    # Parse args
    local mode="serve"
    local CONFIG_ARG=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --once) mode="once"; shift ;;
            --once-http) mode="once-http"; shift ;;
            --serve) mode="serve"; shift ;;
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
    PROMETHEUS_PORT="$(get_config "PROMETHEUS_PORT" "9100")"

    case "$mode" in
        once)
            generate_metrics
            ;;
        once-http)
            # Internal mode: output a full HTTP response (used by serve_metrics via socat)
            local metrics
            metrics="$(generate_metrics)"
            local content_length=${#metrics}
            printf 'HTTP/1.1 200 OK\r\nContent-Type: text/plain; version=0.0.4\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' "$content_length" "$metrics"
            ;;
        serve)
            serve_metrics
            ;;
    esac
}

main "$@"
