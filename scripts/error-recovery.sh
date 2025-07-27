#!/bin/bash

# Libre Blockchain Node Error Recovery Script
# Handles common error conditions and provides automated recovery options

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Network options
NETWORKS=("mainnet" "testnet")

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if a network is valid
is_valid_network() {
    local network=$1
    for n in "${NETWORKS[@]}"; do
        if [[ "$n" == "$network" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to get container name for network
get_container_name() {
    local network=$1
    case $network in
        "mainnet")
            echo "libre-mainnet-api"
            ;;
        "testnet")
            echo "libre-testnet-api"
            ;;
        *)
            error "Invalid network: $network"
            exit 1
            ;;
    esac
}

# Function to check if container is running
is_container_running() {
    local container=$1
    docker ps --format "table {{.Names}}" | grep -q "^$container$"
}

# Function to check if container exists
container_exists() {
    local container=$1
    docker ps -a --format "table {{.Names}}" | grep -q "^$container$"
}

# Function to get container logs
get_container_logs() {
    local container=$1
    local lines=${2:-50}
    docker logs --tail $lines $container 2>/dev/null || echo "No logs available"
}

# Function to check disk space
check_disk_space() {
    local data_dir="$PROJECT_DIR/$1/data"
    local available_space=$(df -h "$data_dir" | awk 'NR==2 {print $4}')
    local used_space=$(df -h "$data_dir" | awk 'NR==2 {print $3}')
    local total_space=$(df -h "$data_dir" | awk 'NR==2 {print $2}')
    
    echo "Disk space for $1:"
    echo "  Used: $used_space"
    echo "  Available: $available_space"
    echo "  Total: $total_space"
    
    # Check if available space is less than 10GB
    local available_gb=$(df "$data_dir" | awk 'NR==2 {print $4}')
    if [[ $available_gb -lt 10485760 ]]; then  # 10GB in KB
        warn "Low disk space detected! Available: ${available_space}"
        return 1
    fi
    
    return 0
}

# Function to check memory usage
check_memory_usage() {
    local container=$1
    local memory_info=$(docker stats --no-stream --format "table {{.MemUsage}}" $container 2>/dev/null || echo "N/A")
    echo "Memory usage for $container: $memory_info"
}

# Function to check API connectivity
check_api_connectivity() {
    local network=$1
    local port
    
    case $network in
        "mainnet")
            port=9888
            ;;
        "testnet")
            port=9889
            ;;
    esac
    
    local response=$(curl -s --max-time 10 "http://localhost:$port/v1/chain/get_info" 2>/dev/null || echo "")
    if [[ -n "$response" ]]; then
        local head_block=$(echo "$response" | grep -o '"head_block_num":[0-9]*' | cut -d':' -f2)
        local last_irreversible=$(echo "$response" | grep -o '"last_irreversible_block_num":[0-9]*' | cut -d':' -f2)
        
        if [[ -n "$head_block" && -n "$last_irreversible" ]]; then
            local sync_diff=$((head_block - last_irreversible))
            echo "API Status: OK"
            echo "  Head Block: $head_block"
            echo "  Last Irreversible: $last_irreversible"
            echo "  Sync Difference: $sync_diff blocks"
            
            if [[ $sync_diff -gt 100 ]]; then
                warn "Node is significantly behind (${sync_diff} blocks)"
                return 1
            fi
            return 0
        else
            echo "API Status: ERROR - Invalid response format"
            return 1
        fi
    else
        echo "API Status: ERROR - No response"
        return 1
    fi
}

