# Libre Node Documentation

This directory contains comprehensive documentation for the Libre blockchain node setup and configuration system.

## Documentation Overview

### 📋 [Deployment Guide](DEPLOYMENT_GUIDE.md)

Complete guide for deploying and configuring Libre nodes using the new configuration system.

**Topics covered:**

- Configuration system overview
- Deployment scripts (basic and advanced)
- Configuration file management
- Validation and backup systems
- Troubleshooting and recovery

### 🔧 [Script Updates](SCRIPT_UPDATES.md)

Detailed documentation of all script updates made to support the new configuration system.

**Topics covered:**

- Configuration utility functions
- Updated script details
- Benefits and improvements
- Testing and validation
- Backward compatibility

### ⚙️ [Default Values](DEFAULT_VALUES.md)

Comprehensive reference for all default values used in the configuration system.

**Topics covered:**

- IP address and port defaults
- Where defaults are defined
- How defaults are used
- Modifying defaults
- Best practices

## Quick Reference

### Deployment Scripts

```bash
# Basic configuration (network settings only)
./scripts/deploy.sh

# Advanced configuration (all settings)
./scripts/deploy-advanced.sh

# Configuration reference
./scripts/config-template.sh

# Build Docker image
./docker/build.sh

# Docker Compose convenience script
./docker-compose.sh up -d
```

### Configuration Utility

```bash
# Show all configuration
./scripts/config-utils.sh show

# Get specific values
./scripts/config-utils.sh http-url mainnet
./scripts/config-utils.sh ws-url testnet
./scripts/config-utils.sh http-port mainnet
```

### Management Scripts

```bash
# Start nodes
./scripts/start.sh

# Check status
./scripts/status.sh

# View logs
./scripts/logs.sh mainnet
./scripts/logs.sh testnet

# Maintenance
./scripts/maintenance.sh health mainnet
./scripts/snapshot-manager.sh create mainnet
```

## Default Configuration

### Network Settings

- **Mainnet HTTP:** `0.0.0.0:9888`
- **Mainnet P2P:** `0.0.0.0:9876`
- **Mainnet State History:** `0.0.0.0:9080`
- **Testnet HTTP:** `0.0.0.0:9889`
- **Testnet P2P:** `0.0.0.0:9877`
- **Testnet State History:** `0.0.0.0:9081`

### P2P Peers

**Mainnet:**

- `p2p.libre.iad.cryptobloks.io:9876`
- `p2p.libre.pdx.cryptobloks.io:9876`

**Testnet:**

- `p2p.testnet.libre.iad.cryptobloks.io:9876`
- `p2p.testnet.libre.pdx.cryptobloks.io:9876`

## Getting Started

1. **Read the [Deployment Guide](DEPLOYMENT_GUIDE.md)** for complete setup instructions
2. **Use the [Default Values](DEFAULT_VALUES.md)** reference for configuration details
3. **Review [Script Updates](SCRIPT_UPDATES.md)** to understand the new system

## Support

For issues and questions:

- Check the troubleshooting sections in each guide
- Review the main [README.md](../README.md) in the project root
- Open an issue on GitHub with detailed information

## Contributing

When contributing to the documentation:

- Keep information up to date with code changes
- Use clear, consistent formatting
- Include practical examples
- Test all commands and procedures
