# Docker Configuration Reorganization

## Changes Made

### 1. Network Mode Change

- Switched from bridge networking to host networking
- Removed port mappings from docker-compose.yml since host networking uses the host's network stack directly
- This change provides better performance and simpler networking configuration

### 2. Configuration Consolidation

- Moved all node-specific configuration to config.ini files
- Simplified docker-compose.yml to only contain Docker-specific settings
- Added explicit data-dir and config-dir settings to config.ini files
- Removed redundant command-line arguments from docker-compose.yml

### 3. Directory Structure

```
docker/
├── docker-compose.yml    # Minimal Docker configuration
└── Dockerfile           # Node image build configuration

mainnet/
└── config/
    ├── config.ini       # Mainnet node configuration
    └── genesis.json     # Mainnet genesis configuration

testnet/
└── config/
    ├── config.ini       # Testnet node configuration
    └── genesis.json     # Testnet genesis configuration
```

## Port Configuration

### Mainnet

- HTTP API: 9888
- P2P: 9876
- State History: 9080

### Testnet

- HTTP API: 9889
- P2P: 9877
- State History: 9081

## Benefits of Changes

1. **Simplified Configuration**

   - Single source of truth for node configuration
   - Easier to maintain and update
   - Reduced risk of configuration conflicts

2. **Improved Network Performance**

   - Direct host network access
   - No bridge network overhead
   - Better connection handling

3. **Cleaner Docker Configuration**
   - Minimal docker-compose.yml
   - Clear separation of concerns
   - Easier to understand and maintain

## Important Notes

1. **Host Network Mode**

   - Containers share the host's network namespace
   - No port mapping needed
   - Ensure no port conflicts on host machine

2. **Configuration Management**

   - All node settings in config.ini
   - Docker only manages container lifecycle
   - Easier to version control configurations

3. **Security Considerations**
   - Host networking requires careful security planning
   - Consider firewall rules at host level
   - Review access control settings in config.ini
