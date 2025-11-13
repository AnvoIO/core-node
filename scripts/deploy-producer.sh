#!/bin/bash

# Libre Node Producer Deployment Script
# This script configures a Libre node for block production

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source configuration utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config-utils.sh"

# Configuration files
MAINNET_CONFIG="mainnet/config/config.ini"
TESTNET_CONFIG="testnet/config/config.ini"

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

# Function to validate producer name
validate_producer_name() {
    local name=$1
    if [[ ! $name =~ ^[a-z1-5]{1,12}$ ]]; then
        print_error "Producer name must be 1-12 characters, lowercase letters and numbers 1-5 only"
        return 1
    fi
    return 0
}

# Function to validate public key
validate_public_key() {
    local key=$1
    if [[ ! $key =~ ^EOS[A-Za-z0-9]{50}$ ]]; then
        print_error "Invalid EOS public key format"
        return 1
    fi
    return 0
}

# Function to configure producer settings
configure_producer() {
    local network=$1
    local config_file=$2
    
    print_header "Configuring $network Producer Settings"
    
    # Create backup
    create_backup "$config_file"
    
    # Get producer configuration
    read -p "Enter producer account name: " producer_name
    validate_producer_name "$producer_name" || return 1
    
    echo ""
    print_warning "SECURITY: Choose authentication method"
    echo "1) Private key (NOT RECOMMENDED for production)"
    echo "2) Signature provider (RECOMMENDED)"
    read -p "Choose option (1 or 2): " auth_method
    
    case $auth_method in
        1)
            read -s -p "Enter private key: " private_key
            echo
            auth_config="private-key = $private_key"
            ;;
        2)
            read -p "Enter public key: " public_key
            validate_public_key "$public_key" || return 1
            read -s -p "Enter private key for signature provider: " private_key
            echo
            auth_config="signature-provider = $public_key=KEY:$private_key"
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac
    
    echo ""
    read -p "Enable stale production? (y/N): " enable_stale
    stale_production="false"
    [[ $enable_stale =~ ^[Yy]$ ]] && stale_production="true"
    
    echo ""
    read -p "Restrict API to localhost only? (Y/n): " restrict_api
    api_restriction=""
    if [[ ! $restrict_api =~ ^[Nn]$ ]]; then
        if [[ $network == "mainnet" ]]; then
            api_restriction="http-server-address = 127.0.0.1:9888"
        else
            api_restriction="http-server-address = 127.0.0.1:9889"
        fi
    fi
    
    echo ""
    read -p "Disable P2P transaction acceptance? (Y/n): " disable_p2p_tx
    p2p_tx_config=""
    if [[ ! $disable_p2p_tx =~ ^[Nn]$ ]]; then
        p2p_tx_config="p2p-accept-transactions = false"
    fi
    
    # Enable producer plugin
    sed -i.bak 's/^#plugin = eosio::producer_plugin/plugin = eosio::producer_plugin/' "$config_file"
    
    # Enable producer API plugin
    sed -i.bak 's/^#plugin = eosio::producer_api_plugin/plugin = eosio::producer_api_plugin/' "$config_file"
    
    # Remove pause-on-startup
    sed -i.bak 's/^pause-on-startup = true/#pause-on-startup = true  # Disabled for producer mode/' "$config_file"
    
    # Configure producer settings
    sed -i.bak "s/^#producer-name = yourproducername/producer-name = $producer_name/" "$config_file"
    sed -i.bak "s/^# private-key = YOUR_PRIVATE_KEY_HERE/$auth_config/" "$config_file"
    sed -i.bak "s/^# signature-provider = YOUR_PUBLIC_KEY=KEY:YOUR_PRIVATE_KEY/$auth_config/" "$config_file"
    sed -i.bak "s/^#enable-stale-production = false/enable-stale-production = $stale_production/" "$config_file"
    
    # Apply additional settings
    if [[ -n $api_restriction ]]; then
        sed -i.bak "s|^#http-server-address = 127.0.0.1:[0-9]*.*|$api_restriction|" "$config_file"
    fi
    
    if [[ -n $p2p_tx_config ]]; then
        sed -i.bak "s/^#p2p-accept-transactions = false.*/$p2p_tx_config/" "$config_file"
        sed -i.bak "s/^#api-accept-transactions = true.*/api-accept-transactions = true/" "$config_file"
    fi
    
    # Enable other producer settings
    sed -i.bak 's/^#max-transaction-time = 30/max-transaction-time = 30/' "$config_file"
    sed -i.bak 's/^#max-irreversible-block-age = 10/max-irreversible-block-age = 10/' "$config_file"
    sed -i.bak 's/^#producer-threads = 2/producer-threads = 2/' "$config_file"
    
    print_status "$network producer configuration completed"
}

