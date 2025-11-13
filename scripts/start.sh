#!/bin/bash

# Source configuration utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/config-utils.sh"

echo "Starting Libre Blockchain nodes..."

# Check if permissions are set up correctly
if [ ! -w "$PROJECT_ROOT/mainnet/data" ] || [ ! -w "$PROJECT_ROOT/testnet/data" ]; then
    echo "⚠️  Warning: Data directories may not have correct permissions."
    echo "   Run './setup-permissions.sh' if you encounter permission errors."
    echo ""
fi

# Check if Docker image exists, build if not
if ! docker images | grep -q "libre-node.*5.0.3"; then
    echo "Docker image not found. Building..."
    "$PROJECT_ROOT/docker/build.sh"
fi

docker-compose -f "$PROJECT_ROOT/docker/docker-compose.yml" up -d
echo "Waiting for nodes to start..."
sleep 15
echo "Libre nodes status:"
docker-compose -f "$PROJECT_ROOT/docker/docker-compose.yml" ps
echo ""

# Get current configuration
mainnet_http_url=$(get_http_url "mainnet")
testnet_http_url=$(get_http_url "testnet")
mainnet_ws_url=$(get_ws_url "mainnet")
testnet_ws_url=$(get_ws_url "testnet")

echo "Libre Mainnet API: $mainnet_http_url"
echo "Libre Testnet API: $testnet_http_url"
echo ""
echo "State History Endpoints:"
echo "Libre Mainnet SHiP: $mainnet_ws_url"
echo "Libre Testnet SHiP: $testnet_ws_url"
echo ""
echo "To check node info:"
echo "curl $mainnet_http_url/v1/chain/get_info  # Mainnet"
echo "curl $testnet_http_url/v1/chain/get_info  # Testnet"
echo ""
echo "Note: Initial sync may take time depending on network connectivity"
