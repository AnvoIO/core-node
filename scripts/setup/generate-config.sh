#!/bin/bash

# =============================================================================
# Core Node — Configuration Generator
# =============================================================================
# Reads a node.conf file and generates all runtime configuration files:
#   - config.ini          (core_netd configuration)
#   - docker-compose.yml  (container orchestration)
#   - genesis.json        (chain genesis)
#   - logging.json        (logging profile)
#   - nginx.conf          (API gateway, if enabled)
#   - lua/auth.lua        (API key auth + rate limiting, if enabled)
#
# Usage:
#   generate-config.sh /path/to/node.conf [--dry-run]
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Script directory resolution and library sourcing
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=../lib/config-utils.sh
source "${LIB_DIR}/config-utils.sh"
# shellcheck source=../lib/network-defaults.sh
source "${LIB_DIR}/network-defaults.sh"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
DRY_RUN=false
CONF_FILE=""

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;
        -*)
            log_error "Unknown option: ${arg}"
            echo "Usage: $(basename "$0") /path/to/node.conf [--dry-run]" >&2
            exit 1
            ;;
        *)
            if [[ -z "$CONF_FILE" ]]; then
                CONF_FILE="$arg"
            else
                log_error "Unexpected argument: ${arg}"
                exit 1
            fi
            ;;
    esac
done

if [[ -z "$CONF_FILE" ]]; then
    log_error "Missing required argument: path to node.conf"
    echo "Usage: $(basename "$0") /path/to/node.conf [--dry-run]" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------------
load_config "$CONF_FILE"

# Read all config values into local variables
NETWORK="$(get_config NETWORK)"
NODE_ROLE="$(get_config NODE_ROLE)"
CORE_VERSION="$(get_config CORE_VERSION)"
BIND_IP="$(get_config BIND_IP)"
HTTP_PORT="$(get_config HTTP_PORT "")"
P2P_PORT="$(get_config P2P_PORT)"
SHIP_PORT="$(get_config SHIP_PORT "")"
STORAGE_PATH="$(get_config STORAGE_PATH)"
STATE_IN_MEMORY="$(get_config STATE_IN_MEMORY "false")"
LOG_PROFILE="$(get_config LOG_PROFILE "production")"
CONTAINER_NAME="$(get_config CONTAINER_NAME)"
AGENT_NAME="$(get_config AGENT_NAME)"
RESTART_POLICY="$(get_config RESTART_POLICY "unless-stopped")"
CHAIN_STATE_DB_SIZE="$(get_config CHAIN_STATE_DB_SIZE)"
CHAIN_THREADS="$(get_config CHAIN_THREADS)"
HTTP_THREADS="$(get_config HTTP_THREADS)"
NET_THREADS="$(get_config NET_THREADS "2")"
MAX_CLIENTS="$(get_config MAX_CLIENTS)"
MAX_TRANSACTION_TIME="$(get_config MAX_TRANSACTION_TIME)"
PEERS="$(get_config PEERS "")"
PRODUCER_NAME="$(get_config PRODUCER_NAME "")"
SIGNATURE_PROVIDER="$(get_config SIGNATURE_PROVIDER "")"
TLS_ENABLED="$(get_config TLS_ENABLED "false")"
TLS_DOMAIN="$(get_config TLS_DOMAIN "")"
API_GATEWAY_ENABLED="$(get_config API_GATEWAY_ENABLED "false")"
API_KEYS_ENABLED="$(get_config API_KEYS_ENABLED "false")"
RATE_LIMIT_RPS="$(get_config RATE_LIMIT_RPS "10")"
RATE_LIMIT_BURST="$(get_config RATE_LIMIT_BURST "20")"
GATEWAY_HTTP_PORT="$(get_config GATEWAY_HTTP_PORT "443")"
GATEWAY_SHIP_PORT="$(get_config GATEWAY_SHIP_PORT "8443")"
CF_TUNNEL_ENABLED="$(get_config CF_TUNNEL_ENABLED "false")"
CF_TUNNEL_TOKEN="$(get_config CF_TUNNEL_TOKEN "")"
BLOCKS_LOG_STRIDE="$(get_config BLOCKS_LOG_STRIDE "")"
MAX_RETAINED_BLOCK_FILES="$(get_config MAX_RETAINED_BLOCK_FILES "")"
TRACE_API_MODE="$(get_config TRACE_API_MODE "raw")"

