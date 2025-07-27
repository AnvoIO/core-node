#!/bin/bash

# Libre Node Database Reset Script
# This script safely resets the database when there are version compatibility issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Function to reset database for a specific network
reset_network_db() {
    local network=$1
    local data_dir="./${network}/data"
    
    print_status "Resetting database for ${network}..."
    
    if [ -d "$data_dir" ]; then
        print_warning "This will delete all existing data for ${network}!"
        print_warning "Data directory: $data_dir"
        
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Stopping ${network} container..."
            docker compose stop libre-${network}
            
            print_status "Removing data directory..."
            rm -rf "$data_dir"
            
            print_status "Creating fresh data directory..."
            mkdir -p "$data_dir"
            
            print_status "Database reset complete for ${network}"
        else
            print_status "Database reset cancelled for ${network}"
        fi
    else
        print_status "Data directory does not exist for ${network}, creating it..."
        mkdir -p "$data_dir"
    fi
}

# Main script
print_status "Libre Node Database Reset Script"
echo

# Check if running in the correct directory
if [ ! -f "docker-compose.yml" ]; then
    print_error "Please run this script from the libre-node directory"
    exit 1
fi

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

echo "Available networks:"
echo "1. mainnet"
echo "2. testnet"
echo "3. both"
echo

read -p "Which network(s) would you like to reset? (1/2/3): " choice

case $choice in
    1)
        reset_network_db "mainnet"
        ;;
    2)
        reset_network_db "testnet"
        ;;
    3)
        reset_network_db "mainnet"
        echo
        reset_network_db "testnet"
        ;;
    *)
        print_error "Invalid choice. Please select 1, 2, or 3."
        exit 1
        ;;
esac

print_status "Database reset process completed!"
print_status "You can now start the nodes with: docker compose up -d" 