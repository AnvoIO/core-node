#!/bin/bash

# Libre Node Configuration Utilities
# This script provides functions to read configuration from config.ini files

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

# Configuration file paths
MAINNET_CONFIG="$PROJECT_DIR/mainnet/config/config.ini"
TESTNET_CONFIG="$PROJECT_DIR/testnet/config/config.ini"

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

# Function to extract value from config.ini
get_config_value() {
    local config_file="$1"
    local key="$2"
    local default_value="$3"
    
    if [ ! -f "$config_file" ]; then
        print_warning "Config file not found: $config_file"
        echo "$default_value"
        return 0
    fi
    
    local value=$(grep "^$key = " "$config_file" | cut -d'=' -f2 | xargs)
    if [ -z "$value" ]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

# Function to get HTTP server address for a network
get_http_address() {
    local network="$1"
    local config_file
    local default_port
    
    case $network in
        "mainnet")
            config_file="$MAINNET_CONFIG"
            default_port="$DEFAULT_MAINNET_HTTP_PORT"
            ;;
        "testnet")
            config_file="$TESTNET_CONFIG"
            default_port="$DEFAULT_TESTNET_HTTP_PORT"
            ;;
        *)
            print_error "Invalid network: $network"
            return 1
            ;;
    esac
    
    get_config_value "$config_file" "http-server-address" "$DEFAULT_LISTEN_IP:$default_port"
}

# Function to get P2P listen endpoint for a network
get_p2p_endpoint() {
    local network="$1"
    local config_file
    local default_port
    
    case $network in
        "mainnet")
            config_file="$MAINNET_CONFIG"
            default_port="$DEFAULT_MAINNET_P2P_PORT"
            ;;
        "testnet")
            config_file="$TESTNET_CONFIG"
            default_port="$DEFAULT_TESTNET_P2P_PORT"
            ;;
        *)
            print_error "Invalid network: $network"
            return 1
            ;;
    esac
    
    get_config_value "$config_file" "p2p-listen-endpoint" "$DEFAULT_LISTEN_IP:$default_port"
}

# Function to get state history endpoint for a network
get_state_history_endpoint() {
    local network="$1"
    local config_file
    local default_port
    
    case $network in
        "mainnet")
            config_file="$MAINNET_CONFIG"
            default_port="$DEFAULT_MAINNET_STATE_HISTORY_PORT"
            ;;
        "testnet")
            config_file="$TESTNET_CONFIG"
            default_port="$DEFAULT_TESTNET_STATE_HISTORY_PORT"
            ;;
        *)
            print_error "Invalid network: $network"
            return 1
            ;;
    esac
    
    get_config_value "$config_file" "state-history-endpoint" "$DEFAULT_LISTEN_IP:$default_port"
}

# Function to get HTTP URL for a network
get_http_url() {
    local network="$1"
    local http_address=$(get_http_address "$network")
    
    # Extract IP and port from http-server-address
    local ip=$(echo "$http_address" | cut -d':' -f1)
    local port=$(echo "$http_address" | cut -d':' -f2)
    
    # Convert 0.0.0.0 to localhost for local access
    if [ "$ip" = "0.0.0.0" ]; then
        ip="localhost"
    fi
    
    echo "http://$ip:$port"
}

# Function to get WebSocket URL for state history
get_ws_url() {
    local network="$1"
    local state_history_endpoint=$(get_state_history_endpoint "$network")
    
    # Extract IP and port from state-history-endpoint
    local ip=$(echo "$state_history_endpoint" | cut -d':' -f1)
    local port=$(echo "$state_history_endpoint" | cut -d':' -f2)
    
    # Convert 0.0.0.0 to localhost for local access
    if [ "$ip" = "0.0.0.0" ]; then
        ip="localhost"
    fi
    
    echo "ws://$ip:$port"
}

# Function to get HTTP port for a network
get_http_port() {
    local network="$1"
    local http_address=$(get_http_address "$network")
    echo "$http_address" | cut -d':' -f2
}

