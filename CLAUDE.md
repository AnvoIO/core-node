# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker-based setup for running Libre blockchain nodes (mainnet and testnet) using AntelopeIO Leap v5.0.3. The repository contains configuration scripts, Docker setup, and management tools for operating Libre API nodes with State History Plugin (SHiP) support.

## Architecture

### Core Components
- **Docker containers**: Two separate containers for mainnet and testnet nodes
- **Configuration system**: Centralized `config.ini` files for each network
- **Management scripts**: Interactive deployment and operational scripts
- **Volume mounts**: Persistent storage for blockchain data, config, and logs

### Directory Structure
```
libre-node/
├── docker/                   # Docker configuration
│   ├── Dockerfile           # Custom Libre node image (Ubuntu 22.04 + Leap v5.0.3)
│   ├── docker-compose.yml   # Container orchestration
│   └── build.sh            # Image build script
├── scripts/                 # Management and deployment scripts
├── mainnet/                 # Mainnet node files
│   ├── config/config.ini   # Mainnet nodeos configuration
│   ├── data/               # Blockchain data (volume mount)
│   └── logs/               # Node logs (volume mount)
├── testnet/                 # Testnet node files (same structure)
└── docs/                   # Comprehensive documentation
```

## Key Configuration Files

### Node Configuration (`config.ini`)
All nodeos runtime settings are centralized in these files:
- `mainnet/config/config.ini` - Mainnet node configuration
- `testnet/config/config.ini` - Testnet node configuration

Key settings include:
- HTTP server endpoints (ports 9888/9889)
- P2P listen endpoints (ports 9876/9877)  
- State History endpoints (ports 9080/9081)
- Plugin configuration (chain, API, net, state_history)
- Performance tuning (threads, timeouts, database sizes)
- P2P peer addresses

### Docker Configuration
- `docker/docker-compose.yml` - Container definitions only (no redundant settings)
- `docker/Dockerfile` - Custom image with AntelopeIO Leap v5.0.3
- Uses `network_mode: host` for direct port access

## Common Commands

### Initial Setup
```bash
# Set up data directory permissions
./setup-permissions.sh

# Configure nodes (interactive)
./scripts/deploy.sh          # Basic network configuration
./scripts/deploy-advanced.sh # Full configuration options
./scripts/deploy-producer.sh # Producer configuration (authorized producers only)

# Build and start nodes
./scripts/start.sh
```

### Daily Operations
```bash
# Check node status
./scripts/status.sh

# View logs
./scripts/logs.sh mainnet    # Mainnet logs
./scripts/logs.sh testnet    # Testnet logs

# Restart nodes
./scripts/restart.sh

# Stop nodes
./scripts/stop.sh
```

### Direct Docker Management
```bash
# Using wrapper script (recommended)
./docker-compose.sh up -d
./docker-compose.sh logs -f libre-mainnet
./docker-compose.sh ps

# Direct docker-compose
docker-compose -f docker/docker-compose.yml up -d
```

### Maintenance Operations
```bash
# Reset blockchain data (WARNING: full resync required)
./scripts/reset.sh

# Database reset only
./scripts/reset-db.sh
```

## Network Information

| Network | Chain ID | HTTP Port | P2P Port | SHiP Port |
|---------|----------|-----------|----------|-----------|
| Mainnet | `38b1d7815474d0bf271d659c50b579893768b3b2c3dc6a14c4be6a7b3e14f2fb` | 9888 | 9876 | 9080 |
| Testnet | `b64646740308df2ee06c6b72f34c0f7fa066d940e831f752db2006fcc2b78dee` | 9889 | 9877 | 9081 |

### API Endpoints
- Mainnet: `http://localhost:9888`
- Testnet: `http://localhost:9889`
- State History: `ws://localhost:9080` (mainnet), `ws://localhost:9081` (testnet)

## Development Guidelines

### Configuration Management
- All nodeos settings are in `config.ini` files - never modify `docker-compose.yml` for runtime settings
- Use deployment scripts for configuration changes rather than manual editing
- Scripts automatically create timestamped backups before changes

### Container Management
- Images are tagged as `libre-node:5.0.3`
- Containers use host networking for direct port access
- Data persistence through Docker volumes in mainnet/testnet directories

### Script System
- All scripts source `scripts/config-utils.sh` for shared functions
- Scripts include input validation and error handling
- Use the provided management scripts rather than direct Docker commands

## Block Producer Configuration

**WARNING**: Producer functionality is only for authorized block producers. Never enable producer mode without proper network authorization.

### Producer Setup Commands
```bash
# Interactive producer configuration
./scripts/deploy-producer.sh

# Include producer settings in advanced deployment
./scripts/deploy-advanced.sh  # Choose "Configure producer mode"

# Check producer status
./scripts/deploy-producer.sh  # Option 3: Show current status

# Disable producer mode
./scripts/deploy-producer.sh  # Option 4: Disable producer mode
```

### Producer Configuration Files
Producer settings are added to existing `config.ini` files:
- `mainnet/config/config.ini` - Mainnet producer configuration
- `testnet/config/config.ini` - Testnet producer configuration

### Key Producer Settings
- `plugin = eosio::producer_plugin` - Enable block production
- `producer-name = yourname` - Registered producer account
- `signature-provider = KEY=VALUE` - Secure key management (recommended)
- `enable-stale-production = false` - Production outside schedule (testnet only)
- `http-server-address = 127.0.0.1:PORT` - Restrict API access for security
- `p2p-accept-transactions = false` - Disable P2P transaction acceptance

### Producer Security Requirements
- Use signature providers instead of raw private keys
- Restrict API access to localhost only in production
- Implement proper firewall rules and network security
- Monitor logs for security issues
- Maintain secure backups of keys and configuration

### Lightweight Producer Mode
For producers that don't need full history, use snapshot-based lightweight mode:

```bash
# Setup lightweight producer
./scripts/deploy-producer.sh  # Choose options 3 or 4

# Download latest snapshot
./scripts/producer-snapshot.sh  # Option 1 (mainnet) or 2 (testnet)

# Start lightweight producer
./scripts/start-producer.sh

# Or use dedicated Docker compose
docker-compose -f docker/docker-compose-producer.yml up -d
```

**Lightweight Mode Features:**
- Downloads fresh snapshots from https://snapshots.eosusa.io
- Keeps only last 1000 blocks in memory
- Uses 4GB state instead of 32GB
- tmpfs (RAM) for blocks/state directories
- Fast restart from snapshot (5-10 minutes)
- Automatic pruning - no state accumulation

## Troubleshooting

### Common Issues
- **Port conflicts**: Check if ports 9876-9081, 9888-9889 are available
- **Permission errors**: Run `./setup-permissions.sh`
- **Slow sync**: Check P2P peer connectivity and network resources
- **Container issues**: Check logs with `./scripts/logs.sh [network]`

### Performance Tuning
- Default: 4 CPU cores for chain processing, 6 HTTP threads
- Memory: 16GB for mainnet, 8GB for testnet chain state
- Adjust in `config.ini` files via deployment scripts

## Testing

This is an infrastructure project for blockchain node operations. Testing primarily involves:
- Node startup and connectivity verification
- API endpoint functionality
- P2P peer synchronization
- State History Plugin operation

Use `./scripts/status.sh` to verify all components are working correctly.