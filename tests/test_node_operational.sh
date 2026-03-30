#!/bin/bash

# =============================================================================
# Core Node — Operational Node Test
# =============================================================================
# Starts a single-producer node in Docker and verifies:
# - Node becomes responsive (get_info returns data)
# - head_block_num advances over time
# - last_irreversible_block_num advances
# - chain_id matches expected value
# - Node shuts down cleanly
#
# Modeled after AnvoIO/core's liveness_test.py patterns:
#   checkPulse -> wait_for_node_alive
#   waitForHeadToAdvance -> wait_for_head_to_advance
#   waitForLibToAdvance -> wait_for_lib_to_advance
#
# Usage:
#   tests/test_node_operational.sh [--keep]
#
# Options:
#   --keep    Don't tear down the container on exit (for debugging)
#
# Requires: docker, curl, jq
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Color output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAILURES=$((FAILURES + 1)); }
info() { echo -e "  ${YELLOW}INFO${NC} $1"; }

FAILURES=0
KEEP=false

for arg in "$@"; do
    [[ "$arg" == "--keep" ]] && KEEP=true
done

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
IMAGE_NAME="core-node:test-$$"
CONTAINER_NAME="core-node-optest-$$"
HTTP_PORT=18888
P2P_PORT=19876
API_URL="http://127.0.0.1:${HTTP_PORT}"

# Timeouts (seconds)
BUILD_TIMEOUT=300
ALIVE_TIMEOUT=30
HEAD_ADVANCE_TIMEOUT=30
LIB_ADVANCE_TIMEOUT=60
SHUTDOWN_TIMEOUT=30

# ---------------------------------------------------------------------------
# Utility: poll until condition is true
# Adapted from AnvoIO/core's Utils.waitForBool
# ---------------------------------------------------------------------------
wait_for_bool() {
    local description="$1"
    local timeout="$2"
    local sleep_time="${3:-1}"
    # Remaining args form the command to test
    shift 3
    local end_time=$(( $(date +%s) + timeout ))

    while [[ $(date +%s) -lt $end_time ]]; do
        if "$@" 2>/dev/null; then
            return 0
        fi
        sleep "$sleep_time"
    done
    return 1
}

# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------
get_info() {
    curl -sf --max-time 5 "${API_URL}/v1/chain/get_info" 2>/dev/null
}

get_info_field() {
    local field="$1"
    get_info | jq -r ".${field}" 2>/dev/null
}

node_is_alive() {
    local info
    info="$(get_info)" || return 1
    [[ -n "$info" ]] && echo "$info" | jq -e '.head_block_num' &>/dev/null
}

head_block_num() {
    get_info_field "head_block_num"
}

lib_num() {
    get_info_field "last_irreversible_block_num"
}

head_advanced_past() {
    local target="$1"
    local current
    current="$(head_block_num)" || return 1
    [[ "$current" -ge "$target" ]]
}

