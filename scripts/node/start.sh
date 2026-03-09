#!/bin/bash
set -euo pipefail

# =============================================================================
# Libre Node — Start Node
# =============================================================================
# Starts the Libre blockchain node container, building the Docker image and
# restoring a snapshot if needed.
#
# Usage: start.sh [path/to/node.conf]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/config-utils.sh"
source "${SCRIPT_DIR}/../lib/network-defaults.sh"

# ---------------------------------------------------------------------------
# find_config — locate node.conf
# ---------------------------------------------------------------------------
find_config() {
    local explicit_path="${1:-}"

    if [[ -n "$explicit_path" ]]; then
        if [[ -f "$explicit_path" ]]; then
            echo "$explicit_path"
            return 0
        fi
        log_error "Specified config not found: ${explicit_path}"
        return 1
    fi

    if [[ -f "${PWD}/node.conf" ]]; then
        echo "${PWD}/node.conf"
        return 0
    fi

    if [[ -f "${PROJECT_DIR}/node.conf" ]]; then
        echo "${PROJECT_DIR}/node.conf"
        return 0
    fi

    log_error "No node.conf found. Provide a path or run from a directory containing node.conf."
    return 1
}

# ---------------------------------------------------------------------------
# download_snapshot — try public providers for the given network
# ---------------------------------------------------------------------------
download_snapshot() {
    local network="$1"
    local dest_dir="$2"
    local providers_conf="${PROJECT_DIR}/config/snapshot-providers.conf"

    if [[ ! -f "$providers_conf" ]]; then
        log_error "Snapshot providers config not found: ${providers_conf}"
        return 1
    fi

    local line provider prov_network url
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

        provider="$(echo "$line" | cut -d'|' -f1)"
        prov_network="$(echo "$line" | cut -d'|' -f2)"
        url="$(echo "$line" | cut -d'|' -f3)"

        [[ "$prov_network" != "$network" ]] && continue

        log_info "Trying snapshot from ${provider}: ${url}"

        local tmp_file="${dest_dir}/download_tmp"
        if curl -fSL --progress-bar -o "$tmp_file" "$url" 2>&1; then
            # Decompress .zst files
            if [[ "$url" == *.zst ]]; then
                log_info "Decompressing snapshot (zstd)..."
                require_command "zstd" "apt-get install zstd"
                zstd -d -f "$tmp_file" -o "${dest_dir}/latest.bin"
                rm -f "$tmp_file"
            else
                mv "$tmp_file" "${dest_dir}/latest.bin"
            fi
            log_success "Snapshot downloaded from ${provider}."
            return 0
        else
            log_warn "Failed to download from ${provider}. Trying next provider..."
            rm -f "$tmp_file"
        fi
    done < "$providers_conf"

    log_error "Could not download snapshot from any provider."
    return 1
}

