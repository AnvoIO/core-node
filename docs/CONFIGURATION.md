# Configuration Reference

All settings live in `node.conf` as `KEY=value` pairs. The wizard sets these interactively; for non-interactive use, edit the file directly.

## Core Settings

| Key | Required | Description | Example |
|-----|----------|-------------|---------|
| `NETWORK` | Yes | `mainnet` or `testnet` | `mainnet` |
| `NODE_ROLE` | Yes | `producer`, `seed`, `light-api`, `full-api`, `full-history` | `producer` |
| `CORE_VERSION` | Yes | AnvoIO Core version | `0.1.4-alpha` |
| `CONTAINER_NAME` | Yes | Docker container name | `core-mainnet-producer` |
| `AGENT_NAME` | Yes | Identifier for alerts/metrics | `core-mainnet` |
| `STORAGE_PATH` | Yes | Base path for node data (must be BTRFS) | `/data/core-mainnet` |

## Network Settings

| Key | Required | Description | Default |
|-----|----------|-------------|---------|
| `BIND_IP` | Yes | IP to bind services | `0.0.0.0` |
| `P2P_PORT` | Yes | P2P network port | `9876` |
| `HTTP_PORT` | Non-seed | HTTP API port | `9888` |
| `SHIP_PORT` | full-api, full-history | State History port | `9080` |

## Performance Tuning

Defaults vary by role. These are set during wizard resource tuning.

| Key | Required | Description | Producer | Seed | Light API | Full API | Full History |
|-----|----------|-------------|----------|------|-----------|----------|--------------|
| `CHAIN_STATE_DB_SIZE` | Yes | DB size in MB | 16384 | 32768 | 32768 | 32768 | 65536 |
| `CHAIN_THREADS` | Yes | Chain threads | 2 | 4 | 4 | 4 | 4 |
| `HTTP_THREADS` | Yes | HTTP threads | 2 | 2 | 6 | 6 | 6 |
| `MAX_CLIENTS` | Yes | Max P2P clients | 50 | 250 | 200 | 200 | 200 |
| `MAX_TRANSACTION_TIME` | Yes | Max tx time (ms) | 30 | 1000 | 1000 | 1000 | 1000 |

## State-in-Memory

| Key | Required | Description |
|-----|----------|-------------|
| `STATE_IN_MEMORY` | Yes | `true` or `false` |

When `STATE_IN_MEMORY=true`, core_netd is launched with `--database-map-mode locked`. At startup chainbase copies `shared_memory.bin` into an anonymous mmap (with huge pages if available) and `mlock2()`s it so the chain state cannot be swapped out. On clean shutdown the in-memory state is flushed back to `shared_memory.bin`.

After a hard crash the on-disk file is dirty-flagged; the docker entrypoint detects this and clears the state directory so the standard snapshot-restore path runs on the next start. Ensure automatic snapshot capture is configured (`SNAPSHOT_INTERVAL`) so a recent snapshot is available for recovery.

Sizing comes from `CHAIN_STATE_DB_SIZE` — no separate tmpfs size. The host's `RLIMIT_MEMLOCK` must cover `CHAIN_STATE_DB_SIZE` plus some overhead, otherwise `mlock2()` fails at startup.

## Snapshots

| Key | Required | Description | Default |
|-----|----------|-------------|---------|
| `SNAPSHOT_INTERVAL` | Yes | Blocks between chain snapshots | `1000` |
| `SNAPSHOT_RETENTION` | Yes | Number of local snapshots to keep | `5` |
| `CUSTOM_SNAPSHOT_URL` | No | URL for snapshot restore fallback (used by `restore.sh` auto-detect) | |

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
| `SIGNATURE_PROVIDER` | `PUB_KEY=FILE:PATH` or `PUB_KEY=KEY:PRIV_KEY` | `EOS...=FILE:/data/core-mainnet/signing.key` |

**`FILE:` is the recommended signature provider** (v0.1.2-alpha+). The key file must have owner-only permissions (0600 or 0400). `KEY:` still works but logs an error-level deprecation warning at startup — it exposes the private key in process arguments visible via `ps`, `/proc/PID/cmdline`, and shell history.

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
| `BACKUP_RETENTION` | No | Number of remote backups to retain (default: `7`, used by `s3-prune.sh`) |

## API Gateway (OpenResty)

The API gateway provides reverse proxying, TLS termination, API key authentication, per-key rate limiting, and WebSocket proxy for the SHiP endpoint. Only applicable to API roles (`light-api`, `full-api`, `full-history`).

| Key | Required | Description | Default |
|-----|----------|-------------|---------|
| `API_GATEWAY_ENABLED` | Always | Master switch for the gateway | `false` |
| `GATEWAY_HTTP_PORT` | When gateway | Public-facing HTTP/HTTPS port | `443` |
| `GATEWAY_SHIP_PORT` | full-api, full-history | Public-facing WebSocket port for SHiP | `8443` |
| `API_KEYS_ENABLED` | No | Require X-API-Key header | `false` |
| `RATE_LIMIT_RPS` | When keys | Requests/sec per API key | `10` |
| `RATE_LIMIT_BURST` | When keys | Burst capacity per key | `20` |
| `TLS_ENABLED` | No | Enable TLS with Let's Encrypt certs | `false` |
| `TLS_DOMAIN` | When TLS | Domain for certificates | |
| `TLS_EMAIL` | When TLS | Email for Let's Encrypt | |
| `CF_TUNNEL_ENABLED` | No | Enable Cloudflare Zero Trust tunnel | `false` |
| `CF_TUNNEL_TOKEN` | When CF tunnel | Cloudflare tunnel token | |

### API Key Management

Use `scripts/setup/manage-keys.sh` to create and manage API keys:

```bash
# Add a key with a label
./scripts/setup/manage-keys.sh add "my-app"

# List all keys
./scripts/setup/manage-keys.sh list

# Remove a key
./scripts/setup/manage-keys.sh remove KEY_VALUE

# Rotate a key (remove old, create new)
./scripts/setup/manage-keys.sh rotate OLD_KEY "my-app"

# Reload keys in the running gateway (sends SIGHUP)
./scripts/setup/manage-keys.sh reload
```

Keys are stored in `${STORAGE_PATH}/config/api_keys` (one per line, `KEY:label`).

### Cloudflare Zero Trust

When `CF_TUNNEL_ENABLED=true`, a `cloudflared` sidecar container runs alongside the gateway. The tunnel provides secure ingress without opening public ports. API key authentication is still enforced — the tunnel handles transport, not application auth.

Typical setup: disable TLS on the gateway (Cloudflare terminates TLS) but keep API keys enabled.

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

## Advanced Chain Options

These core_netd options are not exposed in `node.conf` — they use sensible defaults that work for all standard deployments. They can be passed as extra arguments in the compose command override if needed.

| Option | Default | Purpose |
|--------|---------|---------|
| `--force-all-checks` | `false` | Do not skip any validation checks while replaying blocks. Useful when replaying from an untrusted block log source. Overrides the v0.1.4-alpha deep-sync optimization — see [Troubleshooting: sync stall](troubleshooting/README.md#sync-stall-on-subjective-cpu). |
