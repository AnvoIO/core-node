#!/bin/bash

# =============================================================================
# Libre Node v3 — Interactive Setup Wizard
# =============================================================================
# Walks the user through configuring a Libre blockchain node and writes all
# answers to a node.conf file.  Run with --help for usage information.
#
# Make executable:  chmod +x scripts/setup/wizard.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Directory resolution
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Source library files
# ---------------------------------------------------------------------------
source "${PROJECT_DIR}/scripts/lib/common.sh"
source "${PROJECT_DIR}/scripts/lib/config-utils.sh"
source "${PROJECT_DIR}/scripts/lib/network-defaults.sh"

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
CONFIG_PATH="${PROJECT_DIR}/node.conf"
NON_INTERACTIVE=false

# Required keys that mark a config as "complete"
REQUIRED_KEYS=(
    NETWORK NODE_ROLE LEAP_VERSION BIND_IP P2P_PORT
    STORAGE_PATH STATE_IN_MEMORY SNAPSHOT_INTERVAL SNAPSHOT_RETENTION
    LOG_PROFILE API_GATEWAY_ENABLED FIREWALL_ENABLED WEBHOOK_ENABLED
    PROMETHEUS_ENABLED AGENT_NAME CONTAINER_NAME RESTART_POLICY
)

# ---------------------------------------------------------------------------
# Usage / help
# ---------------------------------------------------------------------------
show_help() {
    cat <<EOF
Libre Node v3 — Setup Wizard

Usage:
  $(basename "$0") [OPTIONS]

Options:
  --config PATH   Path to node.conf (default: <project>/node.conf).
                  In non-interactive mode the file is validated and, if
                  complete, generate-config.sh is called directly.
  --help          Show this help message and exit.

Examples:
  $(basename "$0")
  $(basename "$0") --config /etc/libre/node.conf
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                if [[ -z "${2:-}" ]]; then
                    log_error "--config requires a path argument."
                    exit 1
                fi
                CONFIG_PATH="$2"
                NON_INTERACTIVE=true
                shift 2
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Config completeness check
# ---------------------------------------------------------------------------
config_is_complete() {
    local key
    for key in "${REQUIRED_KEYS[@]}"; do
        if ! config_exists "$key"; then
            return 1
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# Helper: load default ports into associative-style vars
# ---------------------------------------------------------------------------
load_default_ports() {
    local network="$1"
    eval "$(get_default_ports "$network")"
}

# ---------------------------------------------------------------------------
# Helper: load default resources into current scope
# ---------------------------------------------------------------------------
load_default_resources() {
    local role="$1"
    eval "$(get_default_resources "$role")"
}

# ============================================================================
#  WIZARD SECTIONS
# ============================================================================

# ---------------------------------------------------------------------------
# 1. Network selection
# ---------------------------------------------------------------------------
section_network() {
    log_header "Network Selection"

    local prev
    prev="$(get_config NETWORK "")"
    local default_idx=1
    [[ "$prev" == "testnet" ]] && default_idx=2

    local choices=("mainnet" "testnet")
    local selection
    selection="$(ask_choice "Which network will this node join?" choices "$default_idx")"

    set_config NETWORK "$selection"
    log_success "Network set to ${selection}"
}

# ---------------------------------------------------------------------------
# 2. Node role
# ---------------------------------------------------------------------------
section_node_role() {
    log_header "Node Role"

    local prev
    prev="$(get_config NODE_ROLE "")"
    local default_idx=1
    case "$prev" in
        producer)     default_idx=1 ;;
        seed)         default_idx=2 ;;
        light-api)    default_idx=3 ;;
        full-api)     default_idx=4 ;;
        full-history) default_idx=5 ;;
    esac

    local choices=(
        "Block Producer - Produces blocks, minimal footprint"
        "Seed / P2P Relay - Relays blocks, seeds full chain to peers"
        "Light API - Serves API with partial block history"
        "Full API - Serves API with complete history + state history"
        "Full History - Complete historical data for indexers"
    )

    local selection
    selection="$(ask_choice "What role will this node perform?" choices "$default_idx")"

    local role
    case "$selection" in
        "Block Producer"*)  role="producer"     ;;
        "Seed"*)            role="seed"         ;;
        "Light API"*)       role="light-api"    ;;
        "Full API"*)        role="full-api"     ;;
        "Full History"*)    role="full-history" ;;
    esac

    set_config NODE_ROLE "$role"
    log_success "Node role set to ${role}"
}