# ---------------------------------------------------------------------------
# wait_for_api — poll the HTTP API until the node responds
# ---------------------------------------------------------------------------
wait_for_api() {
    local http_port="$1"
    local max_wait=120
    local waited=0

    log_info "Waiting for node to start..."
    while ! curl -sf "http://localhost:${http_port}/v1/chain/get_info" > /dev/null 2>&1; do
        sleep 2
        waited=$((waited + 2))
        if [[ $waited -ge $max_wait ]]; then
            log_warn "Node did not respond within ${max_wait} seconds. Check logs."
            return 1
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_header "Libre Node — Start"

    # Load configuration
    local config_path
    config_path="$(find_config "${1:-}")"
    load_config "$config_path"

    # Read key values
    local NETWORK NODE_ROLE CONTAINER_NAME STORAGE_PATH LEAP_VERSION
    local STATE_IN_MEMORY HTTP_PORT SNAPSHOT_INTERVAL BIND_IP P2P_PORT
    local S3_ENABLED

    NETWORK="$(get_config "NETWORK")"
    NODE_ROLE="$(get_config "NODE_ROLE")"
    CONTAINER_NAME="$(get_config "CONTAINER_NAME")"
    STORAGE_PATH="$(get_config "STORAGE_PATH")"
    LEAP_VERSION="$(get_config "LEAP_VERSION" "$RECOMMENDED_LEAP_VERSION")"
    STATE_IN_MEMORY="$(get_config "STATE_IN_MEMORY" "false")"
    HTTP_PORT="$(get_config "HTTP_PORT")"
    P2P_PORT="$(get_config "P2P_PORT")"
    SNAPSHOT_INTERVAL="$(get_config "SNAPSHOT_INTERVAL" "1000")"
    BIND_IP="$(get_config "BIND_IP" "0.0.0.0")"
    S3_ENABLED="$(get_config "S3_ENABLED" "false")"

    # Validate required fields
    validate_not_empty "$NETWORK" "NETWORK"
    validate_not_empty "$NODE_ROLE" "NODE_ROLE"
    validate_not_empty "$CONTAINER_NAME" "CONTAINER_NAME"
    validate_not_empty "$STORAGE_PATH" "STORAGE_PATH"
    if [[ "$NODE_ROLE" != "seed" ]]; then
        validate_not_empty "$HTTP_PORT" "HTTP_PORT"
    fi

    # Check Docker is available
    require_command "docker"

    # Check if container is already running
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "Container '${CONTAINER_NAME}' is already running."
        exit 0
    fi

    # Check if Docker image exists; build if missing
    if [[ -z "$(docker images -q "libre-node:${LEAP_VERSION}" 2>/dev/null)" ]]; then
        log_info "Building Docker image libre-node:${LEAP_VERSION}..."
        docker build -t "libre-node:${LEAP_VERSION}" \
            -f "${PROJECT_DIR}/docker/Dockerfile" \
            "${PROJECT_DIR}/docker/"
    fi

    # Check if we need a snapshot to boot
    local need_snapshot="false"
    if [[ ! -f "${STORAGE_PATH}/data/state/shared_memory.bin" ]]; then
        if [[ "$STATE_IN_MEMORY" == "true" ]]; then
            need_snapshot="true"
        elif [[ ! -d "${STORAGE_PATH}/data/state" ]] || \
             [[ -z "$(ls -A "${STORAGE_PATH}/data/state/" 2>/dev/null)" ]]; then
            need_snapshot="true"
        fi
    fi

    if [[ "$need_snapshot" == "true" ]]; then
        log_info "No existing chain state found. Attempting to restore a snapshot..."

        mkdir -p "${STORAGE_PATH}/snapshots"
        local snapshot_path=""

        # Priority a: latest local snapshot
        snapshot_path="$(ls -1t "${STORAGE_PATH}/snapshots/"*.bin 2>/dev/null | head -1 || true)"

        # Priority b: S3 pull (if enabled)
        if [[ -z "$snapshot_path" && "$S3_ENABLED" == "true" ]]; then
            local s3_pull_script="${SCRIPT_DIR}/../backup/s3-pull.sh"
            if [[ -x "$s3_pull_script" ]]; then
                log_info "Pulling snapshot from S3..."
                if "$s3_pull_script"; then
                    snapshot_path="$(ls -1t "${STORAGE_PATH}/snapshots/"*.bin 2>/dev/null | head -1 || true)"
                fi
            else
                log_info "S3 pull script not found at ${s3_pull_script}. Skipping S3."
            fi
        fi

        # Priority c: download from public providers
        if [[ -z "$snapshot_path" ]]; then
            log_info "Downloading snapshot from public providers..."
            if download_snapshot "$NETWORK" "${STORAGE_PATH}/snapshots"; then
                snapshot_path="${STORAGE_PATH}/snapshots/latest.bin"
            fi
        fi

        if [[ -n "$snapshot_path" ]]; then
            # Ensure the file is at the expected location
            if [[ "$snapshot_path" != "${STORAGE_PATH}/snapshots/latest.bin" ]]; then
                cp "$snapshot_path" "${STORAGE_PATH}/snapshots/latest.bin"
            fi
            log_success "Snapshot ready: ${STORAGE_PATH}/snapshots/latest.bin"
        else
            log_warn "No snapshot available. The node will attempt to sync from genesis."
        fi
    fi

    # Start the container
    log_info "Starting container '${CONTAINER_NAME}'..."
    docker compose -f "${STORAGE_PATH}/config/docker-compose.yml" up -d

    # Wait for node to be ready (if role has HTTP API)
    if [[ "$NODE_ROLE" != "seed" ]]; then
        wait_for_api "$HTTP_PORT" || true
    fi

    # Schedule periodic snapshots (producer role only)
    if [[ "$NODE_ROLE" == "producer" ]]; then
        log_info "Scheduling periodic snapshots every ${SNAPSHOT_INTERVAL} blocks..."
        curl -sf -X POST "http://localhost:${HTTP_PORT}/v1/producer/schedule_snapshot" \
            -H "Content-Type: application/json" \
            -d "{\"block_spacing\": ${SNAPSHOT_INTERVAL}, \"start_block_num\": 0, \"end_block_num\": 0}" || \
            log_warn "Could not schedule snapshots via API. You may need to do this manually."
    fi

    # Print success summary
    echo ""
    log_success "Node started successfully!"
    echo ""
    echo "  Container:  ${CONTAINER_NAME}"
    echo "  Network:    ${NETWORK}"
    echo "  Role:       ${NODE_ROLE}"
    echo "  API:        http://${BIND_IP}:${HTTP_PORT}"
    echo "  P2P:        ${BIND_IP}:${P2P_PORT}"
    echo ""
}

main "$@"
