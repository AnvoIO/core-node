#!/bin/bash

# Libre Node Deployment Script
# This script configures and deploys Libre mainnet and testnet nodes

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

# Function to update config.ini file
update_config() {
    local config_file="$1"
    local http_address="$2"
    local p2p_endpoint="$3"
    local state_history_endpoint="$4"
    shift 4
    local p2p_peers=("$@")
    
    print_status "Updating $config_file..."
    
    # Create backup
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update HTTP server address
    sed -i "s|^http-server-address = .*|http-server-address = $http_address|" "$config_file"
    
    # Update P2P listen endpoint
    sed -i "s|^p2p-listen-endpoint = .*|p2p-listen-endpoint = $p2p_endpoint|" "$config_file"
    
    # Update state history endpoint
    sed -i "s|^state-history-endpoint = .*|state-history-endpoint = $state_history_endpoint|" "$config_file"
    
    # Remove existing P2P peer addresses
    sed -i '/^p2p-peer-address = /d' "$config_file"
    
    # Add new P2P peer addresses
    for peer in "${p2p_peers[@]}"; do
        echo "p2p-peer-address = $peer" >> "$config_file"
    done
    
    print_status "Configuration updated successfully"
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

# Main deployment function
main() {
    print_header "Libre Node Deployment Configuration"
    
    print_status "This script will configure your Libre mainnet and testnet nodes."
    print_status "You can press Enter to accept default values where shown."
    echo
    
    # Get mainnet configuration
    print_header "Mainnet Configuration"
    
    mainnet_listen_ip=$(get_input "Enter mainnet listen IP address" "$DEFAULT_LISTEN_IP" "validate_ip")
    mainnet_http_port=$(get_input "Enter mainnet HTTP port" "$DEFAULT_MAINNET_HTTP_PORT" "validate_port")
    mainnet_p2p_port=$(get_input "Enter mainnet P2P port" "$DEFAULT_MAINNET_P2P_PORT" "validate_port")
    mainnet_state_history_port=$(get_input "Enter mainnet state history port" "$DEFAULT_MAINNET_STATE_HISTORY_PORT" "validate_port")
    
    print_status "Enter mainnet P2P peers:"
    mainnet_p2p_peers=($(get_p2p_peers))
    
    echo
    
    # Get testnet configuration
    print_header "Testnet Configuration"
    
    testnet_listen_ip=$(get_input "Enter testnet listen IP address" "$DEFAULT_LISTEN_IP" "validate_ip")
    testnet_http_port=$(get_input "Enter testnet HTTP port" "$DEFAULT_TESTNET_HTTP_PORT" "validate_port")
    testnet_p2p_port=$(get_input "Enter testnet P2P port" "$DEFAULT_TESTNET_P2P_PORT" "validate_port")
    testnet_state_history_port=$(get_input "Enter testnet state history port" "$DEFAULT_TESTNET_STATE_HISTORY_PORT" "validate_port")
    
    print_status "Enter testnet P2P peers:"
    testnet_p2p_peers=($(get_p2p_peers))
    
    echo
    
    # Summary
    print_header "Configuration Summary"
    
    print_status "Mainnet Configuration:"
    echo "  Listen IP: $mainnet_listen_ip"
    echo "  HTTP Port: $mainnet_http_port"
    echo "  P2P Port: $mainnet_p2p_port"
    echo "  State History Port: $mainnet_state_history_port"
    echo "  P2P Peers: ${mainnet_p2p_peers[*]}"
    echo
    
    print_status "Testnet Configuration:"
    echo "  Listen IP: $testnet_listen_ip"
    echo "  HTTP Port: $testnet_http_port"
    echo "  P2P Port: $testnet_p2p_port"
    echo "  State History Port: $testnet_state_history_port"
    echo "  P2P Peers: ${testnet_p2p_peers[*]}"
    echo
    
    # Confirm deployment
    confirm=$(get_input "Proceed with deployment? (y/n)" "y" "")
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        print_status "Deployment cancelled."
        exit 0
    fi
    
    # Update configurations
    print_header "Updating Configurations"
    
    # Update mainnet config
    update_config "$MAINNET_CONFIG" \
        "$mainnet_listen_ip:$mainnet_http_port" \
        "$mainnet_listen_ip:$mainnet_p2p_port" \
        "$mainnet_listen_ip:$mainnet_state_history_port" \
        "${mainnet_p2p_peers[@]}"
    
    # Update testnet config
    update_config "$TESTNET_CONFIG" \
        "$testnet_listen_ip:$testnet_http_port" \
        "$testnet_listen_ip:$testnet_p2p_port" \
        "$testnet_listen_ip:$testnet_state_history_port" \
        "${testnet_p2p_peers[@]}"
    
    # Update docker-compose.yml
    update_docker_compose \
        "$mainnet_http_port" \
        "$mainnet_p2p_port" \
        "$mainnet_state_history_port" \
        "$testnet_http_port" \
        "$testnet_p2p_port" \
        "$testnet_state_history_port"
    
    print_header "Deployment Complete"
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