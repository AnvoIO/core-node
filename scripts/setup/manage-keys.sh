#!/bin/bash

# =============================================================================
# Core Node — API Key Manager
# =============================================================================
# Manages API keys for the OpenResty gateway.
#
# Usage:
#   manage-keys.sh [--config node.conf] COMMAND [ARGS]
#
# Commands:
#   add [LABEL]         Generate a new API key with optional label
#   remove KEY          Remove an API key
#   list                List all API keys and labels
#   rotate KEY [LABEL]  Replace a key with a new one
#   reload              Signal OpenResty to reload keys (HUP)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Directory resolution
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Source libraries
# ---------------------------------------------------------------------------
source "${PROJECT_DIR}/scripts/lib/common.sh"
source "${PROJECT_DIR}/scripts/lib/config-utils.sh"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CONF_FILE=""
COMMAND=""
COMMAND_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONF_FILE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $(basename "$0") [--config node.conf] COMMAND [ARGS]"
            echo ""
            echo "Commands:"
            echo "  add [LABEL]         Generate a new API key"
            echo "  remove KEY          Remove an API key"
            echo "  list                List all API keys"
            echo "  rotate KEY [LABEL]  Replace a key with a new one"
            echo "  reload              Signal gateway to reload keys"
            exit 0
            ;;
        *)
            if [[ -z "$COMMAND" ]]; then
                COMMAND="$1"
            else
                COMMAND_ARGS+=("$1")
            fi
            shift
            ;;
    esac
done

if [[ -z "$COMMAND" ]]; then
    log_error "No command specified. Use --help for usage."
    exit 1
fi

# ---------------------------------------------------------------------------
# Locate node.conf
# ---------------------------------------------------------------------------
if [[ -z "$CONF_FILE" ]]; then
    if [[ -f "${PWD}/node.conf" ]]; then
        CONF_FILE="${PWD}/node.conf"
    elif [[ -f "${PROJECT_DIR}/node.conf" ]]; then
        CONF_FILE="${PROJECT_DIR}/node.conf"
    else
        log_error "Cannot find node.conf. Use --config to specify path."
        exit 1
    fi
fi

load_config "$CONF_FILE"

STORAGE_PATH="$(get_config STORAGE_PATH "")"
CONTAINER_NAME="$(get_config CONTAINER_NAME "")"

if [[ -z "$STORAGE_PATH" ]]; then
    log_error "STORAGE_PATH not set in configuration."
    exit 1
fi

KEYS_FILE="${STORAGE_PATH}/config/api_keys"

# Ensure keys file exists
if [[ ! -f "$KEYS_FILE" ]]; then
    mkdir -p "$(dirname "$KEYS_FILE")"
    echo "# API Keys — one per line, format: KEY_VALUE:label" > "$KEYS_FILE"
    chmod 600 "$KEYS_FILE"
fi

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_add() {
    local label="${1:-}"
    local key
    key="$(openssl rand -hex 32)"

    if [[ -n "$label" ]]; then
        echo "${key}:${label}" >> "$KEYS_FILE"
    else
        echo "${key}" >> "$KEYS_FILE"
    fi

    log_success "API key created"
    echo ""
    echo "  Key:   ${key}"
    if [[ -n "$label" ]]; then
        echo "  Label: ${label}"
    fi
    echo ""
    log_warn "Store this key securely — it cannot be recovered."
}

cmd_remove() {
    local target_key="${1:-}"

    if [[ -z "$target_key" ]]; then
        log_error "Usage: $(basename "$0") remove KEY"
        exit 1
    fi

    # Check key exists (match full key, delimited by : or end-of-line)
    if ! grep -q "^${target_key}\(:\|$\)" "$KEYS_FILE" 2>/dev/null; then
        log_error "Key not found: ${target_key}"
        exit 1
    fi

    # Remove the line containing this key
    local tmp="${KEYS_FILE}.tmp"
    grep -v "^${target_key}\(:\|$\)" "$KEYS_FILE" > "$tmp"
    mv "$tmp" "$KEYS_FILE"
    chmod 600 "$KEYS_FILE"

    log_success "API key removed: ${target_key:0:8}..."
}

cmd_list() {
    echo ""
    printf "  %-66s  %s\n" "KEY" "LABEL"
    printf "  %-66s  %s\n" "$(printf '%0.s-' {1..64})" "$(printf '%0.s-' {1..20})"

    while IFS= read -r line; do
        # Skip comments and blanks
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue

        local key_val label
        if [[ "$line" == *:* ]]; then
            key_val="${line%%:*}"
            label="${line#*:}"
        else
            key_val="$line"
            label=""
        fi

        # Show truncated key for security
        local display_key="${key_val:0:8}...${key_val: -8}"
        printf "  %-66s  %s\n" "$display_key" "$label"
    done < "$KEYS_FILE"

    echo ""

    # Count keys
    local count
    count=$(grep -cv '^\s*\(#\|$\)' "$KEYS_FILE" 2>/dev/null || echo "0")
    log_info "Total keys: ${count}"
}

cmd_rotate() {
    local old_key="${1:-}"
    local label="${2:-}"

    if [[ -z "$old_key" ]]; then
        log_error "Usage: $(basename "$0") rotate KEY [LABEL]"
        exit 1
    fi

    # If no label provided, preserve the existing label
    if [[ -z "$label" ]]; then
        local existing_line
        existing_line="$(grep "^${old_key}" "$KEYS_FILE" 2>/dev/null || true)"
        if [[ "$existing_line" == *:* ]]; then
            label="${existing_line#*:}"
        fi
    fi

    cmd_remove "$old_key"
    cmd_add "$label"
}

cmd_reload() {
    if [[ -z "$CONTAINER_NAME" ]]; then
        log_error "CONTAINER_NAME not set in configuration."
        exit 1
    fi

    local gateway_container="${CONTAINER_NAME}-gateway"

    if ! docker ps --format '{{.Names}}' | grep -q "^${gateway_container}$"; then
        log_error "Gateway container '${gateway_container}' is not running."
        exit 1
    fi

    # Clear the Lua shared dict cache by sending HUP (causes worker reload)
    docker kill -s HUP "$gateway_container"
    log_success "Reload signal sent to ${gateway_container}"
    log_info "API keys will be re-read on next request."
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "$COMMAND" in
    add)    cmd_add "${COMMAND_ARGS[@]+"${COMMAND_ARGS[@]}"}" ;;
    remove) cmd_remove "${COMMAND_ARGS[@]+"${COMMAND_ARGS[@]}"}" ;;
    list)   cmd_list ;;
    rotate) cmd_rotate "${COMMAND_ARGS[@]+"${COMMAND_ARGS[@]}"}" ;;
    reload) cmd_reload ;;
    *)
        log_error "Unknown command: ${COMMAND}"
        echo "Use --help for usage." >&2
        exit 1
        ;;
esac
