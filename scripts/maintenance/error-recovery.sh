#!/bin/bash
set -euo pipefail

# =============================================================================
# Libre Node — Error Diagnosis & Automated Recovery
# =============================================================================
# Analyzes node state, detects common failure modes, and attempts automated
# recovery when possible.
#
# Usage:
#   error-recovery.sh [/path/to/node.conf] [OPTIONS]
#
# Options:
#   --diagnose   Analyze node state and suggest fixes (default)
#   --fix        Attempt automated recovery
#   --help       Show this help message
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Source library files
# ---------------------------------------------------------------------------
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/config-utils.sh
source "${SCRIPT_DIR}/../lib/config-utils.sh"

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
# show_help
# ---------------------------------------------------------------------------
show_help() {
    echo "Libre Node — Error Diagnosis & Automated Recovery"
    echo ""
    echo "Usage: $(basename "$0") [/path/to/node.conf] [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --diagnose   Analyze node state and suggest fixes (default)"
    echo "  --fix        Attempt automated recovery"
    echo "  --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") --diagnose"
    echo "  $(basename "$0") /srv/libre/node.conf --fix"
}

# ---------------------------------------------------------------------------
# diagnose — check for common issues and report findings
# ---------------------------------------------------------------------------
diagnose() {
    log_header "Node Diagnosis"

    local issues_found=0

    # 1. Container not running
    echo "1. Container status"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        log_success "  Container '${CONTAINER_NAME}' is running."
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        log_error "  Container '${CONTAINER_NAME}' exists but is NOT running."
        echo "  Suggested fix: restart the container, or run with --fix"
        issues_found=$((issues_found + 1))
    else
        log_error "  Container '${CONTAINER_NAME}' does not exist."
        echo "  Suggested fix: run start.sh to create and start the node"
        issues_found=$((issues_found + 1))
    fi
    echo ""

    # 2. API not responding
    echo "2. API connectivity"
    if [[ -n "$HTTP_PORT" ]]; then
        local api_response
        if api_response="$(curl -sf --max-time 5 "http://localhost:${HTTP_PORT}/v1/chain/get_info" 2>/dev/null)"; then
            log_success "  API is responding on port ${HTTP_PORT}."
        else
            log_error "  API is not responding on http://localhost:${HTTP_PORT}"
            echo "  Suggested fix: check if the container is running and ports are mapped correctly"
            issues_found=$((issues_found + 1))
        fi
    else
        log_warn "  HTTP_PORT not configured — skipping API check."
    fi
    echo ""

    # 3. Node falling behind
    echo "3. Head block age"
    if [[ -n "$HTTP_PORT" ]]; then
        local chain_info
        if chain_info="$(curl -sf --max-time 5 "http://localhost:${HTTP_PORT}/v1/chain/get_info" 2>/dev/null)"; then
            local head_block_time
            head_block_time="$(echo "$chain_info" | grep -o '"head_block_time":"[^"]*"' | cut -d'"' -f4)"
            if [[ -n "$head_block_time" ]]; then
                local head_epoch now_epoch age_seconds
                head_epoch="$(date -d "${head_block_time}" +%s 2>/dev/null || echo "")"
                now_epoch="$(date +%s)"
                if [[ -n "$head_epoch" ]]; then
                    age_seconds=$(( now_epoch - head_epoch ))
                    if [[ $age_seconds -gt 120 ]]; then
                        log_warn "  Head block is ${age_seconds} seconds old — node may be falling behind."
                        echo "  Suggested fix: check peer connectivity and system resources"
                        issues_found=$((issues_found + 1))
                    else
                        log_success "  Head block is ${age_seconds} seconds old — node is in sync."
                    fi
                fi
            fi
        else
            log_warn "  Could not query chain info — skipping block age check."
        fi
    fi
    echo ""

    # 4. Corrupt state (check docker logs)
    echo "4. Database state"
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        local recent_logs
        recent_logs="$(docker logs --tail 200 "${CONTAINER_NAME}" 2>&1 || true)"
        if echo "$recent_logs" | grep -qi "database dirty flag\|bad_alloc\|could not find existing state"; then
            log_error "  Corrupt state or dirty shutdown detected in logs."
            echo "  Suggested fix: stop the node, remove state files, and restore from snapshot"
            issues_found=$((issues_found + 1))
        else
            log_success "  No database corruption patterns found in recent logs."
        fi
    else
        log_warn "  Container not available — skipping log analysis."
    fi
    echo ""

    # 5. Fork detected
    echo "5. Fork detection"
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        local recent_logs
        recent_logs="$(docker logs --tail 200 "${CONTAINER_NAME}" 2>&1 || true)"
        if echo "$recent_logs" | grep -qi "fork\|unlinkable block"; then
            log_error "  Fork or unlinkable block detected in logs."
            echo "  Suggested fix: stop the node, remove state files, and restore from snapshot"
            issues_found=$((issues_found + 1))
        else
            log_success "  No fork patterns found in recent logs."
        fi
    else
        log_warn "  Container not available — skipping fork check."
    fi
    echo ""

    # 6. Disk full
    echo "6. Disk space"
    if [[ -n "$STORAGE_PATH" && -d "$STORAGE_PATH" ]]; then
        local avail_kb
        avail_kb="$(df "$STORAGE_PATH" | awk 'NR==2 {print $4}')"
        local avail_human
        avail_human="$(df -h "$STORAGE_PATH" | awk 'NR==2 {print $4}')"
        local used_pct
        used_pct="$(df "$STORAGE_PATH" | awk 'NR==2 {print $5}')"

        if [[ $avail_kb -lt 5242880 ]]; then  # less than 5 GB
            log_error "  Disk space critically low: ${avail_human} available (${used_pct} used)."
            echo "  Suggested fix: prune old snapshots, remove old logs, or expand storage"
            issues_found=$((issues_found + 1))
        elif [[ $avail_kb -lt 10485760 ]]; then  # less than 10 GB
            log_warn "  Disk space is getting low: ${avail_human} available (${used_pct} used)."
            echo "  Suggested fix: prune old snapshots to free space"
            issues_found=$((issues_found + 1))
        else
            log_success "  Disk space OK: ${avail_human} available (${used_pct} used)."
        fi
    else
        log_warn "  STORAGE_PATH not set or does not exist — skipping disk check."
    fi
    echo ""

    # 7. Out of memory
    echo "7. Memory / OOM"
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        local recent_logs
        recent_logs="$(docker logs --tail 200 "${CONTAINER_NAME}" 2>&1 || true)"
        if echo "$recent_logs" | grep -qi "killed\|oom\|out of memory\|cannot allocate memory"; then
            log_error "  Out-of-memory or OOM-kill pattern detected in logs."
            echo "  Suggested fix: increase available RAM or reduce node memory usage"
            issues_found=$((issues_found + 1))
        else
            log_success "  No OOM patterns found in recent logs."
        fi
    else
        log_warn "  Container not available — skipping OOM check."
    fi
    echo ""

    # Summary
    echo "---------------------------------------"
    if [[ $issues_found -eq 0 ]]; then
        log_success "No issues detected. Node appears healthy."
    else
        log_warn "${issues_found} issue(s) detected. Run with --fix to attempt automated recovery."
    fi

    return $issues_found
}

# ---------------------------------------------------------------------------
# stop_node — gracefully stop the container
# ---------------------------------------------------------------------------
stop_node() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        log_info "Stopping container '${CONTAINER_NAME}'..."
        if [[ -f "${STORAGE_PATH}/config/docker-compose.yml" ]]; then
            docker compose -f "${STORAGE_PATH}/config/docker-compose.yml" stop || true
            docker compose -f "${STORAGE_PATH}/config/docker-compose.yml" down || true
        else
            docker stop "${CONTAINER_NAME}" || true
            docker rm "${CONTAINER_NAME}" || true
        fi
        log_success "Container stopped."
    else
        log_info "Container '${CONTAINER_NAME}' is not running."
    fi
}

