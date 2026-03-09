#!/bin/bash

# =============================================================================
# Libre Node — Restore from Snapshot
# =============================================================================
# Restores a node from a snapshot. Supports multiple snapshot sources:
#   local files, S3, public providers, or a direct URL.
#
# Usage:
#   restore.sh [/path/to/node.conf] [OPTIONS]
#
# Options:
#   --local              Use latest local snapshot only
#   --s3                 Download from S3 (if configured)
#   --provider NAME      Download from a specific public provider
#   --url URL            Download from a specific URL
#   (no options)         Auto-detect: local -> S3 -> public providers
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Source library files
# ---------------------------------------------------------------------------
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/config-utils.sh
source "${SCRIPT_DIR}/../lib/config-utils.sh"
# shellcheck source=../lib/network-defaults.sh
source "${SCRIPT_DIR}/../lib/network-defaults.sh"

# ---------------------------------------------------------------------------
# find_config — locate node.conf from argument, $PWD, or $PROJECT_DIR
# ---------------------------------------------------------------------------
find_config() {
    local config_arg="${1:-}"

    if [[ -n "$config_arg" && -f "$config_arg" ]]; then
        echo "$config_arg"
        return 0
    fi

    if [[ -f "${PWD}/node.conf" ]]; then
        echo "${PWD}/node.conf"
        return 0
    fi

    if [[ -f "${PROJECT_DIR}/node.conf" ]]; then
        echo "${PROJECT_DIR}/node.conf"
        return 0
    fi

    log_error "Cannot find node.conf. Provide it as an argument, or ensure it exists in \$PWD or ${PROJECT_DIR}."
    return 1
}

