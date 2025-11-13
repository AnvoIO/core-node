#!/bin/bash

# Libre Snapshot Management Script
# Creates new snapshots and prunes old ones automatically

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default settings
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KEEP_SNAPSHOTS=3  # Keep latest 3 snapshots by default

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

# Function to create snapshot via API
create_snapshot() {
    local network=$1
    local api_port="9888"
    
    if [ "$network" = "testnet" ]; then
        api_port="9889"
    fi
    
    print_status "Creating snapshot for $network..."
    
    # Create snapshot via API
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{}' \
        "http://localhost:$api_port/v1/producer/create_snapshot" 2>/dev/null)
    
    if [ $? -eq 0 ] && echo "$response" | grep -q "snapshot_name"; then
        local snapshot_name=$(echo "$response" | grep -o '"snapshot_name":"[^"]*' | cut -d'"' -f4)
        print_status "Snapshot created: $snapshot_name"
        return 0
    else
        print_error "Failed to create snapshot for $network"
        print_error "API response: $response"
        return 1
    fi
}

# Function to prune old snapshots
prune_snapshots() {
    local network=$1
    local snapshots_dir="$PROJECT_ROOT/$network/data/snapshots"
    
    if [ ! -d "$snapshots_dir" ]; then
        print_warning "Snapshots directory not found: $snapshots_dir"
        return 0
    fi
    
    print_status "Pruning old snapshots for $network (keeping latest $KEEP_SNAPSHOTS)..."
    
    # Count snapshots
    local snapshot_count=$(ls -1 "$snapshots_dir"/*.bin 2>/dev/null | wc -l)
    
    if [ "$snapshot_count" -le "$KEEP_SNAPSHOTS" ]; then
        print_status "Only $snapshot_count snapshots found, no pruning needed"
        return 0
    fi
    
    # Remove old snapshots, keep the newest ones
    local to_remove=$((snapshot_count - KEEP_SNAPSHOTS))
    print_status "Removing $to_remove old snapshots..."
    
    ls -1t "$snapshots_dir"/*.bin | tail -n "$to_remove" | while read -r old_snapshot; do
        print_status "Removing old snapshot: $(basename "$old_snapshot")"
        rm -f "$old_snapshot"
    done
    
    print_status "Snapshot pruning completed for $network"
}

# Function to show snapshot status
show_snapshot_status() {
    local network=$1
    local snapshots_dir="$PROJECT_ROOT/$network/data/snapshots"
    
    print_header "$network Snapshot Status"
    
    if [ ! -d "$snapshots_dir" ]; then
        print_warning "No snapshots directory found"
        return 0
    fi
    
    local snapshots=($(ls -1t "$snapshots_dir"/*.bin 2>/dev/null || true))
    
    if [ ${#snapshots[@]} -eq 0 ]; then
        print_warning "No snapshots found"
        return 0
    fi
    
    print_status "Found ${#snapshots[@]} snapshots:"
    
    for i in "${!snapshots[@]}"; do
        local snapshot="${snapshots[$i]}"
        local name=$(basename "$snapshot")
        local size=$(du -h "$snapshot" | cut -f1)
        local date=$(stat -f %Sm -t "%Y-%m-%d %H:%M:%S" "$snapshot" 2>/dev/null || stat -c %y "$snapshot" | cut -d'.' -f1)
        
        if [ $i -eq 0 ]; then
            echo "  📸 $name ($size) - $date [LATEST]"
        else
            echo "  📸 $name ($size) - $date"
        fi
    done
}

# Function to check if producer is running
check_producer_running() {
    local network=$1
    local container_name="libre-$network-producer"
    
    if docker ps --format "table {{.Names}}" | grep -q "^$container_name$"; then
        return 0
    else
        return 1
    fi
}

# Main execution
print_header "Libre Snapshot Management"

# Parse command line arguments
ACTION="status"
NETWORK=""

while [[ $# -gt 0 ]]; do
    case $1 in
        create|prune|status)
            ACTION="$1"
            shift
            ;;
        mainnet|testnet)
            NETWORK="$1"
            shift
            ;;
        --keep)
            KEEP_SNAPSHOTS="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [create|prune|status] [mainnet|testnet] [--keep N]"
            echo ""
            echo "Commands:"
            echo "  create    - Create new snapshot"
            echo "  prune     - Remove old snapshots"
            echo "  status    - Show snapshot information"
            echo ""
            echo "Options:"
            echo "  --keep N  - Number of snapshots to keep (default: 3)"
            echo ""
            echo "Examples:"
            echo "  $0 status testnet"
            echo "  $0 create mainnet"
            echo "  $0 prune testnet --keep 5"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Default to both networks if none specified
if [ -z "$NETWORK" ]; then
    NETWORKS=("mainnet" "testnet")
else
    NETWORKS=("$NETWORK")
fi

# Execute action for each network
for net in "${NETWORKS[@]}"; do
    case $ACTION in
        create)
            if check_producer_running "$net"; then
                create_snapshot "$net"
            else
                print_warning "$net producer not running, skipping snapshot creation"
            fi
            ;;
        prune)
            prune_snapshots "$net"
            ;;
        status)
            show_snapshot_status "$net"
            echo ""
            ;;
    esac
done

if [ "$ACTION" = "create" ]; then
    echo ""
    print_status "Snapshot creation completed!"
    print_status "Use './scripts/manage-snapshots.sh status' to view snapshots"
elif [ "$ACTION" = "prune" ]; then
    echo ""
    print_status "Snapshot pruning completed!"
fi