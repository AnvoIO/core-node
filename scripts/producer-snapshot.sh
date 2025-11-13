#!/bin/bash

# Libre Producer Snapshot Management Script
# Downloads and loads snapshots for lightweight producer nodes
# Supports multiple snapshot providers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"
PROVIDERS_CONFIG="$CONFIG_DIR/snapshot-providers.conf"

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

# Function to load snapshot providers
load_providers() {
    local network=$1
    local providers=()
    
    if [ ! -f "$PROVIDERS_CONFIG" ]; then
        print_error "Providers config not found: $PROVIDERS_CONFIG"
        return 1
    fi
    
    # Read providers for the specified network
    while IFS='|' read -r name base_url path_pattern file_pattern compression; do
        # Skip comments and empty lines
        [[ $name =~ ^#.*$ ]] && continue
        [[ -z $name ]] && continue
        
        # Filter by network
        local network_upper=$(echo "$network" | tr '[:lower:]' '[:upper:]')
        if [[ $name == *"_${network_upper}"* ]]; then
            providers+=("$name|$base_url|$path_pattern|$file_pattern|$compression")
        fi
    done < "$PROVIDERS_CONFIG"
    
    printf '%s\n' "${providers[@]}"
}

# Function to list available providers
list_providers() {
    local network=$1
    local providers=($(load_providers "$network"))
    
    if [ ${#providers[@]} -eq 0 ]; then
        print_error "No providers found for $network"
        return 1
    fi
    
    print_header "Available Snapshot Providers for $network"
    local index=1
    for provider in "${providers[@]}"; do
        IFS='|' read -r name base_url path_pattern file_pattern compression <<< "$provider"
        local display_name=$(echo "$name" | sed 's/_MAINNET\|_TESTNET//')
        echo "$index) $display_name"
        if [ "$path_pattern" = "DIRECT" ]; then
            echo "   URL: $base_url (direct download)"
        else
            echo "   URL: $base_url$path_pattern"
        fi
        echo "   Format: $compression compressed"
        echo ""
        ((index++))
    done
}

# Function to get latest snapshot from provider
get_latest_snapshot() {
    local provider_info=$1
    IFS='|' read -r name base_url path_pattern file_pattern compression <<< "$provider_info"
    
    # Check if this is a direct URL (EOSUSA style)
    if [ "$path_pattern" = "DIRECT" ]; then
        # Direct URL - no need to fetch listing
        # Don't print status here as it interferes with the return value
        echo "$base_url|$compression"
    else
        # Standard listing approach for other providers
        local full_url="$base_url$path_pattern"
        # Don't print status here as it interferes with the return value
        
        # Get the snapshot listing page and find matching files
        local latest_snapshot=$(curl -s "$full_url/" | \
            grep -oE 'href="[^"]*"' | \
            sed 's/href="//;s/"//' | \
            grep -E "$file_pattern" | \
            sort -V | \
            tail -1)
        
        if [ -z "$latest_snapshot" ]; then
            print_error "No snapshots found matching pattern: $file_pattern"
            return 1
        fi
        
        echo "$full_url/$latest_snapshot|$compression"
    fi
}

# Function to decompress snapshot
decompress_snapshot() {
    local snapshot_file=$1
    local compression=$2
    local output_dir=$3
    
    print_status "Decompressing $compression file..."
    
    case $compression in
        zst)
            if ! command -v zstd &> /dev/null; then
                print_error "zstd not found. Install with: apt-get install zstd"
                return 1
            fi
            zstd -d "$snapshot_file" -o "$output_dir/snapshot.bin"
            ;;
        gz)
            # Check if it's a tar.gz file
            if [[ "$snapshot_file" == *.tar.gz ]]; then
                print_status "Extracting tar.gz archive..."
                if ! command -v tar &> /dev/null; then
                    print_error "tar not found"
                    return 1
                fi
                # Extract to output directory
                tar -xzf "$snapshot_file" -C "$output_dir"
                
                # Find the snapshot.bin file in the extracted contents
                local snapshot_bin=$(find "$output_dir" -name "*.bin" -o -name "snapshot.*" | head -1)
                if [ -n "$snapshot_bin" ] && [ "$snapshot_bin" != "$output_dir/snapshot.bin" ]; then
                    mv "$snapshot_bin" "$output_dir/snapshot.bin"
                fi
                
                # Clean up any extra directories created by tar
                find "$output_dir" -type d -empty -delete 2>/dev/null || true
            else
                # Plain gzip file
                if ! command -v gzip &> /dev/null; then
                    print_error "gzip not found"
                    return 1
                fi
                gunzip -c "$snapshot_file" > "$output_dir/snapshot.bin"
            fi
            ;;
        bz2)
            if ! command -v bzip2 &> /dev/null; then
                print_error "bzip2 not found"
                return 1
            fi
            bunzip2 -c "$snapshot_file" > "$output_dir/snapshot.bin"
            ;;
        xz)
            if ! command -v xz &> /dev/null; then
                print_error "xz not found"
                return 1
            fi
            xz -dc "$snapshot_file" > "$output_dir/snapshot.bin"
            ;;
        none)
            cp "$snapshot_file" "$output_dir/snapshot.bin"
            ;;
        *)
            print_error "Unsupported compression: $compression"
            return 1
            ;;
    esac
    
    # Verify snapshot.bin exists
    if [ ! -f "$output_dir/snapshot.bin" ]; then
        print_error "Failed to extract snapshot.bin"
        return 1
    fi
    
    print_status "Snapshot extracted successfully"
    return 0
}

