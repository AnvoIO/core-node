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
docker images | grep core-node

# Rebuild if needed
docker build -t "core-node:0.1.4-alpha" -f docker/Dockerfile docker/
```

**Port conflict:**
```bash
ss -tlnp | grep :9888
# Change HTTP_PORT in node.conf and regenerate
```

**Missing snapshot after crash recovery:**
When the docker entrypoint detects a dirty `shared_memory.bin` (hard crash), it clears state and needs a snapshot to rebuild. The start script tries: local → S3 → custom URL → public providers. If all fail:
```bash
./scripts/snapshot/restore.sh --url https://your-snapshot-url/latest.zst
./scripts/node/start.sh
```

### Node not syncing

**Check peer count:**
```bash
curl -s http://localhost:9888/v1/net/connections | jq 'length'
```

**No peers:** Verify peer list is current. Update `config/peers-{network}.conf` and regenerate config.

**Stale head block:** The node may be replaying. Check logs:
```bash
./scripts/node/logs.sh -f | grep "replay"
```

### Sync stall on subjective CPU

**Symptom:** A node syncing from scratch stops advancing and the logs show a repeating cycle of `tx_cpu_usage_exceeded` errors followed by peer disconnection:

```
error controller.cpp: except: tx_cpu_usage_exceeded
    billed CPU time (N us) is greater than the maximum billable CPU time for the transaction (M us)
warn  net_plugin.cpp: block NNNN not accepted, closing connection max violations reached
```

**Cause:** During sync catch-up, per-account CPU validation runs against local wall-clock execution time. On hardware slower than the original producer — or during a VM OC tier-up interruption — local CPU for a historic transaction can exceed the account's per-transaction budget that was recorded at production time. The block is rejected, the peer is disconnected, and the reconnect replays the same failing block indefinitely.

**v0.1.4-alpha fix:** Blocks that are deeply behind the network-finalized tip (more than 1000 blocks behind the highest peer-reported LIB) automatically skip subjective CPU checks, matching the semantics of on-disk block log replay. This fix requires no configuration — upgrade to v0.1.4-alpha and the stall is resolved.

**If you are on an older version:** Set `--force-all-checks=false` (the default) and add the block's producer to `--trusted-producer=ACCOUNT`. Or use `--validation-mode=light`, which also skips these checks but additionally skips authorization checks.

### High memory usage

If `STATE_IN_MEMORY=true`, the chain state DB lives in an anonymous mmap pinned by `mlock2()`. Expected usage is up to `CHAIN_STATE_DB_SIZE` MB. If it exceeds the configured size, the node will crash. Increase `CHAIN_STATE_DB_SIZE` in `node.conf` and regenerate. Ensure the host's `RLIMIT_MEMLOCK` (`ulimit -l`) covers the configured size — otherwise `mlock2()` fails at startup and the node will not come up.

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
stat -f -c %T /data/core-mainnet
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

Certificates are managed via certbot (external to the gateway). If TLS fails:
```bash
# Check gateway logs
docker logs core-mainnet-full-api-gateway

# Renew certificates
certbot renew

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
