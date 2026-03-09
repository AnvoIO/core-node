# Troubleshooting

## Quick Diagnostics

```bash
# Node status (container, head block, LIB, peers, block age)
./scripts/node/status.sh

# View recent logs
./scripts/node/logs.sh -n 200

# Automated diagnostics with recovery options
./scripts/maintenance/error-recovery.sh

# Validate configuration
./scripts/setup/validate-config.sh node.conf
```

## Common Issues

### Node won't start

**Container not found:**
```bash
# Check if image exists
docker images | grep libre-node

# Rebuild if needed
docker build -t "libre-node:5.0.3" -f docker/Dockerfile docker/
```

**Port conflict:**
```bash
ss -tlnp | grep :8888
# Change HTTP_PORT in node.conf and regenerate
```

**Missing snapshot (state-in-memory mode):**
The node needs a snapshot to boot when `STATE_IN_MEMORY=true`. The start script tries: local → S3 → custom URL → public providers. If all fail:
```bash
./scripts/snapshot/restore.sh --url https://your-snapshot-url/latest.zst
./scripts/node/start.sh
```

### Node not syncing

**Check peer count:**
```bash
curl -s http://localhost:8888/v1/net/connections | jq 'length'
```

**No peers:** Verify peer list is current. Update `config/peers-{network}.conf` and regenerate config.

**Stale head block:** The node may be replaying. Check logs:
```bash
./scripts/node/logs.sh -f | grep "replay"
```

### High memory usage

If `STATE_IN_MEMORY=true`, the chain state DB lives in RAM. Expected usage is up to `CHAIN_STATE_DB_SIZE` MB. If it exceeds the tmpfs allocation, the node will crash. Increase `CHAIN_STATE_DB_SIZE` in `node.conf` and regenerate (tmpfs auto-adjusts).

### Database corruption

```bash
./scripts/node/stop.sh
./scripts/snapshot/restore.sh    # auto-detects best source
./scripts/node/start.sh
```

For full recovery from S3:
```bash
./scripts/backup/s3-pull.sh
```

### BTRFS issues

**Check filesystem:**
```bash
btrfs filesystem show /data
btrfs scrub start /data
```

**Snapshot failed:** Ensure storage path is on a BTRFS volume:
```bash
stat -f -c %T /data/libre-mainnet
# Should output "btrfs"
```

### S3 backup failures

```bash
# Test rclone connectivity
rclone lsd myremote:mybucket

# Check S3 config in node.conf
grep S3_ node.conf

# List remote backups
./scripts/backup/s3-list.sh
```

### TLS certificate issues

Caddy auto-renews certificates. If it fails:
```bash
# Check Caddy logs
docker logs libre-caddy

# Verify DNS points to this server
dig +short api.example.com
```

## Recovery Procedures

### Safe reset (selective)
```bash
./scripts/maintenance/reset.sh
# Prompts for each component: config, chain data, snapshots, logs
```

### Full restore from S3
```bash
./scripts/node/stop.sh
./scripts/backup/s3-pull.sh
./scripts/node/start.sh
```

### Restore from snapshot only
```bash
./scripts/node/stop.sh
./scripts/snapshot/restore.sh --url https://snapshot-url/latest.zst
./scripts/node/start.sh
```

## Getting Help

Collect this information when reporting issues:

```bash
./scripts/node/status.sh
./scripts/setup/validate-config.sh node.conf
./scripts/node/logs.sh -n 50
uname -a
docker --version
btrfs --version
```