# ---------------------------------------------------------------------------
# Output directory setup
# ---------------------------------------------------------------------------
OUTPUT_DIR="${STORAGE_PATH}"
CONFIG_OUTPUT_DIR="${OUTPUT_DIR}/config"
DATA_DIR="${OUTPUT_DIR}/data"
LOGS_DIR="${OUTPUT_DIR}/logs"
SNAPSHOTS_DIR="${OUTPUT_DIR}/snapshots"

if [[ "$DRY_RUN" == "true" ]]; then
    log_header "Dry Run — Configuration Preview"
    log_info "Would create directories:"
    log_info "  ${CONFIG_OUTPUT_DIR}"
    log_info "  ${DATA_DIR}"
    log_info "  ${LOGS_DIR}"
    log_info "  ${SNAPSHOTS_DIR}"
else
    mkdir -p "$CONFIG_OUTPUT_DIR" "$DATA_DIR" "$LOGS_DIR" "$SNAPSHOTS_DIR"
fi

# ---------------------------------------------------------------------------
# Helper: write or preview a file
# ---------------------------------------------------------------------------
write_file() {
    local dest="$1"
    local content="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        log_info "--- ${dest} ---"
        echo "$content"
        echo ""
    else
        echo "$content" > "$dest"
        log_info "Generated: ${dest}"
    fi
}

# =============================================================================
# Generate config.ini
# =============================================================================
log_header "Generating config.ini"

TEMPLATE_DIR="${PROJECT_DIR}/config/templates"
CONFIG_TEMPLATE="$(cat "${TEMPLATE_DIR}/config.ini.tmpl")"

# --- Build PLUGINS block ---
PLUGINS_BLOCK=""
while IFS= read -r plugin; do
    [[ -z "$plugin" ]] && continue
    PLUGINS_BLOCK+="plugin = core_net::${plugin}"$'\n'
done < <(get_default_plugins "$NODE_ROLE")
# Remove trailing newline
PLUGINS_BLOCK="${PLUGINS_BLOCK%$'\n'}"

# --- Build STATE_HISTORY_CONFIG block ---
STATE_HISTORY_BLOCK=""
if [[ "$NODE_ROLE" == "full-api" || "$NODE_ROLE" == "full-history" ]]; then
    STATE_HISTORY_BLOCK="state-history-endpoint = ${BIND_IP}:${SHIP_PORT}"$'\n'
    STATE_HISTORY_BLOCK+="trace-history = true"$'\n'
    STATE_HISTORY_BLOCK+="chain-state-history = true"$'\n'
    STATE_HISTORY_BLOCK+="state-history-dir = /opt/core/data/state-history"$'\n'
    STATE_HISTORY_BLOCK+="state-history-stride = 250000"$'\n'
    STATE_HISTORY_BLOCK+="state-history-retained-dir = retained"
    if [[ "$NODE_ROLE" == "full-history" ]]; then
        STATE_HISTORY_BLOCK+=$'\n'"trace-slice-stride = 250000"
        if [[ "$TRACE_API_MODE" == "raw" ]]; then
            STATE_HISTORY_BLOCK+=$'\n'"trace-no-abis = true"
        fi
    fi
else
    STATE_HISTORY_BLOCK="# State history not enabled for this role"
fi

# --- Build PEERS block ---
PEERS_BLOCK=""
if [[ -n "$PEERS" ]]; then
    IFS=',' read -ra PEER_LIST <<< "$PEERS"
    for peer in "${PEER_LIST[@]}"; do
        peer="$(echo "$peer" | xargs)"  # trim whitespace
        [[ -z "$peer" ]] && continue
        PEERS_BLOCK+="p2p-peer-address = ${peer}"$'\n'
    done
    PEERS_BLOCK="${PEERS_BLOCK%$'\n'}"
fi

