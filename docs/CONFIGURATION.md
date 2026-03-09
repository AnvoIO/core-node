# Configuration Reference

All settings live in `node.conf` as `KEY=value` pairs. The wizard sets these interactively; for non-interactive use, edit the file directly.

## Core Settings

| Key | Required | Description | Example |
|-----|----------|-------------|---------|
| `NETWORK` | Yes | `mainnet` or `testnet` | `mainnet` |
| `NODE_ROLE` | Yes | `producer`, `seed`, `light-api`, `full-api`, `full-history` | `producer` |
| `LEAP_VERSION` | Yes | AntelopeIO Leap version | `5.0.3` |
| `CONTAINER_NAME` | Yes | Docker container name | `libre-mainnet-producer` |
| `AGENT_NAME` | Yes | Identifier for alerts/metrics | `libre-mainnet` |
| `STORAGE_PATH` | Yes | Base path for node data (must be BTRFS) | `/data/libre-mainnet` |

## Network Settings

| Key | Required | Description | Default |
|-----|----------|-------------|---------|
| `BIND_IP` | Yes | IP to bind services | `0.0.0.0` |
| `P2P_PORT` | Yes | P2P network port | `9876` |
| `HTTP_PORT` | Non-seed | HTTP API port | `8888` |
| `SHIP_PORT` | full-api, full-history | State History port | `8080` |

## Performance Tuning

Defaults vary by role. These are set during wizard resource tuning.

| Key | Required | Description | Producer | Seed | Light API | Full API | Full History |
|-----|----------|-------------|----------|------|-----------|----------|--------------|
| `CHAIN_STATE_DB_SIZE` | Yes | DB size in MB | 16384 | 32768 | 32768 | 32768 | 65536 |
| `CHAIN_THREADS` | Yes | Chain threads | 2 | 4 | 4 | 4 | 4 |
| `HTTP_THREADS` | Yes | HTTP threads | 2 | 2 | 6 | 6 | 6 |
| `MAX_CLIENTS` | Yes | Max P2P clients | 25 | 250 | 100 | 100 | 100 |
| `MAX_TRANSACTION_TIME` | Yes | Max tx time (ms) | 30 | 1000 | 1000 | 1000 | 1000 |

## State-in-Memory

| Key | Required | Description |
|-----|----------|-------------|
| `STATE_IN_MEMORY` | Yes | `true` or `false` |
| `STATE_TMPFS_SIZE` | No | Auto-calculated: `CHAIN_STATE_DB_SIZE + 10%`. Override if needed. |

When `STATE_IN_MEMORY=true`, the chain state database is stored on a tmpfs mount (RAM). This protects SSDs from write wear but means state is lost on reboot — snapshot restore is required.

tmpfs is allocated on actual use, not reserved. A 22GB tmpfs with 10GB used only consumes ~10GB of RAM.

## Snapshots

| Key | Required | Description | Default |
|-----|----------|-------------|---------|
| `SNAPSHOT_INTERVAL` | Yes | Blocks between snapshots | `1000` |
| `SNAPSHOT_RETENTION` | Yes | Number of snapshots to keep | `5` |
| `CUSTOM_SNAPSHOT_URL` | No | URL for snapshot restore fallback | |

## Operational Settings

| Key | Required | Description | Default |
|-----|----------|-------------|---------|
| `LOG_PROFILE` | Yes | `production`, `standard`, `debug`, `minimal` | `production` |
| `RESTART_POLICY` | Yes | Docker restart policy | `unless-stopped` |

## Producer Settings

Required when `NODE_ROLE=producer`:

| Key | Description | Example |
|-----|-------------|---------|
| `PRODUCER_NAME` | Registered producer account | `cryptobloks` |
| `SIGNATURE_PROVIDER` | `PUB_KEY=KEY:PRIV_KEY` | `EOS...=KEY:5K...` |

## Light API Settings

Required when `NODE_ROLE=light-api`:

| Key | Description |
|-----|-------------|
| `BLOCKS_LOG_STRIDE` | Block log split stride |
| `MAX_RETAINED_BLOCK_FILES` | Max retained block log files |

## S3 Backup

| Key | Required when S3 | Description |
|-----|------------------|-------------|
| `S3_ENABLED` | Always | `true` or `false` |
| `S3_REMOTE` | Yes | rclone remote name |
| `S3_BUCKET` | Yes | S3 bucket name |
| `S3_PREFIX` | Yes | Path prefix in bucket |
| `S3_ARCHIVE_TYPE` | Yes | `full` or `snapshots` |

## TLS

| Key | Required when TLS | Description |
|-----|-------------------|-------------|
| `TLS_ENABLED` | Always | `true` or `false` |
| `TLS_DOMAIN` | Yes | Domain for Let's Encrypt |
| `TLS_EMAIL` | Yes | Email for Let's Encrypt |

## Firewall

| Key | Required | Description |
|-----|----------|-------------|
| `FIREWALL_ENABLED` | Always | `true` or `false` |

## Webhooks

| Key | Required when webhooks | Description |
|-----|------------------------|-------------|
| `WEBHOOK_ENABLED` | Always | `true` or `false` |
| `WEBHOOK_TYPE` | Yes | `slack`, `discord`, `pagerduty`, `generic` |
| `WEBHOOK_URL` | Yes | Webhook endpoint URL |

## Prometheus

| Key | Required when Prometheus | Description |
|-----|--------------------------|-------------|
| `PROMETHEUS_ENABLED` | Always | `true` or `false` |
| `PROMETHEUS_PORT` | Yes | Metrics endpoint port |
