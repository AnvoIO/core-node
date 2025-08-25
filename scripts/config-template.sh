#!/bin/bash

# Libre Node Configuration Template
# This script shows all configurable options for Libre nodes

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

main() {
    print_header "Libre Node Configuration Options"
    
    print_status "This document outlines all configurable options for Libre nodes."
    echo
    
    print_header "Network Configuration"
    echo "1. HTTP Server Address (http-server-address)"
    echo "   - Controls which IP and port the HTTP API listens on"
    echo "   - Format: IP:PORT (e.g., 0.0.0.0:9888)"
    echo "   - Default: 0.0.0.0:9888 (mainnet), 0.0.0.0:9889 (testnet)"
    echo
    
    echo "2. P2P Listen Endpoint (p2p-listen-endpoint)"
    echo "   - Controls which IP and port the P2P network listens on"
    echo "   - Format: IP:PORT (e.g., 0.0.0.0:9876)"
    echo "   - Default: 0.0.0.0:9876 (mainnet), 0.0.0.0:9877 (testnet)"
    echo
    
    echo "3. State History Endpoint (state-history-endpoint)"
    echo "   - Controls which IP and port the state history API listens on"
    echo "   - Format: IP:PORT (e.g., 0.0.0.0:9080)"
    echo "   - Default: 0.0.0.0:9080 (mainnet), 0.0.0.0:9081 (testnet)"
    echo
    
    echo "4. P2P Peer Addresses (p2p-peer-address)"
    echo "   - List of P2P peers to connect to"
    echo "   - Format: HOST:PORT (e.g., p2p.libre.iad.cryptobloks.io:9876)"
    echo "   - Multiple entries can be specified"
    echo
    
    print_header "Performance Configuration"
    echo "5. Chain Threads (chain-threads)"
    echo "   - Number of threads for chain processing"
    echo "   - Default: 4"
    echo "   - Recommended: 2-8 depending on CPU cores"
    echo
    
    echo "6. HTTP Threads (http-threads)"
    echo "   - Number of threads for HTTP API processing"
    echo "   - Default: 6"
    echo "   - Recommended: 4-12 depending on expected load"
    echo
    
    echo "7. Max Transaction Time (max-transaction-time)"
    echo "   - Maximum time in milliseconds for transaction processing"
    echo "   - Default: 1000"
    echo "   - Recommended: 1000-3000"
    echo
    
    echo "8. ABI Serializer Max Time (abi-serializer-max-time-ms)"
    echo "   - Maximum time in milliseconds for ABI serialization"
    echo "   - Default: 12500"
    echo "   - Recommended: 10000-20000"
    echo
    
    print_header "Database Configuration"
    echo "9. Chain State DB Size (chain-state-db-size-mb)"
    echo "   - Size of the chain state database in MB"
    echo "   - Default: 32768 (32GB)"
    echo "   - Recommended: 16384-65536 depending on available RAM"
    echo
    
    echo "10. Max Clients (max-clients)"
    echo "    - Maximum number of P2P connections"
    echo "    - Default: 200 (mainnet), 100 (testnet)"
    echo "    - Recommended: 100-500"
    echo
    
    print_header "Logging Configuration"
    echo "11. Contracts Console (contracts-console)"
    echo "    - Enable smart contract console output"
    echo "    - Default: true"
    echo "    - Recommended: true for development, false for production"
    echo
    
    echo "12. Verbose HTTP Errors (verbose-http-errors)"
    echo "     - Enable detailed HTTP error messages"
    echo "     - Default: true"
    echo "     - Recommended: true for development, false for production"
    echo
    
    print_header "Security Configuration"
    echo "13. Pause on Startup (pause-on-startup)"
    echo "     - Pause node startup for manual verification"
    echo "     - Default: true"
    echo "     - Recommended: true for production nodes"
    echo
    
    echo "14. HTTP Validate Host (http-validate-host)"
    echo "     - Validate HTTP Host header"
    echo "     - Default: false"
    echo "     - Recommended: true for production with proper hostnames"
    echo
    
    print_header "State History Configuration"
    echo "15. Trace History (trace-history)"
    echo "     - Enable transaction trace history"
    echo "     - Default: true"
    echo "     - Recommended: true for API nodes"
    echo
    
    echo "16. Chain State History (chain-state-history)"
    echo "      - Enable chain state history"
    echo "      - Default: true"
    echo "      - Recommended: true for API nodes"
    echo
    
    echo "17. State History Directory (state-history-dir)"
    echo "      - Directory for state history files"
    echo "      - Default: /opt/eosio/data/state-history"
    echo "      - Recommended: Use default or custom path with sufficient space"
    echo
    
    print_header "Stride Configuration"
    echo "18. Blocks Log Stride (blocks-log-stride)"
    echo "     - Number of blocks per log file"
    echo "     - Default: 250000"
    echo "     - Recommended: 100000-500000"
    echo
    
    echo "19. State History Stride (state-history-stride)"
    echo "      - Number of blocks per state history file"
    echo "      - Default: 250000"
    echo "      - Recommended: 100000-500000"
    echo
    
    echo "20. Trace Slice Stride (trace-slice-stride)"
    echo "      - Number of blocks per trace slice file"
    echo "      - Default: 250000"
    echo "      - Recommended: 100000-500000"
    echo
    
    print_header "Additional Runtime Configurations"
    echo "21. Network Configuration"
    echo "     - Custom network interfaces"
    echo "     - Firewall rules"
    echo "     - Load balancer settings"
    echo
    
    echo "22. Storage Configuration"
    echo "     - SSD vs HDD recommendations"
    echo "     - RAID configurations"
    echo "     - Backup strategies"
    echo
    
    echo "23. Monitoring Configuration"
    echo "     - Log aggregation"
    echo "     - Metrics collection"
    echo "     - Alerting rules"
    echo
    
    echo "24. Security Hardening"
    echo "     - SSL/TLS certificates"
    echo "     - Access control lists"
    echo "     - Rate limiting"
    echo
    
    print_header "Deployment Recommendations"
    echo "For Production Nodes:"
    echo "- Use dedicated hardware with SSD storage"
    echo "- Configure proper firewall rules"
    echo "- Set up monitoring and alerting"
    echo "- Use SSL/TLS for HTTP endpoints"
    echo "- Implement proper backup strategies"
    echo "- Consider using a reverse proxy"
    echo
    
    echo "For Development Nodes:"
    echo "- Use default configurations for simplicity"
    echo "- Enable verbose logging for debugging"
    echo "- Use localhost or private IP addresses"
    echo "- Disable pause-on-startup for faster startup"
    echo
    
    print_header "Configuration File Locations"
    echo "Mainnet: mainnet/config/config.ini"
    echo "Testnet:  testnet/config/config.ini"
    echo "Docker:   docker/docker-compose.yml"
    echo
    
    print_status "Use the deploy.sh script to configure these settings interactively."
    print_status "All configuration changes are backed up automatically."
}

# Run main function
main "$@" 