# --- Build PRODUCER_CONFIG block ---
PRODUCER_BLOCK=""
if [[ "$NODE_ROLE" == "producer" ]]; then
    PRODUCER_BLOCK="producer-name = ${PRODUCER_NAME}"$'\n'
    PRODUCER_BLOCK+="signature-provider = ${SIGNATURE_PROVIDER}"$'\n'
    PRODUCER_BLOCK+="enable-stale-production = false"
else
    PRODUCER_BLOCK="# Producer configuration not enabled for this role"
fi

# --- Build BLOCKS_CONFIG block ---
BLOCKS_BLOCK=""
case "$NODE_ROLE" in
    producer)
        BLOCKS_BLOCK="blocks-log-stride = 100000"$'\n'
        BLOCKS_BLOCK+="max-retained-block-files = 10"
        ;;
    seed|full-api|full-history)
        BLOCKS_BLOCK="blocks-log-stride = 250000"$'\n'
        BLOCKS_BLOCK+="blocks-retained-dir = retained"
        ;;
    light-api)
        BLOCKS_BLOCK="blocks-log-stride = ${BLOCKS_LOG_STRIDE}"$'\n'
        BLOCKS_BLOCK+="max-retained-block-files = ${MAX_RETAINED_BLOCK_FILES}"$'\n'
        BLOCKS_BLOCK+="blocks-retained-dir = retained"
        ;;
esac

# --- Build ACCESS_CONTROL block ---
ACCESS_BLOCK=""
case "$NODE_ROLE" in
    light-api|full-api|full-history)
        ACCESS_BLOCK="access-control-allow-origin = *"$'\n'
        ACCESS_BLOCK+="access-control-allow-headers = *"$'\n'
        ACCESS_BLOCK+="http-validate-host = false"
        ;;
    producer)
        ACCESS_BLOCK="access-control-allow-origin = *"$'\n'
        ACCESS_BLOCK+="http-validate-host = false"
        ;;
    seed)
        ACCESS_BLOCK="http-validate-host = true"
        ;;
esac

# --- Build RESOURCE_LIMITS block ---
RESOURCE_BLOCK="http-max-response-time-ms = 12500"

# --- Perform substitutions ---
# Single-line placeholder replacements with sed
CONFIG_CONTENT="$CONFIG_TEMPLATE"
CONFIG_CONTENT="$(echo "$CONFIG_CONTENT" | sed "s|{{NETWORK}}|${NETWORK}|g")"
CONFIG_CONTENT="$(echo "$CONFIG_CONTENT" | sed "s|{{NODE_ROLE}}|${NODE_ROLE}|g")"
CONFIG_CONTENT="$(echo "$CONFIG_CONTENT" | sed "s|{{BIND_IP}}|${BIND_IP}|g")"
CONFIG_CONTENT="$(echo "$CONFIG_CONTENT" | sed "s|{{HTTP_PORT}}|${HTTP_PORT}|g")"
CONFIG_CONTENT="$(echo "$CONFIG_CONTENT" | sed "s|{{P2P_PORT}}|${P2P_PORT}|g")"
CONFIG_CONTENT="$(echo "$CONFIG_CONTENT" | sed "s|{{CHAIN_STATE_DB_SIZE}}|${CHAIN_STATE_DB_SIZE}|g")"
CONFIG_CONTENT="$(echo "$CONFIG_CONTENT" | sed "s|{{CHAIN_THREADS}}|${CHAIN_THREADS}|g")"
CONFIG_CONTENT="$(echo "$CONFIG_CONTENT" | sed "s|{{HTTP_THREADS}}|${HTTP_THREADS}|g")"
CONFIG_CONTENT="$(echo "$CONFIG_CONTENT" | sed "s|{{NET_THREADS}}|${NET_THREADS}|g")"
CONFIG_CONTENT="$(echo "$CONFIG_CONTENT" | sed "s|{{MAX_CLIENTS}}|${MAX_CLIENTS}|g")"
CONFIG_CONTENT="$(echo "$CONFIG_CONTENT" | sed "s|{{MAX_TRANSACTION_TIME}}|${MAX_TRANSACTION_TIME}|g")"
CONFIG_CONTENT="$(echo "$CONFIG_CONTENT" | sed "s|{{AGENT_NAME}}|${AGENT_NAME}|g")"

