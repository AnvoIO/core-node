# Default Values Configuration

This document explains all the default values used in the Libre node configuration system and where they are defined.

## Overview

The configuration system uses default values for IP addresses and ports that are defined as constants in the scripts. This ensures consistency across all components and makes it easy to modify defaults in one place.

## Default Values

### IP Address

- **Default Listen IP:** `0.0.0.0`
- **Purpose:** Binds to all available network interfaces
- **Usage:** Used for HTTP server, P2P endpoint, and state history endpoint

### Mainnet Ports

- **HTTP Port:** `9888`
- **P2P Port:** `9876`
- **State History Port:** `9080`

### Testnet Ports

- **HTTP Port:** `9889`
- **P2P Port:** `9877`
- **State History Port:** `9081`

## Where Defaults Are Defined

### 1. `scripts/config-utils.sh`

```bash
# Default values
DEFAULT_LISTEN_IP="0.0.0.0"
DEFAULT_MAINNET_HTTP_PORT="9888"
DEFAULT_MAINNET_P2P_PORT="9876"
DEFAULT_MAINNET_STATE_HISTORY_PORT="9080"
DEFAULT_TESTNET_HTTP_PORT="9889"
DEFAULT_TESTNET_P2P_PORT="9877"
DEFAULT_TESTNET_STATE_HISTORY_PORT="9081"
```

**Purpose:** Used by the configuration utility functions to provide fallback values when reading from config.ini files.

### 2. `scripts/deploy.sh`

```bash
# Default values
DEFAULT_LISTEN_IP="0.0.0.0"
DEFAULT_MAINNET_HTTP_PORT="9888"
DEFAULT_MAINNET_P2P_PORT="9876"
DEFAULT_MAINNET_STATE_HISTORY_PORT="9080"
DEFAULT_TESTNET_HTTP_PORT="9889"
DEFAULT_TESTNET_P2P_PORT="9877"
DEFAULT_TESTNET_STATE_HISTORY_PORT="9081"
```

**Purpose:** Used as default values in the basic deployment script prompts.

### 3. `scripts/deploy-advanced.sh`

```bash
# Default values
DEFAULT_LISTEN_IP="0.0.0.0"
DEFAULT_MAINNET_HTTP_PORT="9888"
DEFAULT_MAINNET_P2P_PORT="9876"
DEFAULT_MAINNET_STATE_HISTORY_PORT="9080"
DEFAULT_TESTNET_HTTP_PORT="9889"
DEFAULT_TESTNET_P2P_PORT="9877"
DEFAULT_TESTNET_STATE_HISTORY_PORT="9081"
```

**Purpose:** Used as default values in the advanced deployment script prompts.

## How Defaults Are Used

### 1. Configuration Reading

When reading from `config.ini` files, if a setting is not found, the system falls back to these defaults:

```bash
# Example: Reading HTTP server address
get_config_value "$config_file" "http-server-address" "$DEFAULT_LISTEN_IP:$default_port"
```

### 2. User Prompts

When prompting users for input, these defaults are shown as suggested values:

```bash
# Example: Prompting for HTTP port
mainnet_http_port=$(get_input "Enter mainnet HTTP port" "$DEFAULT_MAINNET_HTTP_PORT" "validate_port")
```

### 3. URL Generation

When generating URLs for local access, `0.0.0.0` is converted to `localhost`:

```bash
# Convert 0.0.0.0 to localhost for local access
if [ "$ip" = "0.0.0.0" ]; then
    ip="localhost"
fi
```

## Port Number Ranges

### Standard Ports

- **HTTP API:** 9888 (mainnet), 9889 (testnet)
- **P2P Network:** 9876 (mainnet), 9877 (testnet)
- **State History:** 9080 (mainnet), 9081 (testnet)

### Validation

Port numbers are validated to ensure they are:

- Numeric values
- Between 1 and 65535
- Not conflicting with other services

## IP Address Options

### Common IP Addresses

- **`0.0.0.0`** - Bind to all interfaces (default)
- **`127.0.0.1`** - Bind to localhost only
- **`192.168.x.x`** - Bind to specific local network interface
- **`10.x.x.x`** - Bind to specific local network interface

### Validation

IP addresses are validated to ensure they are:

- Valid IPv4 format
- Each octet between 0-255
- Properly formatted

## Configuration File Defaults

### `mainnet/config/config.ini`

```ini
http-server-address = 0.0.0.0:9888
p2p-listen-endpoint = 0.0.0.0:9876
state-history-endpoint = 0.0.0.0:9080
```

### `testnet/config/config.ini`

```ini
http-server-address = 0.0.0.0:9889
p2p-listen-endpoint = 0.0.0.0:9877
state-history-endpoint = 0.0.0.0:9081
```

## Modifying Defaults

To change the default values:

1. **Update all script files** that contain the default constants
2. **Update configuration files** if they contain hardcoded defaults
3. **Test the changes** to ensure consistency

### Example: Changing Default HTTP Ports

```bash
# In all deployment scripts, change:
DEFAULT_MAINNET_HTTP_PORT="9888"  # to new port
DEFAULT_TESTNET_HTTP_PORT="9889"  # to new port

# In config-utils.sh, change the same values
# In config.ini files, update the http-server-address values
```

## Best Practices

### 1. **Consistency**

- Always use the same default values across all scripts
- Keep defaults synchronized between deployment scripts and config-utils.sh

### 2. **Documentation**

- Document any changes to default values
- Update this document when defaults are modified

### 3. **Validation**

- Test configuration with both default and custom values
- Ensure port conflicts are avoided

### 4. **Security**

- Consider security implications when changing default IP addresses
- Use appropriate firewall rules for custom ports

## Troubleshooting

### Common Issues

1. **Port Conflicts**

   - Check if ports are already in use: `netstat -tulpn | grep :9888`
   - Use different ports if conflicts exist

2. **IP Address Issues**

   - Ensure IP address is valid: `ping 0.0.0.0`
   - Check network interface availability

3. **Configuration Mismatches**
   - Verify all scripts use the same default values
   - Check config.ini files for consistency

### Verification Commands

```bash
# Check current configuration
./scripts/config-utils.sh show

# Check specific values
./scripts/config-utils.sh http-port mainnet
./scripts/config-utils.sh http-port testnet

# Verify configuration files
grep "http-server-address" mainnet/config/config.ini
grep "http-server-address" testnet/config/config.ini
```

## Summary

The default values system provides:

- ✅ **Consistency** across all scripts and configuration files
- ✅ **Flexibility** for users to customize settings
- ✅ **Maintainability** with centralized default definitions
- ✅ **Validation** to prevent configuration errors
- ✅ **Documentation** for easy reference and modification

All default values are now properly defined as constants and can be easily modified in one place to affect the entire system.
