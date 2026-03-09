#!/bin/bash

# =============================================================================
# Libre Node — Network-Specific Default Values
# =============================================================================
# Provides chain IDs, default ports, genesis JSON, plugin lists, resource
# defaults, and tmpfs sizing for mainnet and testnet.
#
# Source this file from other scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/network-defaults.sh"
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Source common.sh for logging
# ---------------------------------------------------------------------------
_NETWORK_DEFAULTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_NETWORK_DEFAULTS_DIR}/common.sh"

# ---------------------------------------------------------------------------
# Source guard — prevent direct execution
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    echo "Usage: source ${BASH_SOURCE[0]}" >&2
    exit 1
fi

# Prevent double-sourcing
if [[ "${_NETWORK_DEFAULTS_SH_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_NETWORK_DEFAULTS_SH_LOADED="true"

# ---------------------------------------------------------------------------
# Recommended Leap version (update when a new version is tested)
# ---------------------------------------------------------------------------
RECOMMENDED_LEAP_VERSION="5.0.3"

# ---------------------------------------------------------------------------
# get_chain_id "network"
# ---------------------------------------------------------------------------
get_chain_id() {
    local network="$1"

    case "$network" in
        mainnet)
            echo "38b1d7815474d0bf271d659c50b579893768b3b2c3dc6a14c4be6a7b3e14f2fb"
            ;;
        testnet)
            echo "b64646740308df2ee06c6b72f34c0f7fa066d940e831f752db2006fcc2b78dee"
            ;;
        *)
            log_error "Unknown network '${network}'. Expected 'mainnet' or 'testnet'."
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# get_default_ports "network"
# Outputs: HTTP_PORT, P2P_PORT, SHIP_PORT (one KEY=VALUE per line)
# ---------------------------------------------------------------------------
get_default_ports() {
    local network="$1"

    case "$network" in
        mainnet)
            echo "HTTP_PORT=9888"
            echo "P2P_PORT=9876"
            echo "SHIP_PORT=9080"
            ;;
        testnet)
            echo "HTTP_PORT=9889"
            echo "P2P_PORT=9877"
            echo "SHIP_PORT=9081"
            ;;
        *)
            log_error "Unknown network '${network}'. Expected 'mainnet' or 'testnet'."
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# get_genesis_json "network"
# Outputs the full genesis.json content.
# ---------------------------------------------------------------------------
get_genesis_json() {
    local network="$1"

    case "$network" in
        mainnet)
            cat <<'GENESIS_EOF'
{
  "initial_timestamp": "2022-07-04T17:44:00.000",
  "initial_key": "EOS5CFq1Bd8HZV8zfDV5tKeRBJ1ibrebQibUgRgFXVeC45K6MSF4q",
  "initial_configuration": {
    "max_block_net_usage": 1048576,
    "target_block_net_usage_pct": 1000,
    "max_transaction_net_usage": 524288,
    "base_per_transaction_net_usage": 12,
    "net_usage_leeway": 500,
    "context_free_discount_net_usage_num": 20,
    "context_free_discount_net_usage_den": 100,
    "max_block_cpu_usage": 100000,
    "target_block_cpu_usage_pct": 500,
    "max_transaction_cpu_usage": 50000,
    "min_transaction_cpu_usage": 100,
    "max_transaction_lifetime": 3600,
    "deferred_trx_expiration_window": 600,
    "max_transaction_delay": 3888000,
    "max_inline_action_size": 524287,
    "max_inline_action_depth": 10,
    "max_authority_depth": 10
  }
}
GENESIS_EOF
            ;;
        testnet)
            cat <<'GENESIS_EOF'
{
  "initial_timestamp": "2022-07-13T12:20:00.000",
  "initial_key": "EOS7dNVunVzniVwyag9t6ci9a2DyegqNowsYohjiVUihEjChMBDVP",
  "initial_configuration": {
    "max_block_net_usage": 1048576,
    "target_block_net_usage_pct": 1000,
    "max_transaction_net_usage": 524288,
    "base_per_transaction_net_usage": 12,
    "net_usage_leeway": 500,
    "context_free_discount_net_usage_num": 20,
    "context_free_discount_net_usage_den": 100,
    "max_block_cpu_usage": 100000,
    "target_block_cpu_usage_pct": 500,
    "max_transaction_cpu_usage": 50000,
    "min_transaction_cpu_usage": 100,
    "max_transaction_lifetime": 3600,
    "deferred_trx_expiration_window": 600,
    "max_transaction_delay": 3888000,
    "max_inline_action_size": 524287,
    "max_inline_action_depth": 10,
    "max_authority_depth": 10
  }
}
GENESIS_EOF
            ;;
        *)
            log_error "Unknown network '${network}'. Expected 'mainnet' or 'testnet'."
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# get_default_plugins "role"
# Returns a newline-separated list of plugins for a node role.
# ---------------------------------------------------------------------------
get_default_plugins() {
    local role="$1"

    case "$role" in
        producer)
            echo "chain_plugin"
            echo "chain_api_plugin"
            echo "http_plugin"
            echo "net_plugin"
            echo "producer_plugin"
            echo "producer_api_plugin"
            ;;
        seed)
            echo "chain_plugin"
            echo "http_plugin"
            echo "net_plugin"
            ;;
        light-api)
            echo "chain_plugin"
            echo "chain_api_plugin"
            echo "http_plugin"
            echo "net_plugin"
            ;;
        full-api)
            echo "chain_plugin"
            echo "chain_api_plugin"
            echo "http_plugin"
            echo "net_plugin"
            echo "state_history_plugin"
            ;;
        full-history)
            echo "chain_plugin"
            echo "chain_api_plugin"
            echo "http_plugin"
            echo "net_plugin"
            echo "state_history_plugin"
            echo "trace_api_plugin"
            ;;
        *)
            log_error "Unknown node role '${role}'. Expected one of: producer, seed, light-api, full-api, full-history."
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# get_default_resources "role"
# Outputs resource defaults as KEY=VALUE lines.
# ---------------------------------------------------------------------------
get_default_resources() {
    local role="$1"

    case "$role" in
        producer)
            echo "CHAIN_STATE_DB_SIZE=16384"
            echo "CHAIN_THREADS=2"
            echo "HTTP_THREADS=2"
            echo "NET_THREADS=2"
            echo "MAX_CLIENTS=50"
            echo "MAX_TRANSACTION_TIME=30"
            ;;
        seed)
            echo "CHAIN_STATE_DB_SIZE=32768"
            echo "CHAIN_THREADS=4"
            echo "HTTP_THREADS=2"
            echo "NET_THREADS=6"
            echo "MAX_CLIENTS=250"
            echo "MAX_TRANSACTION_TIME=1000"
            ;;
        light-api)
            echo "CHAIN_STATE_DB_SIZE=32768"
            echo "CHAIN_THREADS=4"
            echo "HTTP_THREADS=6"
            echo "NET_THREADS=4"
            echo "MAX_CLIENTS=200"
            echo "MAX_TRANSACTION_TIME=1000"
            ;;
        full-api)
            echo "CHAIN_STATE_DB_SIZE=32768"
            echo "CHAIN_THREADS=4"
            echo "HTTP_THREADS=6"
            echo "NET_THREADS=4"
            echo "MAX_CLIENTS=200"
            echo "MAX_TRANSACTION_TIME=1000"
            ;;
        full-history)
            echo "CHAIN_STATE_DB_SIZE=65536"
            echo "CHAIN_THREADS=4"
            echo "HTTP_THREADS=6"
            echo "NET_THREADS=4"
            echo "MAX_CLIENTS=200"
            echo "MAX_TRANSACTION_TIME=1000"
            ;;
        *)
            log_error "Unknown node role '${role}'. Expected one of: producer, seed, light-api, full-api, full-history."
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# calc_state_tmpfs_size "chain_state_db_size_mb"
# Returns tmpfs size string (e.g. "18G") = CHAIN_STATE_DB_SIZE + 10% headroom.
# tmpfs is allocated on use, so the headroom costs nothing until filled.
# ---------------------------------------------------------------------------
calc_state_tmpfs_size() {
    local db_size_mb="$1"
    # Add 10% headroom, convert to GB (rounded up)
    local total_mb=$(( db_size_mb + db_size_mb / 10 ))
    local total_gb=$(( (total_mb + 1023) / 1024 ))
    echo "${total_gb}G"
}
