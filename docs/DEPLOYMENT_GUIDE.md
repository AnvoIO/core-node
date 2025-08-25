# Libre Node Deployment Guide

This guide explains the new configuration system for Libre blockchain nodes and how to use the deployment scripts.

## Overview

The Libre node setup has been updated to eliminate redundant configuration settings and provide a more user-friendly deployment process. All runtime configurations are now centralized in the `config.ini` files, while the `docker-compose.yml` file focuses only on container management.

## What Changed

### Before (Redundant Configuration)

- Settings were duplicated between `docker/docker-compose.yml` and `config.ini`
- Users had to edit multiple files to change configuration
- No validation or backup system
- Manual configuration process

### After (Centralized Configuration)

- All settings centralized in `config.ini` files
- Interactive deployment scripts with validation
- Automatic backup creation
- User-friendly configuration process

## Deployment Scripts

### 1. Basic Deployment (`deploy.sh`)

**Use for:** Quick setup with default settings
**Configures:**

- Network IP addresses and ports
- P2P peer addresses
- Docker port mappings

**Example usage:**

```bash
./scripts/deploy.sh
```

**What it asks for:**

- Mainnet listen IP (default: 0.0.0.0)
- Mainnet HTTP port (default: 9888)
- Mainnet P2P port (default: 9876)
- Mainnet state history port (default: 9080)
- Mainnet P2P peers
- Testnet listen IP (default: 0.0.0.0)
- Testnet HTTP port (default: 9889)
- Testnet P2P port (default: 9877)
- Testnet state history port (default: 9081)
- Testnet P2P peers

### 2. Advanced Deployment (`deploy-advanced.sh`)

**Use for:** Production deployments with custom tuning
**Configures everything from basic deployment plus:**

- Performance settings (threads, timeouts)
- Database configuration
- Logging options
- Security settings

**Example usage:**

```bash
./scripts/deploy-advanced.sh
```

**Additional settings:**

- Chain threads (1-16)
- HTTP threads (1-32)
- Max transaction time (100-10000ms)
- ABI serializer max time (1000-60000ms)
- Chain state DB size (8192-131072MB)
- Max clients (25-1000)
- Contracts console output (y/n)
- Verbose HTTP errors (y/n)
- Pause on startup (y/n)

### 3. Configuration Reference (`config-template.sh`)

**Use for:** Understanding all available options
**Provides:**

- Complete list of configurable settings
- Recommended values for different use cases
- Performance tuning guidelines

**Example usage:**

```bash
./scripts/config-template.sh
```

## Configuration Files

### Mainnet Configuration

- **File:** `mainnet/config/config.ini`
- **Purpose:** All mainnet node settings
- **Backup:** Automatically created with timestamp

### Testnet Configuration

- **File:** `testnet/config/config.ini`
- **Purpose:** All testnet node settings
- **Backup:** Automatically created with timestamp

### Docker Compose

- **File:** `docker/docker-compose.yml`
- **Purpose:** Container management only
- **Contains:** Port mappings, volumes, networks

## Configuration Categories

### Network Settings

```ini
http-server-address = 0.0.0.0:9888
p2p-listen-endpoint = 0.0.0.0:9876
state-history-endpoint = 0.0.0.0:9080
p2p-peer-address = p2p.libre.iad.cryptobloks.io:9876
```

### Performance Settings

```ini
chain-threads = 4
http-threads = 6
max-transaction-time = 1000
abi-serializer-max-time-ms = 12500
```

### Database Settings

```ini
chain-state-db-size-mb = 32768
max-clients = 200
```

### Logging Settings

```ini
contracts-console = true
verbose-http-errors = true
```

### Security Settings

```ini
pause-on-startup = true
http-validate-host = false
```

## Deployment Process

### Step 1: Choose Deployment Type

```bash
# For basic setup
./scripts/deploy.sh

# For production setup
./scripts/deploy-advanced.sh

# For reference
./scripts/config-template.sh
```

### Step 2: Follow Interactive Prompts

The scripts will guide you through:

1. Network configuration
2. Performance tuning (advanced only)
3. Logging options (advanced only)
4. Security settings (advanced only)
5. Configuration summary
6. Confirmation

### Step 3: Start Nodes

```bash
./scripts/start.sh
```

### Step 4: Verify Deployment

```bash
./scripts/status.sh
```

## Validation Features

### Input Validation

- **IP Addresses:** Valid IPv4 format
- **Port Numbers:** 1-65535 range
- **Numeric Values:** Range validation for performance settings
- **Yes/No Questions:** Clear boolean input

### Configuration Validation

- **Port Conflicts:** Prevents duplicate port usage
- **File Existence:** Checks for required configuration files
- **Backup Creation:** Automatic backup before changes