# Function to get P2P port for a network
get_p2p_port() {
    local network="$1"
    local p2p_endpoint=$(get_p2p_endpoint "$network")
    echo "$p2p_endpoint" | cut -d':' -f2
}

# Function to get state history port for a network
get_state_history_port() {
    local network="$1"
    local state_history_endpoint=$(get_state_history_endpoint "$network")
    echo "$state_history_endpoint" | cut -d':' -f2
}

# Function to get container name for a network
get_container_name() {
    local network="$1"
    case $network in
        "mainnet")
            echo "libre-mainnet-api"
            ;;
        "testnet")
            echo "libre-testnet-api"
            ;;
        *)
            print_error "Invalid network: $network"
            return 1
            ;;
    esac
}

# Function to check if container is running
is_container_running() {
    local container="$1"
    docker ps --format "table {{.Names}}" | grep -q "^$container$"
}

# Function to check if container exists
container_exists() {
    local container="$1"
    docker ps -a --format "table {{.Names}}" | grep -q "^$container$"
}

# Function to validate network parameter
is_valid_network() {
    local network="$1"
    case $network in
        "mainnet"|"testnet")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to display current configuration
show_config() {
    local network="$1"
    
    if [ -z "$network" ]; then
        echo "Current Configuration:"
        echo "======================"
        echo ""
        
        echo "Mainnet:"
        echo "  HTTP Server: $(get_http_address mainnet)"
        echo "  HTTP URL: $(get_http_url mainnet)"
        echo "  P2P Endpoint: $(get_p2p_endpoint mainnet)"
        echo "  State History: $(get_state_history_endpoint mainnet)"
        echo "  State History URL: $(get_ws_url mainnet)"
        echo ""
        
        echo "Testnet:"
        echo "  HTTP Server: $(get_http_address testnet)"
        echo "  HTTP URL: $(get_http_url testnet)"
        echo "  P2P Endpoint: $(get_p2p_endpoint testnet)"
        echo "  State History: $(get_state_history_endpoint testnet)"
        echo "  State History URL: $(get_ws_url testnet)"
        echo ""
    else
        if ! is_valid_network "$network"; then
            print_error "Invalid network: $network"
            return 1
        fi
        
        echo "$network Configuration:"
        echo "======================="
        echo ""
        echo "HTTP Server: $(get_http_address $network)"
        echo "HTTP URL: $(get_http_url $network)"
        echo "P2P Endpoint: $(get_p2p_endpoint $network)"
        echo "State History: $(get_state_history_endpoint $network)"
        echo "State History URL: $(get_ws_url $network)"
        echo ""
    fi
}

# Main function for command line usage
main() {
    if [ $# -eq 0 ]; then
        show_config
        return 0
    fi
    
    case $1 in
        "http-url")
            if [ -z "$2" ]; then
                print_error "Network parameter required"
                return 1
            fi
            get_http_url "$2"
            ;;
        "ws-url")
            if [ -z "$2" ]; then
                print_error "Network parameter required"
                return 1
            fi
            get_ws_url "$2"
            ;;
        "http-port")
            if [ -z "$2" ]; then
                print_error "Network parameter required"
                return 1
            fi
            get_http_port "$2"
            ;;
        "p2p-port")
            if [ -z "$2" ]; then
                print_error "Network parameter required"
                return 1
            fi
            get_p2p_port "$2"
            ;;
        "state-history-port")
            if [ -z "$2" ]; then
                print_error "Network parameter required"
                return 1
            fi
            get_state_history_port "$2"
            ;;
        "container")
            if [ -z "$2" ]; then
                print_error "Network parameter required"
                return 1
            fi
            get_container_name "$2"
            ;;
        "show")
            show_config "$2"
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Usage: $0 [http-url|ws-url|http-port|p2p-port|state-history-port|container|show] [mainnet|testnet]"
            return 1
            ;;
    esac
}

# If script is sourced, don't run main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 