# Multi-line placeholder replacements
# Use awk for safe multi-line substitution
replace_placeholder() {
    local placeholder="$1"
    local replacement="$2"
    local input="$3"

    # Use awk to replace the placeholder line with multi-line content
    echo "$input" | awk -v placeholder="$placeholder" -v replacement="$replacement" '
        index($0, placeholder) {
            print replacement
            next
        }
        { print }
    '
}

CONFIG_CONTENT="$(replace_placeholder "{{PLUGINS}}" "$PLUGINS_BLOCK" "$CONFIG_CONTENT")"
CONFIG_CONTENT="$(replace_placeholder "{{STATE_HISTORY_CONFIG}}" "$STATE_HISTORY_BLOCK" "$CONFIG_CONTENT")"
CONFIG_CONTENT="$(replace_placeholder "{{PEERS}}" "$PEERS_BLOCK" "$CONFIG_CONTENT")"
CONFIG_CONTENT="$(replace_placeholder "{{PRODUCER_CONFIG}}" "$PRODUCER_BLOCK" "$CONFIG_CONTENT")"
CONFIG_CONTENT="$(replace_placeholder "{{BLOCKS_CONFIG}}" "$BLOCKS_BLOCK" "$CONFIG_CONTENT")"
CONFIG_CONTENT="$(replace_placeholder "{{ACCESS_CONTROL}}" "$ACCESS_BLOCK" "$CONFIG_CONTENT")"
CONFIG_CONTENT="$(replace_placeholder "{{RESOURCE_LIMITS}}" "$RESOURCE_BLOCK" "$CONFIG_CONTENT")"

# Handle enable-account-queries: true for API roles, remove for seed/producer
case "$NODE_ROLE" in
    light-api|full-api|full-history)
        # Already true in template, keep as-is
        ;;
    seed|producer)
        CONFIG_CONTENT="$(echo "$CONFIG_CONTENT" | sed 's|^enable-account-queries = true|# enable-account-queries not enabled for this role|')"
        ;;
esac

# pause-on-startup stays false for all roles — producers start producing
# immediately when registered and voted in on-chain.

write_file "${CONFIG_OUTPUT_DIR}/config.ini" "$CONFIG_CONTENT"

# =============================================================================
# Generate docker-compose.yml
# =============================================================================
log_header "Generating docker-compose.yml"

COMPOSE_TEMPLATE="$(cat "${TEMPLATE_DIR}/docker-compose.yml.tmpl")"

# Build IMAGE_NAME
IMAGE_NAME="core-node:${CORE_VERSION}"

# Build CORE_COMMAND. When STATE_IN_MEMORY is true, use the native
# --database-map-mode locked: at startup, chainbase copies shared_memory.bin
# into an anonymous mmap with huge pages (if available) and mlock2()s it so
# the chain state stays resident and cannot be swapped. On clean shutdown,
# the database is written back to the file — no external tmpfs mount
# required (see chainbase::pinnable_mapped_file::map_mode).
CORE_COMMAND="      core_netd
      --config-dir /opt/core/config
      --data-dir /opt/core/data
      --genesis-json /opt/core/config/genesis.json"
if [[ "$STATE_IN_MEMORY" == "true" ]]; then
    CORE_COMMAND+=$'\n'"      --database-map-mode locked"
fi

# TMPFS_VOLUMES: no longer needed — state-in-memory is handled natively by
# core_netd. Kept as a placeholder so existing templates still substitute
# cleanly, but always empty.
TMPFS_BLOCK=""

