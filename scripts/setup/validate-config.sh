#!/bin/bash

# =============================================================================
# Libre Node — Configuration Validator
# =============================================================================
# Validates a node.conf file for completeness and correctness.
#
# Usage:
#   validate-config.sh /path/to/node.conf
#
# Exit codes:
#   0 — all validations passed
#   1 — one or more validation errors found
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Script directory resolution and library sourcing
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"

# shellcheck source=../lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=../lib/config-utils.sh
source "${LIB_DIR}/config-utils.sh"
# shellcheck source=../lib/network-defaults.sh
source "${LIB_DIR}/network-defaults.sh"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CONF_FILE="${1:-}"

if [[ -z "$CONF_FILE" ]]; then
    log_error "Missing required argument: path to node.conf"
    echo "Usage: $(basename "$0") /path/to/node.conf" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Error tracking
# ---------------------------------------------------------------------------
ERROR_COUNT=0

add_error() {
    local message="$1"
    log_error "$message"
    (( ERROR_COUNT++ )) || true
}

# ---------------------------------------------------------------------------
# Validation 1: File exists and is readable
# ---------------------------------------------------------------------------
log_header "Validating Configuration"

if [[ ! -f "$CONF_FILE" ]]; then
    add_error "Configuration file not found: ${CONF_FILE}"
    # Cannot continue without the file
    echo ""
    log_error "Validation failed with ${ERROR_COUNT} error(s)."
    exit 1
fi

if [[ ! -r "$CONF_FILE" ]]; then
    add_error "Configuration file is not readable: ${CONF_FILE}"
    echo ""
    log_error "Validation failed with ${ERROR_COUNT} error(s)."
    exit 1
fi

log_info "Validating: ${CONF_FILE}"

# Load the config
load_config "$CONF_FILE"

# ---------------------------------------------------------------------------
# Helper: check that a key exists and is non-empty
# ---------------------------------------------------------------------------
require_key() {
    local key="$1"
    local value
    value="$(get_config "$key" "")"
    if [[ -z "$value" ]]; then
        add_error "Required key '${key}' is missing or empty."
    fi
}

# ---------------------------------------------------------------------------
# Validation 2: Required keys
# ---------------------------------------------------------------------------
log_info "Checking required keys..."

# Always required
ALWAYS_REQUIRED=(
    NETWORK
    NODE_ROLE
    LEAP_VERSION
    BIND_IP
    P2P_PORT
    STORAGE_PATH
    STATE_IN_MEMORY
    SNAPSHOT_INTERVAL
    SNAPSHOT_RETENTION
    LOG_PROFILE
    CONTAINER_NAME
    AGENT_NAME
    RESTART_POLICY
    TLS_ENABLED
    FIREWALL_ENABLED
    WEBHOOK_ENABLED
    PROMETHEUS_ENABLED
    S3_ENABLED
)

for key in "${ALWAYS_REQUIRED[@]}"; do
    require_key "$key"
done

# Resource tuning keys (always required)
RESOURCE_KEYS=(
    CHAIN_STATE_DB_SIZE
    CHAIN_THREADS
    HTTP_THREADS
    MAX_CLIENTS
    MAX_TRANSACTION_TIME
)

for key in "${RESOURCE_KEYS[@]}"; do
    require_key "$key"
done

# Read values for conditional checks
NODE_ROLE="$(get_config NODE_ROLE "")"
STATE_IN_MEMORY="$(get_config STATE_IN_MEMORY "false")"
S3_ENABLED="$(get_config S3_ENABLED "false")"
TLS_ENABLED="$(get_config TLS_ENABLED "false")"
WEBHOOK_ENABLED="$(get_config WEBHOOK_ENABLED "false")"
PROMETHEUS_ENABLED="$(get_config PROMETHEUS_ENABLED "false")"

# Role-dependent keys
if [[ "$NODE_ROLE" != "seed" ]]; then
    require_key "HTTP_PORT"
fi

if [[ "$NODE_ROLE" == "full-api" || "$NODE_ROLE" == "full-history" ]]; then
    require_key "SHIP_PORT"
fi

if [[ "$NODE_ROLE" == "producer" ]]; then
    require_key "PRODUCER_NAME"
    require_key "SIGNATURE_PROVIDER"
fi

if [[ "$NODE_ROLE" == "light-api" ]]; then
    require_key "BLOCKS_LOG_STRIDE"
    require_key "MAX_RETAINED_BLOCK_FILES"
fi

# Conditional feature keys
if [[ "$STATE_IN_MEMORY" == "true" ]]; then
    require_key "STATE_TMPFS_SIZE"
    require_key "BLOCKS_TMPFS_SIZE"
fi

if [[ "$S3_ENABLED" == "true" ]]; then
    require_key "S3_REMOTE"
    require_key "S3_BUCKET"
    require_key "S3_PREFIX"
    require_key "S3_ARCHIVE_TYPE"
fi

if [[ "$TLS_ENABLED" == "true" ]]; then
    require_key "TLS_DOMAIN"
    require_key "TLS_EMAIL"
fi

if [[ "$WEBHOOK_ENABLED" == "true" ]]; then
    require_key "WEBHOOK_TYPE"
    require_key "WEBHOOK_URL"
fi

if [[ "$PROMETHEUS_ENABLED" == "true" ]]; then
    require_key "PROMETHEUS_PORT"