# ---------------------------------------------------------------------------
# start_node — start the container
# ---------------------------------------------------------------------------
start_node() {
    log_info "Starting container '${CONTAINER_NAME}'..."
    if [[ -f "${STORAGE_PATH}/config/docker-compose.yml" ]]; then
        docker compose -f "${STORAGE_PATH}/config/docker-compose.yml" up -d
    else
        log_error "docker-compose.yml not found at ${STORAGE_PATH}/config/docker-compose.yml"
        log_error "Run start.sh instead to properly initialize the node."
        return 1
    fi
    log_success "Container started."
}

# ---------------------------------------------------------------------------
# restore_from_snapshot — find latest local snapshot and restore
# ---------------------------------------------------------------------------
restore_from_snapshot() {
    local snapshots_dir="${STORAGE_PATH}/snapshots"

    if [[ ! -d "$snapshots_dir" ]]; then
        log_warn "No snapshots directory found at ${snapshots_dir}."
        return 1
    fi

    local latest_snapshot
    latest_snapshot="$(ls -1t "${snapshots_dir}"/*.bin 2>/dev/null | head -1 || true)"

    if [[ -z "$latest_snapshot" ]]; then
        log_warn "No local snapshots found in ${snapshots_dir}."
        log_info "You may need to download a snapshot manually or run snapshot/restore.sh."
        return 1
    fi

    log_info "Restoring from snapshot: $(basename "$latest_snapshot")"
    cp "$latest_snapshot" "${snapshots_dir}/latest.bin"
    log_success "Snapshot staged for restore."
    return 0
}