### Error Handling

- **Clear Messages:** Descriptive error messages
- **Graceful Exit:** Safe exit on validation failure
- **Backup Recovery:** Easy restoration from backups

## Backup System

### Automatic Backups

- Created before any configuration changes
- Timestamped filenames (e.g., `config.ini.backup.20241201_143022`)
- Stored in same directory as original files

### Manual Backup

```bash
# Backup mainnet config
cp mainnet/config/config.ini mainnet/config/config.ini.backup

# Backup testnet config
cp testnet/config/config.ini testnet/config/config.ini.backup

# Backup docker-compose
cp docker/docker-compose.yml docker/docker-compose.yml.backup
```

### Restore from Backup

```bash
# Restore mainnet config
cp mainnet/config/config.ini.backup.20241201_143022 mainnet/config/config.ini

# Restore testnet config
cp testnet/config/config.ini.backup.20241201_143022 testnet/config/config.ini

# Restore docker-compose
cp docker/docker-compose.yml.backup.20241201_143022 docker/docker-compose.yml
```

## Use Cases

### Development Environment

```bash
# Quick setup with defaults
./scripts/deploy.sh
```

**Recommended settings:**

- Use default ports
- Enable contracts console
- Enable verbose HTTP errors
- Disable pause on startup

### Production Environment

```bash
# Comprehensive configuration
./scripts/deploy-advanced.sh
```

**Recommended settings:**

- Use dedicated IP addresses
- Custom ports for security
- Optimize performance settings
- Disable verbose logging
- Enable pause on startup
- Use multiple P2P peers

### Testing Environment

```bash
# Basic setup with custom ports
./scripts/deploy.sh
```

**Recommended settings:**

- Use different ports from production
- Enable all logging for debugging
- Use testnet peers only

## Troubleshooting

### Common Issues

1. **Port Already in Use**

   ```
   [ERROR] Invalid input. Please try again.
   ```

   **Solution:** Choose different ports or stop conflicting services

2. **Invalid IP Address**

   ```
   [ERROR] Invalid input. Please try again.
   ```

   **Solution:** Use valid IPv4 format (e.g., 0.0.0.0, 127.0.0.1)

3. **Configuration File Not Found**

   ```
   [ERROR] Mainnet config file not found: mainnet/config/config.ini
   ```

   **Solution:** Ensure you're in the correct directory

4. **Permission Denied**
   ```
   [ERROR] Please do not run this script as root.
   ```
   **Solution:** Run as regular user, not root

### Recovery Procedures

1. **Restore from Backup**

   ```bash
   # Find latest backup
   ls -la mainnet/config/config.ini.backup.*

   # Restore
   cp mainnet/config/config.ini.backup.20241201_143022 mainnet/config/config.ini
   ```

2. **Reset to Defaults**

   ```bash
   # Run deployment script again
   ./scripts/deploy.sh
   ```

3. **Manual Configuration**
   ```bash
   # Edit files directly
   nano mainnet/config/config.ini
   nano testnet/config/config.ini
   ```

## Best Practices

### Security

- Use dedicated IP addresses for production
- Choose non-standard ports when possible
- Enable pause on startup for verification
- Use multiple P2P peers for redundancy

### Performance

- Match thread counts to CPU cores
- Allocate sufficient RAM for database
- Monitor resource usage after deployment
- Adjust settings based on load testing

### Maintenance

- Keep backups of working configurations
- Document custom settings
- Test changes in development first
- Monitor logs for issues

### Monitoring

- Use `./scripts/status.sh` regularly
- Monitor log files for errors
- Check resource usage
- Verify peer connectivity

## Migration from Old Configuration

If you have an existing setup:

1. **Backup Current Configuration**

   ```bash
   cp mainnet/config/config.ini mainnet/config/config.ini.old
   cp testnet/config/config.ini testnet/config/config.ini.old
   cp docker/docker-compose.yml docker/docker-compose.yml.old
   ```

2. **Run Deployment Script**

   ```bash
   ./scripts/deploy.sh
   ```

3. **Verify Settings**

   - Check that your custom settings are preserved
   - Verify port mappings are correct
   - Test node connectivity

4. **Start Nodes**
   ```bash
   ./scripts/start.sh
   ```

## Support

For issues with the deployment scripts:

1. Check the troubleshooting section
2. Review the configuration template
3. Check backup files for working configurations
4. Open an issue with detailed error messages

## Future Enhancements

Planned improvements:

- Environment variable support
- Configuration profiles (dev/staging/prod)
- Automated testing of configurations
- Integration with monitoring systems
- Web-based configuration interface
