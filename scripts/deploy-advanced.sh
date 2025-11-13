#!/bin/bash

# Libre Node Advanced Deployment Script
# This script provides comprehensive configuration for Libre nodes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration files
MAINNET_CONFIG="$PROJECT_ROOT/mainnet/config/config.ini"
TESTNET_CONFIG="$PROJECT_ROOT/testnet/config/config.ini"
DOCKER_COMPOSE="$PROJECT_ROOT/docker/docker-compose.yml"

# Default values
DEFAULT_LISTEN_IP="0.0.0.0"
DEFAULT_MAINNET_HTTP_PORT="9888"
DEFAULT_MAINNET_P2P_PORT="9876"
DEFAULT_MAINNET_STATE_HISTORY_PORT="9080"
DEFAULT_TESTNET_HTTP_PORT="9889"
DEFAULT_TESTNET_P2P_PORT="9877"
DEFAULT_TESTNET_STATE_HISTORY_PORT="9081"

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

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a ip_parts <<< "$ip"
        for part in "${ip_parts[@]}"; do
            if [[ $part -lt 0 || $part -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Function to validate port number
validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ $port -ge 1 ] && [ $port -le 65535 ]; then
        return 0
    fi
    return 1
}

# Function to validate number range
validate_range() {
    local value=$1
    local min=$2
    local max=$3
    if [[ $value =~ ^[0-9]+$ ]] && [ $value -ge $min ] && [ $value -le $max ]; then
        return 0
    fi
    return 1
}

# Function to get user input with validation
get_input() {
    local prompt="$1"
    local default="$2"
    local validator="$3"
    local input
    
    while true; do
        if [ -n "$default" ]; then
            read -p "$prompt [$default]: " input
            input=${input:-$default}
        else
            read -p "$prompt: " input
        fi
        
        if [ -z "$input" ]; then
            print_warning "Input cannot be empty. Please try again."
            continue
        fi
        
        if [ -n "$validator" ]; then
            if $validator "$input"; then
                break
            else
                print_error "Invalid input. Please try again."
                continue
            fi
        else
            break
        fi
    done
    
    echo "$input"
}

# Function to get yes/no input
get_yes_no() {
    local prompt="$1"
    local default="$2"
    local input
    
    while true; do
        if [ -n "$default" ]; then
            read -p "$prompt [$default]: " input
            input=${input:-$default}
        else
            read -p "$prompt: " input
        fi
        
        case $input in
            [Yy]|[Yy][Ee][Ss])
                echo "true"
                break
                ;;
            [Nn]|[Nn][Oo])
                echo "false"
                break
                ;;
            *)
                print_error "Please enter 'y' or 'n'"
                ;;
        esac
    done
}

# Function to get multiple P2P peers
get_p2p_peers() {
    local peers=()
    local peer
    local add_more="y"
    
    print_status "Enter P2P peer addresses (format: host:port)"
    
    while [ "$add_more" = "y" ] || [ "$add_more" = "Y" ]; do
        peer=$(get_input "Enter P2P peer address" "" "")
        peers+=("$peer")
        
        add_more=$(get_input "Add another P2P peer? (y/n)" "n" "")
    done
    
    echo "${peers[@]}"
}

