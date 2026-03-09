# Examples

## Minimal Producer Setup

```bash
# Run wizard, select: mainnet, producer role, accept defaults
./scripts/setup/wizard.sh

# Start
./scripts/node/start.sh

# Verify producing
./scripts/node/status.sh
```

## Full API Node with S3 Backup

```ini
# node.conf
NETWORK=mainnet
NODE_ROLE=full-api
LEAP_VERSION=5.0.3
CONTAINER_NAME=libre-mainnet-api
BIND_IP=0.0.0.0
HTTP_PORT=8888
P2P_PORT=9876
SHIP_PORT=8080
STORAGE_PATH=/data/libre-mainnet
STATE_IN_MEMORY=true
CHAIN_STATE_DB_SIZE=32768
CHAIN_THREADS=4
HTTP_THREADS=6
MAX_CLIENTS=100
MAX_TRANSACTION_TIME=1000
SNAPSHOT_INTERVAL=1000
SNAPSHOT_RETENTION=5
LOG_PROFILE=production
RESTART_POLICY=unless-stopped
AGENT_NAME=libre-mainnet-api
TLS_ENABLED=false
FIREWALL_ENABLED=true
WEBHOOK_ENABLED=false
PROMETHEUS_ENABLED=true
PROMETHEUS_PORT=9100
S3_ENABLED=true
S3_REMOTE=wasabi
S3_BUCKET=libre-backups
S3_PREFIX=mainnet-api/
S3_ARCHIVE_TYPE=full
```

```bash
# Generate configs and start
./scripts/setup/wizard.sh --config node.conf
./scripts/node/start.sh

# Schedule daily full backup (add to crontab)
0 2 * * * /opt/libre-node/scripts/backup/full-backup.sh /data/libre-mainnet/node.conf
```

## Seed Node

```bash
# Seed nodes have no HTTP API — only P2P
./scripts/setup/wizard.sh
# Select: seed role, configure P2P port only
./scripts/node/start.sh
```

## Health Check Cron

```bash
# Add to crontab for every 5 minutes
*/5 * * * * /opt/libre-node/scripts/monitoring/health-check.sh /data/libre-mainnet/node.conf
```

## Prometheus Metrics

```bash
# One-shot metrics dump
./scripts/monitoring/metrics.sh --once

# Persistent metrics server (e.g., via systemd)
./scripts/monitoring/metrics.sh --serve
```