# ---------------------------------------------------------------------------
# 3. Leap version
# ---------------------------------------------------------------------------
section_leap_version() {
    log_header "Leap Version"

    local prev
    prev="$(get_config LEAP_VERSION "")"

    # Attempt to fetch releases from GitHub
    local -a versions=()
    local github_json=""
    github_json="$(curl -s --max-time 10 \
        "https://api.github.com/repos/AntelopeIO/leap/releases" 2>/dev/null)" || true

    if [[ -n "$github_json" ]]; then
        local -a raw_tags=()
        while IFS= read -r tag; do
            # Strip leading "v" and surrounding quotes/whitespace
            tag="${tag#*: \"}"
            tag="${tag%\"*}"
            tag="${tag#v}"
            [[ -z "$tag" ]] && continue
            # Skip pre-release tags (rc, alpha, beta, dev)
            if [[ "$tag" =~ (rc|alpha|beta|dev) ]]; then
                continue
            fi
            raw_tags+=("$tag")
        done < <(echo "$github_json" | grep '"tag_name"')

        # Deduplicate and take up to 5
        local -A seen=()
        for t in "${raw_tags[@]}"; do
            if [[ -z "${seen[$t]:-}" ]]; then
                seen["$t"]=1
                versions+=("$t")
            fi
            [[ ${#versions[@]} -ge 5 ]] && break
        done
    fi

    # Build the choices array
    local -a choices=()
    local default_idx=1

    # Always include the recommended version
    choices+=("${RECOMMENDED_LEAP_VERSION} (recommended)")

    # Add GitHub versions that differ from recommended
    local added=0
    for v in "${versions[@]}"; do
        [[ "$v" == "$RECOMMENDED_LEAP_VERSION" ]] && continue
        if [[ $added -eq 0 ]]; then
            choices+=("${v} (latest)")
        else
            choices+=("${v}")
        fi
        (( added++ ))
        [[ $added -ge 3 ]] && break
    done

    # Adjust default if previous value matches a choice
    if [[ -n "$prev" ]]; then
        local i
        for i in "${!choices[@]}"; do
            if [[ "${choices[$i]}" == "${prev}"* ]]; then
                default_idx=$((i + 1))
                break
            fi
        done
    fi

    local selection
    selection="$(ask_choice "Select Leap version to install:" choices "$default_idx")"

    # Extract the version number (first space-delimited token)
    local version
    version="$(echo "$selection" | awk '{print $1}')"

    set_config LEAP_VERSION "$version"
    log_success "Leap version set to ${version}"
}

# ---------------------------------------------------------------------------
# 4. Bind IP
# ---------------------------------------------------------------------------
section_bind_ip() {
    log_header "Bind Address"

    local prev
    prev="$(get_config BIND_IP "")"

    local -a choices=("0.0.0.0 (all interfaces - public)" "127.0.0.1 (localhost only)")
    local default_idx=1

    # Detect network interfaces
    local iface_line iface_name iface_ip
    while IFS='|' read -r iface_name iface_ip; do
        [[ -z "$iface_ip" ]] && continue
        choices+=("${iface_ip} (${iface_name})")
    done < <(detect_interfaces)

    # Resolve default from previous value
    if [[ -n "$prev" ]]; then
        local i
        for i in "${!choices[@]}"; do
            if [[ "${choices[$i]}" == "${prev}"* ]]; then
                default_idx=$((i + 1))
                break
            fi
        done
    fi

    local selection
    selection="$(ask_choice "Which IP address should the node bind to?" choices "$default_idx")"

    local ip
    ip="$(echo "$selection" | awk '{print $1}')"

    set_config BIND_IP "$ip"
    log_success "Bind address set to ${ip}"
}

# ---------------------------------------------------------------------------
# 5. Ports
# ---------------------------------------------------------------------------
section_ports() {
    log_header "Port Configuration"

    local network role
    network="$(get_config NETWORK "mainnet")"
    role="$(get_config NODE_ROLE "full-api")"

    # Load default ports for the network
    local HTTP_PORT P2P_PORT SHIP_PORT
    load_default_ports "$network"

    # Override defaults with any previously saved values
    local prev_http prev_p2p prev_ship
    prev_http="$(get_config HTTP_PORT "$HTTP_PORT")"
    prev_p2p="$(get_config P2P_PORT "$P2P_PORT")"
    prev_ship="$(get_config SHIP_PORT "$SHIP_PORT")"

    # --- P2P port (always) ---
    local p2p_val
    while true; do
        p2p_val="$(ask_input "P2P port" "$prev_p2p")"
        if ! validate_port "$p2p_val"; then
            log_warn "Invalid port number. Must be 1-65535."
            continue
        fi
        if ! check_port_available "$p2p_val"; then
            log_warn "Port ${p2p_val} is already in use on this host."
            if ! ask_yes_no "Use it anyway?" "n"; then continue; fi
        fi
        break
    done
    set_config P2P_PORT "$p2p_val"

    # --- HTTP port (skip for seed) ---
    if [[ "$role" != "seed" ]]; then
        local http_val
        while true; do
            http_val="$(ask_input "HTTP API port" "$prev_http")"
            if ! validate_port "$http_val"; then
                log_warn "Invalid port number. Must be 1-65535."
                continue
            fi
            if ! check_port_available "$http_val"; then
                log_warn "Port ${http_val} is already in use on this host."
                if ! ask_yes_no "Use it anyway?" "n"; then continue; fi
            fi
            break
        done
        set_config HTTP_PORT "$http_val"
    fi

    # --- SHiP port (full-api and full-history only) ---
    if [[ "$role" == "full-api" || "$role" == "full-history" ]]; then
        local ship_val
        while true; do
            ship_val="$(ask_input "State History (SHiP) port" "$prev_ship")"
            if ! validate_port "$ship_val"; then
                log_warn "Invalid port number. Must be 1-65535."
                continue
            fi
            if ! check_port_available "$ship_val"; then
                log_warn "Port ${ship_val} is already in use on this host."
                if ! ask_yes_no "Use it anyway?" "n"; then continue; fi
            fi
            break
        done
        set_config SHIP_PORT "$ship_val"
    fi

    log_success "Ports configured"
}

# ---------------------------------------------------------------------------
# 6. Peers
# ---------------------------------------------------------------------------
section_peers() {
    log_header "P2P Peers"

    local network
    network="$(get_config NETWORK "mainnet")"

    local peers_file="${PROJECT_DIR}/config/peers-${network}.conf"

    if [[ ! -f "$peers_file" ]]; then
        log_warn "Peers file not found: ${peers_file}"
        log_warn "Skipping automatic peer loading."
    fi

    # Parse peers from config file
    local -a peer_providers=()
    local -a peer_addresses=()
    local -a peer_regions=()

    if [[ -f "$peers_file" ]]; then
        local line
        while IFS= read -r line; do
            # Skip comments and blanks
            [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
            local provider address region
            IFS='|' read -r provider address region <<< "$line"
            peer_providers+=("$provider")
            peer_addresses+=("$address")
            peer_regions+=("$region")
        done < "$peers_file"
    fi

    local total=${#peer_addresses[@]}
    if [[ $total -gt 0 ]]; then
        echo -e "  Available peers for ${BOLD}${network}${NC}:"
        echo ""
        local i
        for i in "${!peer_addresses[@]}"; do
            local num=$((i + 1))
            printf "    %2d) %-45s  %s (%s)\n" "$num" "${peer_addresses[$i]}" "${peer_providers[$i]}" "${peer_regions[$i]}"
        done
        echo ""
    fi

    # Build final peer list — start with all known peers
    local -a selected_peers=()

    if [[ $total -gt 0 ]]; then
        if ask_yes_no "Include all ${total} listed peers?" "y"; then
            selected_peers=("${peer_addresses[@]}")
        else
            # Let user pick with multi-select
            local -a display_peers=()
            for i in "${!peer_addresses[@]}"; do
                display_peers+=("${peer_addresses[$i]} (${peer_providers[$i]}, ${peer_regions[$i]})")
            done
            local ms_result
            ms_result="$(ask_multi_select "Select peers to include:" display_peers)"
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                # Extract address (first space-delimited token)
                local addr
                addr="$(echo "$line" | awk '{print $1}')"
                selected_peers+=("$addr")
            done <<< "$ms_result"
        fi
    fi

    # Custom peers
    if ask_yes_no "Add custom peer addresses?" "n"; then
        echo "  Enter peer addresses one per line (host:port). Empty line to finish."
        while true; do
            local custom
            custom="$(ask_input "Peer address" "")"
            if [[ -z "$custom" ]]; then
                break
            fi
            selected_peers+=("$custom")
        done
    fi

    # Join with commas
    local peers_csv=""
    local p
    for p in "${selected_peers[@]}"; do
        if [[ -z "$peers_csv" ]]; then
            peers_csv="$p"
        else
            peers_csv="${peers_csv},${p}"
        fi
    done

    set_config PEERS "$peers_csv"
    log_success "Configured ${#selected_peers[@]} peer(s)"
}

# ---------------------------------------------------------------------------
# 7. Storage
# ---------------------------------------------------------------------------
section_storage() {
    log_header "Storage Configuration"

    local network
    network="$(get_config NETWORK "mainnet")"

    local default_path="/data/libre-${network}"
    local prev
    prev="$(get_config STORAGE_PATH "$default_path")"

    local storage_path
    storage_path="$(ask_input "Base storage path" "$prev")"

    if [[ ! -d "$storage_path" ]]; then
        log_warn "Directory does not exist: ${storage_path}"
        if ask_yes_no "Create it now?" "y"; then
            mkdir -p "$storage_path" 2>/dev/null || {
                log_warn "Could not create directory (may need sudo). It will be created during deployment."
            }
        fi
    fi

    # Check for BTRFS
    if [[ -d "$storage_path" ]]; then
        if validate_btrfs "$storage_path"; then
            log_success "Storage path is on a BTRFS filesystem (recommended)"
        else
            log_warn "Storage path is NOT on a BTRFS filesystem."
            echo "  BTRFS is recommended for atomic snapshots and efficient backups."
            echo "  To set up BTRFS:"
            echo "    1. Create a BTRFS partition: mkfs.btrfs /dev/sdX"
            echo "    2. Mount it: mount /dev/sdX ${storage_path}"
            echo "    3. Add to /etc/fstab for persistence"
            echo ""
        fi
    fi

    set_config STORAGE_PATH "$storage_path"
    log_success "Storage path set to ${storage_path}"
}

# ---------------------------------------------------------------------------
# 8. State memory (tmpfs)
# ---------------------------------------------------------------------------
section_state_memory() {
    log_header "Chain State Storage"

    local network
    network="$(get_config NETWORK "mainnet")"

    local prev_in_mem
    prev_in_mem="$(get_config STATE_IN_MEMORY "")"
    local default_yn="y"
    [[ "$prev_in_mem" == "false" ]] && default_yn="n"

    echo "  Storing chain state in memory (tmpfs) protects SSDs from excessive"
    echo "  write wear, but data is lost on reboot and requires a snapshot restore."
    echo ""

    if ask_yes_no "Store chain state in memory (tmpfs)?" "$default_yn"; then
        set_config STATE_IN_MEMORY "true"

        # Auto-calculate tmpfs size from CHAIN_STATE_DB_SIZE + 10% headroom
        local db_size_mb
        db_size_mb="$(get_config CHAIN_STATE_DB_SIZE "")"
        if [[ -n "$db_size_mb" ]]; then
            local tmpfs_size
            tmpfs_size="$(calc_state_tmpfs_size "$db_size_mb")"
            set_config STATE_TMPFS_SIZE "$tmpfs_size"
            log_info "State tmpfs size auto-set to ${tmpfs_size} (CHAIN_STATE_DB_SIZE ${db_size_mb}MB + 10% headroom)"
        else
            log_warn "CHAIN_STATE_DB_SIZE not yet set — tmpfs size will be calculated during config generation."
        fi

        echo ""
        log_warn "With tmpfs, chain state will be lost if the server reboots."
        echo "  Ensure automatic snapshot restore is configured for recovery."
    else
        set_config STATE_IN_MEMORY "false"
    fi

    log_success "State memory configuration saved"
}

# ---------------------------------------------------------------------------
# 9. Snapshots
# ---------------------------------------------------------------------------
section_snapshots() {
    log_header "Snapshot Configuration"

    local prev_interval
    prev_interval="$(get_config SNAPSHOT_INTERVAL "")"

    # Map display labels to block counts (2 blocks/sec)
    local choices=(
        "30 minutes"
        "1 hour"
        "4 hours"
        "12 hours"
        "24 hours"
    )
    local -a block_counts=(3600 7200 28800 86400 172800)

    local default_idx=2  # 1 hour
    if [[ -n "$prev_interval" ]]; then
        local i
        for i in "${!block_counts[@]}"; do
            if [[ "${block_counts[$i]}" == "$prev_interval" ]]; then
                default_idx=$((i + 1))
                break
            fi
        done
    fi

    local selection
    selection="$(ask_choice "How often should automatic snapshots be taken?" choices "$default_idx")"

    local interval_blocks
    local i
    for i in "${!choices[@]}"; do
        if [[ "${choices[$i]}" == "$selection" ]]; then
            interval_blocks="${block_counts[$i]}"
            break
        fi
    done

    set_config SNAPSHOT_INTERVAL "$interval_blocks"

    # Retention
    local prev_retention
    prev_retention="$(get_config SNAPSHOT_RETENTION "5")"
    local retention
    retention="$(ask_input "Local snapshot retention count" "$prev_retention")"
    set_config SNAPSHOT_RETENTION "$retention"

    # Custom snapshot source
    local prev_custom_url
    prev_custom_url="$(get_config CUSTOM_SNAPSHOT_URL "")"

    local custom_url=""
    if ask_yes_no "Do you have a custom snapshot source (URL or S3 path)?" "n"; then
        custom_url="$(ask_input "Snapshot URL or S3 path" "$prev_custom_url")"
    fi
    set_config CUSTOM_SNAPSHOT_URL "$custom_url"

    log_success "Snapshot configuration saved (every ${interval_blocks} blocks, keep ${retention})"
}

# ---------------------------------------------------------------------------
# 10. Block retention (light-api only)
# ---------------------------------------------------------------------------
section_block_retention() {
    local role
    role="$(get_config NODE_ROLE "")"
    [[ "$role" != "light-api" ]] && return 0

    log_header "Block Log Retention (Light API)"

    echo "  Light API nodes retain only recent blocks to save storage."
    echo "  blocks-log-stride: number of blocks per retained block log file."
    echo "  max-retained-block-files: number of block log files to keep."
    echo ""

    local prev_stride
    prev_stride="$(get_config BLOCKS_LOG_STRIDE "250000")"
    local stride
    stride="$(ask_input "Block log stride size" "$prev_stride")"
    set_config BLOCKS_LOG_STRIDE "$stride"

    local prev_max
    prev_max="$(get_config MAX_RETAINED_BLOCK_FILES "10")"
    local max_files
    max_files="$(ask_input "Max retained block files" "$prev_max")"
    set_config MAX_RETAINED_BLOCK_FILES "$max_files"

    log_success "Block retention: stride=${stride}, max files=${max_files}"
}

# ---------------------------------------------------------------------------
# 11. S3 / remote backup
# ---------------------------------------------------------------------------
section_s3() {
    log_header "S3 / Remote Backup"

    local prev_enabled
    prev_enabled="$(get_config S3_ENABLED "")"
    local default_yn="n"
    [[ "$prev_enabled" == "true" ]] && default_yn="y"

    if ! ask_yes_no "Enable S3/S3-compatible remote backup?" "$default_yn"; then
        set_config S3_ENABLED "false"
        return 0
    fi

    set_config S3_ENABLED "true"

    # Check for rclone
    if ! check_command rclone; then
        log_warn "rclone is not installed. S3 backup requires rclone."
        echo "  Install: https://rclone.org/install/"
        if ! ask_yes_no "Continue without rclone (configure later)?" "y"; then
            set_config S3_ENABLED "false"
            return 0
        fi
    fi

    local network
    network="$(get_config NETWORK "mainnet")"

    # Rclone remote name
    local prev_remote
    prev_remote="$(get_config S3_REMOTE "libre-backup")"
    local remote_name
    remote_name="$(ask_input "Rclone remote name" "$prev_remote")"
    set_config S3_REMOTE "$remote_name"

    # Offer to run rclone config
    if check_command rclone; then
        if ask_yes_no "Configure rclone remote '${remote_name}' now?" "n"; then
            echo ""
            log_info "Launching rclone config..."
            rclone config || log_warn "rclone config exited with an error."
            echo ""
        fi
    fi

    # S3 bucket
    local prev_bucket
    prev_bucket="$(get_config S3_BUCKET "")"
    local bucket
    bucket="$(ask_input "S3 bucket name" "$prev_bucket")"
    set_config S3_BUCKET "$bucket"

    # S3 path prefix
    local prev_prefix
    prev_prefix="$(get_config S3_PREFIX "libre-${network}/")"
    local prefix
    prefix="$(ask_input "S3 path prefix" "$prev_prefix")"
    set_config S3_PREFIX "$prefix"

    # Archive type
    local prev_archive
    prev_archive="$(get_config S3_ARCHIVE_TYPE "")"
    local archive_default_idx=1
    [[ "$prev_archive" == "full" ]] && archive_default_idx=2

    local archive_choices=("Snapshots only" "Full backups (requires BTRFS)")
    local archive_selection
    archive_selection="$(ask_choice "What should be archived to S3?" archive_choices "$archive_default_idx")"

    local archive_type="snapshots"
    [[ "$archive_selection" == "Full"* ]] && archive_type="full"
    set_config S3_ARCHIVE_TYPE "$archive_type"

    log_success "S3 backup enabled: ${remote_name}:${bucket}/${prefix}"
}

# ---------------------------------------------------------------------------
# 12. Backup schedule (only if S3 enabled)
# ---------------------------------------------------------------------------
section_backup_schedule() {
    local s3_enabled
    s3_enabled="$(get_config S3_ENABLED "false")"
    [[ "$s3_enabled" != "true" ]] && return 0

    log_header "Backup Schedule"

    local prev_freq
    prev_freq="$(get_config BACKUP_FREQUENCY "")"
    local default_idx=1
    case "$prev_freq" in
        daily)  default_idx=1 ;;
        weekly) default_idx=2 ;;
        custom) default_idx=3 ;;
    esac

    local freq_choices=("daily" "weekly" "custom")
    local freq
    freq="$(ask_choice "How often should backups run?" freq_choices "$default_idx")"
    set_config BACKUP_FREQUENCY "$freq"

    local cron_expr
    case "$freq" in
        daily)
            cron_expr="0 3 * * *"
            ;;
        weekly)
            cron_expr="0 3 * * 0"
            ;;
        custom)
            local prev_cron
            prev_cron="$(get_config BACKUP_CRON "0 3 * * *")"
            cron_expr="$(ask_input "Cron expression (min hour dom mon dow)" "$prev_cron")"
            ;;
    esac
    set_config BACKUP_CRON "$cron_expr"

    # Retention
    local default_retention=7
    [[ "$freq" == "weekly" ]] && default_retention=4
    local prev_retention
    prev_retention="$(get_config BACKUP_RETENTION "$default_retention")"
    local retention
    retention="$(ask_input "Remote backup retention count" "$prev_retention")"
    set_config BACKUP_RETENTION "$retention"

    log_success "Backup schedule: ${freq} (cron: ${cron_expr}), keep ${retention}"
}