# Function to show producer status
show_producer_info() {
    local config_file=$1
    local network=$2
    
    print_header "$network Producer Configuration Status"
    
    if grep -q "^plugin = eosio::producer_plugin" "$config_file"; then
        print_status "Producer plugin: ENABLED"
        
        producer_name=$(grep "^producer-name = " "$config_file" | cut -d' ' -f3)
        print_status "Producer name: $producer_name"
        
        if grep -q "^enable-stale-production = true" "$config_file"; then
            print_warning "Stale production: ENABLED"
        else
            print_status "Stale production: DISABLED"
        fi
        
        if grep -q "^http-server-address = 127.0.0.1" "$config_file"; then
            print_status "API access: RESTRICTED to localhost"
        else
            print_warning "API access: OPEN to all interfaces"
        fi
        
        if grep -q "^pause-on-startup = true" "$config_file"; then
            print_warning "Node will pause on startup - disable for production"
        else
            print_status "Auto-start: ENABLED"
        fi
    else
        print_status "Producer plugin: DISABLED"
    fi
    echo
}

# Main execution
print_header "Libre Producer Configuration"

print_warning "IMPORTANT: Only configure producer mode if you are an authorized block producer"
print_warning "Producer mode requires proper key management and security measures"
echo ""

echo "Available options:"
echo "1) Configure mainnet producer (standard)"
echo "2) Configure testnet producer (standard)"
echo "3) Configure mainnet producer (lightweight/snapshot-based)"
echo "4) Configure testnet producer (lightweight/snapshot-based)"
echo "5) Show current status"
echo "6) Disable producer mode"
read -p "Select option (1-6): " network_choice

case $network_choice in
    1)
        configure_producer "mainnet" "$MAINNET_CONFIG"
        ;;
    2)
        configure_producer "testnet" "$TESTNET_CONFIG"
        ;;
    3)
        print_header "Lightweight Mainnet Producer Setup"
        configure_producer "mainnet" "$MAINNET_CONFIG"
        print_warning "Now run: ./scripts/producer-snapshot.sh (Option 1) to download snapshot"
        print_status "Then start with: docker-compose -f docker/docker-compose-producer.yml up -d libre-mainnet-producer"
        ;;
    4)
        print_header "Lightweight Testnet Producer Setup"
        configure_producer "testnet" "$TESTNET_CONFIG"
        print_warning "Now run: ./scripts/producer-snapshot.sh (Option 2) to download snapshot"
        print_status "Then start with: docker-compose -f docker/docker-compose-producer.yml up -d libre-testnet-producer"
        ;;
    5)
        show_producer_info "$MAINNET_CONFIG" "Mainnet"
        show_producer_info "$TESTNET_CONFIG" "Testnet"
        ;;
    6)
        print_header "Disabling Producer Mode"
        
        # Disable producer plugins
        sed -i.bak 's/^plugin = eosio::producer_plugin/#plugin = eosio::producer_plugin/' "$MAINNET_CONFIG"
        sed -i.bak 's/^plugin = eosio::producer_plugin/#plugin = eosio::producer_plugin/' "$TESTNET_CONFIG"
        sed -i.bak 's/^plugin = eosio::producer_api_plugin/#plugin = eosio::producer_api_plugin/' "$MAINNET_CONFIG"
        sed -i.bak 's/^plugin = eosio::producer_api_plugin/#plugin = eosio::producer_api_plugin/' "$TESTNET_CONFIG"
        
        # Re-enable pause on startup
        sed -i.bak 's/^#pause-on-startup = true.*disable.*/pause-on-startup = true/' "$MAINNET_CONFIG"
        sed -i.bak 's/^#pause-on-startup = true.*disable.*/pause-on-startup = true/' "$TESTNET_CONFIG"
        
        print_status "Producer mode disabled for both networks"
        ;;
    *)
        print_error "Invalid option"
        exit 1
        ;;
esac

echo ""
print_status "Configuration complete!"
print_warning "Remember to restart nodes for changes to take effect: ./scripts/restart.sh"
echo ""
print_status "Security recommendations:"
echo "- Use signature providers instead of private keys"
echo "- Restrict API access to localhost in production"
echo "- Use proper firewall rules"
echo "- Monitor logs for any issues"
echo "- Keep private keys secure and backed up"