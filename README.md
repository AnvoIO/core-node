# Libre Blockchain Node Docker Setup

This repository contains a Docker-based setup for running Libre blockchain nodes (mainnet and testnet) using AntelopeIO Leap v5.0.3.

## 🚀 New in v2.0: Block Producer Support

- **Full Producer Mode**: Configure nodes as block producers with security best practices
- **Lightweight Producer Mode**: Run producers with minimal resources using snapshots (4-6GB RAM)
- **Flexible Snapshot System**: Support for multiple snapshot providers and compression formats
- **Enhanced Scripts**: All scripts now work from any directory with improved error handling

## Overview

Libre is a blockchain platform based on AntelopeIO technology. This setup provides:

- **Libre Mainnet API Node** (Port 9888)
- **Libre Testnet API Node** (Port 9889)
- **State History Plugin (SHiP)** endpoints for both networks
- **P2P connectivity** to official Libre peers
- **Block Producer Support** with lightweight mode option

## Prerequisites

### For API Nodes
- Docker and Docker Compose installed
- At least 8GB RAM available
- 100GB+ free disk space for blockchain data
- Stable internet connection
- Ports 9888, 9889, 9876, 9877, 9080, 9081 available

### For Block Producers (Lightweight Mode)
- Docker and Docker Compose installed
- 4-6GB RAM available
- 20GB free disk space (snapshots only)
- Stable internet connection
- Producer account and keys registered on network

## Quick Start

1. **Clone the repository:**

   ```bash
   git clone <repository-url>
   cd docker-libre-node
   ```

2. **Set up permissions (required for Docker volume mounts):**

   ```bash
   ./setup-permissions.sh
   ```

3. **Configure the nodes (recommended):**

   ```bash
   # Basic configuration (network settings only)
   ./scripts/deploy.sh

   # OR Advanced configuration (all settings)
   ./scripts/deploy-advanced.sh
   ```

4. **Build and start the nodes:**

   ```bash
   ./scripts/start.sh
   ```

5. **Check node status:**
   ```bash
   ./scripts/status.sh
   ```

## Manual Setup

If you prefer to set up manually:

1. **Build the Docker image:**

   ```bash
   ./docker/build.sh
   ```

2. **Start the nodes:**

   ```bash
   # Using the convenience script (recommended)
   ./docker-compose.sh up -d

   # Or directly with docker-compose
   docker-compose -f docker/docker-compose.yml up -d
   ```

3. **View logs:**

   ```bash
   # Using convenience script
   ./docker-compose.sh logs -f libre-mainnet    # Mainnet logs
   ./docker-compose.sh logs -f libre-testnet    # Testnet logs

   # Or using management scripts
   ./scripts/logs.sh mainnet    # Mainnet logs
   ./scripts/logs.sh testnet    # Testnet logs
   ```

## Configuration

### Deployment Scripts

The repository includes two deployment scripts for configuring nodes:

#### Basic Deployment (`deploy.sh`)

- Configures network settings (IP addresses, ports, P2P peers)
- Suitable for most users
- Quick setup with sensible defaults

#### Advanced Deployment (`deploy-advanced.sh`)

- Configures all available settings
- Performance tuning options
- Logging and security settings
- Database configuration
- Suitable for production deployments

#### Configuration Template (`config-template.sh`)

- Shows all available configuration options
- Provides recommendations for different use cases
- Reference for manual configuration

### Network Information

| Network | Chain ID                                                           | API Port | P2P Port | SHiP Port |
| ------- | ------------------------------------------------------------------ | -------- | -------- | --------- |
| Mainnet | `38b1d7815474d0bf271d659c50b579893768b3b2c3dc6a14c4be6a7b3e14f2fb` | 9888     | 9876     | 9080      |
| Testnet | `b64646740308df2ee06c6b72f34c0f7fa066d940e831f752db2006fcc2b78dee` | 9889     | 9877     | 9081      |

### P2P Peers

**Mainnet:**

- `p2p.libre.iad.cryptobloks.io:9876`
- `p2p.libre.pdx.cryptobloks.io:9876`

**Testnet:**

- `p2p.testnet.libre.iad.cryptobloks.io:9876`
- `p2p.testnet.libre.pdx.cryptobloks.io:9876`

## API Endpoints

### Mainnet

- **HTTP API:** http://localhost:9888
- **State History:** ws://localhost:9080
- **Node Info:** http://localhost:9888/v1/chain/get_info

### Testnet

- **HTTP API:** http://localhost:9889
- **State History:** ws://localhost:9081
- **Node Info:** http://localhost:9889/v1/chain/get_info

## Management Scripts

