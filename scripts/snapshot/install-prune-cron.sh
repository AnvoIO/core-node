#!/bin/bash

# =============================================================================
# Core Node — Install Recurring Snapshot Prune Job
# =============================================================================
# Installs a cron.d job that periodically runs prune.sh for a node, keeping
# only SNAPSHOT_RETENTION most-recent snapshots.
#
# The node's own producer API creates snapshots on an interval (see
# schedule.sh), but nothing prunes them — so without this job the snapshots
# directory grows without bound and eventually trips core_netd's
# resource_monitor_plugin, gracefully shutting the node down. This installs the
# "local job" that keeps snapshot retention bounded.
#
# Usage:
#   install-prune-cron.sh [/path/to/node.conf] [OPTIONS]
#
# Options:
#   --schedule "<cron expr>"  Five-field cron schedule (default: "17 * * * *", hourly)
#   --uninstall               Remove the cron job for this node instead of installing
#   --dry-run                 Show what would be written without touching anything
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/config-utils.sh
source "${SCRIPT_DIR}/../lib/config-utils.sh"

# find_config is provided by config-utils.sh

PRUNE_SCRIPT="${SCRIPT_DIR}/prune.sh"

main() {
    local config_path=""
    local schedule="17 * * * *"
    local uninstall=false
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --schedule)
                schedule="${2:-}"
                if [[ -z "$schedule" ]]; then
                    log_error "--schedule requires a cron expression argument."
                    exit 1
                fi
                shift 2
                ;;
            --uninstall)
                uninstall=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
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

    local conf
    conf="$(find_config "$config_path")"
    load_config "$conf"
    # Absolute path — cron has no working directory to rely on.
    conf="$(cd "$(dirname "$conf")" && pwd)/$(basename "$conf")"

    local container_name
    container_name="$(get_config "CONTAINER_NAME" "")"
    if [[ -z "$container_name" ]]; then
        log_error "CONTAINER_NAME is not set in ${conf}"
        exit 1
    fi

    local storage_path
    storage_path="$(get_config "STORAGE_PATH" "")"

    local cron_file="/etc/cron.d/core-node-snapshot-prune-${container_name}"

    if [[ "$uninstall" == "true" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log_info "[dry-run] Would remove ${cron_file}"
            return 0
        fi
        if [[ -f "$cron_file" ]]; then
            rm -f "$cron_file"
            log_success "Removed snapshot-prune cron job: ${cron_file}"
        else
            log_info "No cron job to remove at ${cron_file}"
        fi
        return 0
    fi

    if [[ ! -x "$PRUNE_SCRIPT" ]]; then
        log_error "prune.sh not found or not executable at ${PRUNE_SCRIPT}"
        exit 1
    fi

    local log_file="${storage_path:-/tmp}/logs/snapshot-prune.log"
    local lock_file="/tmp/core-node-prune-${container_name}.lock"

    # cron.d format: m h dom mon dow user command
    # flock prevents overlapping runs if a prune ever takes longer than the interval.
    local cron_line
    cron_line="${schedule} root flock -n ${lock_file} ${PRUNE_SCRIPT} ${conf} >> ${log_file} 2>&1"

    local content
    content="# Core Node snapshot prune — keeps SNAPSHOT_RETENTION newest snapshots for ${container_name}
# Managed by install-prune-cron.sh — edits will be overwritten on reinstall.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${cron_line}"

    if [[ "$dry_run" == "true" ]]; then
        log_info "[dry-run] Would write ${cron_file}:"
        echo "----"
        echo "$content"
        echo "----"
        return 0
    fi

    echo "$content" > "$cron_file"
    chmod 0644 "$cron_file"
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
    log_success "Installed snapshot-prune cron job: ${cron_file}"
    log_info "Schedule: ${schedule}  (keeps SNAPSHOT_RETENTION newest snapshots)"
    log_info "Log:      ${log_file}"
}

main "$@"
