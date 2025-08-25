#!/bin/bash

# Libre Node Docker Compose Wrapper
# This script provides convenient access to docker-compose commands
# with the correct file path for the docker directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker/docker-compose.yml"

# Function to print usage
print_usage() {
    echo "Libre Node Docker Compose Wrapper"
    echo "Usage: $0 [docker-compose-command] [options...]"
    echo ""
    echo "Examples:"
    echo "  $0 up -d                    # Start nodes in background"
    echo "  $0 down                     # Stop nodes"
    echo "  $0 restart                  # Restart nodes"
    echo "  $0 ps                       # Show container status"
    echo "  $0 logs -f libre-mainnet    # Follow mainnet logs"
    echo "  $0 logs -f libre-testnet    # Follow testnet logs"
    echo "  $0 logs                     # Show all logs"
    echo ""
    echo "This script automatically uses: docker-compose -f docker/docker-compose.yml"
}

# Check if docker-compose file exists
if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
    echo "Error: Docker Compose file not found at $DOCKER_COMPOSE_FILE"
    echo "Please ensure you're running this script from the project root directory."
    exit 1
fi

# Check if command is provided
if [ $# -eq 0 ]; then
    print_usage
    exit 1
fi

# Check for help flag
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    print_usage
    exit 0
fi

# Execute docker-compose command
echo "Running: docker-compose -f $DOCKER_COMPOSE_FILE $*"
echo ""

docker-compose -f "$DOCKER_COMPOSE_FILE" "$@" 