# Function to update config.ini file with advanced settings
update_config_advanced() {
    local config_file="$1"
    local http_address="$2"
    local p2p_endpoint="$3"
    local state_history_endpoint="$4"
    local chain_threads="$5"
    local http_threads="$6"
    local max_transaction_time="$7"
    local abi_serializer_max_time="$8"
    local chain_state_db_size="$9"
    local max_clients="${10}"
    local contracts_console="${11}"
    local verbose_http_errors="${12}"
    local pause_on_startup="${13}"
    local producer_enabled="${14}"
    local producer_name="${15}"
    shift 15
    local p2p_peers=("$@")
    
    print_status "Updating $config_file with advanced settings..."
    
    # Create backup
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update network settings
    sed -i "s|^http-server-address = .*|http-server-address = $http_address|" "$config_file"
    sed -i "s|^p2p-listen-endpoint = .*|p2p-listen-endpoint = $p2p_endpoint|" "$config_file"
    sed -i "s|^state-history-endpoint = .*|state-history-endpoint = $state_history_endpoint|" "$config_file"
    
    # Update performance settings
    sed -i "s|^chain-threads = .*|chain-threads = $chain_threads|" "$config_file"
    sed -i "s|^http-threads = .*|http-threads = $http_threads|" "$config_file"
    sed -i "s|^max-transaction-time = .*|max-transaction-time = $max_transaction_time|" "$config_file"
    sed -i "s|^abi-serializer-max-time-ms = .*|abi-serializer-max-time-ms = $abi_serializer_max_time|" "$config_file"
    
    # Update database settings
    sed -i "s|^chain-state-db-size-mb = .*|chain-state-db-size-mb = $chain_state_db_size|" "$config_file"
    sed -i "s|^max-clients = .*|max-clients = $max_clients|" "$config_file"
    
    # Update logging settings
    if [ "$contracts_console" = "true" ]; then
        sed -i "s|^contracts-console = .*|contracts-console = true|" "$config_file"
    else
        sed -i "s|^contracts-console = .*|contracts-console = false|" "$config_file"
    fi
    
    if [ "$verbose_http_errors" = "true" ]; then
        sed -i "s|^verbose-http-errors = .*|verbose-http-errors = true|" "$config_file"
    else
        sed -i "s|^verbose-http-errors = .*|verbose-http-errors = false|" "$config_file"
    fi
    
    # Update security settings
    if [ "$pause_on_startup" = "true" ]; then
        sed -i "s|^pause-on-startup = .*|pause-on-startup = true|" "$config_file"
    else
        sed -i "s|^pause-on-startup = .*|pause-on-startup = false|" "$config_file"
    fi
    
    # Remove existing P2P peer addresses
    sed -i '/^p2p-peer-address = /d' "$config_file"
    
    # Add new P2P peer addresses
    for peer in "${p2p_peers[@]}"; do
        echo "p2p-peer-address = $peer" >> "$config_file"
    done
    
    # Update producer configuration
    if [ "$producer_enabled" = "true" ]; then
        print_status "Enabling producer mode for $producer_name"
        
        # Enable producer plugin
        sed -i 's|^#plugin = eosio::producer_plugin|plugin = eosio::producer_plugin|' "$config_file"
        sed -i 's|^#plugin = eosio::producer_api_plugin|plugin = eosio::producer_api_plugin|' "$config_file"
        
        # Set producer name
        sed -i "s|^#producer-name = yourproducername|producer-name = $producer_name|" "$config_file"
        
        # Disable pause on startup for producers
        if [ "$pause_on_startup" = "true" ]; then
            print_warning "Disabling pause-on-startup for producer mode"
            sed -i "s|^pause-on-startup = true|#pause-on-startup = true  # Disabled for producer mode|" "$config_file"
        fi
        
        print_warning "IMPORTANT: Configure producer keys using deploy-producer.sh after deployment"
    else
        # Ensure producer plugins are disabled
        sed -i 's|^plugin = eosio::producer_plugin|#plugin = eosio::producer_plugin|' "$config_file"
        sed -i 's|^plugin = eosio::producer_api_plugin|#plugin = eosio::producer_api_plugin|' "$config_file"
    fi
    
    print_status "Advanced configuration updated successfully"
}

# Function to update docker-compose.yml
update_docker_compose() {
    local mainnet_http_port="$1"
    local mainnet_p2p_port="$2"
    local mainnet_state_history_port="$3"
    local testnet_http_port="$4"
    local testnet_p2p_port="$5"
    local testnet_state_history_port="$6"
    
    print_status "Updating docker-compose.yml..."
    
    # Create backup
    cp "$DOCKER_COMPOSE" "${DOCKER_COMPOSE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update mainnet ports
    sed -i "s|      - \"9888:9888\"|      - \"$mainnet_http_port:$mainnet_http_port\"|" "$DOCKER_COMPOSE"
    sed -i "s|      - \"9876:9876\"|      - \"$mainnet_p2p_port:$mainnet_p2p_port\"|" "$DOCKER_COMPOSE"
    sed -i "s|      - \"9080:9080\"|      - \"$mainnet_state_history_port:$mainnet_state_history_port\"|" "$DOCKER_COMPOSE"
    
    # Update testnet ports
    sed -i "s|      - \"9889:9889\"|      - \"$testnet_http_port:$testnet_http_port\"|" "$DOCKER_COMPOSE"
    sed -i "s|      - \"9877:9877\"|      - \"$testnet_p2p_port:$testnet_p2p_port\"|" "$DOCKER_COMPOSE"
    sed -i "s|      - \"9081:9081\"|      - \"$testnet_state_history_port:$testnet_state_history_port\"|" "$DOCKER_COMPOSE"
    
    print_status "Docker Compose configuration updated successfully"
}