| Script                       | Description                                        |
| ---------------------------- | -------------------------------------------------- |
| `scripts/deploy.sh`          | Basic node configuration (network settings)        |
| `scripts/deploy-advanced.sh` | Advanced node configuration (all settings)         |
| `scripts/deploy-producer.sh` | **NEW**: Configure block producer functionality   |
| `scripts/producer-snapshot.sh` | **NEW**: Download/manage snapshots for producers |
| `scripts/start-producer.sh`  | **NEW**: Start lightweight producer nodes         |
| `scripts/config-template.sh` | Show all configuration options and recommendations |
| `scripts/start.sh`           | Start both nodes (builds image if needed)          |
| `scripts/stop.sh`            | Stop both nodes                                    |
| `scripts/restart.sh`         | Restart both nodes                                 |
| `scripts/logs.sh`            | View logs (mainnet\|testnet)                       |
| `scripts/status.sh`          | Check node status and connectivity                 |
| `scripts/reset.sh`           | Reset node data (WARNING: deletes all data)        |
| `build.sh`                   | Build Docker image manually                        |

## Directory Structure

```
libre-node/
├── CLAUDE.md                  # Claude Code guidance file
├── README.md                  # This documentation
├── docker-compose.sh          # Docker compose wrapper
├── setup-permissions.sh       # Permission setup script
├── logs.sh                    # Quick log viewer
├── config/                    # Configuration directory
│   └── snapshot-providers.conf # Snapshot provider configuration
├── docker/                    # Docker configuration
│   ├── Dockerfile            # Custom Libre node image
│   ├── docker-compose.yml    # Standard node compose file
│   ├── docker-compose-producer.yml # Producer node compose file
│   └── build.sh              # Docker image build script
├── mainnet/                   # Mainnet configuration
│   ├── config/
│   │   ├── config.ini        # Mainnet node configuration
│   │   ├── genesis.json      # Mainnet genesis block
│   │   └── logging.json      # Logging configuration
│   ├── data/                 # Mainnet blockchain data
│   ├── logs/                 # Mainnet logs
│   └── snapshots/            # Snapshot directory
├── testnet/                   # Testnet configuration
│   ├── config/
│   │   ├── config.ini        # Testnet node configuration
│   │   ├── genesis.json      # Testnet genesis block
│   │   └── logging.json      # Logging configuration
│   ├── data/                 # Testnet blockchain data
│   ├── logs/                 # Testnet logs
│   └── snapshots/            # Snapshot directory
├── scripts/                   # Management scripts
│   ├── deploy.sh             # Basic configuration
│   ├── deploy-advanced.sh    # Advanced configuration
│   ├── deploy-producer.sh    # Producer configuration
│   ├── producer-snapshot.sh  # Snapshot management
│   ├── start-producer.sh     # Start producer nodes
│   ├── config-template.sh    # Configuration reference
│   ├── config-utils.sh       # Configuration utilities
│   ├── start.sh              # Start nodes
│   ├── stop.sh               # Stop nodes
│   ├── restart.sh            # Restart nodes
│   ├── status.sh             # Check status
│   ├── logs.sh               # View logs
│   ├── reset.sh              # Reset all data
│   ├── reset-db.sh           # Reset database only
│   ├── snapshot-manager.sh   # Snapshot management
│   ├── maintenance.sh        # Maintenance utilities
│   └── error-recovery.sh     # Error recovery tools
└── docs/                      # Documentation
    ├── README.md             # Documentation index
    ├── DEPLOYMENT_GUIDE.md   # Deployment guide
    ├── SCRIPT_UPDATES.md     # Script documentation
    ├── DEFAULT_VALUES.md     # Default values reference
    ├── api/                  # API documentation
    ├── examples/             # Example configurations
    └── troubleshooting/      # Troubleshooting guides
```

## Configuration Files

### Node Configuration (`config.ini`)

Key configuration options:

- **Network Settings:** HTTP server, P2P endpoints, state history
- **Performance Tuning:** Chain threads, HTTP threads, transaction timeouts
- **Database Configuration:** Chain state size, client limits
- **Logging Settings:** Console output, verbose errors, startup behavior
- **Security Settings:** Pause on startup, host validation
- **P2P Configuration:** Peer addresses, connection limits

### Configuration Management

All configuration is now centralized in the `config.ini` files. The `docker-compose.yml` file no longer contains redundant settings and only manages:

- Container configuration
- Port mappings
- Volume mounts
- Network settings

### Genesis Files

Contains initial blockchain state:

- **Initial Timestamp:** Genesis block time
- **Initial Key:** Genesis block producer key
- **Initial Configuration:** Network parameters

## Troubleshooting

### Common Issues

1. **Port conflicts:**

   ```bash
   # Check if ports are in use
   netstat -tulpn | grep -E ':(9888|9889|9876|9877|9080|9081)'
   ```

2. **Insufficient memory:**

   ```bash
   # Check available memory
   free -h
   ```

3. **Slow sync:**

   - Ensure stable internet connection
   - Check peer connectivity
   - Monitor system resources