# Function to download and extract snapshot
download_snapshot() {
    local network=$1
    local data_dir=$2
    local provider_choice=$3
    
    print_header "Downloading Snapshot for $network"
    
    # Load providers
    local providers=($(load_providers "$network"))
    if [ ${#providers[@]} -eq 0 ]; then
        print_error "No providers found for $network"
        return 1
    fi
    
    # Select provider
    local selected_provider=""
    if [ -n "$provider_choice" ] && [ "$provider_choice" -ge 1 ] && [ "$provider_choice" -le ${#providers[@]} ]; then
        selected_provider="${providers[$((provider_choice-1))]}"
    else
        # Default to first provider if no choice given
        selected_provider="${providers[0]}"
        if [ -z "$provider_choice" ]; then
            local provider_name=$(echo "$selected_provider" | cut -d'|' -f1 | sed 's/_MAINNET\|_TESTNET//')
            print_status "Using provider: $provider_name"
        fi
    fi
    
    # Get snapshot URL
    local snapshot_info=$(get_latest_snapshot "$selected_provider")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    IFS='|' read -r full_url compression <<< "$snapshot_info"
    local snapshot_file=$(basename "$full_url")
    local temp_dir="/tmp/libre-snapshot-$network"
    
    echo ""  # New line after previous output
    print_status "Download URL: $full_url"
    print_warning "This may take several minutes depending on connection speed..."
    
    # Create temp directory
    mkdir -p "$temp_dir"
    
    # Download snapshot with progress
    print_status "Saving to: $temp_dir/$snapshot_file"
    
    # Try wget first with timeout and retries
    if command -v wget &> /dev/null; then
        print_status "Downloading with wget..."
        if wget --timeout=30 --tries=3 --show-progress -O "$temp_dir/$snapshot_file" "$full_url" 2>&1; then
            print_status "Download successful with wget"
        else
            print_warning "wget failed, trying curl..."
            WGET_FAILED=1
        fi
    else
        WGET_FAILED=1
    fi
    
    # Try curl if wget failed or not available
    if [ "${WGET_FAILED:-0}" = "1" ]; then
        if command -v curl &> /dev/null; then
            print_status "Downloading with curl..."
            if curl -L --connect-timeout 30 --retry 3 --progress-bar -o "$temp_dir/$snapshot_file" "$full_url"; then
                print_status "Download successful with curl"
            else
                print_error "Download failed with curl"
                rm -rf "$temp_dir"
                return 1
            fi
        else
            print_error "Neither wget nor curl is available"
            rm -rf "$temp_dir"
            return 1
        fi
    fi
    
    print_status "Download complete. Extracting snapshot..."
    
    # Clear existing data directory (backup first if exists)
    if [ -d "$data_dir" ] && [ "$(ls -A $data_dir)" ]; then
        print_warning "Backing up existing data directory..."
        mv "$data_dir" "${data_dir}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Create fresh data directory
    mkdir -p "$data_dir"
    
    # Extract snapshot (pass directory, not file path)
    if ! decompress_snapshot "$temp_dir/$snapshot_file" "$compression" "$data_dir"; then
        print_error "Extraction failed"
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
    
    # Enable lightweight producer settings in config
    sed -i 's/^#snapshot = \/opt\/eosio\/data\/snapshot\.bin/snapshot = \/opt\/eosio\/data\/snapshot.bin/' "$config_file"
    sed -i 's/^#blocks-log-stride = 1000/blocks-log-stride = 1000/' "$config_file"
    sed -i 's/^#max-retained-block-files = 1/max-retained-block-files = 1/' "$config_file"
    sed -i 's/^#blocks-retained-dir =/blocks-retained-dir =/' "$config_file"
    sed -i 's/^#chain-state-db-size-mb = 4096/chain-state-db-size-mb = 4096/' "$config_file"
    sed -i 's/^#reversible-blocks-db-size-mb = 340/reversible-blocks-db-size-mb = 340/' "$config_file"
    sed -i 's/^#read-mode = head/read-mode = head/' "$config_file"
    sed -i 's/^#validation-mode = light/validation-mode = light/' "$config_file"
    sed -i 's/^#database-map-mode = mapped/database-map-mode = mapped/' "$config_file"
    
    print_status "Lightweight producer configuration enabled in $config_file"
}

# Function to prepare producer container
prepare_producer_container() {
    local network=$1
    local provider_choice=$2
    local data_dir="$PROJECT_ROOT/$network/data"
    local config_file="$PROJECT_ROOT/$network/config/config.ini"
    
    print_header "Preparing $network Producer Container"
    
    # Check if container is running
    if docker ps | grep -q "libre-$network"; then
        print_warning "Stopping existing $network container..."
        docker stop "libre-$network-api" 2>/dev/null || true
    fi
    
    # Download snapshot
    if ! download_snapshot "$network" "$data_dir" "$provider_choice"; then
        print_error "Failed to download snapshot"
        return 1
    fi
    
    # Configure for lightweight mode
    configure_lightweight_producer "$config_file" "$network"
    
    print_status "Producer container prepared successfully"
    print_warning "Start with: ./scripts/start-producer.sh"
    
    return 0
}

# Function to show provider information
show_provider_info() {
    print_header "Snapshot Provider Information"
    
    echo "Configured providers:"
    echo ""
    
    # Show mainnet providers
    echo "Mainnet providers:"
    list_providers "mainnet" || echo "  No mainnet providers configured"
    
    echo ""
    
    # Show testnet providers  
    echo "Testnet providers:"
    list_providers "testnet" || echo "  No testnet providers configured"
    
    echo ""
    print_status "To add more providers, edit: $PROVIDERS_CONFIG"
}

# Main execution
print_header "Libre Producer Snapshot Manager"

echo "This tool sets up lightweight producer nodes using snapshots"
echo "Supports multiple snapshot providers for flexibility"
echo ""

# Check if config directory exists
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
fi

# Check if providers config exists
if [ ! -f "$PROVIDERS_CONFIG" ]; then
    print_error "Providers configuration not found"
    print_status "Please ensure $PROVIDERS_CONFIG exists"
    exit 1
fi

echo "Options:"
echo "1) Setup mainnet producer with snapshot"
echo "2) Setup testnet producer with snapshot"
echo "3) Download snapshot only (mainnet)"
echo "4) Download snapshot only (testnet)"
echo "5) Show provider information"
echo "6) List providers and select"
read -p "Select option (1-6): " option

case $option in
    1)
        prepare_producer_container "mainnet"
        ;;
    2)
        prepare_producer_container "testnet"
        ;;
    3)
        download_snapshot "mainnet" "$PROJECT_ROOT/mainnet/data"
        ;;
    4)
        download_snapshot "testnet" "$PROJECT_ROOT/testnet/data"
        ;;
    5)
        show_provider_info
        ;;
    6)
        echo ""
        echo "Select network:"
        echo "1) Mainnet"
        echo "2) Testnet"
        read -p "Choose network (1-2): " net_choice
        
        local network=""
        case $net_choice in
            1) network="mainnet" ;;
            2) network="testnet" ;;
            *) print_error "Invalid choice"; exit 1 ;;
        esac
        
        echo ""
        list_providers "$network"
        read -p "Select provider (number): " prov_choice
        
        echo ""
        echo "What would you like to do?"
        echo "1) Setup producer container"
        echo "2) Download snapshot only"
        read -p "Choose action (1-2): " action_choice
        
        case $action_choice in
            1) prepare_producer_container "$network" "$prov_choice" ;;
            2) download_snapshot "$network" "$PROJECT_ROOT/$network/data" "$prov_choice" ;;
            *) print_error "Invalid choice"; exit 1 ;;
        esac
        ;;
    *)
        print_error "Invalid option"
        exit 1
        ;;
esac

echo ""
print_status "Operation complete!"