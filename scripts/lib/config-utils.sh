#!/bin/bash

# =============================================================================
# Libre Node — Configuration File (node.conf) Read/Write Utilities
# =============================================================================
# node.conf is a simple key=value file (no spaces around =).
#
# Source this file from other scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/config-utils.sh"
#
# Or run directly for a quick CLI:
#   config-utils.sh get KEY [default]
#   config-utils.sh set KEY VALUE
#   config-utils.sh exists KEY
#   config-utils.sh remove KEY
#   config-utils.sh list
#   config-utils.sh backup
#   config-utils.sh new /path/to/node.conf
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Source common.sh for logging
# ---------------------------------------------------------------------------
_CONFIG_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_CONFIG_UTILS_DIR}/common.sh"

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------
CONFIG_FILE=""

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

# load_config "path/to/node.conf"
# Sources the config file into the environment and records the path for
# subsequent get/set/remove operations.
load_config() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        log_error "Configuration file not found: ${path}"
        return 1
    fi

    CONFIG_FILE="$path"

    # Source the file so variables are available in the caller's environment.
    # We use set +u temporarily because the config file may reference unset vars.
    set +u
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    set -u

    log_debug "Loaded configuration from ${CONFIG_FILE}"
}

# get_config "KEY" "default"
# Returns the value of KEY from the loaded config file, or default if not set.
# Reads directly from the file (not environment) for accuracy.
get_config() {
    local key="$1"
    local default_value="${2:-}"

    if [[ -z "$CONFIG_FILE" || ! -f "$CONFIG_FILE" ]]; then
        echo "$default_value"
        return 0
    fi

    local value
    value="$(grep -E "^${key}=" "$CONFIG_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2-)"

    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default_value"
    fi
}

# set_config "KEY" "VALUE"
# Writes or updates KEY=VALUE in the config file.
# If the key already exists, replaces the line. Otherwise appends.
set_config() {
    local key="$1"
    local value="$2"

    if [[ -z "$CONFIG_FILE" ]]; then
        log_error "No configuration file loaded. Call load_config first."
        return 1
    fi

    if grep -qE "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
        # Replace existing line — use a separator that won't collide with values.
        sed -i "s|^${key}=.*|${key}=${value}|" "$CONFIG_FILE"
        log_debug "Updated ${key} in ${CONFIG_FILE}"
    else
        echo "${key}=${value}" >> "$CONFIG_FILE"
        log_debug "Added ${key} to ${CONFIG_FILE}"
    fi
}

# config_exists "KEY"
# Returns 0 if KEY exists in the config file, 1 otherwise.
config_exists() {
    local key="$1"

    if [[ -z "$CONFIG_FILE" || ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi

    grep -qE "^${key}=" "$CONFIG_FILE" 2>/dev/null
}

# remove_config "KEY"
# Removes KEY from the config file.
remove_config() {
    local key="$1"

    if [[ -z "$CONFIG_FILE" ]]; then
        log_error "No configuration file loaded. Call load_config first."
        return 1
    fi

    if grep -qE "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
        sed -i "/^${key}=/d" "$CONFIG_FILE"
        log_debug "Removed ${key} from ${CONFIG_FILE}"
    else
        log_warn "Key '${key}' not found in ${CONFIG_FILE}"
    fi
}

# list_config
# Prints all key=value pairs from the config file (skipping comments and blanks).
list_config() {
    if [[ -z "$CONFIG_FILE" || ! -f "$CONFIG_FILE" ]]; then
        log_error "No configuration file loaded. Call load_config first."
        return 1
    fi

    grep -vE '^\s*(#|$)' "$CONFIG_FILE" || true
}

# backup_config
# Copies the config file to config_file.bak.TIMESTAMP.
backup_config() {
    if [[ -z "$CONFIG_FILE" || ! -f "$CONFIG_FILE" ]]; then
        log_error "No configuration file loaded. Call load_config first."
        return 1
    fi

    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local backup_path="${CONFIG_FILE}.bak.${timestamp}"

    cp "$CONFIG_FILE" "$backup_path"
    log_info "Configuration backed up to ${backup_path}"
    echo "$backup_path"
}

# new_config "path/to/node.conf"
# Creates an empty config file with a header comment and sets CONFIG_FILE.
new_config() {
    local path="$1"
    local dir
    dir="$(dirname "$path")"

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi

    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    cat > "$path" <<EOF
# Libre Node Configuration
# Generated by setup wizard on ${timestamp}
EOF

    CONFIG_FILE="$path"
    log_info "Created new configuration file: ${path}"
}

# ---------------------------------------------------------------------------
# CLI mode — when executed directly
# ---------------------------------------------------------------------------
_config_utils_cli() {
    local command="${1:-}"
    shift || true

    case "$command" in
        get)
            local key="${1:-}"
            local default="${2:-}"
            if [[ -z "$key" ]]; then
                log_error "Usage: $(basename "${BASH_SOURCE[0]}") get KEY [default]"
                exit 1
            fi
            get_config "$key" "$default"
            ;;
        set)
            local key="${1:-}"
            local value="${2:-}"
            if [[ -z "$key" || -z "$value" ]]; then
                log_error "Usage: $(basename "${BASH_SOURCE[0]}") set KEY VALUE"
                exit 1
            fi
            set_config "$key" "$value"
            ;;
        exists)
            local key="${1:-}"
            if [[ -z "$key" ]]; then
                log_error "Usage: $(basename "${BASH_SOURCE[0]}") exists KEY"
                exit 1
            fi
            if config_exists "$key"; then
                echo "true"
            else
                echo "false"
                exit 1
            fi
            ;;
        remove)
            local key="${1:-}"
            if [[ -z "$key" ]]; then
                log_error "Usage: $(basename "${BASH_SOURCE[0]}") remove KEY"
                exit 1
            fi
            remove_config "$key"
            ;;
        list)
            list_config
            ;;
        backup)
            backup_config
            ;;
        new)
            local path="${1:-}"
            if [[ -z "$path" ]]; then
                log_error "Usage: $(basename "${BASH_SOURCE[0]}") new /path/to/node.conf"
                exit 1
            fi
            new_config "$path"
            ;;
        *)
            echo "Libre Node Configuration Utilities"
            echo ""
            echo "Usage: $(basename "${BASH_SOURCE[0]}") [-f CONFIG_FILE] COMMAND [ARGS...]"
            echo ""
            echo "Commands:"
            echo "  get KEY [default]   Get value of KEY from config"
            echo "  set KEY VALUE       Set KEY=VALUE in config"
            echo "  exists KEY          Check if KEY exists (exit 0=yes, 1=no)"
            echo "  remove KEY          Remove KEY from config"
            echo "  list                List all key=value pairs"
            echo "  backup              Create timestamped backup"
            echo "  new PATH            Create new empty config file"
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Source guard / CLI entry point
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Running directly — support CLI usage.
    # Allow -f CONFIG_FILE before the command.
    if [[ "${1:-}" == "-f" ]]; then
        CONFIG_FILE="${2:-}"
        if [[ -z "$CONFIG_FILE" ]]; then
            log_error "Missing config file path after -f"
            exit 1
        fi
        if [[ -f "$CONFIG_FILE" ]]; then
            load_config "$CONFIG_FILE"
        else
            # For "new" command, the file doesn't exist yet — that's fine.
            true
        fi
        shift 2
    fi
    _config_utils_cli "$@"
fi