4. **Container won't start:**
   ```bash
   # Check container logs
   docker-compose logs libre-mainnet
   docker-compose logs libre-testnet
   ```

### Reset Node Data

⚠️ **WARNING:** This will delete all blockchain data and require full resync.

```bash
./scripts/reset.sh
```

### View Detailed Logs

```bash
# Mainnet logs
./logs.sh mainnet

# Testnet logs
./logs.sh testnet

# All logs
docker-compose logs -f
```

## Performance Tuning

### Resource Allocation

The default configuration is optimized for:

- **4 CPU cores** for chain processing
- **6 HTTP threads** for API requests
- **16GB RAM** for mainnet state
- **8GB RAM** for testnet state

### Customization

Use the deployment scripts to configure:

- **Network settings:** IP addresses, ports, P2P peers
- **Performance tuning:** Thread counts, timeouts, database sizes
- **Logging options:** Console output, error verbosity
- **Security settings:** Startup behavior, validation

For manual customization, edit the `config.ini` files directly:

- `mainnet/config/config.ini` for mainnet settings
- `testnet/config/config.ini` for testnet settings

The `docker-compose.yml` file manages container configuration only.

## Block Producer Configuration

⚠️ **IMPORTANT**: Producer functionality is only for authorized block producers. Only enable if you have proper authorization from the Libre network.

### Producer Setup

1. **Configure Producer Mode:**

   ```bash
   # Interactive producer configuration
   ./scripts/deploy-producer.sh
   
   # Or include in advanced deployment
   ./scripts/deploy-advanced.sh
   ```

2. **Producer Configuration Options:**

   - **Producer Account Name**: Your registered block producer account
   - **Authentication Method**: Private key or signature provider (recommended)
   - **Stale Production**: Enable production when not scheduled (testnet only)
   - **API Restriction**: Limit API access to localhost for security
   - **P2P Transaction Control**: Disable transaction acceptance via P2P

3. **Security Requirements:**

   ```bash
   # Restrict API to localhost only (recommended for producers)
   http-server-address = 127.0.0.1:9888  # Mainnet
   http-server-address = 127.0.0.1:9889  # Testnet
   
   # Use signature providers instead of private keys
   signature-provider = YOUR_PUBLIC_KEY=KEY:YOUR_PRIVATE_KEY
   
   # Disable P2P transaction acceptance
   p2p-accept-transactions = false
   api-accept-transactions = true
   ```

4. **Producer Status Check:**

   ```bash
   # Check producer configuration
   ./scripts/deploy-producer.sh  # Option 3: Show current status
   
   # View current producer settings
   grep -E "(producer-name|signature-provider|enable-stale)" mainnet/config/config.ini
   ```

### Producer Security Guidelines

- **Key Management**: Never store private keys in plaintext. Use secure key management solutions.
- **Network Security**: Use firewall rules to restrict access to producer nodes.
- **API Access**: Restrict HTTP API to localhost only in production.
- **Monitoring**: Monitor logs for any security issues or unexpected behavior.
- **Backups**: Maintain secure backups of configuration and keys.
- **Updates**: Keep the node software updated with latest security patches.

### Producer Configuration Files

Producer settings are added to the existing `config.ini` files:

- **Mainnet Producer**: `mainnet/config/config.ini`
- **Testnet Producer**: `testnet/config/config.ini`

Key producer settings:
```ini
# Producer Plugin (enable for block production)
plugin = eosio::producer_plugin
plugin = eosio::producer_api_plugin

# Producer Configuration
producer-name = yourproducername
signature-provider = YOUR_PUBLIC_KEY=KEY:YOUR_PRIVATE_KEY
enable-stale-production = false  # true for testnet only

# Security Settings for Producers
http-server-address = 127.0.0.1:9888  # Restrict API access
p2p-accept-transactions = false        # Disable P2P transactions
api-accept-transactions = true         # Accept transactions via API only
```

### Lightweight Producer Mode (Snapshot-Based)