# ---------------------------------------------------------------------------
# 13. Logging
# ---------------------------------------------------------------------------
section_logging() {
    log_header "Logging Profile"

    local prev
    prev="$(get_config LOG_PROFILE "")"
    local default_idx=2
    case "$prev" in
        production) default_idx=1 ;;
        standard)   default_idx=2 ;;
        debug)      default_idx=3 ;;
        minimal)    default_idx=4 ;;
    esac

    local choices=(
        "Production (quiet)"
        "Standard (balanced)"
        "Debug (verbose)"
        "Minimal (errors only)"
    )

    local selection
    selection="$(ask_choice "Select logging profile:" choices "$default_idx")"

    local profile
    case "$selection" in
        "Production"*) profile="production" ;;
        "Standard"*)   profile="standard"   ;;
        "Debug"*)      profile="debug"      ;;
        "Minimal"*)    profile="minimal"    ;;
    esac

    set_config LOG_PROFILE "$profile"
    log_success "Logging profile set to ${profile}"
}

# ---------------------------------------------------------------------------
# 14. API Gateway (OpenResty) — TLS, API Keys, Rate Limiting, CF Tunnel
# ---------------------------------------------------------------------------
section_api_gateway() {
    local role
    role="$(get_config NODE_ROLE "")"

    # Gateway only applies to API-serving roles
    case "$role" in
        light-api|full-api|full-history) ;;
        *)
            set_config API_GATEWAY_ENABLED "false"
            set_config TLS_ENABLED "false"
            return 0
            ;;
    esac

    log_header "API Gateway (OpenResty)"

    echo "  The API gateway provides reverse proxying, TLS termination,"
    echo "  API key authentication, per-key rate limiting, and WebSocket"
    echo "  proxy for the State History (SHiP) endpoint."
    echo ""

    # --- Master enable ---
    local prev_enabled
    prev_enabled="$(get_config API_GATEWAY_ENABLED "")"
    local default_yn="n"
    [[ "$prev_enabled" == "true" ]] && default_yn="y"

    if ! ask_yes_no "Enable API gateway?" "$default_yn"; then
        set_config API_GATEWAY_ENABLED "false"
        set_config TLS_ENABLED "false"
        return 0
    fi
    set_config API_GATEWAY_ENABLED "true"

    # --- Gateway HTTP port ---
    local prev_gw_http
    prev_gw_http="$(get_config GATEWAY_HTTP_PORT "443")"
    local gw_http
    while true; do
        gw_http="$(ask_input "Public gateway HTTP port" "$prev_gw_http")"
        if ! validate_port "$gw_http"; then
            log_warn "Invalid port number. Must be 1-65535."
            continue
        fi
        if ! check_port_available "$gw_http"; then
            log_warn "Port ${gw_http} is already in use on this host."
            if ! ask_yes_no "Use it anyway?" "n"; then continue; fi
        fi
        break
    done
    set_config GATEWAY_HTTP_PORT "$gw_http"

    # --- Gateway SHiP/WebSocket port (full-api/full-history only) ---
    if [[ "$role" == "full-api" || "$role" == "full-history" ]]; then
        local prev_gw_ship
        prev_gw_ship="$(get_config GATEWAY_SHIP_PORT "8443")"
        local gw_ship
        while true; do
            gw_ship="$(ask_input "Public gateway SHiP/WebSocket port" "$prev_gw_ship")"
            if ! validate_port "$gw_ship"; then
                log_warn "Invalid port number. Must be 1-65535."
                continue
            fi
            if ! check_port_available "$gw_ship"; then
                log_warn "Port ${gw_ship} is already in use on this host."
                if ! ask_yes_no "Use it anyway?" "n"; then continue; fi
            fi
            break
        done
        set_config GATEWAY_SHIP_PORT "$gw_ship"
    fi

    # --- TLS ---
    echo ""
    local prev_tls
    prev_tls="$(get_config TLS_ENABLED "")"
    local tls_default="n"
    [[ "$prev_tls" == "true" ]] && tls_default="y"

    if ask_yes_no "Enable TLS with Let's Encrypt?" "$tls_default"; then
        set_config TLS_ENABLED "true"

        local prev_domain
        prev_domain="$(get_config TLS_DOMAIN "")"
        local domain
        domain="$(ask_input "Domain name (e.g. api.libre.example.com)" "$prev_domain")"
        set_config TLS_DOMAIN "$domain"

        local prev_email
        prev_email="$(get_config TLS_EMAIL "")"
        local email
        email="$(ask_input "Let's Encrypt email" "$prev_email")"
        set_config TLS_EMAIL "$email"
    else
        set_config TLS_ENABLED "false"
    fi

    # --- API Keys ---
    echo ""
    local prev_keys
    prev_keys="$(get_config API_KEYS_ENABLED "")"
    local keys_default="y"
    [[ "$prev_keys" == "false" ]] && keys_default="n"

    if ask_yes_no "Enable API key authentication?" "$keys_default"; then
        set_config API_KEYS_ENABLED "true"

        echo "  Rate limiting is per API key. Requests beyond the limit"
        echo "  receive HTTP 429 with a Retry-After header."
        echo ""

        local prev_rps
        prev_rps="$(get_config RATE_LIMIT_RPS "10")"
        local rps
        rps="$(ask_input "Rate limit (requests/sec per key)" "$prev_rps")"
        set_config RATE_LIMIT_RPS "$rps"

        local prev_burst
        prev_burst="$(get_config RATE_LIMIT_BURST "20")"
        local burst
        burst="$(ask_input "Rate limit burst capacity" "$prev_burst")"
        set_config RATE_LIMIT_BURST "$burst"
    else
        set_config API_KEYS_ENABLED "false"
    fi

    # --- Cloudflare Zero Trust Tunnel ---
    echo ""
    local prev_cf
    prev_cf="$(get_config CF_TUNNEL_ENABLED "")"
    local cf_default="n"
    [[ "$prev_cf" == "true" ]] && cf_default="y"

    echo "  Cloudflare Zero Trust tunnels provide secure ingress without"
    echo "  opening public ports. Requires a Cloudflare tunnel token."
    echo ""

    if ask_yes_no "Enable Cloudflare Zero Trust tunnel?" "$cf_default"; then
        set_config CF_TUNNEL_ENABLED "true"

        local prev_token
        prev_token="$(get_config CF_TUNNEL_TOKEN "")"
        local token
        token="$(ask_input "Cloudflare tunnel token" "$prev_token")"
        set_config CF_TUNNEL_TOKEN "$token"
    else
        set_config CF_TUNNEL_ENABLED "false"
    fi

    log_success "API gateway configured"
}

