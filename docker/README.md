# Docker Configuration

This directory contains all Docker-related files for the Libre blockchain node setup.

## Files

### `Dockerfile`

The main Docker image definition for Libre nodes based on AntelopeIO Leap v5.0.3.

**Features:**

- Ubuntu 22.04 base image
- AntelopeIO Leap v5.0.3 installation
- Nodeos and cleos binaries
- Optimized for Libre blockchain

### `docker-compose.yml`

Docker Compose configuration for orchestrating Libre mainnet and testnet nodes.

**Services:**

- `libre-mainnet-api` - Mainnet node service
- `libre-testnet-api` - Testnet node service

**Features:**

- Volume mounts for persistent data
- Port mappings for API access
- Health checks and restart policies
- Resource limits and constraints

### `build.sh`

Script to build the Docker image locally.

**Usage:**

```bash
# Build from docker directory
cd docker
./build.sh

# Or build from project root
./docker/build.sh
```

### `.dockerignore`

Specifies files and directories to exclude from Docker build context.

**Excluded:**

- Git repository files
- Documentation
- Scripts (not needed in container)
- Log files
- Temporary files

## Usage

### Building the Image

```bash
# From project root
./docker/build.sh

# Or manually
docker build -t libre-node:latest docker/
```

### Running with Docker Compose

```bash
# From project root
docker-compose -f docker/docker-compose.yml up -d

# Or from docker directory
cd docker
docker-compose up -d
```

### Development

```bash
# Build and run in development mode
cd docker
./build.sh
docker-compose up --build
```

## Configuration

### Environment Variables

The Docker Compose file supports environment variables for customization:

- `LIBRE_VERSION` - AntelopeIO Leap version (default: 5.0.3)
- `NODEOS_ARGS` - Additional nodeos arguments
- `RESOURCE_LIMITS` - Memory and CPU limits

### Volume Mounts

- `./mainnet/data:/opt/eosio/data` - Mainnet blockchain data
- `./mainnet/config:/opt/eosio/config` - Mainnet configuration
- `./testnet/data:/opt/eosio/data` - Testnet blockchain data
- `./testnet/config:/opt/eosio/config` - Testnet configuration

### Port Mappings

- `9888:9888` - Mainnet HTTP API
- `9889:9889` - Testnet HTTP API
- `9876:9876` - Mainnet P2P
- `9877:9877` - Testnet P2P
- `9080:9080` - Mainnet State History
- `9081:9081` - Testnet State History

## Troubleshooting

### Build Issues

```bash
# Clean build
docker system prune -f
docker build --no-cache -t libre-node:latest docker/

# Check build context
docker build --progress=plain docker/
```

### Runtime Issues

```bash
# Check container logs
docker-compose -f docker/docker-compose.yml logs

# Check container status
docker-compose -f docker/docker-compose.yml ps

# Restart services
docker-compose -f docker/docker-compose.yml restart
```

### Resource Issues

```bash
# Check resource usage
docker stats

# Adjust resource limits in docker-compose.yml
# Example:
#   deploy:
#     resources:
#       limits:
#         memory: 8G
#         cpus: '4.0'
```

## Best Practices

### Security

- Use non-root user in container
- Limit container capabilities
- Scan images for vulnerabilities
- Keep base images updated

### Performance

- Use multi-stage builds
- Optimize layer caching
- Set appropriate resource limits
- Use volume mounts for data persistence

### Maintenance

- Regular image updates
- Monitor resource usage
- Clean up unused images
- Backup volume data

## Customization

### Custom Base Image

```dockerfile
# In Dockerfile
FROM custom-ubuntu:22.04
# ... rest of configuration
```

### Additional Tools

```dockerfile
# Add development tools
RUN apt-get update && apt-get install -y \
    vim \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*
```

### Custom Configuration

```yaml
# In docker-compose.yml
services:
  libre-mainnet-api:
    environment:
      - NODEOS_ARGS=--config-dir /opt/eosio/config --data-dir /opt/eosio/data
    volumes:
      - ./custom-config:/opt/eosio/config
```

## Version History

### v1.1.0

- Updated to AntelopeIO Leap v5.0.3
- Improved build optimization
- Added health checks
- Enhanced resource management

### v1.0.0

- Initial Docker setup
- Basic nodeos configuration
- Volume persistence
- Port mapping setup
