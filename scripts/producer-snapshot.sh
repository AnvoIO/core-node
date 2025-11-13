#!/bin/bash

# Libre Producer Snapshot Management Script
# Downloads and loads snapshots for lightweight producer nodes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Snapshot URLs
MAINNET_SNAPSHOT_URL="https://snapshots.eosusa.io/snapshots/libre"
TESTNET_SNAPSHOT_URL="https://snapshots.eosusa.io/snapshots/libretestnet"

# Default paths
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

# Function to get latest snapshot
get_latest_snapshot() {
    local network=$1
    local snapshot_url=$2
    
    print_status "Fetching latest snapshot info for $network..."
    
    # Get the snapshot listing page
    local latest_snapshot=$(curl -s "$snapshot_url/" | \
        grep -oE 'href="[^"]*\.bin\.zst"' | \
        sed 's/href="//;s/"//' | \
        sort -V | \
        tail -1)
    
    if [ -z "$latest_snapshot" ]; then
        print_error "Could not find latest snapshot"
        return 1
    fi
    
    echo "$snapshot_url/$latest_snapshot"
}

# Function to download and extract snapshot
download_snapshot() {
    local network=$1
    local snapshot_url=$2
    local data_dir=$3
    
    print_header "Downloading Snapshot for $network"
    
    # Get the latest snapshot URL
    local full_url=$(get_latest_snapshot "$network" "$snapshot_url")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local snapshot_file=$(basename "$full_url")
    local temp_dir="/tmp/libre-snapshot-$network"
    
    print_status "Downloading from: $full_url"
    print_warning "This may take several minutes depending on connection speed..."
    
    # Create temp directory
    mkdir -p "$temp_dir"
    
    # Download snapshot
    if ! wget -q --show-progress -O "$temp_dir/$snapshot_file" "$full_url"; then
        print_error "Download failed"
        rm -rf "$temp_dir"
        return 1
    fi
    
    print_status "Download complete. Extracting snapshot..."
    
    # Clear existing data directory (backup first if exists)
    if [ -d "$data_dir" ] && [ "$(ls -A $data_dir)" ]; then
        print_warning "Backing up existing data directory..."
        mv "$data_dir" "${data_dir}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Create fresh data directory
    mkdir -p "$data_dir"
    
    # Extract snapshot using zstd
    if ! zstd -d "$temp_dir/$snapshot_file" -o "$data_dir/snapshot.bin"; then
        print_error "Extraction failed. Make sure zstd is installed: apt-get install zstd"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    
    print_status "Snapshot ready at: $data_dir/snapshot.bin"
    return 0
}

# Function to configure producer for lightweight mode
configure_lightweight_producer() {
    local config_file=$1
    local network=$2
    
    print_header "Configuring Lightweight Producer Mode for $network"
    
    # Create backup
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add lightweight producer settings
    cat >> "$config_file" << EOL

## Lightweight Producer Configuration
# Minimal state persistence for block producers

# Keep only recent blocks in memory
blocks-retained-dir = 
blocks-log-stride = 1000
max-retained-block-files = 1

# Disable state history for producers
#plugin = eosio::state_history_plugin

# Memory-optimized settings
chain-state-db-size-mb = 4096       # Reduced from 32GB
reversible-blocks-db-size-mb = 340  # Minimum required
eos-vm-oc-cache-size-mb = 512       # Reduced cache

# Snapshot loading on startup
snapshot = /opt/eosio/data/snapshot.bin

# Producer-specific optimizations
read-mode = head                    # Only maintain head state
validation-mode = light             # Light validation for producers

# Disable transaction history
filter-on = *                       # Disable all action filtering
filter-out = eosio:onblock:*        # Except onblock

# Reduce P2P overhead
p2p-max-nodes-per-host = 2          # Limit connections per host
max-clients = 25                    # Reduce client connections

# Fast startup from snapshot
database-map-mode = mapped          # Use memory-mapped files
database-hugepage-path = /dev/hugepages  # Use huge pages if available
EOL
    
    print_status "Lightweight producer configuration added to $config_file"
}

# Function to prepare producer container
prepare_producer_container() {
    local network=$1
    local data_dir="$PROJECT_ROOT/$network/data"
    local config_file="$PROJECT_ROOT/$network/config/config.ini"
    
    print_header "Preparing $network Producer Container"
    
    # Check if container is running
    if docker ps | grep -q "libre-$network"; then
        print_warning "Stopping existing $network container..."
        docker stop "libre-$network-api"
    fi
    
    # Download snapshot
    local snapshot_url=""
    if [ "$network" = "mainnet" ]; then
        snapshot_url="$MAINNET_SNAPSHOT_URL"
    else
        snapshot_url="$TESTNET_SNAPSHOT_URL"
    fi
    
    if ! download_snapshot "$network" "$snapshot_url" "$data_dir"; then
        print_error "Failed to download snapshot"
        return 1
    fi
    
    # Configure for lightweight mode
    configure_lightweight_producer "$config_file" "$network"
    
    print_status "Producer container prepared successfully"
    print_warning "Start with: docker-compose -f docker/docker-compose-producer.yml up -d libre-$network"
    
    return 0
}

# Function to show producer info
show_producer_info() {
    print_header "Lightweight Producer Mode Information"
    
    echo "Lightweight producer mode optimizations:"
    echo "- Downloads latest snapshot on startup"
    echo "- Keeps only last 1000 blocks in memory"
    echo "- Minimal disk persistence (4GB chain state)"
    echo "- Fast restart from snapshot"
    echo "- Reduced P2P and client connections"
    echo ""
    echo "Snapshot sources:"
    echo "- Mainnet: $MAINNET_SNAPSHOT_URL"
    echo "- Testnet: $TESTNET_SNAPSHOT_URL"
    echo ""
    echo "Memory requirements:"
    echo "- Mainnet: ~6GB RAM (4GB state + overhead)"
    echo "- Testnet: ~4GB RAM (2GB state + overhead)"
    echo ""
    print_warning "Note: Snapshots are downloaded fresh on each setup"
    print_warning "Initial sync from snapshot takes 5-10 minutes"
}

# Main execution
print_header "Libre Producer Snapshot Manager"

echo "This tool sets up lightweight producer nodes using snapshots"
echo ""
echo "Options:"
echo "1) Setup mainnet producer with snapshot"
echo "2) Setup testnet producer with snapshot"
echo "3) Download snapshot only (mainnet)"
echo "4) Download snapshot only (testnet)"
echo "5) Show lightweight mode info"
read -p "Select option (1-5): " option

case $option in
    1)
        prepare_producer_container "mainnet"
        ;;
    2)
        prepare_producer_container "testnet"
        ;;
    3)
        download_snapshot "mainnet" "$MAINNET_SNAPSHOT_URL" "$PROJECT_ROOT/mainnet/data"
        ;;
    4)
        download_snapshot "testnet" "$TESTNET_SNAPSHOT_URL" "$PROJECT_ROOT/testnet/data"
        ;;
    5)
        show_producer_info
        ;;
    *)
        print_error "Invalid option"
        exit 1
        ;;
esac

echo ""
print_status "Operation complete!"

if [ "$option" = "1" ] || [ "$option" = "2" ]; then
    echo ""
    print_status "Next steps:"
    echo "1. Configure producer keys: ./scripts/deploy-producer.sh"
    echo "2. Start producer node: ./scripts/start-producer.sh"
    echo "3. Monitor logs: ./scripts/logs.sh [mainnet|testnet]"
fi