# ---------------------------------------------------------------------------
# 15. Firewall
# ---------------------------------------------------------------------------
section_firewall() {
    log_header "Firewall"

    local prev_enabled
    prev_enabled="$(get_config FIREWALL_ENABLED "")"
    local default_yn="n"
    [[ "$prev_enabled" == "true" ]] && default_yn="y"

    if ask_yes_no "Configure firewall with docker-ufw?" "$default_yn"; then
        set_config FIREWALL_ENABLED "true"
        log_info "Firewall rules will be configured during generation."
    else
        set_config FIREWALL_ENABLED "false"
    fi

    log_success "Firewall configuration saved"
}

# ---------------------------------------------------------------------------
# 16. Monitoring
# ---------------------------------------------------------------------------
section_monitoring() {
    log_header "Monitoring & Alerts"

    # --- Webhook alerts ---
    local prev_webhook
    prev_webhook="$(get_config WEBHOOK_ENABLED "")"
    local wh_default="n"
    [[ "$prev_webhook" == "true" ]] && wh_default="y"

    if ask_yes_no "Enable webhook alerts?" "$wh_default"; then
        set_config WEBHOOK_ENABLED "true"

        local prev_type
        prev_type="$(get_config WEBHOOK_TYPE "")"
        local type_default=1
        case "$prev_type" in
            slack)     type_default=1 ;;
            discord)   type_default=2 ;;
            pagerduty) type_default=3 ;;
            generic)   type_default=4 ;;
        esac

        local type_choices=("Slack" "Discord" "PagerDuty" "Generic HTTP")
        local type_selection
        type_selection="$(ask_choice "Webhook type:" type_choices "$type_default")"

        local webhook_type
        case "$type_selection" in
            Slack)      webhook_type="slack"     ;;
            Discord)    webhook_type="discord"   ;;
            PagerDuty)  webhook_type="pagerduty" ;;
            *)          webhook_type="generic"   ;;
        esac
        set_config WEBHOOK_TYPE "$webhook_type"

        local prev_url
        prev_url="$(get_config WEBHOOK_URL "")"
        local webhook_url
        while true; do
            webhook_url="$(ask_input "Webhook URL" "$prev_url")"
            if validate_url "$webhook_url"; then
                break
            fi
            log_warn "Invalid URL. Must start with http:// or https://"
        done
        set_config WEBHOOK_URL "$webhook_url"
    else
        set_config WEBHOOK_ENABLED "false"
    fi

    echo ""

    # --- Prometheus metrics ---
    local prev_prom
    prev_prom="$(get_config PROMETHEUS_ENABLED "")"
    local prom_default="n"
    [[ "$prev_prom" == "true" ]] && prom_default="y"

    if ask_yes_no "Enable Prometheus metrics?" "$prom_default"; then
        set_config PROMETHEUS_ENABLED "true"

        local prev_prom_port
        prev_prom_port="$(get_config PROMETHEUS_PORT "9100")"
        local prom_port
        while true; do
            prom_port="$(ask_input "Prometheus metrics port" "$prev_prom_port")"
            if ! validate_port "$prom_port"; then
                log_warn "Invalid port number. Must be 1-65535."
                continue
            fi
            if ! check_port_available "$prom_port"; then
                log_warn "Port ${prom_port} is already in use on this host."
                if ! ask_yes_no "Use it anyway?" "n"; then continue; fi
            fi
            break
        done
        set_config PROMETHEUS_PORT "$prom_port"
    else
        set_config PROMETHEUS_ENABLED "false"
    fi

    log_success "Monitoring configuration saved"
}