# ---------------------------------------------------------------------------
# find_local_snapshot — return path to latest local .bin snapshot
# ---------------------------------------------------------------------------
find_local_snapshot() {
    local snapshots_dir="$1"

    local latest_local
    latest_local=$(ls -1t "${snapshots_dir}"/*.bin 2>/dev/null | head -1)
    if [[ -n "$latest_local" ]]; then
        log_info "Found local snapshot: $(basename "$latest_local")"
        log_info "Size: $(du -h "$latest_local" | cut -f1)"
        echo "$latest_local"
        return 0
    fi

    return 1
}

# ---------------------------------------------------------------------------
# find_s3_snapshot — download latest snapshot from S3 via rclone
# ---------------------------------------------------------------------------
find_s3_snapshot() {
    local s3_remote="$1"
    local s3_bucket="$2"
    local s3_prefix="$3"
    local snapshots_dir="$4"

    log_info "Checking S3 for snapshots..."

    if ! command -v rclone &>/dev/null; then
        log_warn "rclone is not installed — skipping S3 source."
        return 1
    fi

    local s3_latest
    s3_latest=$(rclone ls "${s3_remote}:${s3_bucket}/${s3_prefix}snapshots/" 2>/dev/null \
        | grep '\.bin' | sort -k2 | tail -1 | awk '{print $2}')

    if [[ -n "$s3_latest" ]]; then
        log_info "Downloading snapshot from S3: ${s3_latest}"
        rclone copy "${s3_remote}:${s3_bucket}/${s3_prefix}snapshots/${s3_latest}" "${snapshots_dir}/" || {
            log_warn "S3 download failed."
            return 1
        }
        echo "${snapshots_dir}/${s3_latest}"
        return 0
    fi

    log_warn "No snapshots found on S3."
    return 1
}

# ---------------------------------------------------------------------------
# find_provider_snapshot — iterate public providers from snapshot-providers.conf
# ---------------------------------------------------------------------------
find_provider_snapshot() {
    local network="$1"
    local snapshots_dir="$2"
    local target_provider="${3:-}"   # empty = try all

    local providers_conf="${PROJECT_DIR}/config/snapshot-providers.conf"
    if [[ ! -f "$providers_conf" ]]; then
        log_warn "Providers config not found: ${providers_conf}"
        return 1
    fi

    while IFS='|' read -r provider prov_network url; do
        # Skip comments and blank lines
        [[ "$provider" =~ ^#.*$ ]] && continue
        [[ -z "$provider" ]] && continue

        # Strip leading/trailing whitespace
        provider="$(echo "$provider" | xargs)"
        prov_network="$(echo "$prov_network" | xargs)"
        url="$(echo "$url" | xargs)"

        # Filter by network
        [[ "$prov_network" != "$network" ]] && continue

        # If a specific provider was requested, skip non-matches
        if [[ -n "$target_provider" && "${provider,,}" != "${target_provider,,}" ]]; then
            continue
        fi

        log_info "Trying ${provider}..."
        local filename="snapshot-${provider,,}-$(date +%Y%m%d%H%M%S)"

        if curl -fL -o "${snapshots_dir}/${filename}.zst" "$url" 2>/dev/null; then
            log_info "Downloaded from ${provider}. Decompressing..."

            if ! command -v zstd &>/dev/null; then
                log_error "zstd is required to decompress snapshots. Install with: apt-get install zstd"
                rm -f "${snapshots_dir}/${filename}.zst"
                return 1
            fi

            zstd -d "${snapshots_dir}/${filename}.zst" -o "${snapshots_dir}/${filename}.bin" || {
                log_error "Decompression failed for ${filename}.zst"
                rm -f "${snapshots_dir}/${filename}.zst"
                return 1
            }
            rm -f "${snapshots_dir}/${filename}.zst"

            log_success "Snapshot ready: ${filename}.bin"
            echo "${snapshots_dir}/${filename}.bin"
            return 0
        else
            log_warn "Failed to download from ${provider}, trying next..."
        fi
    done < "$providers_conf"

    return 1
}

# ---------------------------------------------------------------------------
# download_url_snapshot — download from an explicit URL
# ---------------------------------------------------------------------------
download_url_snapshot() {
    local url="$1"
    local snapshots_dir="$2"

    local filename="snapshot-url-$(date +%Y%m%d%H%M%S)"

    log_info "Downloading snapshot from: ${url}"

    # Determine if the file is zstd-compressed by extension
    if [[ "$url" == *.zst ]]; then
        curl -fL -o "${snapshots_dir}/${filename}.zst" "$url" || {
            log_error "Failed to download from URL: ${url}"
            return 1
        }

        if ! command -v zstd &>/dev/null; then
            log_error "zstd is required to decompress snapshots. Install with: apt-get install zstd"
            rm -f "${snapshots_dir}/${filename}.zst"
            return 1
        fi

        log_info "Decompressing..."
        zstd -d "${snapshots_dir}/${filename}.zst" -o "${snapshots_dir}/${filename}.bin" || {
            log_error "Decompression failed."
            rm -f "${snapshots_dir}/${filename}.zst"
            return 1
        }
        rm -f "${snapshots_dir}/${filename}.zst"
    else
        curl -fL -o "${snapshots_dir}/${filename}.bin" "$url" || {
            log_error "Failed to download from URL: ${url}"
            return 1
        }
    fi

    log_success "Snapshot ready: ${filename}.bin"
    echo "${snapshots_dir}/${filename}.bin"
    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local config_path=""
    local mode=""          # "", "local", "s3", "provider", "url"
    local provider_name=""
    local download_url=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --local)
                mode="local"
                shift
                ;;
            --s3)
                mode="s3"
                shift
                ;;
            --provider)
                mode="provider"
                provider_name="${2:-}"
                if [[ -z "$provider_name" ]]; then
                    log_error "--provider requires a NAME argument."
                    exit 1
                fi
                shift 2
                ;;
            --url)
                mode="url"
                download_url="${2:-}"
                if [[ -z "$download_url" ]]; then
                    log_error "--url requires a URL argument."
                    exit 1
                fi
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [[ -z "$config_path" ]]; then
                    config_path="$1"
                fi
                shift
                ;;
        esac
    done

    # Locate and load configuration
    local conf
    conf="$(find_config "$config_path")"
    load_config "$conf"

    local network
    network="$(get_config "NETWORK" "")"
    if [[ -z "$network" ]]; then
        log_error "NETWORK is not set in ${conf}"
        exit 1
    fi

    local storage_path
    storage_path="$(get_config "STORAGE_PATH" "")"
    if [[ -z "$storage_path" ]]; then
        log_error "STORAGE_PATH is not set in ${conf}"
        exit 1
    fi

    local snapshots_dir="${storage_path}/snapshots"
    mkdir -p "$snapshots_dir"

    local s3_enabled
    s3_enabled="$(get_config "S3_ENABLED" "false")"
    local s3_remote
    s3_remote="$(get_config "S3_REMOTE" "")"
    local s3_bucket
    s3_bucket="$(get_config "S3_BUCKET" "")"
    local s3_prefix
    s3_prefix="$(get_config "S3_PREFIX" "")"

    local snapshot_file=""

    case "$mode" in
        local)
            snapshot_file="$(find_local_snapshot "$snapshots_dir")" || {
                log_error "No local snapshots found in ${snapshots_dir}"
                exit 1
            }
            ;;

        s3)
            if [[ "$s3_enabled" != "true" ]]; then
                log_error "S3 is not enabled in configuration. Set S3_ENABLED=true in node.conf."
                exit 1
            fi
            snapshot_file="$(find_s3_snapshot "$s3_remote" "$s3_bucket" "$s3_prefix" "$snapshots_dir")" || {
                log_error "Failed to retrieve snapshot from S3."
                exit 1
            }
            ;;

        provider)
            snapshot_file="$(find_provider_snapshot "$network" "$snapshots_dir" "$provider_name")" || {
                log_error "Failed to download snapshot from provider '${provider_name}'."
                exit 1
            }
            ;;

        url)
            snapshot_file="$(download_url_snapshot "$download_url" "$snapshots_dir")" || {
                log_error "Failed to download snapshot from URL."
                exit 1
            }
            ;;

        "")
            # Auto-detect mode: local -> S3 -> public providers
            log_info "Auto-detecting best snapshot source for ${network}..."

            # a. Try local
            snapshot_file="$(find_local_snapshot "$snapshots_dir" 2>/dev/null)" || true

            # b. Try S3
            if [[ -z "$snapshot_file" && "$s3_enabled" == "true" ]]; then
                snapshot_file="$(find_s3_snapshot "$s3_remote" "$s3_bucket" "$s3_prefix" "$snapshots_dir" 2>/dev/null)" || true
            fi

            # c. Try custom snapshot URL from config
            if [[ -z "$snapshot_file" ]]; then
                local custom_url
                custom_url="$(get_config "CUSTOM_SNAPSHOT_URL" "")"
                if [[ -n "$custom_url" ]]; then
                    log_info "Trying custom snapshot URL from config..."
                    snapshot_file="$(download_url_snapshot "$custom_url" "$snapshots_dir" 2>/dev/null)" || true
                fi
            fi

            # d. Try public providers
            if [[ -z "$snapshot_file" ]]; then
                snapshot_file="$(find_provider_snapshot "$network" "$snapshots_dir" 2>/dev/null)" || true
            fi

            if [[ -z "$snapshot_file" ]]; then
                log_error "No snapshot source available. Tried: local, S3, public providers."
                log_error "Use --url <URL> to provide a download link manually."
                exit 1
            fi
            ;;
    esac

    # Final output
    log_success "Snapshot file: ${snapshot_file}"
    if [[ -f "$snapshot_file" ]]; then
        log_info "Size: $(du -h "$snapshot_file" | cut -f1)"
    fi
}

main "$@"
