#!/bin/bash

# =============================================================================
# Core Node — Config Generation Integration Tests
# =============================================================================
# Feeds known node.conf inputs into generate-config.sh and verifies:
# - config.ini has correct values
# - docker-compose.yml is well-formed
# - No unresolved {{PLACEHOLDER}} tokens survive
# - Role-specific plugins are present
# - Network-specific peers are loaded
#
# Usage:
#   tests/test_config_generation.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Color output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAILURES=$((FAILURES + 1)); }

FAILURES=0

# ---------------------------------------------------------------------------
# Setup: create temporary workspace
# ---------------------------------------------------------------------------
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "========================================="
echo "Config Generation Integration Tests"
echo "========================================="
echo ""

# =============================================================================
# Test Suite 1: Full-API mainnet node
# =============================================================================
echo "--- Test Suite 1: full-api mainnet ---"

STORAGE_1="${WORK_DIR}/test-mainnet"
mkdir -p "$STORAGE_1"

cat > "${WORK_DIR}/node-mainnet.conf" <<'CONF'
NETWORK=mainnet
NODE_ROLE=full-api
CORE_VERSION=0.1.3-alpha
BIND_IP=0.0.0.0
HTTP_PORT=8888
P2P_PORT=9876
SHIP_PORT=8080
CONTAINER_NAME=core-mainnet-api
AGENT_NAME=core-mainnet-api
RESTART_POLICY=unless-stopped
CHAIN_STATE_DB_SIZE=32768
CHAIN_THREADS=4
HTTP_THREADS=6
NET_THREADS=4
MAX_CLIENTS=200
MAX_TRANSACTION_TIME=1000
LOG_PROFILE=production
STATE_IN_MEMORY=true
API_GATEWAY_ENABLED=false
FIREWALL_ENABLED=false
WEBHOOK_ENABLED=false
PROMETHEUS_ENABLED=false
S3_ENABLED=false
SNAPSHOT_INTERVAL=86400
SNAPSHOT_RETENTION=7
CONF
# Inject STORAGE_PATH dynamically (absolute path)
echo "STORAGE_PATH=${STORAGE_1}" >> "${WORK_DIR}/node-mainnet.conf"

# Run generator
"${PROJECT_DIR}/scripts/setup/generate-config.sh" "${WORK_DIR}/node-mainnet.conf"

CONFIG_INI="${STORAGE_1}/config/config.ini"
COMPOSE_YML="${STORAGE_1}/config/docker-compose.yml"
GENESIS_JSON="${STORAGE_1}/config/genesis.json"
LOGGING_JSON="${STORAGE_1}/config/logging.json"

# --- Check files were created ---
for f in "$CONFIG_INI" "$COMPOSE_YML" "$GENESIS_JSON" "$LOGGING_JSON"; do
    if [[ -f "$f" ]]; then
        pass "File created: $(basename "$f")"
    else
        fail "File missing: $f"
    fi
done

# --- Check no unresolved placeholders ---
for f in "$CONFIG_INI" "$COMPOSE_YML"; do
    if [[ -f "$f" ]]; then
        if grep -v '^#' "$f" | grep -q '{{[A-Z_]*}}'; then
            fail "Unresolved placeholders in $(basename "$f"): $(grep -v '^#' "$f" | grep -o '{{[A-Z_]*}}' | sort -u | tr '\n' ' ')"
        else
            pass "No unresolved placeholders in $(basename "$f")"
        fi
    fi
done

# --- Check config.ini content ---
if [[ -f "$CONFIG_INI" ]]; then
    # HTTP/P2P ports
    if grep -q 'http-server-address = 0.0.0.0:8888' "$CONFIG_INI"; then
        pass "config.ini: HTTP port correct"
    else
        fail "config.ini: HTTP port incorrect"
    fi

    if grep -q 'p2p-listen-endpoint = 0.0.0.0:9876' "$CONFIG_INI"; then
        pass "config.ini: P2P port correct"
    else
        fail "config.ini: P2P port incorrect"
    fi

    # full-api must have state_history_plugin
    if grep -q 'core_net::state_history_plugin' "$CONFIG_INI"; then
        pass "config.ini: state_history_plugin present for full-api"
    else
        fail "config.ini: state_history_plugin missing for full-api"
    fi

    # full-api must have chain_api_plugin
    if grep -q 'core_net::chain_api_plugin' "$CONFIG_INI"; then
        pass "config.ini: chain_api_plugin present"
    else
        fail "config.ini: chain_api_plugin missing"
    fi

    # full-api must NOT have producer_plugin
    if grep -q 'core_net::producer_plugin' "$CONFIG_INI"; then
        fail "config.ini: producer_plugin should not be present for full-api"
    else
        pass "config.ini: producer_plugin correctly absent for full-api"
    fi

    # Chain state DB size
    if grep -q 'chain-state-db-size-mb = 32768' "$CONFIG_INI"; then
        pass "config.ini: chain-state-db-size correct"
    else
        fail "config.ini: chain-state-db-size incorrect"
    fi

    # Net threads
    if grep -q 'net-threads = 4' "$CONFIG_INI"; then
        pass "config.ini: net-threads correct"
    else
        fail "config.ini: net-threads incorrect"
    fi

    # Peer addresses section exists (peers are empty when PEERS key is not set,
    # which is correct — the wizard populates PEERS from peer config files)
    if grep -q 'P2P Peer Addresses' "$CONFIG_INI"; then
        pass "config.ini: peer addresses section present"
    else
        fail "config.ini: peer addresses section missing"
    fi

    # SHiP endpoint for full-api
    if grep -q 'state-history-endpoint = 0.0.0.0:8080' "$CONFIG_INI"; then
        pass "config.ini: state-history-endpoint correct for full-api"
    else
        fail "config.ini: state-history-endpoint incorrect"
    fi