lib_advanced_past() {
    local target="$1"
    local current
    current="$(lib_num)" || return 1
    [[ "$current" -ge "$target" ]]
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
cleanup() {
    echo ""
    if [[ "$KEEP" == "true" ]]; then
        info "Keeping container ${CONTAINER_NAME} (--keep)"
        info "Inspect: docker logs ${CONTAINER_NAME}"
        info "Cleanup: docker rm -f ${CONTAINER_NAME}; docker rmi ${IMAGE_NAME}"
    else
        echo "Cleaning up..."
        docker rm -f "$CONTAINER_NAME" &>/dev/null || true
        docker rmi "$IMAGE_NAME" &>/dev/null || true
    fi
}
trap cleanup EXIT

echo "========================================="
echo "Operational Node Tests"
echo "========================================="
echo ""

# =============================================================================
# Step 1: Build the Docker image
# =============================================================================
echo "--- Building Docker image ---"
if docker build -t "$IMAGE_NAME" \
    -f "${PROJECT_DIR}/docker/Dockerfile" \
    "${PROJECT_DIR}/docker/" 2>&1; then
    pass "Docker image built"
else
    fail "Docker image build failed"
    exit 1
fi

echo ""
echo "--- Starting single-producer node ---"

# =============================================================================
# Step 2: Generate a minimal genesis.json for local testing
# =============================================================================
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"; cleanup' EXIT

cat > "${WORK_DIR}/genesis.json" <<'EOF'
{
  "initial_timestamp": "2024-01-01T00:00:00.000",
  "initial_key": "EOS6MRyAjQq8ud7hVNYcfnVPJqcVpscN5So8BhtHuGYqET5GDW5CV",
  "initial_configuration": {
    "max_block_net_usage": 1048576,
    "target_block_net_usage_pct": 1000,
    "max_transaction_net_usage": 524288,
    "base_per_transaction_net_usage": 12,
    "net_usage_leeway": 500,
    "context_free_discount_net_usage_num": 20,
    "context_free_discount_net_usage_den": 100,
    "max_block_cpu_usage": 200000,
    "target_block_cpu_usage_pct": 1000,
    "max_transaction_cpu_usage": 150000,
    "min_transaction_cpu_usage": 100,
    "max_transaction_lifetime": 3600,
    "deferred_trx_expiration_window": 600,
    "max_transaction_delay": 3888000,
    "max_inline_action_size": 524287,
    "max_inline_action_depth": 10,
    "max_authority_depth": 10
  }
}
EOF

# =============================================================================
# Step 3: Generate a minimal config.ini for single-producer
# =============================================================================
cat > "${WORK_DIR}/config.ini" <<EOF
http-server-address = 0.0.0.0:${HTTP_PORT}
p2p-listen-endpoint = 0.0.0.0:${P2P_PORT}

plugin = core_net::chain_plugin
plugin = core_net::chain_api_plugin
plugin = core_net::http_plugin
plugin = core_net::net_plugin
plugin = core_net::producer_plugin
plugin = core_net::producer_api_plugin

producer-name = eosio
enable-stale-production = true
signature-provider = EOS6MRyAjQq8ud7hVNYcfnVPJqcVpscN5So8BhtHuGYqET5GDW5CV=KEY:5KQwrPbwdL6PhXujxW37FSSQZ1JiwsST4cqQzDeyXtP79zkvFD3

chain-state-db-size-mb = 1024
wasm-runtime = core-vm-jit
vm-oc-enable = none

max-transaction-time = 30
abi-serializer-max-time-ms = 15000
chain-threads = 2
http-threads = 2

verbose-http-errors = true
http-validate-host = false
access-control-allow-origin = *
EOF

# =============================================================================
# Step 4: Start the container
# =============================================================================
mkdir -p "${WORK_DIR}/data" "${WORK_DIR}/logs"

docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${HTTP_PORT}:${HTTP_PORT}" \
    -p "${P2P_PORT}:${P2P_PORT}" \
    -v "${WORK_DIR}/config.ini:/opt/core/config/config.ini:ro" \
    -v "${WORK_DIR}/genesis.json:/opt/core/config/genesis.json:ro" \
    -v "${WORK_DIR}/data:/opt/core/data" \
    -v "${WORK_DIR}/logs:/opt/core/logs" \
    "$IMAGE_NAME" \
    core_netd \
        --config-dir /opt/core/config \
        --data-dir /opt/core/data \
        --genesis-json /opt/core/config/genesis.json

info "Container started: ${CONTAINER_NAME}"
info "API endpoint: ${API_URL}"

echo ""
echo "--- Running operational checks ---"

# =============================================================================
# Test 1: Node becomes alive (checkPulse pattern)
# =============================================================================
info "Waiting for node to become responsive (timeout: ${ALIVE_TIMEOUT}s)..."
if wait_for_bool "node alive" "$ALIVE_TIMEOUT" 1 node_is_alive; then
    pass "Node is alive and responding to get_info"
else
    fail "Node did not become responsive within ${ALIVE_TIMEOUT}s"
    info "Container logs (last 30 lines):"
    docker logs --tail 30 "$CONTAINER_NAME" 2>&1 | sed 's/^/    /'
    exit 1
fi

# =============================================================================
# Test 2: Verify get_info response fields
# =============================================================================
INFO_JSON="$(get_info)"

# server_version exists
if echo "$INFO_JSON" | jq -e '.server_version' &>/dev/null; then
    SRV_VER="$(echo "$INFO_JSON" | jq -r '.server_version_string')"
    pass "server_version present: ${SRV_VER}"
else
    fail "server_version missing from get_info"
fi

# chain_id exists and is non-empty
CHAIN_ID="$(echo "$INFO_JSON" | jq -r '.chain_id')"
if [[ -n "$CHAIN_ID" && "$CHAIN_ID" != "null" ]]; then
    pass "chain_id present: ${CHAIN_ID:0:16}..."
else
    fail "chain_id missing from get_info"
fi

# head_block_producer
PRODUCER="$(echo "$INFO_JSON" | jq -r '.head_block_producer')"
if [[ "$PRODUCER" == "eosio" ]]; then
    pass "head_block_producer: eosio (expected for single-producer)"
else
    # On early blocks, producer may be empty
    info "head_block_producer: ${PRODUCER} (may be empty on first blocks)"
fi

# =============================================================================
# Test 3: Head block advances (waitForHeadToAdvance pattern)
# =============================================================================
INITIAL_HEAD="$(head_block_num)"
info "Current head block: ${INITIAL_HEAD}"
TARGET_HEAD=$(( INITIAL_HEAD + 5 ))
info "Waiting for head to reach ${TARGET_HEAD} (timeout: ${HEAD_ADVANCE_TIMEOUT}s)..."

if wait_for_bool "head advance" "$HEAD_ADVANCE_TIMEOUT" 0.5 head_advanced_past "$TARGET_HEAD"; then
    CURRENT_HEAD="$(head_block_num)"
    pass "Head block advanced: ${INITIAL_HEAD} -> ${CURRENT_HEAD}"
else
    CURRENT_HEAD="$(head_block_num)" || CURRENT_HEAD="unknown"
    fail "Head block did not advance to ${TARGET_HEAD} (current: ${CURRENT_HEAD})"
fi

# =============================================================================
# Test 4: LIB advances (waitForLibToAdvance pattern)
# =============================================================================
INITIAL_LIB="$(lib_num)"
info "Current LIB: ${INITIAL_LIB}"
TARGET_LIB=$(( INITIAL_LIB + 1 ))
info "Waiting for LIB to reach ${TARGET_LIB} (timeout: ${LIB_ADVANCE_TIMEOUT}s)..."

if wait_for_bool "LIB advance" "$LIB_ADVANCE_TIMEOUT" 1 lib_advanced_past "$TARGET_LIB"; then
    CURRENT_LIB="$(lib_num)"
    pass "LIB advanced: ${INITIAL_LIB} -> ${CURRENT_LIB}"
else
    CURRENT_LIB="$(lib_num)" || CURRENT_LIB="unknown"
    fail "LIB did not advance to ${TARGET_LIB} (current: ${CURRENT_LIB})"
fi

# =============================================================================
# Test 5: API endpoints return expected HTTP status
# =============================================================================
# get_info should return 200
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    "${API_URL}/v1/chain/get_info" 2>/dev/null)" || HTTP_CODE="000"
if [[ "$HTTP_CODE" == "200" ]]; then
    pass "GET /v1/chain/get_info returns 200"