# Function to validate configuration
validate_configuration() {
    local mainnet_http_port="$1"
    local mainnet_p2p_port="$2"
    local testnet_http_port="$3"
    local testnet_p2p_port="$4"
    
    # Check for port conflicts
    if [ "$mainnet_http_port" = "$mainnet_p2p_port" ]; then
        print_error "Mainnet HTTP and P2P ports cannot be the same"
        return 1
    fi
    
    if [ "$testnet_http_port" = "$testnet_p2p_port" ]; then
        print_error "Testnet HTTP and P2P ports cannot be the same"
        return 1
    fi
    
    if [ "$mainnet_http_port" = "$testnet_http_port" ]; then
        print_error "Mainnet and testnet HTTP ports cannot be the same"
        return 1
    fi
    
    if [ "$mainnet_p2p_port" = "$testnet_p2p_port" ]; then
        print_error "Mainnet and testnet P2P ports cannot be the same"
        return 1
    fi
    
    return 0
}

# Main deployment function
main() {
    print_header "Libre Node Advanced Deployment Configuration"
    
    print_status "This script will configure your Libre mainnet and testnet nodes with advanced settings."
    print_status "You can press Enter to accept default values where shown."
    echo
    
    # Get mainnet configuration
    print_header "Mainnet Network Configuration"
    
    mainnet_listen_ip=$(get_input "Enter mainnet listen IP address" "$DEFAULT_LISTEN_IP" "validate_ip")
    mainnet_http_port=$(get_input "Enter mainnet HTTP port" "$DEFAULT_MAINNET_HTTP_PORT" "validate_port")
    mainnet_p2p_port=$(get_input "Enter mainnet P2P port" "$DEFAULT_MAINNET_P2P_PORT" "validate_port")
    mainnet_state_history_port=$(get_input "Enter mainnet state history port" "$DEFAULT_MAINNET_STATE_HISTORY_PORT" "validate_port")
    
    print_status "Enter mainnet P2P peers:"
    mainnet_p2p_peers=($(get_p2p_peers))
    
    echo
    
    # Get mainnet performance configuration
    print_header "Mainnet Performance Configuration"
    
    mainnet_chain_threads=$(get_input "Enter mainnet chain threads" "4" "validate_range 1 16")
    mainnet_http_threads=$(get_input "Enter mainnet HTTP threads" "6" "validate_range 1 32")
    mainnet_max_transaction_time=$(get_input "Enter mainnet max transaction time (ms)" "1000" "validate_range 100 10000")
    mainnet_abi_serializer_max_time=$(get_input "Enter mainnet ABI serializer max time (ms)" "12500" "validate_range 1000 60000")
    mainnet_chain_state_db_size=$(get_input "Enter mainnet chain state DB size (MB)" "32768" "validate_range 8192 131072")
    mainnet_max_clients=$(get_input "Enter mainnet max clients" "200" "validate_range 50 1000")
    
    echo
    
    # Get mainnet logging configuration
    print_header "Mainnet Logging Configuration"
    
    mainnet_contracts_console=$(get_yes_no "Enable mainnet contracts console output?" "true")
    mainnet_verbose_http_errors=$(get_yes_no "Enable mainnet verbose HTTP errors?" "true")
    mainnet_pause_on_startup=$(get_yes_no "Enable mainnet pause on startup?" "true")
    
    echo
    
    # Get testnet configuration
    print_header "Testnet Network Configuration"
    
    testnet_listen_ip=$(get_input "Enter testnet listen IP address" "$DEFAULT_LISTEN_IP" "validate_ip")
    testnet_http_port=$(get_input "Enter testnet HTTP port" "$DEFAULT_TESTNET_HTTP_PORT" "validate_port")
    testnet_p2p_port=$(get_input "Enter testnet P2P port" "$DEFAULT_TESTNET_P2P_PORT" "validate_port")
    testnet_state_history_port=$(get_input "Enter testnet state history port" "$DEFAULT_TESTNET_STATE_HISTORY_PORT" "validate_port")
    
    print_status "Enter testnet P2P peers:"
    testnet_p2p_peers=($(get_p2p_peers))
    
    echo
    
    # Get testnet performance configuration
    print_header "Testnet Performance Configuration"
    
    testnet_chain_threads=$(get_input "Enter testnet chain threads" "4" "validate_range 1 16")
    testnet_http_threads=$(get_input "Enter testnet HTTP threads" "6" "validate_range 1 32")
    testnet_max_transaction_time=$(get_input "Enter testnet max transaction time (ms)" "1000" "validate_range 100 10000")
    testnet_abi_serializer_max_time=$(get_input "Enter testnet ABI serializer max time (ms)" "12500" "validate_range 1000 60000")
    testnet_chain_state_db_size=$(get_input "Enter testnet chain state DB size (MB)" "32768" "validate_range 8192 131072")
    testnet_max_clients=$(get_input "Enter testnet max clients" "100" "validate_range 25 500")
    
    echo
    
    # Get testnet logging configuration
    print_header "Testnet Logging Configuration"
    
    testnet_contracts_console=$(get_yes_no "Enable testnet contracts console output?" "true")
    testnet_verbose_http_errors=$(get_yes_no "Enable testnet verbose HTTP errors?" "true")
    testnet_pause_on_startup=$(get_yes_no "Enable testnet pause on startup?" "true")
    
    echo
    
    # Get producer configuration
    print_header "Producer Configuration (Optional)"
    
    print_warning "Producer mode is for authorized block producers only"
    print_warning "Only enable if you have proper authorization and keys"
    echo
    
    configure_producer=$(get_yes_no "Configure producer mode?" "false")
    
    mainnet_producer_enabled="false"
    testnet_producer_enabled="false"
    mainnet_producer_name=""
    testnet_producer_name=""
    
    if [ "$configure_producer" = "true" ]; then
        mainnet_producer_enabled=$(get_yes_no "Enable mainnet producer?" "false")
        testnet_producer_enabled=$(get_yes_no "Enable testnet producer?" "false")
        
        if [ "$mainnet_producer_enabled" = "true" ]; then
            mainnet_producer_name=$(get_input "Mainnet producer account name" "")
        fi
        
        if [ "$testnet_producer_enabled" = "true" ]; then
            testnet_producer_name=$(get_input "Testnet producer account name" "")
        fi
        
        print_warning "Producer keys must be configured manually after deployment"
        print_warning "Use the deploy-producer.sh script for detailed producer setup"
    fi
    
    echo
    
    # Validate configuration
    print_header "Validating Configuration"
    
    if ! validate_configuration "$mainnet_http_port" "$mainnet_p2p_port" "$testnet_http_port" "$testnet_p2p_port"; then
        print_error "Configuration validation failed. Please fix the issues and try again."
        exit 1
    fi
    
    print_status "Configuration validation passed."
    echo
    
    # Summary
    print_header "Configuration Summary"
    
    print_status "Mainnet Configuration:"
    echo "  Listen IP: $mainnet_listen_ip"
    echo "  HTTP Port: $mainnet_http_port"
    echo "  P2P Port: $mainnet_p2p_port"
    echo "  State History Port: $mainnet_state_history_port"
    echo "  Chain Threads: $mainnet_chain_threads"
    echo "  HTTP Threads: $mainnet_http_threads"
    echo "  Max Transaction Time: ${mainnet_max_transaction_time}ms"
    echo "  ABI Serializer Max Time: ${mainnet_abi_serializer_max_time}ms"
    echo "  Chain State DB Size: ${mainnet_chain_state_db_size}MB"
    echo "  Max Clients: $mainnet_max_clients"
    echo "  Contracts Console: $mainnet_contracts_console"
    echo "  Verbose HTTP Errors: $mainnet_verbose_http_errors"
    echo "  Pause on Startup: $mainnet_pause_on_startup"
    echo "  P2P Peers: ${mainnet_p2p_peers[*]}"
    echo
    
    print_status "Testnet Configuration:"
    echo "  Listen IP: $testnet_listen_ip"
    echo "  HTTP Port: $testnet_http_port"
    echo "  P2P Port: $testnet_p2p_port"
    echo "  State History Port: $testnet_state_history_port"
    echo "  Chain Threads: $testnet_chain_threads"
    echo "  HTTP Threads: $testnet_http_threads"
    echo "  Max Transaction Time: ${testnet_max_transaction_time}ms"
    echo "  ABI Serializer Max Time: ${testnet_abi_serializer_max_time}ms"
    echo "  Chain State DB Size: ${testnet_chain_state_db_size}MB"
    echo "  Max Clients: $testnet_max_clients"
    echo "  Contracts Console: $testnet_contracts_console"
    echo "  Verbose HTTP Errors: $testnet_verbose_http_errors"
    echo "  Pause on Startup: $testnet_pause_on_startup"
    echo "  P2P Peers: ${testnet_p2p_peers[*]}"
    echo
    
    if [ "$configure_producer" = "true" ]; then
        print_status "Producer Configuration:"
        echo "  Mainnet Producer: $mainnet_producer_enabled"
        if [ "$mainnet_producer_enabled" = "true" ]; then
            echo "    Account: $mainnet_producer_name"
        fi
        echo "  Testnet Producer: $testnet_producer_enabled"
        if [ "$testnet_producer_enabled" = "true" ]; then
            echo "    Account: $testnet_producer_name"
        fi
        echo "  Note: Use deploy-producer.sh for complete producer setup"
        echo
    fi
    
    # Confirm deployment
    confirm=$(get_input "Proceed with deployment? (y/n)" "y" "")
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        print_status "Deployment cancelled."
        exit 0
    fi
    
    # Update configurations
    print_header "Updating Configurations"
    
    # Update mainnet config
    update_config_advanced "$MAINNET_CONFIG" \
        "$mainnet_listen_ip:$mainnet_http_port" \
        "$mainnet_listen_ip:$mainnet_p2p_port" \
        "$mainnet_listen_ip:$mainnet_state_history_port" \
        "$mainnet_chain_threads" \
        "$mainnet_http_threads" \
        "$mainnet_max_transaction_time" \
        "$mainnet_abi_serializer_max_time" \
        "$mainnet_chain_state_db_size" \
        "$mainnet_max_clients" \
        "$mainnet_contracts_console" \
        "$mainnet_verbose_http_errors" \
        "$mainnet_pause_on_startup" \
        "$mainnet_producer_enabled" \
        "$mainnet_producer_name" \
        "${mainnet_p2p_peers[@]}"
    
    # Update testnet config
    update_config_advanced "$TESTNET_CONFIG" \
        "$testnet_listen_ip:$testnet_http_port" \
        "$testnet_listen_ip:$testnet_p2p_port" \
        "$testnet_listen_ip:$testnet_state_history_port" \
        "$testnet_chain_threads" \
        "$testnet_http_threads" \
        "$testnet_max_transaction_time" \
        "$testnet_abi_serializer_max_time" \
        "$testnet_chain_state_db_size" \
        "$testnet_max_clients" \
        "$testnet_contracts_console" \
        "$testnet_verbose_http_errors" \
        "$testnet_pause_on_startup" \
        "$testnet_producer_enabled" \
        "$testnet_producer_name" \
        "${testnet_p2p_peers[@]}"
    
    # Update docker-compose.yml
    update_docker_compose \
        "$mainnet_http_port" \
        "$mainnet_p2p_port" \
        "$mainnet_state_history_port" \
        "$testnet_http_port" \
        "$testnet_p2p_port" \
        "$testnet_state_history_port"
    
    print_header "Advanced Deployment Complete"
    print_status "Configuration files have been updated successfully."
    print_status "Backup files have been created with timestamps."
    echo
    print_status "To start the nodes, run:"
    echo "  docker-compose -f docker/docker-compose.yml up -d"
    echo
    print_status "To view logs, run:"
    echo "  docker-compose -f docker/docker-compose.yml logs -f"
    echo
    print_status "To stop the nodes, run:"
    echo "  docker-compose -f docker/docker-compose.yml down"
    echo
    print_status "For monitoring and maintenance, see the scripts/ directory."
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root."
    exit 1
fi

# Check if required files exist
if [ ! -f "$MAINNET_CONFIG" ]; then
    print_error "Mainnet config file not found: $MAINNET_CONFIG"
    exit 1
fi

if [ ! -f "$TESTNET_CONFIG" ]; then
    print_error "Testnet config file not found: $TESTNET_CONFIG"
    exit 1
fi

if [ ! -f "$DOCKER_COMPOSE" ]; then
    print_error "Docker Compose file not found: $DOCKER_COMPOSE"
    exit 1
fi

# Run main function
main "$@" 