fi

# --- Check docker-compose.yml content ---
if [[ -f "$COMPOSE_YML" ]]; then
    if grep -q 'container_name: core-mainnet-api' "$COMPOSE_YML"; then
        pass "compose: container_name correct"
    else
        fail "compose: container_name incorrect"
    fi

    if grep -q 'image: core-node:0.1.3-alpha' "$COMPOSE_YML"; then
        pass "compose: image tag correct"
    else
        fail "compose: image tag incorrect"
    fi

    if grep -q 'core_netd' "$COMPOSE_YML"; then
        pass "compose: core_netd command present"
    else
        fail "compose: core_netd command missing"
    fi

    if grep -q 'network_mode: host' "$COMPOSE_YML"; then
        pass "compose: host networking"
    else
        fail "compose: host networking missing"
    fi

    # STATE_IN_MEMORY=true -> --database-map-mode locked in core_netd command
    if grep -q -- '--database-map-mode locked' "$COMPOSE_YML"; then
        pass "compose: --database-map-mode locked for STATE_IN_MEMORY=true"
    else
        fail "compose: --database-map-mode locked missing despite STATE_IN_MEMORY=true"
    fi

    # No tmpfs mount — the native mode replaces the tmpfs hack.
    if grep -q 'tmpfs' "$COMPOSE_YML"; then
        fail "compose: unexpected tmpfs mount — should use --database-map-mode locked instead"
    else
        pass "compose: no tmpfs mount (STATE_IN_MEMORY handled natively)"
    fi

    # --database-map-mode locked needs RLIMIT_MEMLOCK=unlimited in the container.
    if grep -qE 'memlock:\s*$' "$COMPOSE_YML" && grep -qE 'soft:\s*-1' "$COMPOSE_YML"; then
        pass "compose: memlock ulimit set for --database-map-mode locked"
    else
        fail "compose: memlock ulimit missing — mlock2() will fail for locked mode"
    fi
fi

# --- Check genesis.json ---
if [[ -f "$GENESIS_JSON" ]]; then
    # Mainnet genesis timestamp
    if grep -q '2022-07-04T17:44:00.000' "$GENESIS_JSON"; then
        pass "genesis.json: mainnet timestamp correct"
    else
        fail "genesis.json: wrong timestamp for mainnet"
    fi
fi

echo ""

# =============================================================================
# Test Suite 2: Producer testnet node
# =============================================================================
echo "--- Test Suite 2: producer testnet ---"

STORAGE_2="${WORK_DIR}/test-testnet"
mkdir -p "$STORAGE_2"

cat > "${WORK_DIR}/node-testnet.conf" <<CONF
NETWORK=testnet
NODE_ROLE=producer
CORE_VERSION=0.1.3-alpha
BIND_IP=127.0.0.1
HTTP_PORT=9889
P2P_PORT=9877
CONTAINER_NAME=core-testnet-producer
AGENT_NAME=core-testnet-producer
RESTART_POLICY=on-failure
CHAIN_STATE_DB_SIZE=16384
CHAIN_THREADS=2
HTTP_THREADS=2
NET_THREADS=2
MAX_CLIENTS=50
MAX_TRANSACTION_TIME=30
LOG_PROFILE=standard
STATE_IN_MEMORY=false
PRODUCER_NAME=myproducer
SIGNATURE_PROVIDER=EOS6MRyAjQq8ud7hVNYcfnVPJqcVpscN5So8BhtHuGYqET5GDW5CV=KEY:5KQwrPbwdL6PhXujxW37FSSQZ1JiwsST4cqQzDeyXtP79zkvFD3
STORAGE_PATH=${STORAGE_2}
API_GATEWAY_ENABLED=false
FIREWALL_ENABLED=false
WEBHOOK_ENABLED=false
PROMETHEUS_ENABLED=false
S3_ENABLED=false
SNAPSHOT_INTERVAL=86400
SNAPSHOT_RETENTION=7
CONF

