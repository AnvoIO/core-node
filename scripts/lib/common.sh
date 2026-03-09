#!/bin/bash

# =============================================================================
# Libre Node — Shared Utility Functions
# =============================================================================
# Source this file from other scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Script directory resolution
# ---------------------------------------------------------------------------
_COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$_COMMON_LIB_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Source guard — warn on direct execution (allow sourcing from other scripts)
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    echo "Usage: source ${BASH_SOURCE[0]}" >&2
    exit 1
fi

# Prevent double-sourcing
if [[ "${_COMMON_SH_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_COMMON_SH_LOADED="true"

# ---------------------------------------------------------------------------
# Color codes
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Logging functions
# ---------------------------------------------------------------------------

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

log_header() {
    echo ""
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo ""
}

# ---------------------------------------------------------------------------
# User prompt helpers
# ---------------------------------------------------------------------------

# ask_yes_no "question" "default"
# Returns 0 for yes, 1 for no.
# Default is "y" or "n" (case-insensitive). If omitted, defaults to "y".
ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local hint

    default="$(echo "$default" | tr '[:upper:]' '[:lower:]')"
    if [[ "$default" == "y" ]]; then
        hint="[Y/n]"
    else
        hint="[y/N]"
    fi

    while true; do
        read -rp "$(echo -e "${CYAN}?${NC} ${prompt} ${hint}: ")" answer
        answer="$(echo "${answer:-$default}" | tr '[:upper:]' '[:lower:]')"
        case "$answer" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     log_warn "Please answer y or n." ;;
        esac
    done
}

# ask_input "prompt" "default"
# Reads a line of input and echoes it. Returns default if empty.
ask_input() {
    local prompt="$1"
    local default="${2:-}"
    local hint=""

    if [[ -n "$default" ]]; then
        hint=" (default: ${default})"
    fi

    read -rp "$(echo -e "${CYAN}?${NC} ${prompt}${hint}: ")" answer
    echo "${answer:-$default}"
}

# ask_choice "prompt" choices_array default_index
# Presents a numbered menu. Returns the selected value on stdout.
# choices_array is the name of a bash array variable.
# default_index is 1-based (optional).
ask_choice() {
    local prompt="$1"
    local -n _choices=$2
    local default_index="${3:-1}"
    local count=${#_choices[@]}

    echo -e "${CYAN}?${NC} ${prompt}"
    local i
    for i in "${!_choices[@]}"; do
        local num=$((i + 1))
        local marker="  "
        if [[ "$num" -eq "$default_index" ]]; then
            marker="->"
        fi
        echo -e "  ${marker} ${num}) ${_choices[$i]}"
    done

    while true; do
        read -rp "$(echo -e "  Enter choice [1-${count}] (default: ${default_index}): ")" answer
        answer="${answer:-$default_index}"

        if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= count )); then
            echo "${_choices[$((answer - 1))]}"
            return 0
        fi
        log_warn "Invalid selection. Please enter a number between 1 and ${count}."
    done
}

# ask_multi_select "prompt" choices_array
# Presents a checkboxed list. User toggles items by number, confirms with empty enter.
# Returns selected items on stdout, one per line.
ask_multi_select() {
    local prompt="$1"
    local -n _ms_choices=$2
    local count=${#_ms_choices[@]}

    # Track selected state (0 = unselected, 1 = selected)
    local -a selected=()
    local i
    for (( i = 0; i < count; i++ )); do
        selected+=("0")
    done

    echo -e "${CYAN}?${NC} ${prompt}"
    echo "  Toggle items by entering their number. Press Enter with no input to confirm."

    while true; do
        echo ""
        for i in "${!_ms_choices[@]}"; do
            local num=$((i + 1))
            local checkbox="[ ]"
            if [[ "${selected[$i]}" == "1" ]]; then
                checkbox="[x]"
            fi
            echo "  ${num}) ${checkbox} ${_ms_choices[$i]}"
        done

        read -rp "  Toggle (1-${count}) or Enter to confirm: " answer

        if [[ -z "$answer" ]]; then
            # Output selected items
            for i in "${!_ms_choices[@]}"; do
                if [[ "${selected[$i]}" == "1" ]]; then
                    echo "${_ms_choices[$i]}"
                fi
            done
            return 0
        fi

        if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= count )); then
            local idx=$((answer - 1))
            if [[ "${selected[$idx]}" == "0" ]]; then
                selected[$idx]="1"
            else
                selected[$idx]="0"
            fi
        else
            log_warn "Invalid input. Enter a number between 1 and ${count}, or press Enter to confirm."
        fi
    done
}

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

