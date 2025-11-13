#!/bin/bash

# Libre Lightweight Producer Start Script
# Starts producer nodes with snapshot-based initialization

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

# Function to check if snapshot exists
check_snapshot() {
    local network=$1
    local snapshot_path="$PROJECT_ROOT/$network/data/snapshot.bin"
    
    if [ ! -f "$snapshot_path" ]; then
        print_error "Snapshot not found for $network at $snapshot_path"
        print_warning "Run '$SCRIPT_DIR/producer-snapshot.sh' to download snapshot first"
        return 1
    fi
    
    # Check snapshot age (warn if older than 24 hours)
    local snapshot_age=$(( ($(date +%s) - $(stat -f %m "$snapshot_path" 2>/dev/null || stat -c %Y "$snapshot_path")) / 3600 ))
    if [ $snapshot_age -gt 24 ]; then
        print_warning "Snapshot is $snapshot_age hours old. Consider downloading a fresh one."
    fi
    
    return 0
}

# Function to check producer configuration
check_producer_config() {
    local network=$1
    local config_file="$PROJECT_ROOT/$network/config/config.ini"
    
    if ! grep -q "^plugin = eosio::producer_plugin" "$config_file"; then
        print_error "Producer plugin not enabled for $network"
        print_warning "Run '$SCRIPT_DIR/deploy-producer.sh' to configure producer first"
        return 1
    fi
    
    local producer_name=$(grep "^producer-name = " "$config_file" | cut -d' ' -f3)
    if [ -z "$producer_name" ]; then
        print_error "Producer name not configured for $network"
        return 1
    fi
    
    print_status "Producer configured: $producer_name"
    return 0
}

# Function to start producer container
start_producer() {
    local network=$1
    
    print_header "Starting $network Producer"
    
    # Check prerequisites
    if ! check_snapshot "$network"; then
        return 1
    fi
    
    if ! check_producer_config "$network"; then
        return 1
    fi
    
    # Check if container already exists
    if docker ps -a | grep -q "libre-$network-producer"; then
        print_warning "Removing existing $network producer container..."
        docker rm -f "libre-$network-producer" 2>/dev/null || true
    fi
    
    # Start the producer container
    print_status "Starting lightweight producer container..."
    
    if ! docker-compose -f "$PROJECT_ROOT/docker/docker-compose-producer.yml" up -d "libre-$network-producer"; then
        print_error "Failed to start producer container"
        return 1
    fi
    
    # Wait for node to start
    print_status "Waiting for node to initialize..."
    sleep 10
    
    # Check if node is running
    local api_port="9888"
    [ "$network" = "testnet" ] && api_port="9889"
    
    if curl -s "http://localhost:$api_port/v1/chain/get_info" > /dev/null 2>&1; then
        print_status "Producer node started successfully!"
        
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
    else
        print_warning "Node is starting up. Check logs with: docker logs libre-$network-producer"
    fi
    
    return 0
}

# Main execution
print_header "Libre Lightweight Producer Startup"

echo "This starts producer nodes using minimal resources and snapshots"
echo ""
echo "Options:"
echo "1) Start mainnet producer"
echo "2) Start testnet producer"
echo "3) Start both producers"
echo "4) Check producer status"
read -p "Select option (1-4): " option

case $option in
    1)
        start_producer "mainnet"
        ;;
    2)
        start_producer "testnet"
        ;;
    3)
        start_producer "mainnet"
        echo ""
        start_producer "testnet"
        ;;
    4)
        print_header "Producer Status"
        
        # Check mainnet
        if docker ps | grep -q "libre-mainnet-producer"; then
            print_status "Mainnet producer: RUNNING"
            docker logs --tail 5 libre-mainnet-producer 2>&1 | sed 's/^/  /'
        else
            print_warning "Mainnet producer: NOT RUNNING"
        fi
        
        echo ""
        
        # Check testnet
        if docker ps | grep -q "libre-testnet-producer"; then
            print_status "Testnet producer: RUNNING"
            docker logs --tail 5 libre-testnet-producer 2>&1 | sed 's/^/  /'
        else
            print_warning "Testnet producer: NOT RUNNING"
        fi
        ;;
    *)
        print_error "Invalid option"
        exit 1
        ;;
esac

echo ""
print_status "Done!"

if [ "$option" != "4" ]; then
    echo ""
    print_status "Monitor logs with:"
    echo "  docker logs -f libre-mainnet-producer"
    echo "  docker logs -f libre-testnet-producer"
    echo ""
    print_status "Stop producers with:"
    echo "  docker-compose -f docker/docker-compose-producer.yml down"
fi