# ---------------------------------------------------------------------------
# 17. Producer settings (producer role only)
# ---------------------------------------------------------------------------
section_producer() {
    local role
    role="$(get_config NODE_ROLE "")"
    [[ "$role" != "producer" ]] && return 0

    log_header "Block Producer Configuration"

    local prev_name
    prev_name="$(get_config PRODUCER_NAME "")"
    local producer_name
    producer_name="$(ask_input "Producer account name" "$prev_name")"
    set_config PRODUCER_NAME "$producer_name"

    echo ""
    echo "  The signature provider links your public key to the private key used"
    echo "  for block signing.  Format:"
    echo "    PUBLIC_KEY=KEY:PRIVATE_KEY"
    echo ""
    log_warn "Keep your private key secure. It will be stored in node.conf."
    echo ""

    local prev_sig
    prev_sig="$(get_config SIGNATURE_PROVIDER "")"
    local sig_provider
    sig_provider="$(ask_input "Signature provider" "$prev_sig")"
    set_config SIGNATURE_PROVIDER "$sig_provider"

    log_success "Producer configuration saved for ${producer_name}"
}

# ---------------------------------------------------------------------------
# 18. Resource tuning
# ---------------------------------------------------------------------------
section_resources() {
    log_header "Resource Tuning"

    local role
    role="$(get_config NODE_ROLE "full-api")"

    # Load defaults for this role
    local CHAIN_STATE_DB_SIZE CHAIN_THREADS HTTP_THREADS NET_THREADS MAX_CLIENTS MAX_TRANSACTION_TIME
    load_default_resources "$role"

    echo "  Default resources for role '${role}':"
    echo "    CHAIN_STATE_DB_SIZE  = ${CHAIN_STATE_DB_SIZE} MB"
    echo "    CHAIN_THREADS        = ${CHAIN_THREADS}"
    echo "    HTTP_THREADS         = ${HTTP_THREADS}"
    echo "    NET_THREADS          = ${NET_THREADS}"
    echo "    MAX_CLIENTS          = ${MAX_CLIENTS}"
    echo "    MAX_TRANSACTION_TIME = ${MAX_TRANSACTION_TIME} ms"
    echo ""

    if ask_yes_no "Customize resource settings?" "n"; then
        local val

        val="$(ask_input "Chain state DB size (MB)" "$(get_config CHAIN_STATE_DB_SIZE "$CHAIN_STATE_DB_SIZE")")"
        set_config CHAIN_STATE_DB_SIZE "$val"

        val="$(ask_input "Chain threads" "$(get_config CHAIN_THREADS "$CHAIN_THREADS")")"
        set_config CHAIN_THREADS "$val"

        val="$(ask_input "HTTP threads" "$(get_config HTTP_THREADS "$HTTP_THREADS")")"
        set_config HTTP_THREADS "$val"

        val="$(ask_input "Net threads" "$(get_config NET_THREADS "$NET_THREADS")")"
        set_config NET_THREADS "$val"

        val="$(ask_input "Max clients" "$(get_config MAX_CLIENTS "$MAX_CLIENTS")")"
        set_config MAX_CLIENTS "$val"

        val="$(ask_input "Max transaction time (ms)" "$(get_config MAX_TRANSACTION_TIME "$MAX_TRANSACTION_TIME")")"
        set_config MAX_TRANSACTION_TIME "$val"
    else
        # Apply defaults (preserve any previously customized values)
        set_config CHAIN_STATE_DB_SIZE "$(get_config CHAIN_STATE_DB_SIZE "$CHAIN_STATE_DB_SIZE")"
        set_config CHAIN_THREADS "$(get_config CHAIN_THREADS "$CHAIN_THREADS")"
        set_config HTTP_THREADS "$(get_config HTTP_THREADS "$HTTP_THREADS")"
        set_config NET_THREADS "$(get_config NET_THREADS "$NET_THREADS")"
        set_config MAX_CLIENTS "$(get_config MAX_CLIENTS "$MAX_CLIENTS")"
        set_config MAX_TRANSACTION_TIME "$(get_config MAX_TRANSACTION_TIME "$MAX_TRANSACTION_TIME")"
    fi

    log_success "Resource settings saved"
}