# Function to check for common error patterns in logs
analyze_logs() {
    local network=$1
    local container=$(get_container_name $network)
    local logs=$(get_container_logs $container 100)
    
    echo "=== Log Analysis for $network ==="
    
    # Check for common error patterns
    local error_count=$(echo "$logs" | grep -i "error\|exception\|fatal" | wc -l)
    local warning_count=$(echo "$logs" | grep -i "warning" | wc -l)
    
    echo "Error count: $error_count"
    echo "Warning count: $warning_count"
    
    # Check for specific error patterns
    if echo "$logs" | grep -q "database.*corrupt\|corruption"; then
        error "DATABASE CORRUPTION DETECTED"
        echo "Recent database errors:"
        echo "$logs" | grep -i "database.*corrupt\|corruption" | tail -5
        return 1
    fi
    
    if echo "$logs" | grep -q "out of memory\|memory.*exhausted"; then
        error "MEMORY EXHAUSTION DETECTED"
        echo "Recent memory errors:"
        echo "$logs" | grep -i "out of memory\|memory.*exhausted" | tail -5
        return 1
    fi
    
    if echo "$logs" | grep -q "disk.*full\|no space left"; then
        error "DISK SPACE EXHAUSTION DETECTED"
        echo "Recent disk space errors:"
        echo "$logs" | grep -i "disk.*full\|no space left" | tail -5
        return 1
    fi
    
    if echo "$logs" | grep -q "connection.*refused\|peer.*unreachable"; then
        warn "NETWORK CONNECTIVITY ISSUES DETECTED"
        echo "Recent network errors:"
        echo "$logs" | grep -i "connection.*refused\|peer.*unreachable" | tail -5
        return 1
    fi
    
    if echo "$logs" | grep -q "fork.*detected\|fork.*db"; then
        error "FORK DETECTED"
        echo "Recent fork errors:"
        echo "$logs" | grep -i "fork.*detected\|fork.*db" | tail -5
        return 1
    fi
    
    if [[ $error_count -gt 0 ]]; then
        warn "General errors detected in logs"
        echo "Recent errors:"
        echo "$logs" | grep -i "error" | tail -5
        return 1
    fi
    
    log "No critical errors detected in recent logs"
    return 0
}

# Function to diagnose node issues
diagnose_node() {
    local network=$1
    local container=$(get_container_name $network)
    
    info "Diagnosing $network node..."
    
    echo "=== Node Diagnosis Report ==="
    echo "Network: $network"
    echo "Container: $container"
    echo "Timestamp: $(date)"
    echo ""
    
    # Check container status
    echo "1. Container Status:"
    if container_exists $container; then
        if is_container_running $container; then
            log "Container is running"
        else
            error "Container exists but is not running"
            echo "Container logs:"
            get_container_logs $container 20
            return 1
        fi
    else
        error "Container does not exist"
        return 1
    fi
    echo ""
    
    # Check disk space
    echo "2. Disk Space:"
    if ! check_disk_space $network; then
        return 1
    fi
    echo ""
    
    # Check memory usage
    echo "3. Memory Usage:"
    check_memory_usage $container
    echo ""
    
    # Check API connectivity
    echo "4. API Connectivity:"
    if ! check_api_connectivity $network; then
        return 1
    fi
    echo ""
    
    # Analyze logs
    echo "5. Log Analysis:"
    if ! analyze_logs $network; then
        return 1
    fi
    echo ""
    
    log "Node diagnosis completed successfully"
    return 0
}

# Function to fix database corruption
fix_database_corruption() {
    local network=$1
    local container=$(get_container_name $network)
    
    info "Attempting to fix database corruption for $network..."
    
    # Stop the node
    if is_container_running $container; then
        info "Stopping node..."
        docker stop $container
    fi
    
    # Create backup
    local backup_dir="$PROJECT_DIR/${network}/data/backup_corruption_$(date +%Y%m%d_%H%M%S)"
    if [[ -d "$PROJECT_DIR/${network}/data/blocks" ]]; then
        info "Creating backup of current data..."
        mkdir -p "$backup_dir"
        cp -r "$PROJECT_DIR/${network}/data/blocks" "$backup_dir/"
        cp -r "$PROJECT_DIR/${network}/data/state" "$backup_dir/" 2>/dev/null || true
        log "Backup created at: $backup_dir"
    fi
    
    # Remove corrupted data
    info "Removing potentially corrupted data..."
    rm -rf "$PROJECT_DIR/${network}/data/blocks"
    rm -rf "$PROJECT_DIR/${network}/data/state"
    
    # Start fresh sync
    info "Starting fresh blockchain sync..."
    docker start $container
    
    # Wait for node to start
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if is_container_running $container; then
            sleep 2
            if check_api_connectivity $network >/dev/null 2>&1; then
                log "Node restarted successfully and is syncing"
                return 0
            fi
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    error "Failed to restart node after corruption fix"
    return 1
}