For block producers who don't need full state history, use the lightweight mode that:
- Downloads fresh snapshots from EOSUSA (https://snapshots.eosusa.io)
- Keeps only the last 1000 blocks in memory
- Uses minimal disk space (4GB state vs 32GB)
- Starts quickly from snapshot (5-10 minutes)
- Runs with tmpfs (RAM-based) storage for blocks/state

#### Lightweight Setup Process

1. **Configure Producer Keys:**
   ```bash
   # Choose option 3 or 4 for lightweight mode
   ./scripts/deploy-producer.sh
   ```

2. **Download Latest Snapshot:**
   ```bash
   # Downloads and prepares snapshot
   ./scripts/producer-snapshot.sh
   # Choose option 1 for mainnet or 2 for testnet
   ```

3. **Start Lightweight Producer:**
   ```bash
   # Start with optimized Docker compose
   ./scripts/start-producer.sh
   # Or manually:
   docker-compose -f docker/docker-compose-producer.yml up -d
   ```

#### Lightweight Mode Benefits

- **Minimal Resources**: 4-6GB RAM instead of 16GB+
- **Fast Restarts**: Fresh from snapshot in minutes
- **No State Accumulation**: Blocks pruned automatically
- **RAM-Based Performance**: Uses tmpfs for temporary data
- **Automatic Snapshot Loading**: Starts from latest network state

#### Snapshot Sources

The system supports multiple snapshot providers configured in `config/snapshot-providers.conf`:

**Default Provider (EOSUSA):**
- **Mainnet**: https://snapshots.eosusa.io/snapshots/libre
- **Testnet**: https://snapshots.eosusa.io/snapshots/libretestnet
- Format: `.bin.zst` (zstandard compressed)
- Updated daily

**Adding Custom Providers:**

To add your own snapshot provider, edit `config/snapshot-providers.conf`:
```bash
# Format: PROVIDER_NAME|BASE_URL|PATH_PATTERN|FILE_PATTERN|COMPRESSION
YOURPROVIDER_MAINNET|https://your-snapshots.com|/path/to/mainnet|.*\.bin\.zst$|zst
YOURPROVIDER_TESTNET|https://your-snapshots.com|/path/to/testnet|.*\.bin\.zst$|zst
```

**Supported Compression Formats:**
- `zst` - Zstandard (requires zstd)
- `gz` - Gzip (requires gzip)  
- `bz2` - Bzip2 (requires bzip2)
- `xz` - XZ (requires xz)
- `none` - Uncompressed

**Provider Selection:**
```bash
# List available providers
./scripts/producer-snapshot.sh  # Option 5: Show provider information

# Select specific provider
./scripts/producer-snapshot.sh  # Option 6: List providers and select
```

## Security Considerations

- **Firewall:** Restrict access to necessary ports only
- **Authentication:** Implement API authentication if exposed publicly
- **Updates:** Regularly update the Docker image for security patches
- **Backups:** Regularly backup configuration and data directories

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- **[docs/README.md](docs/README.md)** - Documentation index and overview
- **[docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)** - Complete deployment and configuration guide
- **[docs/SCRIPT_UPDATES.md](docs/SCRIPT_UPDATES.md)** - Documentation of script updates and improvements
- **[docs/DEFAULT_VALUES.md](docs/DEFAULT_VALUES.md)** - Reference for all default configuration values
- **[docs/api/](docs/api/)** - API documentation and examples
- **[docs/troubleshooting/](docs/troubleshooting/)** - Troubleshooting guide and common issues
- **[docs/examples/](docs/examples/)** - Example scripts and configurations

## Support

For issues and questions:

- Check the [troubleshooting guide](docs/troubleshooting/README.md)
- Review [Libre blockchain documentation](https://libre.org/)
- Open an issue on GitHub

## Changelog

### v2.0.0 - Block Producer Support

- **Producer Functionality:** Complete block producer support
  - `deploy-producer.sh` for producer configuration
  - Producer plugin integration
  - Signature provider support
  - Security-focused defaults
- **Lightweight Producer Mode:** Minimal resource usage for producers
  - Snapshot-based initialization
  - Memory-only state (4-6GB RAM vs 16GB+)
  - tmpfs volumes for temporary data
  - Automatic state pruning (last 1000 blocks)
- **Snapshot Management:** Flexible snapshot provider system
  - `producer-snapshot.sh` for snapshot downloads
  - `config/snapshot-providers.conf` for provider configuration
  - Support for multiple compression formats (zst, gz, bz2, xz)
  - EOSUSA as default provider
- **Enhanced Scripts:**
  - `start-producer.sh` for lightweight producer startup
  - Path fixes for all scripts (work from any directory)
  - Improved error handling and validation
  - Added `CLAUDE.md` for AI assistance
- **Docker Improvements:**
  - `docker-compose-producer.yml` for optimized producer containers
  - Memory limits and health checks
  - Host network mode for performance

### v1.1.0 - Configuration Management

- **Configuration Management:** Centralized all settings in `config.ini` files
- **Deployment Scripts:** Added interactive configuration scripts
  - `deploy.sh` for basic network configuration
  - `deploy-advanced.sh` for comprehensive settings
  - `config-template.sh` for configuration reference
- **Redundancy Removal:** Eliminated duplicate settings between `docker-compose.yml` and `config.ini`
- **Validation:** Added input validation and configuration checks
- **Backup System:** Automatic backup creation with timestamps
- **Documentation:** Updated README with new configuration process

### v1.0.0 - Initial Release

- Initial release
- Libre mainnet and testnet support
- AntelopeIO Leap v5.0.3
- State History Plugin support
- Comprehensive management scripts
