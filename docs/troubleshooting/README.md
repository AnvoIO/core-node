# Libre Node Troubleshooting Guide

This guide helps you diagnose and resolve common issues with Libre blockchain nodes.

## Quick Diagnostic Commands

### Check Node Status

```bash
# Check if containers are running
docker-compose -f docker/docker-compose.yml ps

# Check node health
./scripts/status.sh

# Check configuration
./scripts/config-utils.sh show
```

### Check Logs

```bash
# View mainnet logs
./scripts/logs.sh mainnet

# View testnet logs
./scripts/logs.sh testnet

# Follow logs in real-time
./scripts/logs.sh mainnet --follow
```

## Common Issues and Solutions

### 1. Node Won't Start

#### Symptoms

- Container fails to start
- Error messages in logs
- Port conflicts

#### Solutions

**Check Port Conflicts:**

```bash
# Check if ports are in use
netstat -tulpn | grep -E ':(9888|9889|9876|9877|9080|9081)'

# Kill conflicting processes
sudo lsof -ti:9888 | xargs kill -9
```

**Check Permissions:**

```bash
# Set correct permissions
./setup-permissions.sh

# Check data directory permissions
ls -la mainnet/data/
ls -la testnet/data/
```

**Check Disk Space:**

```bash
# Check available space
df -h

# Clean up if needed
docker system prune -f
```

### 2. Node Not Syncing

#### Symptoms

- Head block not advancing
- Large sync difference
- "Node is behind" warnings

#### Solutions

**Check P2P Connections:**

```bash
# Check peer connections
curl -s http://localhost:9888/v1/net/connections | jq 'length'

# Verify peer addresses
curl -s http://localhost:9888/v1/net/connections | jq '.[].peer'
```

**Check Network Connectivity:**

```bash
# Test peer connectivity
ping p2p.libre.iad.cryptobloks.io
ping p2p.libre.pdx.cryptobloks.io

# Test DNS resolution
nslookup p2p.libre.iad.cryptobloks.io
```

**Restart Node:**

```bash
# Restart specific node
./scripts/restart.sh

# Or restart both nodes
docker-compose -f docker/docker-compose.yml restart
```

### 3. High Memory Usage

#### Symptoms

- Container using excessive RAM
- System becomes unresponsive
- Out of memory errors

#### Solutions

**Check Memory Usage:**

```bash
# Check container memory usage
docker stats

# Check system memory
free -h
```

**Optimize Configuration:**

```bash
# Use advanced deployment to adjust settings
./scripts/deploy-advanced.sh

# Reduce chain-state-db-size-mb if needed
# Reduce max-clients if needed
```

**Monitor Resource Usage:**

```bash
# Monitor in real-time
watch -n 1 'docker stats --no-stream'
```

### 4. Database Corruption

#### Symptoms

- "Database corruption" errors
- Node crashes on startup
- Inconsistent block data

#### Solutions

**Backup and Reset:**

```bash
# Backup current data
cp -r mainnet/data mainnet/data.backup.$(date +%Y%m%d_%H%M%S)
cp -r testnet/data testnet/data.backup.$(date +%Y%m%d_%H%M%S)

# Reset node data
./scripts/reset.sh
```

**Use Snapshot Recovery:**

```bash
# List available snapshots
./scripts/snapshot-manager.sh list mainnet

# Restore from snapshot
./scripts/snapshot-manager.sh restore mainnet /path/to/snapshot.bin
```

### 5. API Not Responding

#### Symptoms

- HTTP requests timeout
- "Connection refused" errors
- API endpoints unavailable

#### Solutions

**Check API Configuration:**

```bash
# Verify API settings
./scripts/config-utils.sh show

# Check if API is enabled
grep "plugin = eosio::http_plugin" mainnet/config/config.ini
```

**Test API Endpoints:**

```bash
# Test basic connectivity
curl -v http://localhost:9888/v1/chain/get_info

# Check response time
time curl http://localhost:9888/v1/chain/get_info
```

**Check Firewall:**

```bash
# Check if ports are open
sudo ufw status

# Allow ports if needed
sudo ufw allow 9888
sudo ufw allow 9889
```

### 6. Configuration Issues

#### Symptoms

- Invalid configuration errors
- Settings not applied
- Deployment script failures

#### Solutions

**Validate Configuration:**

```bash
# Check configuration syntax
./scripts/config-utils.sh show

# Verify configuration files
cat mainnet/config/config.ini | grep -E "(http-server-address|p2p-listen-endpoint)"
```

**Reset Configuration:**

```bash
# Backup current config
cp mainnet/config/config.ini mainnet/config/config.ini.backup
cp testnet/config/config.ini testnet/config/config.ini.backup

# Re-run deployment
./scripts/deploy.sh
```

### 7. Performance Issues

#### Symptoms

- Slow API responses
- High CPU usage
- Block processing delays

#### Solutions

**Optimize Performance Settings:**