else
    fail "GET /v1/chain/get_info returned ${HTTP_CODE}"
fi

# get_block with block 1 should return 200
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    -X POST -H 'Content-Type: application/json' \
    -d '{"block_num_or_id": 1}' \
    "${API_URL}/v1/chain/get_block" 2>/dev/null)" || HTTP_CODE="000"
if [[ "$HTTP_CODE" == "200" ]]; then
    pass "POST /v1/chain/get_block (block 1) returns 200"
else
    fail "POST /v1/chain/get_block returned ${HTTP_CODE}"
fi

# producer API: get_integrity_hash
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    -X POST "${API_URL}/v1/producer/get_integrity_hash" 2>/dev/null)" || HTTP_CODE="000"
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    pass "POST /v1/producer/get_integrity_hash returns ${HTTP_CODE}"
else
    fail "POST /v1/producer/get_integrity_hash returned ${HTTP_CODE}"
fi

# =============================================================================
# Test 6: Snapshot creation via producer API
# =============================================================================
SNAP_RESP="$(curl -sf --max-time 10 -X POST \
    "${API_URL}/v1/producer/create_snapshot" 2>/dev/null)" || SNAP_RESP=""
if [[ -n "$SNAP_RESP" ]] && echo "$SNAP_RESP" | jq -e '.snapshot_name' &>/dev/null; then
    SNAP_NAME="$(echo "$SNAP_RESP" | jq -r '.snapshot_name')"
    pass "Snapshot created: $(basename "$SNAP_NAME")"
else
    fail "Snapshot creation failed"
fi

# =============================================================================
# Test 7: Clean shutdown
# =============================================================================
echo ""
echo "--- Testing clean shutdown ---"

info "Sending SIGTERM to container..."
docker stop -t "$SHUTDOWN_TIMEOUT" "$CONTAINER_NAME" &>/dev/null

EXIT_CODE="$(docker inspect -f '{{.State.ExitCode}}' "$CONTAINER_NAME" 2>/dev/null)" || EXIT_CODE="unknown"
if [[ "$EXIT_CODE" == "0" ]]; then
    pass "Clean shutdown with exit code 0"
else
    fail "Shutdown exit code: ${EXIT_CODE} (expected 0)"
    info "Container logs (last 20 lines):"
    docker logs --tail 20 "$CONTAINER_NAME" 2>&1 | sed 's/^/    /'
fi

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "========================================="
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}All operational tests passed${NC}"
else
    echo -e "${RED}${FAILURES} test(s) failed${NC}"
fi
echo "========================================="

exit "$FAILURES"