"${PROJECT_DIR}/scripts/setup/generate-config.sh" "${WORK_DIR}/node-testnet.conf"

CONFIG_INI_2="${STORAGE_2}/config/config.ini"
GENESIS_JSON_2="${STORAGE_2}/config/genesis.json"

if [[ -f "$CONFIG_INI_2" ]]; then
    # Producer must have producer_plugin
    if grep -q 'core_net::producer_plugin' "$CONFIG_INI_2"; then
        pass "config.ini: producer_plugin present for producer role"
    else
        fail "config.ini: producer_plugin missing for producer role"
    fi

    # Producer must have producer_api_plugin
    if grep -q 'core_net::producer_api_plugin' "$CONFIG_INI_2"; then
        pass "config.ini: producer_api_plugin present"
    else
        fail "config.ini: producer_api_plugin missing"
    fi

    # Producer should NOT have state_history_plugin
    if grep -q 'core_net::state_history_plugin' "$CONFIG_INI_2"; then
        fail "config.ini: state_history_plugin should not be present for producer"
    else
        pass "config.ini: state_history_plugin correctly absent for producer"
    fi

    # Bind IP should be localhost
    if grep -q 'http-server-address = 127.0.0.1:9889' "$CONFIG_INI_2"; then
        pass "config.ini: producer bound to localhost"
    else
        fail "config.ini: producer not bound to localhost"
    fi

    # Producer name should be set
    if grep -q 'producer-name = myproducer' "$CONFIG_INI_2"; then
        pass "config.ini: producer-name set"
    else
        fail "config.ini: producer-name missing"
    fi
fi

# Testnet genesis timestamp
if [[ -f "$GENESIS_JSON_2" ]]; then
    if grep -q '2022-07-13T12:20:00.000' "$GENESIS_JSON_2"; then
        pass "genesis.json: testnet timestamp correct"
    else
        fail "genesis.json: wrong timestamp for testnet"
    fi
fi

echo ""

# =============================================================================
# Test Suite 3: Seed node (no HTTP port)
# =============================================================================
echo "--- Test Suite 3: seed node ---"

STORAGE_3="${WORK_DIR}/test-seed"
mkdir -p "$STORAGE_3"

cat > "${WORK_DIR}/node-seed.conf" <<CONF
NETWORK=mainnet
NODE_ROLE=seed
CORE_VERSION=0.1.3-alpha
BIND_IP=0.0.0.0
P2P_PORT=9876
CONTAINER_NAME=core-mainnet-seed
AGENT_NAME=core-mainnet-seed
RESTART_POLICY=unless-stopped
CHAIN_STATE_DB_SIZE=32768
CHAIN_THREADS=4
HTTP_THREADS=2
NET_THREADS=4
MAX_CLIENTS=250
MAX_TRANSACTION_TIME=1000
LOG_PROFILE=production
STATE_IN_MEMORY=false
STORAGE_PATH=${STORAGE_3}
API_GATEWAY_ENABLED=false
FIREWALL_ENABLED=false
WEBHOOK_ENABLED=false
PROMETHEUS_ENABLED=false
S3_ENABLED=false
SNAPSHOT_INTERVAL=86400
SNAPSHOT_RETENTION=7
CONF

"${PROJECT_DIR}/scripts/setup/generate-config.sh" "${WORK_DIR}/node-seed.conf"

CONFIG_INI_3="${STORAGE_3}/config/config.ini"

if [[ -f "$CONFIG_INI_3" ]]; then
    # Seed should NOT have chain_api_plugin
    if grep -q 'core_net::chain_api_plugin' "$CONFIG_INI_3"; then
        fail "config.ini: chain_api_plugin should not be present for seed"
    else
        pass "config.ini: chain_api_plugin correctly absent for seed"
    fi

    # Seed should have net_plugin
    if grep -q 'core_net::net_plugin' "$CONFIG_INI_3"; then
        pass "config.ini: net_plugin present for seed"
    else
        fail "config.ini: net_plugin missing for seed"
    fi
fi

echo ""

# =============================================================================
# Test Suite 4: Validate-config accepts valid config
# =============================================================================
echo "--- Test Suite 4: validate-config ---"

if "${PROJECT_DIR}/scripts/setup/validate-config.sh" "${WORK_DIR}/node-mainnet.conf" &>/dev/null; then
    pass "validate-config.sh accepts valid mainnet config"
else
    fail "validate-config.sh rejected valid mainnet config"
fi

if "${PROJECT_DIR}/scripts/setup/validate-config.sh" "${WORK_DIR}/node-testnet.conf" &>/dev/null; then
    pass "validate-config.sh accepts valid testnet config"
else
    fail "validate-config.sh rejected valid testnet config"
fi

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "========================================="
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}All config generation tests passed${NC}"
else
    echo -e "${RED}${FAILURES} test(s) failed${NC}"
fi
echo "========================================="

exit "$FAILURES"