```bash
# Use advanced deployment to tune performance
./scripts/deploy-advanced.sh

# Adjust these settings:
# - chain-threads (match CPU cores)
# - http-threads (4-12 depending on load)
# - max-transaction-time (1000-3000ms)
# - abi-serializer-max-time-ms (10000-20000ms)
```

**Monitor Performance:**

```bash
# Check system resources
htop

# Monitor node performance
./scripts/maintenance.sh health mainnet
```

## Advanced Troubleshooting

### Debug Mode

**Enable Verbose Logging:**

```bash
# Edit config.ini to enable debug logging
echo "log-level-net-plugin = debug" >> mainnet/config/config.ini
echo "log-level-chain-plugin = debug" >> mainnet/config/config.ini

# Restart node
./scripts/restart.sh
```

**Check Detailed Logs:**

```bash
# View detailed logs
./scripts/logs.sh mainnet | grep -i "error\|warning\|debug"

# Follow logs in real-time
./scripts/logs.sh mainnet --follow | grep -i "error\|warning"
```

### Network Diagnostics

**Check Network Configuration:**

```bash
# Check network interfaces
ip addr show

# Check routing
ip route show

# Test connectivity
ping -c 4 8.8.8.8
```

**Check DNS Resolution:**

```bash
# Test DNS
nslookup p2p.libre.iad.cryptobloks.io
nslookup p2p.libre.pdx.cryptobloks.io

# Check DNS configuration
cat /etc/resolv.conf
```

### System Diagnostics

**Check System Resources:**

```bash
# CPU and memory usage
top

# Disk I/O
iotop

# Network I/O
iftop
```

**Check Docker Resources:**

```bash
# Docker system info
docker system df

# Container resource usage
docker stats

# Clean up Docker
docker system prune -f
```

## Recovery Procedures

### Complete Reset

```bash
# Stop all containers
./scripts/stop.sh

# Reset all data
./scripts/reset.sh

# Reconfigure nodes
./scripts/deploy.sh

# Start nodes
./scripts/start.sh
```

### Snapshot Recovery

```bash
# Stop node
./scripts/stop.sh

# Restore from snapshot
./scripts/snapshot-manager.sh restore mainnet /path/to/snapshot.bin

# Start node
./scripts/start.sh
```

### Configuration Recovery

```bash
# Restore from backup
cp mainnet/config/config.ini.backup.20241201_143022 mainnet/config/config.ini
cp testnet/config/config.ini.backup.20241201_143022 testnet/config/config.ini

# Restart nodes
./scripts/restart.sh
```

## Monitoring and Alerts

### Health Monitoring Script

```bash
#!/bin/bash

# Monitor node health
source ./scripts/config-utils.sh

while true; do
    # Check mainnet
    mainnet_url=$(get_http_url "mainnet")
    response=$(curl -s "$mainnet_url/v1/chain/get_info" 2>/dev/null)

    if [[ -n "$response" ]]; then
        head_block=$(echo "$response" | jq -r '.head_block_num')
        irreversible=$(echo "$response" | jq -r '.last_irreversible_block_num')
        sync_diff=$((head_block - irreversible))

        if [[ $sync_diff -gt 100 ]]; then
            echo "WARNING: Mainnet sync difference: $sync_diff blocks"
        fi
    else
        echo "ERROR: Mainnet not responding"
    fi

    sleep 60
done
```

### Log Monitoring

```bash
#!/bin/bash

# Monitor logs for errors
./scripts/logs.sh mainnet --follow | while read line; do
    if echo "$line" | grep -q -i "error\|exception\|fatal"; then
        echo "ERROR DETECTED: $line"
        # Add notification logic here
    fi
done
```

## Getting Help

### Information to Collect

When seeking help, collect the following information:

1. **System Information:**

   ```bash
   uname -a
   docker --version
   docker-compose --version
   ```

2. **Configuration:**

   ```bash
   ./scripts/config-utils.sh show
   ```

3. **Logs:**

   ```bash
   ./scripts/logs.sh mainnet | tail -100
   ./scripts/logs.sh testnet | tail -100
   ```

4. **Status:**

   ```bash
   ./scripts/status.sh
   docker-compose -f docker/docker-compose.yml ps
   ```

5. **System Resources:**
   ```bash
   free -h
   df -h
   top -n 1
   ```

### Support Channels

- GitHub Issues: [Repository Issues](https://github.com/your-repo/issues)
- Libre Community: [Libre Discord/Telegram]
- Documentation: [docs/README.md](../README.md)

## Prevention

### Regular Maintenance

```bash
# Daily health checks
./scripts/status.sh

# Weekly log review
./scripts/logs.sh mainnet | grep -i "error\|warning" | tail -50

# Monthly snapshot creation
./scripts/snapshot-manager.sh create mainnet
```

### Monitoring Setup

- Set up automated health checks
- Configure log monitoring
- Implement alerting for critical issues
- Regular backup of configuration and data

### Best Practices

- Keep system updated
- Monitor resource usage
- Regular snapshot creation
- Test recovery procedures
- Document custom configurations