# ============================================================================
#  DERIVED VALUES & SUMMARY
# ============================================================================

generate_derived_values() {
    local network role log_profile
    network="$(get_config NETWORK "mainnet")"
    role="$(get_config NODE_ROLE "full-api")"
    log_profile="$(get_config LOG_PROFILE "standard")"

    # Pretty labels
    local net_label role_label
    net_label="$(echo "${network:0:1}" | tr '[:lower:]' '[:upper:]')${network:1}"
    case "$role" in
        producer)     role_label="Producer"     ;;
        seed)         role_label="Seed"         ;;
        light-api)    role_label="Light API"    ;;
        full-api)     role_label="Full API"     ;;
        full-history) role_label="Full History" ;;
        *)            role_label="$role"        ;;
    esac

    local agent_name="Libre ${net_label} ${role_label} Node"
    set_config AGENT_NAME "$agent_name"

    local container_name="libre-${network}-${role}"
    set_config CONTAINER_NAME "$container_name"

    local restart_policy="unless-stopped"
    [[ "$log_profile" == "debug" ]] && restart_policy="on-failure"
    set_config RESTART_POLICY "$restart_policy"
}

show_summary() {
    log_header "Configuration Summary"

    local key value
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        key="${line%%=*}"
        value="${line#*=}"

        # Mask sensitive values
        if [[ ( "$key" == "SIGNATURE_PROVIDER" || "$key" == "CF_TUNNEL_TOKEN" ) && -n "$value" ]]; then
            value="********(hidden)"
        fi

        printf "  ${BOLD}%-28s${NC} = %s\n" "$key" "$value"
    done < <(list_config)

    echo ""
}