# validate_ip "ip" — returns 0 if valid IPv4
validate_ip() {
    local ip="$1"
    local IFS='.'
    read -ra octets <<< "$ip"

    # Must have exactly 4 octets
    [[ ${#octets[@]} -ne 4 ]] && return 1

    local octet
    for octet in "${octets[@]}"; do
        # Must be a number, no leading zeros (except "0" itself)
        [[ ! "$octet" =~ ^[0-9]+$ ]] && return 1
        (( octet < 0 || octet > 255 )) && return 1
        # Reject leading zeros (e.g., "01", "001")
        if [[ "${#octet}" -gt 1 && "${octet:0:1}" == "0" ]]; then
            return 1
        fi
    done
    return 0
}

# validate_port "port" — returns 0 if valid port number (1-65535)
validate_port() {
    local port="$1"
    [[ ! "$port" =~ ^[0-9]+$ ]] && return 1
    (( port >= 1 && port <= 65535 ))
}

# validate_url "url" — basic URL validation
validate_url() {
    local url="$1"
    [[ "$url" =~ ^https?:// ]]
}

# validate_path "path" — returns 0 if path exists
validate_path() {
    local path="$1"
    [[ -e "$path" ]]
}

# validate_btrfs "path" — returns 0 if path is on a BTRFS filesystem
validate_btrfs() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        log_error "Path does not exist: ${path}"
        return 1
    fi

    local fstype
    fstype="$(df -T "$path" 2>/dev/null | awk 'NR==2 {print $2}')"

    if [[ "$fstype" == "btrfs" ]]; then
        return 0
    fi
    return 1
}

# validate_not_empty "value" "field_name" — returns 0 if not empty
validate_not_empty() {
    local value="$1"
    local field_name="$2"

    if [[ -z "$value" ]]; then
        log_error "${field_name} cannot be empty."
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

# detect_interfaces — lists network interfaces and their IPs
# Outputs "interface_name|ip_address" per line
detect_interfaces() {
    local iface ip_addr
    while IFS= read -r line; do
        iface="$(echo "$line" | awk '{print $2}' | tr -d ':')"
        ip_addr="$(ip -4 addr show dev "$iface" 2>/dev/null \
            | awk '/inet / {print $2}' | cut -d'/' -f1 | head -n1)"
        if [[ -n "$ip_addr" ]]; then
            echo "${iface}|${ip_addr}"
        fi
    done < <(ip -o link show | grep -v 'lo:')
}

# check_command "cmd" — returns 0 if command exists in PATH
check_command() {
    command -v "$1" &>/dev/null
}

# require_command "cmd" "install_hint" — exits with error if command not found
require_command() {
    local cmd="$1"
    local install_hint="${2:-}"

    if ! check_command "$cmd"; then
        log_error "Required command '${cmd}' not found."
        if [[ -n "$install_hint" ]]; then
            log_info "Install hint: ${install_hint}"
        fi
        exit 1
    fi
}

# require_root — exits if not running as root
require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "This script must be run as root (or with sudo)."
        exit 1
    fi
}

# confirm_action "description" — asks user to confirm before proceeding
confirm_action() {
    local description="$1"

    echo ""
    log_warn "About to: ${description}"
    if ! ask_yes_no "Do you want to proceed?" "n"; then
        log_info "Aborted by user."
        exit 0
    fi
}