# Function to fix memory issues
fix_memory_issues() {
    local network=$1
    local container=$(get_container_name $network)
    
    info "Attempting to fix memory issues for $network..."
    
    # Restart container to clear memory
    info "Restarting container to clear memory..."
    docker restart $container
    
    # Wait for restart
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if is_container_running $container; then
            sleep 2
            if check_api_connectivity $network >/dev/null 2>&1; then
                log "Container restarted successfully"
                
                # Check memory usage after restart
                info "Memory usage after restart:"
                check_memory_usage $container
                return 0
            fi
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    error "Failed to restart container"
    return 1
}

# Function to fix disk space issues
fix_disk_space_issues() {
    local network=$1
    
    info "Attempting to fix disk space issues for $network..."
    
    # Clean up old backups
    local backup_dir="$PROJECT_DIR/${network}/data"
    if [[ -d "$backup_dir" ]]; then
        info "Cleaning up old backups..."
        find "$backup_dir" -name "backup_*" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
        log "Old backups cleaned up"
    fi
    
    # Clean up old snapshots
    local snapshots_dir="$PROJECT_DIR/${network}/snapshots"
    if [[ -d "$snapshots_dir" ]]; then
        info "Cleaning up old snapshots..."
        find "$snapshots_dir" -name "*.bin" -type f -mtime +30 -delete 2>/dev/null || true
        log "Old snapshots cleaned up"
    fi
    
    # Clean up old logs
    local logs_dir="$PROJECT_DIR/${network}/logs"
    if [[ -d "$logs_dir" ]]; then
        info "Cleaning up old logs..."
        find "$logs_dir" -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
        log "Old logs cleaned up"
    fi
    
    # Check disk space after cleanup
    info "Disk space after cleanup:"
    check_disk_space $network
}

# Function to fix network connectivity issues
fix_network_issues() {
    local network=$1
    local container=$(get_container_name $network)
    
    info "Attempting to fix network connectivity issues for $network..."
    
    # Restart container
    info "Restarting container to reset network connections..."
    docker restart $container
    
    # Wait for restart
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if is_container_running $container; then
            sleep 2
            if check_api_connectivity $network >/dev/null 2>&1; then
                log "Network connectivity restored"
                return 0
            fi
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    error "Failed to restore network connectivity"
    return 1
}

# Function to fix fork issues
fix_fork_issues() {
    local network=$1
    local container=$(get_container_name $network)
    
    info "Attempting to fix fork issues for $network..."
    
    # Stop the node
    if is_container_running $container; then
        info "Stopping node..."
        docker stop $container
    fi
    
    # Create backup
    local backup_dir="$PROJECT_DIR/${network}/data/backup_fork_$(date +%Y%m%d_%H%M%S)"
    if [[ -d "$PROJECT_DIR/${network}/data/blocks" ]]; then
        info "Creating backup of current data..."
        mkdir -p "$backup_dir"
        cp -r "$PROJECT_DIR/${network}/data/blocks" "$backup_dir/"
        cp -r "$PROJECT_DIR/${network}/data/state" "$backup_dir/" 2>/dev/null || true
        log "Backup created at: $backup_dir"
    fi
    
    # Remove recent blocks to resolve fork
    info "Removing recent blocks to resolve fork..."
    rm -rf "$PROJECT_DIR/${network}/data/blocks"
    rm -rf "$PROJECT_DIR/${network}/data/state"
    
    # Start node to resync
    info "Starting node to resync..."
    docker start $container
    
    # Wait for node to start
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if is_container_running $container; then
            sleep 2
            if check_api_connectivity $network >/dev/null 2>&1; then
                log "Node restarted and is resyncing to resolve fork"
                return 0
            fi
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    error "Failed to restart node after fork fix"
    return 1
}

