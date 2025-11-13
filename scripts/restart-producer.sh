#!/bin/bash

# Libre Producer Restart Script
# Restarts producer nodes from fresh snapshots for recovery

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Function to check if container exists and is running
check_container_status() {
    local network=$1
    local container_name="libre-$network-producer"
    
    if docker ps -a --format "table {{.Names}}" | grep -q "^$container_name$"; then
        if docker ps --format "table {{.Names}}" | grep -q "^$container_name$"; then
            echo "running"
        else
            echo "stopped"
        fi
    else
        echo "not_found"
    fi
}

# Function to stop and remove container
stop_container() {
    local network=$1
    local container_name="libre-$network-producer"
    
    print_status "Stopping $network producer container..."
    
    # Stop container if running
    if docker ps --format "table {{.Names}}" | grep -q "^$container_name$"; then
        docker stop "$container_name" 2>/dev/null || true
    fi
    
    # Remove container if exists
    if docker ps -a --format "table {{.Names}}" | grep -q "^$container_name$"; then
        docker rm "$container_name" 2>/dev/null || true
    fi
    
    print_status "$network producer container stopped and removed"
}

# Function to download fresh snapshot
download_fresh_snapshot() {
    local network=$1
    local data_dir="$PROJECT_ROOT/$network/data"
    
    print_header "Downloading Fresh Snapshot for $network"
    
    # Backup existing data if present
    if [ -d "$data_dir" ] && [ "$(ls -A $data_dir)" ]; then
        print_warning "Backing up existing data directory..."
        local backup_dir="${data_dir}.backup.restart.$(date +%Y%m%d_%H%M%S)"
        mv "$data_dir" "$backup_dir"
        print_status "Backup created: $backup_dir"
    fi
    
    # Download snapshot using the producer-snapshot script
    print_status "Downloading latest snapshot..."
    if ! "$SCRIPT_DIR/producer-snapshot.sh" <<< "$([ "$network" = "mainnet" ] && echo "3" || echo "4")"; then
        print_error "Failed to download fresh snapshot for $network"
        return 1
    fi
    
    return 0
}

# Function to restart producer from snapshot
restart_producer() {
    local network=$1
    local force_download=$2
    
    print_header "Restarting $network Producer from Snapshot"
    
    # Check current container status
    local status=$(check_container_status "$network")
    print_status "Current container status: $status"
    
    # Stop and remove existing container if present
    if [ "$status" != "not_found" ]; then
        stop_container "$network"
    fi
    
    # Download fresh snapshot if requested or if no snapshot exists
    local snapshot_path="$PROJECT_ROOT/$network/data/snapshot.bin"
    if [ "$force_download" = "true" ] || [ ! -f "$snapshot_path" ]; then
        if ! download_fresh_snapshot "$network"; then
            return 1
        fi
    else
        print_status "Using existing snapshot at: $snapshot_path"
    fi
    
    # Start the producer container using start-producer logic
    print_status "Starting producer container from snapshot..."
    
    # Try docker compose first (newer), then docker-compose (older)
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        if ! docker compose -f "$PROJECT_ROOT/docker/docker-compose-producer.yml" up -d "libre-$network-producer"; then
            print_error "Failed to start producer container"
            return 1
        fi
    elif command -v docker-compose &> /dev/null; then
        if ! docker-compose -f "$PROJECT_ROOT/docker/docker-compose-producer.yml" up -d "libre-$network-producer"; then
            print_error "Failed to start producer container"
            return 1
        fi
    else
        print_error "Neither 'docker compose' nor 'docker-compose' command found"
        return 1
    fi
    
    # Wait for node to start
    print_status "Waiting for node to initialize..."
    sleep 15
    
    # Check if node is running
    local api_port="9888"
    [ "$network" = "testnet" ] && api_port="9889"
    
    if curl -s "http://localhost:$api_port/v1/chain/get_info" > /dev/null 2>&1; then
        print_status "Producer node restarted successfully!"
        
        # Show node info
        local info=$(curl -s "http://localhost:$api_port/v1/chain/get_info")
        local head_block=$(echo "$info" | grep -o '"head_block_num":[0-9]*' | cut -d: -f2)
        local chain_id=$(echo "$info" | grep -o '"chain_id":"[^"]*' | cut -d'"' -f4)
        
        echo ""
        print_status "Node Information:"
        echo "  Chain ID: ${chain_id:0:16}..."
        echo "  Head Block: $head_block"
        echo "  API Endpoint: http://localhost:$api_port"
        echo ""
        print_status "Monitor logs with: docker logs -f libre-$network-producer"
    else
        print_warning "Node is starting up. Check logs with: docker logs libre-$network-producer"
    fi
    
    return 0
}

# Main execution
print_header "Libre Producer Restart Manager"

echo "This tool restarts producer nodes from fresh snapshots for recovery"
echo ""
echo "Options:"
echo "1) Restart mainnet producer (use existing snapshot)"
echo "2) Restart testnet producer (use existing snapshot)"
echo "3) Restart mainnet producer (download fresh snapshot)"
echo "4) Restart testnet producer (download fresh snapshot)"
echo "5) Restart both producers (use existing snapshots)"
echo "6) Restart both producers (download fresh snapshots)"
echo "7) Show container status"
read -p "Select option (1-7): " option

case $option in
    1)
        restart_producer "mainnet" "false"
        ;;
    2)
        restart_producer "testnet" "false"
        ;;
    3)
        restart_producer "mainnet" "true"
        ;;
    4)
        restart_producer "testnet" "true"
        ;;
    5)
        restart_producer "mainnet" "false"
        echo ""
        restart_producer "testnet" "false"
        ;;
    6)
        restart_producer "mainnet" "true"
        echo ""
        restart_producer "testnet" "true"
        ;;
    7)
        print_header "Container Status"
        
        # Check mainnet
        local mainnet_status=$(check_container_status "mainnet")
        print_status "Mainnet producer: $mainnet_status"
        if [ "$mainnet_status" = "running" ]; then
            docker logs --tail 3 libre-mainnet-producer 2>&1 | sed 's/^/  /'
        fi
        
        echo ""
        
        # Check testnet
        local testnet_status=$(check_container_status "testnet")
        print_status "Testnet producer: $testnet_status"
        if [ "$testnet_status" = "running" ]; then
            docker logs --tail 3 libre-testnet-producer 2>&1 | sed 's/^/  /'
        fi
        ;;
    *)
        print_error "Invalid option"
        exit 1
        ;;
esac

echo ""
print_status "Restart operation complete!"