# ============================================================================
#  MAIN
# ============================================================================

main() {
    parse_args "$@"

    log_header "Libre Node v3 Setup Wizard"

    # Load existing config if present
    if [[ -f "$CONFIG_PATH" ]]; then
        log_info "Loading existing configuration from ${CONFIG_PATH}"
        load_config "$CONFIG_PATH"

        # Non-interactive mode: if config is complete, skip wizard
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            if config_is_complete; then
                log_success "Configuration is complete. Skipping interactive wizard."
                if [[ -x "${SCRIPT_DIR}/generate-config.sh" ]]; then
                    log_info "Running generate-config.sh..."
                    exec "${SCRIPT_DIR}/generate-config.sh" "$CONFIG_PATH"
                else
                    log_warn "generate-config.sh not found or not executable at ${SCRIPT_DIR}/generate-config.sh"
                    log_info "Configuration file is ready at: ${CONFIG_PATH}"
                fi
                return 0
            else
                log_warn "Configuration is incomplete. Falling through to interactive mode."
            fi
        else
            log_info "Previous values will be used as defaults."
        fi
    else
        log_info "No existing configuration found. Creating new config."
        new_config "$CONFIG_PATH"
    fi

    # --- Interactive wizard sections ---

    section_network
    section_node_role
    section_leap_version
    section_bind_ip
    section_ports
    section_peers
    section_storage
    section_state_memory
    section_snapshots
    section_block_retention
    section_s3
    section_backup_schedule
    section_logging
    section_api_gateway
    section_firewall
    section_monitoring
    section_producer
    section_resources

    # Derived values
    generate_derived_values

    # Summary and confirmation
    show_summary

    if ask_yes_no "Apply this configuration and generate deployment files?" "y"; then
        log_info "Configuration saved to ${CONFIG_PATH}"

        if [[ -x "${SCRIPT_DIR}/generate-config.sh" ]]; then
            log_info "Running generate-config.sh..."
            "${SCRIPT_DIR}/generate-config.sh" "$CONFIG_PATH"
        else
            log_warn "generate-config.sh not found at ${SCRIPT_DIR}/generate-config.sh"
            log_info "You can run it manually once it is available."
        fi

        echo ""
        log_success "Setup complete!"
    else
        log_info "Configuration saved to ${CONFIG_PATH} but generation was skipped."
        log_info "Re-run the wizard or manually run generate-config.sh when ready."
    fi
}

main "$@"