# Build HEALTHCHECK
HEALTHCHECK_BLOCK=""
if [[ "$NODE_ROLE" != "seed" ]]; then
    HEALTHCHECK_HOST="${BIND_IP}"
    [[ "$HEALTHCHECK_HOST" == "0.0.0.0" ]] && HEALTHCHECK_HOST="localhost"
    HEALTHCHECK_BLOCK="    healthcheck:
      test: [\"CMD\", \"curl\", \"-f\", \"http://${HEALTHCHECK_HOST}:${HTTP_PORT}/v1/chain/get_info\"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s"
fi

# Build ENVIRONMENT. STATE_IN_MEMORY is surfaced to the container so
# entrypoint/ops scripts can detect it (e.g. for snapshot-restore on
# container recreate when no persisted file exists yet).
ENVIRONMENT_BLOCK="    environment:
      - NODE_ROLE=${NODE_ROLE}
      - NETWORK=${NETWORK}"
if [[ "$STATE_IN_MEMORY" == "true" ]]; then
    ENVIRONMENT_BLOCK+=$'\n'"      - STATE_IN_MEMORY=true"
fi

# Build GATEWAY_SERVICE (OpenResty + optional Cloudflare Tunnel)
GATEWAY_BLOCK=""
if [[ "$API_GATEWAY_ENABLED" == "true" ]]; then
    GATEWAY_BLOCK="  ${CONTAINER_NAME}-gateway:
    image: openresty/openresty:latest
    container_name: ${CONTAINER_NAME}-gateway
    volumes:
      - ${CONFIG_OUTPUT_DIR}/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf:ro
      - ${CONFIG_OUTPUT_DIR}/lua:/etc/openresty/lua:ro
      - ${CONFIG_OUTPUT_DIR}/api_keys:/etc/openresty/api_keys:ro
      - ${LOGS_DIR}/gateway:/var/log/openresty"

    if [[ "$TLS_ENABLED" == "true" ]]; then
        GATEWAY_BLOCK+="
      - /etc/letsencrypt:/etc/letsencrypt:ro"
    fi

    GATEWAY_BLOCK+="
    network_mode: host
    restart: unless-stopped
    environment:
      - API_KEYS_ENABLED=${API_KEYS_ENABLED}
      - RATE_LIMIT_RPS=${RATE_LIMIT_RPS}
      - RATE_LIMIT_BURST=${RATE_LIMIT_BURST}"

    # Cloudflare Zero Trust tunnel sidecar
    if [[ "$CF_TUNNEL_ENABLED" == "true" ]]; then
        GATEWAY_BLOCK+="

  ${CONTAINER_NAME}-cftunnel:
    image: cloudflare/cloudflared:latest
    container_name: ${CONTAINER_NAME}-cftunnel
    command: tunnel run
    environment:
      - TUNNEL_TOKEN=${CF_TUNNEL_TOKEN}
    network_mode: host
    restart: unless-stopped
    depends_on:
      - ${CONTAINER_NAME}-gateway"
    fi
fi

# Perform substitutions
COMPOSE_CONTENT="$COMPOSE_TEMPLATE"
COMPOSE_CONTENT="$(echo "$COMPOSE_CONTENT" | sed "s|{{CONTAINER_NAME}}|${CONTAINER_NAME}|g")"
COMPOSE_CONTENT="$(echo "$COMPOSE_CONTENT" | sed "s|{{IMAGE_NAME}}|${IMAGE_NAME}|g")"
COMPOSE_CONTENT="$(echo "$COMPOSE_CONTENT" | sed "s|{{CONFIG_DIR}}|${CONFIG_OUTPUT_DIR}|g")"
COMPOSE_CONTENT="$(echo "$COMPOSE_CONTENT" | sed "s|{{DATA_DIR}}|${DATA_DIR}|g")"
COMPOSE_CONTENT="$(echo "$COMPOSE_CONTENT" | sed "s|{{LOGS_DIR}}|${LOGS_DIR}|g")"
COMPOSE_CONTENT="$(echo "$COMPOSE_CONTENT" | sed "s|{{SNAPSHOTS_DIR}}|${SNAPSHOTS_DIR}|g")"
COMPOSE_CONTENT="$(echo "$COMPOSE_CONTENT" | sed "s|{{RESTART_POLICY}}|${RESTART_POLICY}|g")"
COMPOSE_CONTENT="$(echo "$COMPOSE_CONTENT" | sed "s|{{STOP_GRACE_PERIOD}}|30m|g")"

# Multi-line replacements
COMPOSE_CONTENT="$(replace_placeholder "{{CORE_COMMAND}}" "$CORE_COMMAND" "$COMPOSE_CONTENT")"
COMPOSE_CONTENT="$(replace_placeholder "{{TMPFS_VOLUMES}}" "$TMPFS_BLOCK" "$COMPOSE_CONTENT")"
COMPOSE_CONTENT="$(replace_placeholder "{{EXTRA_VOLUMES}}" "" "$COMPOSE_CONTENT")"
COMPOSE_CONTENT="$(replace_placeholder "{{HEALTHCHECK}}" "$HEALTHCHECK_BLOCK" "$COMPOSE_CONTENT")"
COMPOSE_CONTENT="$(replace_placeholder "{{ENVIRONMENT}}" "$ENVIRONMENT_BLOCK" "$COMPOSE_CONTENT")"
COMPOSE_CONTENT="$(replace_placeholder "{{GATEWAY_SERVICE}}" "$GATEWAY_BLOCK" "$COMPOSE_CONTENT")"

write_file "${CONFIG_OUTPUT_DIR}/docker-compose.yml" "$COMPOSE_CONTENT"

# =============================================================================
# Generate genesis.json
# =============================================================================
log_header "Generating genesis.json"

GENESIS_CONTENT="$(get_genesis_json "$NETWORK")"
write_file "${CONFIG_OUTPUT_DIR}/genesis.json" "$GENESIS_CONTENT"

# =============================================================================
# Generate logging.json
# =============================================================================
log_header "Generating logging.json"

LOGGING_TEMPLATE="${TEMPLATE_DIR}/logging-${LOG_PROFILE}.json"
if [[ ! -f "$LOGGING_TEMPLATE" ]]; then
    log_error "Logging profile template not found: ${LOGGING_TEMPLATE}"
    log_error "Available profiles: production, standard, debug, minimal"
    exit 1
fi

LOGGING_CONTENT="$(cat "$LOGGING_TEMPLATE")"
write_file "${CONFIG_OUTPUT_DIR}/logging.json" "$LOGGING_CONTENT"

# =============================================================================
# Generate nginx.conf + Lua auth (if API gateway is enabled)
# =============================================================================
if [[ "$API_GATEWAY_ENABLED" == "true" ]]; then
    log_header "Generating nginx.conf"

    NGINX_TEMPLATE="$(cat "${TEMPLATE_DIR}/nginx.conf.tmpl")"
    NGINX_CONTENT="$NGINX_TEMPLATE"

    # Simple substitutions
    NGINX_CONTENT="$(echo "$NGINX_CONTENT" | sed "s|{{HTTP_PORT}}|${HTTP_PORT}|g")"

    # Build LISTEN_DIRECTIVE_HTTP
    if [[ "$TLS_ENABLED" == "true" ]]; then
        LISTEN_HTTP="listen ${GATEWAY_HTTP_PORT} ssl;"
    else
        LISTEN_HTTP="listen ${GATEWAY_HTTP_PORT};"
    fi
    NGINX_CONTENT="$(replace_placeholder "{{LISTEN_DIRECTIVE_HTTP}}" "        ${LISTEN_HTTP}" "$NGINX_CONTENT")"

    # Build TLS_DIRECTIVES
    TLS_BLOCK=""
    if [[ "$TLS_ENABLED" == "true" ]]; then
        TLS_BLOCK="        ssl_certificate /etc/letsencrypt/live/${TLS_DOMAIN}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${TLS_DOMAIN}/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;"
    fi
    NGINX_CONTENT="$(replace_placeholder "{{TLS_DIRECTIVES}}" "$TLS_BLOCK" "$NGINX_CONTENT")"

    # Build SHIP_UPSTREAM
    SHIP_UPSTREAM_BLOCK=""
    if [[ "$NODE_ROLE" == "full-api" || "$NODE_ROLE" == "full-history" ]]; then
        SHIP_UPSTREAM_BLOCK="    upstream core_ship {
        server 127.0.0.1:${SHIP_PORT};
    }"
    fi
    NGINX_CONTENT="$(replace_placeholder "{{SHIP_UPSTREAM}}" "$SHIP_UPSTREAM_BLOCK" "$NGINX_CONTENT")"

    # Build SHIP_SERVER_BLOCK (WebSocket proxy for SHiP)
    SHIP_SERVER_BLOCK=""
    if [[ "$NODE_ROLE" == "full-api" || "$NODE_ROLE" == "full-history" ]]; then
        if [[ "$TLS_ENABLED" == "true" ]]; then
            SHIP_LISTEN="listen ${GATEWAY_SHIP_PORT} ssl;"
            SHIP_TLS="        ssl_certificate /etc/letsencrypt/live/${TLS_DOMAIN}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${TLS_DOMAIN}/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;"
        else
            SHIP_LISTEN="listen ${GATEWAY_SHIP_PORT};"
            SHIP_TLS=""
        fi

        SHIP_SERVER_BLOCK="    # --- SHiP WebSocket proxy ---
    server {
        ${SHIP_LISTEN}
        ${SHIP_TLS}

        access_by_lua_file /etc/openresty/lua/auth.lua;

        location / {
            proxy_pass http://core_ship;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \"upgrade\";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }
    }"
    fi
    NGINX_CONTENT="$(replace_placeholder "{{SHIP_SERVER_BLOCK}}" "$SHIP_SERVER_BLOCK" "$NGINX_CONTENT")"

    write_file "${CONFIG_OUTPUT_DIR}/nginx.conf" "$NGINX_CONTENT"

    # Copy Lua auth script
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Would copy lua/auth.lua -> ${CONFIG_OUTPUT_DIR}/lua/auth.lua"
    else
        mkdir -p "${CONFIG_OUTPUT_DIR}/lua"
        cp "${TEMPLATE_DIR}/lua/auth.lua" "${CONFIG_OUTPUT_DIR}/lua/auth.lua"
        log_info "Generated: ${CONFIG_OUTPUT_DIR}/lua/auth.lua"
    fi

    # Ensure api_keys file exists
    if [[ "$DRY_RUN" != "true" && ! -f "${CONFIG_OUTPUT_DIR}/api_keys" ]]; then
        echo "# API Keys — one per line, format: KEY_VALUE:label" > "${CONFIG_OUTPUT_DIR}/api_keys"
        chmod 600 "${CONFIG_OUTPUT_DIR}/api_keys"
        log_info "Created empty API keys file: ${CONFIG_OUTPUT_DIR}/api_keys"
    fi
fi

# =============================================================================
# Copy node.conf for reference
# =============================================================================
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Would copy ${CONF_FILE} -> ${CONFIG_OUTPUT_DIR}/node.conf"
else
    cp "$CONF_FILE" "${CONFIG_OUTPUT_DIR}/node.conf"
    log_info "Copied node.conf to ${CONFIG_OUTPUT_DIR}/node.conf"
fi

# =============================================================================
# Summary
# =============================================================================
log_header "Configuration Generation Complete"

log_info "Network:    ${NETWORK}"
log_info "Node Role:  ${NODE_ROLE}"
log_info "Core:       ${CORE_VERSION}"
log_info "Container:  ${CONTAINER_NAME}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "Dry run mode — no files were written."
else
    log_success "Generated files:"
    log_info "  ${CONFIG_OUTPUT_DIR}/config.ini"
    log_info "  ${CONFIG_OUTPUT_DIR}/docker-compose.yml"
    log_info "  ${CONFIG_OUTPUT_DIR}/genesis.json"
    log_info "  ${CONFIG_OUTPUT_DIR}/logging.json"
    if [[ "$API_GATEWAY_ENABLED" == "true" ]]; then
        log_info "  ${CONFIG_OUTPUT_DIR}/nginx.conf"
        log_info "  ${CONFIG_OUTPUT_DIR}/lua/auth.lua"
        log_info "  ${CONFIG_OUTPUT_DIR}/api_keys"
    fi
    log_info "  ${CONFIG_OUTPUT_DIR}/node.conf"
fi
