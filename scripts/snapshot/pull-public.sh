#!/bin/bash

# =============================================================================
# Core Node — Refresh snapshots/latest.bin from a Public Snapshot Provider
# =============================================================================
# Downloads the newest public snapshot for the node's network (providers from
# config/snapshot-providers.conf, tried in order), validates it, and atomically
# replaces ${STORAGE_PATH}/snapshots/latest.bin.
#
# latest.bin is what the entrypoint restores from when the state database is
# missing or dirty (e.g. after an unclean stop). Nodes without producer_api —
# full-history / SHiP nodes — never create snapshots of their own, so without
# this job their latest.bin only ages, and recovery means replaying everything
# since it was taken.
#
# Validation before replacing latest.bin:
#   - binary snapshot header magic (0x30510550, version 1)
#   - minimum size (SNAPSHOT_PULL_MIN_MB, default 5)
#   - the network's raw chain ID appears in the snapshot
# A provider's ETag is recorded in snapshots/.latest.bin.source; an unchanged
# ETag skips the download.
#
# Usage:
#   pull-public.sh [/path/to/node.conf] [OPTIONS]
#
# Options:
#   --provider NAME     Use only this provider from snapshot-providers.conf
#   --allow-http        Also try plain-http provider URLs (default: https only)
#   --max-age-hours N   Warn if the provider's snapshot is older (default: 48)
#   --force             Download even if the ETag is unchanged
#   --dry-run           Show the selected provider and what would happen
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/config-utils.sh
source "${SCRIPT_DIR}/../lib/config-utils.sh"
# shellcheck source=../lib/network-defaults.sh
source "${SCRIPT_DIR}/../lib/network-defaults.sh"

PROVIDERS_CONF="${PROJECT_DIR}/config/snapshot-providers.conf"
SNAPSHOT_MAGIC="5005513001000000"

TMP_DL=""
TMP_BIN=""
cleanup() { rm -f "${TMP_DL:-}" "${TMP_BIN:-}"; }
trap cleanup EXIT

# list_providers "network" — prints "name|url" lines for the network
list_providers() {
    local network="$1"
    [[ -f "$PROVIDERS_CONF" ]] || return 0
    grep -vE '^\s*(#|$)' "$PROVIDERS_CONF" | awk -F'|' -v n="$network" '$2==n {print $1"|"$3}'
}

# try_provider "name" "url" "dest" "chain_id" "min_bytes" "max_age" "force" "dry_run"
# Returns 0 when latest.bin is current (installed or unchanged), 1 to try the next provider.
try_provider() {
    local name="$1" url="$2" dest="$3" chain_id="$4" min_bytes="$5" max_age="$6" force="$7" dry_run="$8"
    local marker="${dest}/.latest.bin.source"

    local headers etag modified
    if ! headers="$(curl -fsSIL -m30 "$url" | tr -d '\r')"; then
        log_warn "${name}: HEAD ${url} failed"
        return 1
    fi
    etag="$(awk -F': ' 'tolower($1)=="etag"{v=$2} END{print v}' <<< "$headers" | tr -d '"')"
    modified="$(awk -F': ' 'tolower($1)=="last-modified"{v=$2} END{print v}' <<< "$headers")"

    if [[ -n "$modified" ]]; then
        local age=$(( $(date +%s) - $(date -d "$modified" +%s) ))
        (( age <= max_age )) || log_warn "${name}: snapshot is $(( age / 3600 ))h old (Last-Modified ${modified})"
    fi

    if [[ "$force" != "true" && -n "$etag" && -f "$marker" && -f "${dest}/latest.bin" \
          && "$(cat "$marker")" == "${name}|${etag}" ]]; then
        log_info "${name}: unchanged (etag ${etag}); latest.bin is current"
        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_info "[dry-run] Would download ${url} (Last-Modified ${modified:-unknown}, etag ${etag:-none}) into ${dest}/latest.bin"
        return 0
    fi

    TMP_DL="${dest}/.latest.download.tmp"
    TMP_BIN="${dest}/.latest.bin.tmp"
    if ! curl -fsSL -m1800 -o "$TMP_DL" "$url"; then
        log_warn "${name}: download failed"
        return 1
    fi

    case "$url" in
        *.zst)
            if ! zstd -q -d -f "$TMP_DL" -o "$TMP_BIN"; then
                log_warn "${name}: zstd decompress failed"
                return 1
            fi
            rm -f "$TMP_DL"
            ;;
        *.bin)
            mv -f "$TMP_DL" "$TMP_BIN"
            ;;
        *)
            log_warn "${name}: unsupported snapshot format (${url##*/}); expected .bin or .zst"
            return 1
            ;;
    esac

    local magic size
    magic="$(head -c 8 "$TMP_BIN" | od -An -tx1 | tr -d ' \n')"
    size="$(stat -c %s "$TMP_BIN")"
    if [[ "$magic" != "$SNAPSHOT_MAGIC" ]]; then
        log_warn "${name}: not a binary snapshot (header ${magic})"
        return 1
    fi
    if (( size < min_bytes )); then
        log_warn "${name}: snapshot only ${size} bytes (minimum ${min_bytes})"
        return 1
    fi
    # The chain ID is stored raw in the global property object; reject other chains.
    if ! python3 -I -c 'import sys; sys.exit(0 if bytes.fromhex(sys.argv[2]) in open(sys.argv[1], "rb").read() else 1)' \
            "$TMP_BIN" "$chain_id"; then
        log_warn "${name}: chain ID ${chain_id:0:16}… not found in snapshot"
        return 1
    fi

    # Match the snapshots directory's owner (the container user), then swap atomically.
    chown "$(stat -c '%u:%g' "$dest")" "$TMP_BIN"
    chmod 0644 "$TMP_BIN"
    mv -f "$TMP_BIN" "${dest}/latest.bin"
    echo "${name}|${etag}" > "$marker"
    log_success "${name}: installed latest.bin ($(( size / 1024 / 1024 )) MiB, Last-Modified ${modified:-unknown}, etag ${etag:-none})"
    return 0
}

