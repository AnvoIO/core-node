# Script Updates for Configuration System

This document summarizes the updates made to all scripts in the `scripts/` directory to support the new centralized configuration system.

## Overview

All scripts have been updated to use the new configuration utilities instead of hardcoded port numbers and localhost URLs. This ensures compatibility with custom IP addresses and ports configured through the deployment scripts.

## New Configuration Utility

### `scripts/config-utils.sh`

A new utility script that provides functions to read configuration from `config.ini` files:

**Key Functions:**

- `get_http_url(network)` - Get HTTP URL for a network
- `get_ws_url(network)` - Get WebSocket URL for state history
- `get_http_port(network)` - Get HTTP port for a network
- `get_p2p_port(network)` - Get P2P port for a network
- `get_state_history_port(network)` - Get state history port for a network
- `get_container_name(network)` - Get container name for a network
- `show_config()` - Display current configuration

**Usage:**

```bash
# Show all configuration
./scripts/config-utils.sh show

# Get specific values
./scripts/config-utils.sh http-url mainnet
./scripts/config-utils.sh ws-url testnet
./scripts/config-utils.sh http-port mainnet
```

## Updated Scripts

### 1. `scripts/start.sh`

**Changes:**

- Added sourcing of `config-utils.sh`
- Replaced hardcoded URLs with dynamic configuration
- Now displays actual configured URLs instead of defaults

**Before:**

```bash
echo "Libre Mainnet API: http://localhost:9888"
echo "Libre Testnet API: http://localhost:9889"
```

**After:**

```bash
mainnet_http_url=$(get_http_url "mainnet")
testnet_http_url=$(get_http_url "testnet")
echo "Libre Mainnet API: $mainnet_http_url"
echo "Libre Testnet API: $testnet_http_url"
```

### 2. `scripts/status.sh`

**Changes:**

- Added sourcing of `config-utils.sh`
- Replaced hardcoded localhost URLs with dynamic configuration
- All API calls now use configured URLs

**Before:**

```bash
curl -s http://localhost:9888/v1/chain/get_info
curl -s http://localhost:9889/v1/chain/get_info
```

**After:**

```bash
mainnet_http_url=$(get_http_url "mainnet")
testnet_http_url=$(get_http_url "testnet")
curl -s "$mainnet_http_url/v1/chain/get_info"
curl -s "$testnet_http_url/v1/chain/get_info"
```

### 3. `scripts/restart.sh`

**Changes:**

- Added sourcing of `config-utils.sh`
- Replaced hardcoded URLs with dynamic configuration

### 4. `scripts/maintenance.sh`

**Changes:**

- Added sourcing of `config-utils.sh`
- Removed duplicate `get_container_name()` function
- Updated all functions to use configuration utilities
- Replaced hardcoded ports in:
  - `get_current_block()`
  - `get_head_block_id()`
  - `check_node_health()`
  - `create_snapshot()`

**Before:**

```bash
case $network in
    "mainnet")
        port=9888
        ;;
    "testnet")
        port=9889
        ;;
esac
local response=$(curl -s "http://localhost:$port/v1/chain/get_info")
```

**After:**

```bash
local http_url=$(get_http_url "$network")
local response=$(curl -s "$http_url/v1/chain/get_info")
```

### 5. `scripts/snapshot-manager.sh`

**Changes:**

- Added sourcing of `config-utils.sh`
- Removed duplicate `get_container_name()` function
- Updated all functions to use configuration utilities
- Replaced hardcoded URLs in:
  - `get_current_block()`
  - `create_snapshot()`
  - Snapshot restoration functions

### 6. `scripts/error-recovery.sh`

**Changes:**

- Added sourcing of `config-utils.sh`
- Removed duplicate `get_container_name()` function
- Updated `check_api_connectivity()` to use configuration utilities

## Benefits of These Updates

### 1. **Configuration Flexibility**

- Scripts now work with any IP address and port combination
- No need to modify scripts when changing configuration
- Supports both local and remote node configurations

### 2. **Consistency**

- All scripts use the same configuration source
- No risk of mismatched port numbers between scripts
- Centralized configuration management

### 3. **Maintainability**

- Single source of truth for configuration
- Easy to update configuration logic in one place
- Reduced code duplication

### 4. **Error Prevention**

- No more hardcoded values that could become outdated
- Automatic fallback to defaults if configuration files are missing
- Validation of configuration values

## Testing

All updated scripts have been tested to ensure they:

- Work with default configuration
- Work with custom IP addresses and ports
- Handle missing configuration files gracefully
- Display correct URLs and endpoints

## Backward Compatibility

The updates maintain full backward compatibility:

- Default values are preserved if configuration files are missing
- Scripts work with existing setups without modification
- No breaking changes to script interfaces

## Usage Examples

### With Default Configuration

```bash
# All scripts work as before
./scripts/start.sh
./scripts/status.sh
./scripts/maintenance.sh health mainnet
```

### With Custom Configuration

```bash
# Configure custom settings
./scripts/deploy.sh

# Scripts automatically use new configuration
./scripts/status.sh  # Uses configured URLs
./scripts/maintenance.sh health mainnet  # Uses configured ports
```

### Configuration Verification

```bash
# Check current configuration
./scripts/config-utils.sh show

# Get specific values
./scripts/config-utils.sh http-url mainnet
./scripts/config-utils.sh ws-url testnet
```

## Future Enhancements

The configuration utility system provides a foundation for:

- Environment-specific configurations
- Configuration validation and testing
- Dynamic configuration updates
- Integration with external configuration management systems

## Troubleshooting

If scripts fail to work with custom configuration:

1. **Check Configuration Files**

   ```bash
   cat mainnet/config/config.ini | grep http-server-address
   cat testnet/config/config.ini | grep http-server-address
   ```

2. **Verify Configuration Utility**

   ```bash
   ./scripts/config-utils.sh show
   ```

3. **Check Script Dependencies**

   ```bash
   # Ensure config-utils.sh is executable
   ls -la scripts/config-utils.sh
   ```

4. **Test Individual Functions**
   ```bash
   ./scripts/config-utils.sh http-url mainnet
   ./scripts/config-utils.sh http-url testnet
   ```

## Summary

All scripts in the `scripts/` directory have been successfully updated to use the new configuration system. The changes ensure that:

- ✅ Scripts work with any IP/port configuration
- ✅ No hardcoded values remain
- ✅ Configuration is centralized and consistent
- ✅ Backward compatibility is maintained
- ✅ Error handling is improved
- ✅ Code is more maintainable

The new system provides a robust foundation for managing Libre node configurations while maintaining the simplicity and reliability of the existing scripts.
