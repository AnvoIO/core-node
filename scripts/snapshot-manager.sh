#!/bin/bash

# Libre Blockchain Node Snapshot Manager
# Provides advanced snapshot management, scheduling, and restoration capabilities

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

# Source configuration utilities
source "$SCRIPT_DIR/config-utils.sh"

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

# Container name function is now provided by config-utils.sh

# Function to check if container is running
is_container_running() {
    local container=$1
    docker ps --format "table {{.Names}}" | grep -q "^$container$"
}

# Function to get current block number
get_current_block() {
    local network=$1
    local http_url=$(get_http_url "$network")
    
    local response=$(curl -s "$http_url/v1/chain/get_info" 2>/dev/null || echo "")
    if [[ -n "$response" ]]; then
        echo "$response" | grep -o '"head_block_num":[0-9]*' | cut -d':' -f2
    else
        echo "0"
    fi
}

# Function to create a snapshot
create_snapshot() {
    local network=$1
    local container=$(get_container_name $network)
    
    info "Creating snapshot for $network..."
    
    if ! is_container_running $container; then
        error "Container $container is not running"
        return 1
    fi
    
    # Create snapshots directory if it doesn't exist
    mkdir -p "$PROJECT_DIR/${network}/snapshots"
    
    # Get current block number for filename
    local current_block=$(get_current_block $network)
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local snapshot_file="$PROJECT_DIR/${network}/snapshots/snapshot_block_${current_block}_${timestamp}.bin"
    
    # Create snapshot using cleos
    info "Creating snapshot at block $current_block..."
    local http_url=$(get_http_url "$network")
    local result=$(docker exec $container cleos --url "$http_url" snapshot create "$snapshot_file" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        log "Snapshot created successfully: $snapshot_file"
        
        # Get snapshot info
        local snapshot_info=$(docker exec $container cleos --url "$http_url" snapshot info "$snapshot_file" 2>/dev/null || echo "")
        if [[ -n "$snapshot_info" ]]; then
            info "Snapshot info:"
            echo "$snapshot_info"
        fi
        
        # Create metadata file
        local metadata_file="${snapshot_file}.json"
        cat > "$metadata_file" << EOF
{
    "network": "$network",
    "block_number": "$current_block",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "filename": "$(basename "$snapshot_file")",
    "size_bytes": "$(stat -c %s "$snapshot_file" 2>/dev/null || echo "0")",
    "checksum": "$(sha256sum "$snapshot_file" | cut -d' ' -f1)"
}
EOF
        log "Metadata saved to: $metadata_file"
        
        return 0
    else
        error "Failed to create snapshot: $result"
        return 1
    fi
}

# Function to list available snapshots with details
list_snapshots() {
    local network=$1
    local snapshots_dir="$PROJECT_DIR/${network}/snapshots"
    
    if [[ ! -d "$snapshots_dir" ]]; then
        info "No snapshots directory found for $network"
        return 0
    fi
    
    local snapshots=($(find "$snapshots_dir" -name "*.bin" -type f 2>/dev/null | sort -r))
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        info "No snapshots found for $network"
        return 0
    fi
    
    info "Available snapshots for $network:"
    echo ""
    printf "%-50s %-15s %-20s %-10s %-15s\n" "Filename" "Block Number" "Date" "Size" "Checksum"
    printf "%-50s %-15s %-20s %-10s %-15s\n" "--------" "------------" "----" "----" "--------"
    
    for snapshot in "${snapshots[@]}"; do
        local filename=$(basename "$snapshot")
        local size=$(du -h "$snapshot" | cut -f1)
        local date=$(stat -c %y "$snapshot" 2>/dev/null | cut -d' ' -f1 || stat -f %Sm "$snapshot" 2>/dev/null | cut -d' ' -f1 || echo "Unknown")
        local checksum=$(sha256sum "$snapshot" | cut -d' ' -f1 | head -c 12)
        
        # Extract block number from filename
        local block_number="Unknown"
        if [[ $filename =~ block_([0-9]+)_ ]]; then
            block_number="${BASH_REMATCH[1]}"
        fi
        
        printf "%-50s %-15s %-20s %-10s %-15s\n" "$filename" "$block_number" "$date" "$size" "$checksum..."
    done
    echo ""
}

# Function to get snapshot details
get_snapshot_details() {
    local snapshot_file=$1
    
    if [[ ! -f "$snapshot_file" ]]; then
        error "Snapshot file not found: $snapshot_file"
        return 1
    fi
    
    local metadata_file="${snapshot_file}.json"
    
    echo "=== Snapshot Details ==="
    echo "File: $(basename "$snapshot_file")"
    echo "Size: $(du -h "$snapshot_file" | cut -f1)"
    echo "Created: $(stat -c %y "$snapshot_file" 2>/dev/null || stat -f %Sm "$snapshot_file" 2>/dev/null || echo "Unknown")"
    echo "Checksum: $(sha256sum "$snapshot_file" | cut -d' ' -f1)"
    
    if [[ -f "$metadata_file" ]]; then
        echo ""
        echo "Metadata:"
        cat "$metadata_file" | jq '.' 2>/dev/null || cat "$metadata_file"
    fi
}

# Function to validate snapshot integrity
validate_snapshot() {
    local snapshot_file=$1
    
    if [[ ! -f "$snapshot_file" ]]; then
        error "Snapshot file not found: $snapshot_file"
        return 1
    fi
    
    info "Validating snapshot: $(basename "$snapshot_file")"
    
    # Check file size
    local file_size=$(stat -c %s "$snapshot_file" 2>/dev/null || echo "0")
    if [[ $file_size -lt 1000 ]]; then
        error "Snapshot file appears to be too small ($file_size bytes)"
        return 1
    fi
    
    # Check if file is readable
    if [[ ! -r "$snapshot_file" ]]; then
        error "Snapshot file is not readable"
        return 1
    fi
    
    # Verify checksum if metadata exists
    local metadata_file="${snapshot_file}.json"
    if [[ -f "$metadata_file" ]]; then
        local stored_checksum=$(jq -r '.checksum' "$metadata_file" 2>/dev/null || echo "")
        local actual_checksum=$(sha256sum "$snapshot_file" | cut -d' ' -f1)
        
        if [[ -n "$stored_checksum" && "$stored_checksum" != "$actual_checksum" ]]; then
            error "Checksum mismatch! Stored: $stored_checksum, Actual: $actual_checksum"
            return 1
        fi
    fi
    
    log "Snapshot validation passed"
    return 0
}

# Function to restore from snapshot
restore_from_snapshot() {
    local network=$1
    local snapshot_file=$2
    local container=$(get_container_name $network)
    
    if [[ -z "$snapshot_file" ]]; then
        error "Snapshot file path is required"
        echo "Usage: $0 restore <network> <snapshot_file>"
        return 1
    fi
    
    if [[ ! -f "$snapshot_file" ]]; then
        error "Snapshot file not found: $snapshot_file"
        return 1
    fi
    
    # Validate snapshot
    if ! validate_snapshot "$snapshot_file"; then
        error "Snapshot validation failed"
        return 1
    fi
    
    info "Restoring $network from snapshot: $snapshot_file"
    
    # Stop the node
    if is_container_running $container; then
        info "Stopping node..."
        docker stop $container
    fi
    
    # Create backup
    local backup_dir="$PROJECT_DIR/${network}/data/backup_restore_$(date +%Y%m%d_%H%M%S)"
    if [[ -d "$PROJECT_DIR/${network}/data/blocks" ]]; then
        info "Creating backup of current data..."
        mkdir -p "$backup_dir"
        cp -r "$PROJECT_DIR/${network}/data/blocks" "$backup_dir/"
        cp -r "$PROJECT_DIR/${network}/data/state" "$backup_dir/" 2>/dev/null || true
        log "Backup created at: $backup_dir"
    fi
    
    # Remove existing blockchain data
    info "Removing existing blockchain data..."
    rm -rf "$PROJECT_DIR/${network}/data/blocks"
    rm -rf "$PROJECT_DIR/${network}/data/state"
    
    # Copy snapshot to data directory
    local snapshot_dest="$PROJECT_DIR/${network}/data/snapshot.bin"
    info "Copying snapshot to data directory..."
    cp "$snapshot_file" "$snapshot_dest"
    
    # Start node with snapshot
    info "Starting node with snapshot..."
    docker run --rm \
        --name "${container}-snapshot-restore" \
        --network libre-network \
        -v "$PROJECT_DIR/${network}/config:/opt/eosio/config" \
        -v "$PROJECT_DIR/${network}/data:/opt/eosio/data" \
        -v "$PROJECT_DIR/${network}/logs:/opt/eosio/logs" \
        libre-node:5.0.3 \
        nodeos \
        --config-dir /opt/eosio/config \
        --data-dir /opt/eosio/data \
        --genesis-json /opt/eosio/config/genesis.json \
        --http-server-address=0.0.0.0:9888 \
        --p2p-listen-endpoint=0.0.0.0:9876 \
        --p2p-peer-address=p2p.libre.iad.cryptobloks.io:9876 \
        --p2p-peer-address=p2p.libre.pdx.cryptobloks.io:9876 \
        --state-history-endpoint=0.0.0.0:9080 \
        --contracts-console \
        --verbose-http-errors \
        --max-transaction-time=1000 \
        --abi-serializer-max-time-ms=2000 \
        --chain-threads=4 \
        --http-threads=6 \
        --snapshot "$snapshot_dest" &
    
    local snapshot_pid=$!
    
    info "Snapshot restoration process started with PID: $snapshot_pid"
    info "Monitor progress with: ./scripts/logs.sh $network"
    info "To stop restoration process: kill $snapshot_pid"
    
    # Wait for snapshot to complete
    log "Waiting for snapshot restoration to complete..."
    wait $snapshot_pid
    
    if [[ $? -eq 0 ]]; then
        log "Snapshot restored successfully"
        
        # Remove snapshot file
        rm -f "$snapshot_dest"
        
        # Start the normal node
        info "Starting normal node operation..."
        docker start $container
        
        # Wait for node to come online
        local max_attempts=30
        local attempt=0
        while [[ $attempt -lt $max_attempts ]]; do
            if is_container_running $container; then
                sleep 2
                local http_url=$(get_http_url "$network")
                local response=$(curl -s "$http_url/v1/chain/get_info" 2>/dev/null || echo "")
                if [[ -n "$response" ]]; then
                    log "Node is back online after snapshot restoration"
                    return 0
                fi
            fi
            attempt=$((attempt + 1))
            sleep 2
        done
        
        error "Node failed to come back online after restoration"
        return 1
    else
        error "Snapshot restoration failed"
        return 1
    fi
}

# Function to clean up old snapshots
cleanup_snapshots() {
    local network=$1
    local keep_days=${2:-30}
    local snapshots_dir="$PROJECT_DIR/${network}/snapshots"
    
    if [[ ! -d "$snapshots_dir" ]]; then
        info "No snapshots directory found for $network"
        return 0
    fi
    
    info "Cleaning up snapshots older than $keep_days days for $network..."
    
    # Find old snapshots
    local old_snapshots=($(find "$snapshots_dir" -name "*.bin" -type f -mtime +$keep_days 2>/dev/null))
    
    if [[ ${#old_snapshots[@]} -eq 0 ]]; then
        info "No old snapshots to clean up"
        return 0
    fi
    
    local total_size=0
    for snapshot in "${old_snapshots[@]}"; do
        local size=$(stat -c %s "$snapshot" 2>/dev/null || echo "0")
        total_size=$((total_size + size))
        
        info "Removing: $(basename "$snapshot")"
        rm -f "$snapshot"
        
        # Remove metadata file if it exists
        local metadata_file="${snapshot}.json"
        if [[ -f "$metadata_file" ]]; then
            rm -f "$metadata_file"
        fi
    done
    
    local total_size_mb=$((total_size / 1024 / 1024))
    log "Cleaned up ${#old_snapshots[@]} snapshots, freed ${total_size_mb}MB"
}

# Function to schedule automatic snapshots
schedule_snapshots() {
    local network=$1
    local interval_hours=${2:-24}
    local snapshots_dir="$PROJECT_DIR/${network}/snapshots"
    
    info "Setting up automatic snapshot schedule for $network (every ${interval_hours} hours)"
    
    # Create snapshots directory if it doesn't exist
    mkdir -p "$snapshots_dir"
    
    # Create cron job
    local cron_job="0 */${interval_hours} * * * cd $PROJECT_DIR && ./scripts/snapshot-manager.sh create $network >> $snapshots_dir/snapshot.log 2>&1"
    
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "snapshot-manager.sh create $network"; then
        warn "Snapshot schedule already exists for $network"
        echo "Current cron jobs for $network:"
        crontab -l 2>/dev/null | grep "snapshot-manager.sh create $network"
        return 0
    fi
    
    # Add cron job
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    
    log "Snapshot schedule created successfully"
    log "Next snapshot will be created in ${interval_hours} hours"
}

# Function to remove snapshot schedule
remove_schedule() {
    local network=$1
    
    info "Removing snapshot schedule for $network..."
    
    # Remove cron jobs for this network
    local temp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -v "snapshot-manager.sh create $network" > "$temp_cron"
    crontab "$temp_cron"
    rm -f "$temp_cron"
    
    log "Snapshot schedule removed for $network"
}

# Function to show snapshot schedule status
show_schedule() {
    local network=$1
    
    info "Snapshot schedule status for $network:"
    
    local scheduled_jobs=$(crontab -l 2>/dev/null | grep "snapshot-manager.sh create $network" || echo "")
    
    if [[ -n "$scheduled_jobs" ]]; then
        echo "Scheduled jobs:"
        echo "$scheduled_jobs"
    else
        echo "No snapshot schedule found for $network"
    fi
}

# Function to export snapshot
export_snapshot() {
    local snapshot_file=$1
    local export_path=$2
    
    if [[ -z "$snapshot_file" || -z "$export_path" ]]; then
        error "Snapshot file and export path are required"
        echo "Usage: $0 export <snapshot_file> <export_path>"
        return 1
    fi
    
    if [[ ! -f "$snapshot_file" ]]; then
        error "Snapshot file not found: $snapshot_file"
        return 1
    fi
    
    info "Exporting snapshot to: $export_path"
    
    # Create export directory if it doesn't exist
    mkdir -p "$(dirname "$export_path")"
    
    # Copy snapshot file
    cp "$snapshot_file" "$export_path"
    
    # Copy metadata if it exists
    local metadata_file="${snapshot_file}.json"
    if [[ -f "$metadata_file" ]]; then
        cp "$metadata_file" "${export_path}.json"
    fi
    
    log "Snapshot exported successfully"
    log "File: $export_path"
    log "Size: $(du -h "$export_path" | cut -f1)"
}

# Function to import snapshot
import_snapshot() {
    local network=$1
    local import_file=$2
    
    if [[ -z "$network" || -z "$import_file" ]]; then
        error "Network and import file are required"
        echo "Usage: $0 import <network> <import_file>"
        return 1
    fi
    
    if [[ ! -f "$import_file" ]]; then
        error "Import file not found: $import_file"
        return 1
    fi
    
    info "Importing snapshot for $network from: $import_file"
    
    # Create snapshots directory if it doesn't exist
    mkdir -p "$PROJECT_DIR/${network}/snapshots"
    
    # Generate new filename
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local new_filename="imported_snapshot_${timestamp}.bin"
    local dest_path="$PROJECT_DIR/${network}/snapshots/$new_filename"
    
    # Copy file
    cp "$import_file" "$dest_path"
    
    # Copy metadata if it exists
    local import_metadata="${import_file}.json"
    if [[ -f "$import_metadata" ]]; then
        cp "$import_metadata" "${dest_path}.json"
    fi
    
    log "Snapshot imported successfully"
    log "Location: $dest_path"
    
    # Validate the imported snapshot
    if validate_snapshot "$dest_path"; then
        log "Imported snapshot validation passed"
    else
        warn "Imported snapshot validation failed"
    fi
}

# Function to show snapshot manager help
show_help() {
    echo "Libre Blockchain Node Snapshot Manager"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  create <network>                     - Create a new snapshot"
    echo "  list <network>                       - List available snapshots"
    echo "  details <snapshot_file>              - Show snapshot details"
    echo "  validate <snapshot_file>             - Validate snapshot integrity"
    echo "  restore <network> <snapshot_file>    - Restore from snapshot"
    echo "  cleanup <network> [days]             - Clean up old snapshots (default: 30 days)"
    echo "  schedule <network> [hours]           - Schedule automatic snapshots (default: 24 hours)"
    echo "  remove-schedule <network>            - Remove snapshot schedule"
    echo "  show-schedule <network>              - Show current schedule"
    echo "  export <snapshot_file> <export_path> - Export snapshot to external location"
    echo "  import <network> <import_file>       - Import snapshot from external location"
    echo "  help                                 - Show this help message"
    echo ""
    echo "Networks:"
    echo "  mainnet                              - Libre mainnet"
    echo "  testnet                              - Libre testnet"
    echo ""
    echo "Examples:"
    echo "  $0 create mainnet"
    echo "  $0 list mainnet"
    echo "  $0 restore mainnet /path/to/snapshot.bin"
    echo "  $0 schedule mainnet 12"
    echo "  $0 export /path/to/snapshot.bin /backup/snapshot.bin"
}

# Main script logic
main() {
    local command=$1
    local arg1=$2
    local arg2=$3
    local arg3=$4
    
    case $command in
        "create")
            if [[ -z "$arg1" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$arg1"; then
                error "Invalid network: $arg1"
                exit 1
            fi
            create_snapshot "$arg1"
            ;;
        "list")
            if [[ -z "$arg1" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$arg1"; then
                error "Invalid network: $arg1"
                exit 1
            fi
            list_snapshots "$arg1"
            ;;
        "details")
            if [[ -z "$arg1" ]]; then
                error "Snapshot file parameter required"
                show_help
                exit 1
            fi
            get_snapshot_details "$arg1"
            ;;
        "validate")
            if [[ -z "$arg1" ]]; then
                error "Snapshot file parameter required"
                show_help
                exit 1
            fi
            validate_snapshot "$arg1"
            ;;
        "restore")
            if [[ -z "$arg1" || -z "$arg2" ]]; then
                error "Network and snapshot file parameters required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$arg1"; then
                error "Invalid network: $arg1"
                exit 1
            fi
            restore_from_snapshot "$arg1" "$arg2"
            ;;
        "cleanup")
            if [[ -z "$arg1" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$arg1"; then
                error "Invalid network: $arg1"
                exit 1
            fi
            cleanup_snapshots "$arg1" "$arg2"
            ;;
        "schedule")
            if [[ -z "$arg1" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$arg1"; then
                error "Invalid network: $arg1"
                exit 1
            fi
            schedule_snapshots "$arg1" "$arg2"
            ;;
        "remove-schedule")
            if [[ -z "$arg1" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$arg1"; then
                error "Invalid network: $arg1"
                exit 1
            fi
            remove_schedule "$arg1"
            ;;
        "show-schedule")
            if [[ -z "$arg1" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$arg1"; then
                error "Invalid network: $arg1"
                exit 1
            fi
            show_schedule "$arg1"
            ;;
        "export")
            if [[ -z "$arg1" || -z "$arg2" ]]; then
                error "Snapshot file and export path parameters required"
                show_help
                exit 1
            fi
            export_snapshot "$arg1" "$arg2"
            ;;
        "import")
            if [[ -z "$arg1" || -z "$arg2" ]]; then
                error "Network and import file parameters required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$arg1"; then
                error "Invalid network: $arg1"
                exit 1
            fi
            import_snapshot "$arg1" "$arg2"
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