main() {
    local config_path="" only_provider="" allow_http=false max_age_hours=48 force=false dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider)
                only_provider="${2:-}"
                [[ -n "$only_provider" ]] || { log_error "--provider requires a name"; exit 1; }
                shift 2
                ;;
            --allow-http)    allow_http=true; shift ;;
            --max-age-hours)
                max_age_hours="${2:-}"
                [[ "$max_age_hours" =~ ^[0-9]+$ ]] || { log_error "--max-age-hours requires a number"; exit 1; }
                shift 2
                ;;
            --force)         force=true; shift ;;
            --dry-run)       dry_run=true; shift ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                [[ -z "$config_path" ]] && config_path="$1"
                shift
                ;;
        esac
    done

    require_command curl
    require_command zstd
    require_command python3

    local conf
    conf="$(find_config "$config_path")"
    load_config "$conf"

    local network storage_path min_mb chain_id
    network="$(get_config "NETWORK" "")"
    storage_path="$(get_config "STORAGE_PATH" "")"
    min_mb="$(get_config "SNAPSHOT_PULL_MIN_MB" "5")"
    [[ -n "$network" && -n "$storage_path" ]] || { log_error "NETWORK and STORAGE_PATH must be set in ${conf}"; exit 1; }
    chain_id="$(get_chain_id "$network")"

    local dest="${storage_path}/snapshots"
    [[ -d "$dest" ]] || { log_error "Snapshots directory not found: ${dest}"; exit 1; }

    local tried=0 name url
    while IFS='|' read -r name url; do
        [[ -n "$only_provider" && "$name" != "$only_provider" ]] && continue
        if [[ "$url" != https://* && "$allow_http" != "true" ]]; then
            log_info "${name}: skipping non-https URL (use --allow-http to include)"
            continue
        fi
        tried=$(( tried + 1 ))
        if try_provider "$name" "$url" "$dest" "$chain_id" "$(( min_mb * 1024 * 1024 ))" \
                "$(( max_age_hours * 3600 ))" "$force" "$dry_run"; then
            return 0
        fi
        cleanup
    done < <(list_providers "$network")

    if (( tried == 0 )); then
        local which="${network} provider"
        [[ -n "$only_provider" ]] && which="${network} provider named ${only_provider}"
        log_error "No usable ${which} in ${PROVIDERS_CONF}"
    else
        log_error "All ${tried} provider(s) failed; existing latest.bin left unchanged"
    fi
    exit 1
}

main "$@"
