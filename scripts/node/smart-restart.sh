#!/bin/bash
set -euo pipefail

# =============================================================================
# Core Node — Smart Restart (producer-aware)
# =============================================================================
# Restarts a producer node at the end of its signing round, so the full
# inter-round window is available for recovery before the next scheduled
# slot.
#
# Polls /v1/chain/get_info and waits until head_block_producer equals the
# target (we're in our round), then waits for it to move off the target
# (round just ended), then delegates to restart.sh. With a 21-producer
# schedule and 6 s/round this leaves ~120 s of slack before the next
# time we're due to sign.
#
# Only supports NODE_ROLE=producer. For non-producer nodes use restart.sh
# directly — there's no round to align with.
#
# Usage:
#   smart-restart.sh [path/to/node.conf]
#
# Environment:
#   PHASE1_TIMEOUT   — seconds to wait for our round to start (default 300)
#   POLL_URL         — override polling endpoint (default from HTTP_PORT)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/config-utils.sh
source "${SCRIPT_DIR}/../lib/config-utils.sh"

# ---------------------------------------------------------------------------
# head_block_producer reader. Uses python3 + json since jq isn't a baseline
# dependency in the repo's scripts. Empty string on any failure so callers
# can treat it as "unknown" and keep polling.
# ---------------------------------------------------------------------------
get_head_producer() {
    local url="$1"
    curl -s --max-time 3 "$url" 2>/dev/null \
      | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("head_block_producer",""))
except Exception:
    pass' 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_header "Core Node — Smart Restart"

    local config_path
    config_path="$(find_config "${1:-}")"
    load_config "$config_path"

    local NODE_ROLE PRODUCER_NAME BIND_IP HTTP_PORT CONTAINER_NAME
    NODE_ROLE="$(get_config NODE_ROLE)"
    PRODUCER_NAME="$(get_config PRODUCER_NAME)"
    BIND_IP="$(get_config BIND_IP 0.0.0.0)"
    HTTP_PORT="$(get_config HTTP_PORT)"
    CONTAINER_NAME="$(get_config CONTAINER_NAME)"

    if [[ "$NODE_ROLE" != "producer" ]]; then
        log_error "smart-restart only applies to NODE_ROLE=producer (got '${NODE_ROLE}')."
        log_info  "For non-producer roles there's no signing round to align with — use restart.sh instead."
        exit 1
    fi

    validate_not_empty "$PRODUCER_NAME"  "PRODUCER_NAME"
    validate_not_empty "$HTTP_PORT"      "HTTP_PORT"
    validate_not_empty "$CONTAINER_NAME" "CONTAINER_NAME"

    require_command "docker"
    require_command "curl"
    require_command "python3"

    # Polling URL. Healthcheck in the generated compose uses "localhost"
    # when BIND_IP is 0.0.0.0, so match that here.
    local host="$BIND_IP"
    [[ "$host" == "0.0.0.0" ]] && host="localhost"
    local url="${POLL_URL:-http://${host}:${HTTP_PORT}/v1/chain/get_info}"

    log_info "Target:     ${PRODUCER_NAME}"
    log_info "Container:  ${CONTAINER_NAME}"
    log_info "Poll URL:   ${url}"

    # Sanity check — must be able to reach the node right now, otherwise
    # phase 1 will block until the timeout with no useful signal.
    if [[ -z "$(get_head_producer "$url")" ]]; then
        log_error "Could not read head_block_producer from ${url} — is the container running and healthy?"
        exit 2
    fi

    # -----------------------------------------------------------------------
    # Phase 1 — wait for our round to begin. On a 21-producer rotation at
    # 6 s/round the full cycle is ~126 s, so the default 300 s ceiling
    # covers two full rotations with margin. If the node isn't on the
    # active schedule, Phase 1 will legitimately time out — bail rather
    # than block forever.
    # -----------------------------------------------------------------------
    local phase1_timeout="${PHASE1_TIMEOUT:-300}"
    log_info "Phase 1: waiting for head_block_producer=${PRODUCER_NAME} (timeout ${phase1_timeout}s)..."
    local deadline=$(( $(date +%s) + phase1_timeout ))
    while :; do
        if [[ "$(get_head_producer "$url")" == "$PRODUCER_NAME" ]]; then
            log_success "In round."
            break
        fi
        if (( $(date +%s) >= deadline )); then
            log_error "Phase 1 timeout — ${PRODUCER_NAME} never became head_block_producer within ${phase1_timeout}s."
            log_info  "Producer may not be on the active schedule. Inspect with 'get_producer_schedule' or restart.sh to force."
            exit 3
        fi
        sleep 0.3
    done

    # -----------------------------------------------------------------------
    # Phase 2 — wait for our round to end. Poll tightly; a 12-block round
    # is ~6 s, and we want to act within a block or two of the last signed
    # block so the full inter-round window is available for recovery.
    # -----------------------------------------------------------------------
    log_info "Phase 2: waiting for round to end..."
    local next=""
    while :; do
        next="$(get_head_producer "$url")"
        if [[ -n "$next" && "$next" != "$PRODUCER_NAME" ]]; then
            log_success "Round ended — next producer is ${next}. Restarting immediately."
            break
        fi
        sleep 0.2
    done

    # -----------------------------------------------------------------------
    # Phase 3 — delegate to restart.sh and let it run stop + start with
    # the same config. Keeps the two restart entrypoints in sync without
    # duplicating compose/volume logic.
    # -----------------------------------------------------------------------
    "${SCRIPT_DIR}/restart.sh" "$config_path"
}

main "$@"
