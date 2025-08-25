#!/bin/bash

# Libre Blockchain Node Maintenance Script
# Provides functions for error recovery, blockchain replay, and snapshot operations

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

# Function to check if container exists
container_exists() {
    local container=$1
    docker ps -a --format "table {{.Names}}" | grep -q "^$container$"
}

# Function to get current block number
get_current_block() {
    local network=$1
    local container=$(get_container_name $network)
    
    if ! is_container_running $container; then
        error "Container $container is not running"
        return 1
    fi
    
    local http_url=$(get_http_url "$network")
    local response=$(curl -s "$http_url/v1/chain/get_info" 2>/dev/null || echo "")
    if [[ -n "$response" ]]; then
        echo "$response" | grep -o '"head_block_num":[0-9]*' | cut -d':' -f2
    else
        echo "0"
    fi
}

# Function to get current head block ID
get_head_block_id() {
    local network=$1
    local container=$(get_container_name $network)
    
    if ! is_container_running $container; then
        error "Container $container is not running"
        return 1
    fi
    
    local http_url=$(get_http_url "$network")
    local response=$(curl -s "$http_url/v1/chain/get_info" 2>/dev/null || echo "")
    if [[ -n "$response" ]]; then
        echo "$response" | grep -o '"head_block_id":"[^"]*"' | cut -d'"' -f4
    else
        echo ""
    fi
}

# Function to check node health
check_node_health() {
    local network=$1
    local container=$(get_container_name $network)
    
    info "Checking health for $network node..."
    
    if ! container_exists $container; then
        error "Container $container does not exist"
        return 1
    fi
    
    if ! is_container_running $container; then
        error "Container $container is not running"
        return 1
    fi
    
    local http_url=$(get_http_url "$network")
    
    # Check if API is responding
    local response=$(curl -s "$http_url/v1/chain/get_info" 2>/dev/null || echo "")
    if [[ -z "$response" ]]; then
        error "API endpoint not responding at $http_url"
        return 1
    fi
    
    # Check if node is syncing
    local head_block=$(echo "$response" | grep -o '"head_block_num":[0-9]*' | cut -d':' -f2)
    local last_irreversible=$(echo "$response" | grep -o '"last_irreversible_block_num":[0-9]*' | cut -d':' -f2)
    
    if [[ -n "$head_block" && -n "$last_irreversible" ]]; then
        local sync_diff=$((head_block - last_irreversible))
        if [[ $sync_diff -gt 100 ]]; then
            warn "Node is behind by $sync_diff blocks"
        else
            log "Node is healthy - Head: $head_block, Irreversible: $last_irreversible"
        fi
    else
        error "Could not determine block numbers"
        return 1
    fi
}

# Function to stop a specific node
stop_node() {
    local network=$1
    local container=$(get_container_name $network)
    
    info "Stopping $network node..."
    
    if is_container_running $container; then
        docker stop $container
        log "$network node stopped"
    else
        warn "$network node is not running"
    fi
}

# Function to start a specific node
start_node() {
    local network=$1
    local container=$(get_container_name $network)
    
    info "Starting $network node..."
    
    if ! container_exists $container; then
        error "Container $container does not exist. Run ./scripts/start.sh first."
        return 1
    fi
    
    if is_container_running $container; then
        warn "$network node is already running"
        return 0
    fi
    
    docker start $container
    
    # Wait for node to start
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if is_container_running $container; then
            sleep 2
            if check_node_health $network >/dev/null 2>&1; then
                log "$network node started successfully"
                return 0
            fi
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    error "$network node failed to start properly"
    return 1
}

# Function to restart a specific node
restart_node() {
    local network=$1
    local container=$(get_container_name $network)
    
    info "Restarting $network node..."
    
    if is_container_running $container; then
        docker restart $container
        log "$network node restarted"
        
        # Wait for node to come back online
        local max_attempts=30
        local attempt=0
        while [[ $attempt -lt $max_attempts ]]; do
            if check_node_health $network >/dev/null 2>&1; then
                log "$network node is back online"
                return 0
            fi
            attempt=$((attempt + 1))
            sleep 2
        done
        
        error "$network node failed to come back online"
        return 1
    else
        warn "$network node is not running, starting it..."
        start_node $network
    fi
}

# Function to replay blockchain from a specific block
replay_blockchain() {
    local network=$1
    local start_block=${2:-0}
    local container=$(get_container_name $network)
    
    info "Starting blockchain replay for $network from block $start_block..."
    
    # Stop the node
    stop_node $network
    
    # Backup current data
    local backup_dir="$PROJECT_DIR/${network}/data/backup_$(date +%Y%m%d_%H%M%S)"
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
    
    # Start node with replay flag
    info "Starting node with replay mode..."
    docker run --rm \
        --name "${container}-replay" \
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
        --replay-blockchain \
        --replay-blockchain-start-block=$start_block &
    
    local replay_pid=$!
    
    info "Replay process started with PID: $replay_pid"
    info "Monitor progress with: ./scripts/logs.sh $network"
    info "To stop replay: kill $replay_pid"
    
    # Wait for replay to complete
    log "Waiting for replay to complete..."
    wait $replay_pid
    
    if [[ $? -eq 0 ]]; then
        log "Replay completed successfully"
        
        # Start the normal node
        start_node $network
    else
        error "Replay failed"
        return 1
    fi
}

