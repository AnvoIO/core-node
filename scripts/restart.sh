#!/bin/bash

# Source configuration utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config-utils.sh"

echo "Restarting Libre Blockchain nodes..."
cd "$(dirname "$0")/.."
docker-compose -f docker/docker-compose.yml restart
echo "Waiting for nodes to restart..."
sleep 10
echo "Libre nodes status:"
docker-compose -f docker/docker-compose.yml ps
echo ""

# Get current configuration
mainnet_http_url=$(get_http_url "mainnet")
testnet_http_url=$(get_http_url "testnet")

echo "Libre Mainnet API: $mainnet_http_url"
echo "Libre Testnet API: $testnet_http_url" 