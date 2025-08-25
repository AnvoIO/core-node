#!/bin/bash

# Libre Blockchain Node Logs Script

cd "$(dirname "$0")/.."

if [ $# -eq 0 ]; then
    echo "Usage: $0 [mainnet|testnet] [--follow]"
    echo ""
    echo "Examples:"
    echo "  $0 mainnet          # Show mainnet logs"
    echo "  $0 testnet          # Show testnet logs"
    echo "  $0 mainnet --follow # Follow mainnet logs"
    echo "  $0 testnet --follow # Follow testnet logs"
    exit 1
fi

NETWORK=$1
FOLLOW_FLAG=""

if [ "$2" = "--follow" ]; then
    FOLLOW_FLAG="-f"
fi

case $NETWORK in
    mainnet)
        echo "=== Libre Mainnet Logs ==="
        docker-compose -f docker/docker-compose.yml logs $FOLLOW_FLAG libre-mainnet
        ;;
    testnet)
        echo "=== Libre Testnet Logs ==="
        docker-compose -f docker/docker-compose.yml logs $FOLLOW_FLAG libre-testnet
        ;;
    *)
        echo "Error: Invalid network. Use 'mainnet' or 'testnet'"
        exit 1
        ;;
esac 