# Function to start from a snapshot
start_from_snapshot() {
    local network=$1
    local snapshot_file=$2
    
    if [[ -z "$snapshot_file" ]]; then
        error "Snapshot file path is required"
        echo "Usage: $0 start-from-snapshot <network> <snapshot_file>"
        return 1
    fi
    
    if [[ ! -f "$snapshot_file" ]]; then
        error "Snapshot file not found: $snapshot_file"
        return 1
    fi
    
    info "Starting $network from snapshot: $snapshot_file"
    
    # Stop the node
    stop_node $network
    
    # Backup current data
    local backup_dir="$PROJECT_DIR/${network}/data/backup_$(date +%Y%m%d_%H%M%S)"
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
        --name "${container}-snapshot" \
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
    
    info "Snapshot process started with PID: $snapshot_pid"
    info "Monitor progress with: ./scripts/logs.sh $network"
    info "To stop snapshot process: kill $snapshot_pid"
    
    # Wait for snapshot to complete
    log "Waiting for snapshot to complete..."
    wait $snapshot_pid
    
    if [[ $? -eq 0 ]]; then
        log "Snapshot loaded successfully"
        
        # Remove snapshot file
        rm -f "$snapshot_dest"
        
        # Start the normal node
        start_node $network
    else
        error "Snapshot loading failed"
        return 1
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
    
    # Generate snapshot filename with timestamp
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local snapshot_file="$PROJECT_DIR/${network}/snapshots/snapshot_${timestamp}.bin"
    
    # Create snapshot using cleos
    info "Creating snapshot..."
    local http_url=$(get_http_url "$network")
    docker exec $container cleos --url "$http_url" snapshot create "$snapshot_file"
    
    if [[ $? -eq 0 ]]; then
        log "Snapshot created successfully: $snapshot_file"
        
        # Get snapshot info
        local snapshot_info=$(docker exec $container cleos --url "$http_url" snapshot info "$snapshot_file" 2>/dev/null || echo "")
        if [[ -n "$snapshot_info" ]]; then
            info "Snapshot info:"
            echo "$snapshot_info"
        fi
    else
        error "Failed to create snapshot"
        return 1
    fi
}

# Function to list available snapshots
list_snapshots() {
    local network=$1
    
    local snapshots_dir="$PROJECT_DIR/${network}/snapshots"
    
    if [[ ! -d "$snapshots_dir" ]]; then
        info "No snapshots directory found for $network"
        return 0
    fi
    
    local snapshots=($(find "$snapshots_dir" -name "*.bin" -type f 2>/dev/null))
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        info "No snapshots found for $network"
        return 0
    fi
    
    info "Available snapshots for $network:"
    for snapshot in "${snapshots[@]}"; do
        local filename=$(basename "$snapshot")
        local size=$(du -h "$snapshot" | cut -f1)
        local date=$(stat -c %y "$snapshot" 2>/dev/null || stat -f %Sm "$snapshot" 2>/dev/null || echo "Unknown")
        echo "  - $filename ($size, $date)"
    done
}

# Function to show maintenance help
show_help() {
    echo "Libre Blockchain Node Maintenance Script"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  health <network>                    - Check node health"
    echo "  stop <network>                      - Stop a specific node"
    echo "  start <network>                     - Start a specific node"
    echo "  restart <network>                   - Restart a specific node"
    echo "  replay <network> [start_block]      - Replay blockchain from block (default: 0)"
    echo "  create-snapshot <network>           - Create a new snapshot"
    echo "  list-snapshots <network>            - List available snapshots"
    echo "  start-from-snapshot <network> <file> - Start from a snapshot file"
    echo "  help                                - Show this help message"
    echo ""
    echo "Networks:"
    echo "  mainnet                             - Libre mainnet"
    echo "  testnet                             - Libre testnet"
    echo ""
    echo "Examples:"
    echo "  $0 health mainnet"
    echo "  $0 replay mainnet 1000000"
    echo "  $0 create-snapshot mainnet"
    echo "  $0 start-from-snapshot mainnet /path/to/snapshot.bin"
}

# Main script logic
main() {
    local command=$1
    local network=$2
    local arg3=$3
    
    case $command in
        "health")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            check_node_health "$network"
            ;;
        "stop")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            stop_node "$network"
            ;;
        "start")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            start_node "$network"
            ;;
        "restart")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            restart_node "$network"
            ;;
        "replay")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            replay_blockchain "$network" "$arg3"
            ;;
        "create-snapshot")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            create_snapshot "$network"
            ;;
        "list-snapshots")
            if [[ -z "$network" ]]; then
                error "Network parameter required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            list_snapshots "$network"
            ;;
        "start-from-snapshot")
            if [[ -z "$network" || -z "$arg3" ]]; then
                error "Network and snapshot file parameters required"
                show_help
                exit 1
            fi
            if ! is_valid_network "$network"; then
                error "Invalid network: $network"
                exit 1
            fi
            start_from_snapshot "$network" "$arg3"
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