# ---------------------------------------------------------------------------
# fix — attempt automated recovery based on detected issues
# ---------------------------------------------------------------------------
fix() {
    log_header "Automated Error Recovery"

    local container_running=false
    local has_corrupt_state=false
    local has_fork=false
    local has_disk_full=false
    local has_oom=false
    local container_exists=false

    # Gather state
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        container_running=true
        container_exists=true
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        container_exists=true
    fi

    local recent_logs=""
    if [[ "$container_exists" == "true" ]]; then
        recent_logs="$(docker logs --tail 200 "${CONTAINER_NAME}" 2>&1 || true)"
    fi

    if echo "$recent_logs" | grep -qi "database dirty flag\|bad_alloc\|could not find existing state"; then
        has_corrupt_state=true
    fi

    if echo "$recent_logs" | grep -qi "fork\|unlinkable block"; then
        has_fork=true
    fi

    if [[ -n "$STORAGE_PATH" && -d "$STORAGE_PATH" ]]; then
        local avail_kb
        avail_kb="$(df "$STORAGE_PATH" | awk 'NR==2 {print $4}')"
        if [[ $avail_kb -lt 5242880 ]]; then
            has_disk_full=true
        fi
    fi

    if echo "$recent_logs" | grep -qi "killed\|oom\|out of memory\|cannot allocate memory"; then
        has_oom=true
    fi

    # --- Fix: Container not running (simple case, no corruption) ---
    if [[ "$container_running" == "false" && "$has_corrupt_state" == "false" && "$has_fork" == "false" ]]; then
        if [[ "$container_exists" == "true" ]]; then
            log_info "Container exists but is not running."
            confirm_action "Start the container '${CONTAINER_NAME}'"
            start_node
            return $?
        else
            log_error "Container '${CONTAINER_NAME}' does not exist."
            log_info "Run start.sh to create and start the node."
            return 1
        fi
    fi

    # --- Fix: Corrupt state / database dirty ---
    if [[ "$has_corrupt_state" == "true" ]]; then
        log_warn "Corrupt state or dirty shutdown detected."
        confirm_action "Stop the node, remove state files, and restore from snapshot"

        stop_node

        log_info "Removing state directory..."
        rm -rf "${STORAGE_PATH}/data/state"
        log_info "State directory removed."

        if restore_from_snapshot; then
            log_info "Starting node with restored snapshot..."
            start_node
        else
            log_warn "No snapshot available for automatic restore."
            log_info "Download a snapshot and run start.sh to resync."
        fi
        return 0
    fi

    # --- Fix: Fork detected ---
    if [[ "$has_fork" == "true" ]]; then
        log_warn "Fork or unlinkable block detected."
        confirm_action "Stop the node, remove state files, and restore from snapshot"

        stop_node

        log_info "Removing state directory..."
        rm -rf "${STORAGE_PATH}/data/state"
        log_info "State directory removed."

        if restore_from_snapshot; then
            log_info "Starting node with restored snapshot..."
            start_node
        else
            log_warn "No snapshot available for automatic restore."
            log_info "Download a snapshot and run start.sh to resync."
        fi
        return 0
    fi

    # --- Fix: Disk full ---
    if [[ "$has_disk_full" == "true" ]]; then
        log_warn "Disk space critically low."
        echo ""
        echo "  Disk usage breakdown for ${STORAGE_PATH}:"
        du -sh "${STORAGE_PATH}/data/blocks" 2>/dev/null | awk '{print "    blocks:        " $1}' || true
        du -sh "${STORAGE_PATH}/data/state" 2>/dev/null | awk '{print "    state:         " $1}' || true
        du -sh "${STORAGE_PATH}/data/state-history" 2>/dev/null | awk '{print "    state-history: " $1}' || true
        du -sh "${STORAGE_PATH}/snapshots" 2>/dev/null | awk '{print "    snapshots:     " $1}' || true
        du -sh "${STORAGE_PATH}/logs" 2>/dev/null | awk '{print "    logs:          " $1}' || true
        echo ""

        confirm_action "Prune old snapshots and clean up logs to free disk space"

        # Run snapshot pruning
        local prune_script="${SCRIPT_DIR}/../snapshot/prune.sh"
        if [[ -x "$prune_script" ]]; then
            log_info "Running snapshot pruning..."
            "$prune_script" "${CONFIG_FILE}" || true
        else
            log_warn "Snapshot prune script not found at ${prune_script}."
            log_info "Manually remove old snapshots from ${STORAGE_PATH}/snapshots/"
        fi

        # Suggest removing old logs
        if [[ -d "${STORAGE_PATH}/logs" ]]; then
            local log_size
            log_size="$(du -sh "${STORAGE_PATH}/logs" 2>/dev/null | cut -f1)"
            log_info "Logs directory is using ${log_size}."
            if ask_yes_no "Remove old log files?" "n"; then
                find "${STORAGE_PATH}/logs" -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
                log_success "Old log files removed."
            fi
        fi

        # Report final state
        local avail_after
        avail_after="$(df -h "$STORAGE_PATH" | awk 'NR==2 {print $4}')"
        log_info "Available disk space after cleanup: ${avail_after}"
        return 0
    fi

    # --- Fix: OOM (informational) ---
    if [[ "$has_oom" == "true" ]]; then
        log_warn "Out-of-memory patterns detected in logs."
        log_info "This typically requires increasing available RAM or adjusting node configuration."
        log_info "Consider setting STATE_IN_MEMORY=false in node.conf if memory is limited."
        confirm_action "Restart the container to recover from OOM"

        stop_node
        start_node
        return 0
    fi

    log_info "No fixable issues detected automatically."
    log_info "Run --diagnose for a detailed report."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local action="diagnose"
    local config_arg=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --diagnose) action="diagnose"; shift ;;
            --fix) action="fix"; shift ;;
            --help) show_help; exit 0 ;;
            -*) log_error "Unknown option: $1"; show_help; exit 1 ;;
            *) config_arg="$1"; shift ;;
        esac
    done

    load_config "$(find_config "$config_arg")"

    # Read needed config values
    CONTAINER_NAME="$(get_config "CONTAINER_NAME" "")"
    STORAGE_PATH="$(get_config "STORAGE_PATH" "")"
    HTTP_PORT="$(get_config "HTTP_PORT" "")"

    validate_not_empty "$CONTAINER_NAME" "CONTAINER_NAME"
    validate_not_empty "$STORAGE_PATH" "STORAGE_PATH"

    case "$action" in
        diagnose) diagnose ;;
        fix) fix ;;
    esac
}

main "$@"