# Function to perform automatic error recovery
auto_recovery() {
    local network=$1
    
    info "Starting automatic error recovery for $network..."
    
    # First, diagnose the issue
    if diagnose_node $network; then
        log "No issues detected, node is healthy"
        return 0
    fi
    
    # Get container logs to determine the issue
    local container=$(get_container_name $network)
    local logs=$(get_container_logs $container 50)
    
    # Determine the type of issue and apply appropriate fix
    if echo "$logs" | grep -q "database.*corrupt\|corruption"; then
        warn "Database corruption detected, attempting fix..."
        fix_database_corruption $network
    elif echo "$logs" | grep -q "out of memory\|memory.*exhausted"; then
        warn "Memory issues detected, attempting fix..."
        fix_memory_issues $network
    elif echo "$logs" | grep -q "disk.*full\|no space left"; then
        warn "Disk space issues detected, attempting fix..."
        fix_disk_space_issues $network
    elif echo "$logs" | grep -q "connection.*refused\|peer.*unreachable"; then
        warn "Network connectivity issues detected, attempting fix..."
        fix_network_issues $network
    elif echo "$logs" | grep -q "fork.*detected\|fork.*db"; then
        warn "Fork detected, attempting fix..."
        fix_fork_issues $network
    else
        warn "Unknown issue detected, attempting general restart..."
        docker restart $container
        
        # Wait for restart
        local max_attempts=30
        local attempt=0
        while [[ $attempt -lt $max_attempts ]]; do
            if is_container_running $container; then
                sleep 2
                if check_api_connectivity $network >/dev/null 2>&1; then
                    log "General restart successful"
                    return 0
                fi
            fi
            attempt=$((attempt + 1))
            sleep 2
        done
        
        error "General restart failed"
        return 1
    fi
    
    # Verify the fix worked
    sleep 10
    if diagnose_node $network; then
        log "Error recovery completed successfully"
        return 0
    else
        error "Error recovery failed"
        return 1
    fi
}

# Function to show error recovery help
show_help() {
    echo "Libre Blockchain Node Error Recovery Script"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  diagnose <network>                   - Diagnose node issues"
    echo "  auto-recovery <network>              - Automatically detect and fix issues"
    echo "  fix-corruption <network>             - Fix database corruption"
    echo "  fix-memory <network>                 - Fix memory issues"
    echo "  fix-disk <network>                   - Fix disk space issues"
    echo "  fix-network <network>                - Fix network connectivity issues"
    echo "  fix-fork <network>                   - Fix fork issues"
    echo "  help                                 - Show this help message"
    echo ""
    echo "Networks:"
    echo "  mainnet                              - Libre mainnet"
    echo "  testnet                              - Libre testnet"
    echo ""
    echo "Examples:"
    echo "  $0 diagnose mainnet"
    echo "  $0 auto-recovery mainnet"
    echo "  $0 fix-corruption mainnet"
}

# Main script logic
main() {
    local command=$1
    local network=$2
    
    case $command in
        "diagnose")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            diagnose_node "$network"
            ;;
        "auto-recovery")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            auto_recovery "$network"
            ;;
        "fix-corruption")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            fix_database_corruption "$network"
            ;;
        "fix-memory")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            fix_memory_issues "$network"
            ;;
        "fix-disk")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            fix_disk_space_issues "$network"
            ;;
        "fix-network")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            fix_network_issues "$network"
            ;;
        "fix-fork")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            fix_fork_issues "$network"
            ;;
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        *)
            error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@" 