fi

# ---------------------------------------------------------------------------
# Validation 3: NETWORK value
# ---------------------------------------------------------------------------
log_info "Checking NETWORK value..."
NETWORK="$(get_config NETWORK "")"
if [[ -n "$NETWORK" && "$NETWORK" != "mainnet" && "$NETWORK" != "testnet" ]]; then
    add_error "NETWORK must be 'mainnet' or 'testnet', got '${NETWORK}'."
fi

# ---------------------------------------------------------------------------
# Validation 4: NODE_ROLE value
# ---------------------------------------------------------------------------
log_info "Checking NODE_ROLE value..."
VALID_ROLES=("producer" "seed" "light-api" "full-api" "full-history")
ROLE_VALID=false
if [[ -n "$NODE_ROLE" ]]; then
    for role in "${VALID_ROLES[@]}"; do
        if [[ "$NODE_ROLE" == "$role" ]]; then
            ROLE_VALID=true
            break
        fi
    done
    if [[ "$ROLE_VALID" == "false" ]]; then
        add_error "NODE_ROLE must be one of: producer, seed, light-api, full-api, full-history. Got '${NODE_ROLE}'."
    fi
fi

# ---------------------------------------------------------------------------
# Validation 5: BIND_IP is a valid IP
# ---------------------------------------------------------------------------
log_info "Checking BIND_IP..."
BIND_IP="$(get_config BIND_IP "")"
if [[ -n "$BIND_IP" ]]; then
    if ! validate_ip "$BIND_IP"; then
        add_error "BIND_IP '${BIND_IP}' is not a valid IPv4 address."
    fi
fi

# ---------------------------------------------------------------------------
# Validation 6: All ports are valid
# ---------------------------------------------------------------------------
log_info "Checking port values..."

declare -A PORT_VALUES=()

check_port() {
    local key="$1"
    local value
    value="$(get_config "$key" "")"
    if [[ -n "$value" ]]; then
        if ! validate_port "$value"; then
            add_error "${key} '${value}' is not a valid port number (1-65535)."
        else
            PORT_VALUES["$key"]="$value"
        fi
    fi
}

check_port "HTTP_PORT"
check_port "P2P_PORT"
check_port "SHIP_PORT"

if [[ "$PROMETHEUS_ENABLED" == "true" ]]; then
    check_port "PROMETHEUS_PORT"
fi

# ---------------------------------------------------------------------------
# Validation 7: No port conflicts
# ---------------------------------------------------------------------------
log_info "Checking for port conflicts..."

# Collect the main service ports (HTTP, P2P, SHIP)
MAIN_PORT_KEYS=("HTTP_PORT" "P2P_PORT" "SHIP_PORT")
for (( i = 0; i < ${#MAIN_PORT_KEYS[@]}; i++ )); do
    local_key="${MAIN_PORT_KEYS[$i]}"
    local_val="${PORT_VALUES[$local_key]:-}"
    [[ -z "$local_val" ]] && continue
    for (( j = i + 1; j < ${#MAIN_PORT_KEYS[@]}; j++ )); do
        other_key="${MAIN_PORT_KEYS[$j]}"
        other_val="${PORT_VALUES[$other_key]:-}"
        [[ -z "$other_val" ]] && continue
        if [[ "$local_val" == "$other_val" ]]; then
            add_error "Port conflict: ${local_key} and ${other_key} are both set to ${local_val}."
        fi
    done
done

# ---------------------------------------------------------------------------
# Validation 8: LOG_PROFILE value
# ---------------------------------------------------------------------------
log_info "Checking LOG_PROFILE..."
LOG_PROFILE="$(get_config LOG_PROFILE "")"
if [[ -n "$LOG_PROFILE" ]]; then
    VALID_PROFILES=("production" "standard" "debug" "minimal")
    PROFILE_VALID=false
    for profile in "${VALID_PROFILES[@]}"; do
        if [[ "$LOG_PROFILE" == "$profile" ]]; then
            PROFILE_VALID=true
            break
        fi
    done
    if [[ "$PROFILE_VALID" == "false" ]]; then
        add_error "LOG_PROFILE must be one of: production, standard, debug, minimal. Got '${LOG_PROFILE}'."
    fi
fi

# ---------------------------------------------------------------------------
# Validation 9: RESTART_POLICY value
# ---------------------------------------------------------------------------
log_info "Checking RESTART_POLICY..."
RESTART_POLICY="$(get_config RESTART_POLICY "")"
if [[ -n "$RESTART_POLICY" ]]; then
    VALID_POLICIES=("unless-stopped" "on-failure" "always" "no")
    POLICY_VALID=false
    for policy in "${VALID_POLICIES[@]}"; do
        if [[ "$RESTART_POLICY" == "$policy" ]]; then
            POLICY_VALID=true
            break
        fi
    done
    if [[ "$POLICY_VALID" == "false" ]]; then
        add_error "RESTART_POLICY must be one of: unless-stopped, on-failure, always, no. Got '${RESTART_POLICY}'."
    fi
fi

# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------
echo ""
if [[ "$ERROR_COUNT" -eq 0 ]]; then
    log_success "All validations passed."
    exit 0
else
    log_error "Validation failed with ${ERROR_COUNT} error(s)."
    exit 1
fi
