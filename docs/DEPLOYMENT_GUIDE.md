# Deployment Guide

## Prerequisites

- Docker and Docker Compose installed
- BTRFS filesystem on storage volumes (`mkfs.btrfs /dev/sdX`, mount with `compress=zstd`)
- Ports available for your node role (HTTP, P2P, SHiP as configured)
- For producers: registered account name and signing keys

## Step 1: Run the Wizard

```bash
./scripts/setup/wizard.sh
```

The wizard walks through all configuration sections:

1. **Network** — mainnet or testnet
2. **Node role** — producer, seed, light-api, full-api, full-history
3. **Core version** — queries GitHub for available releases, recommends 0.1.3-alpha
4. **Container name** — Docker container name
5. **Bind IP** — auto-detects network interfaces for selection
6. **Ports** — HTTP, P2P, SHiP (role-dependent)
7. **Storage path** — base directory for all node data (must be on BTRFS)
8. **State-in-memory** — tmpfs for chain state (protects SSDs, auto-sized)
9. **Snapshots** — interval and retention count
10. **Resource tuning** — chain state DB size, threads, clients, transaction time
11. **Logging profile** — production, standard, debug, or minimal
12. **Restart policy** — unless-stopped, on-failure, always, no
13. **Peers** — loaded from config/peers-{network}.conf, editable
14. **Producer settings** — account name and signature provider (producer role only)
15. **S3 backup** — rclone remote, bucket, prefix, archive type
16. **API Gateway** — OpenResty reverse proxy with API keys, rate limiting, WebSocket proxy, TLS, and optional Cloudflare Zero Trust tunnel
17. **Firewall** — docker-ufw rules for configured ports
18. **Webhooks** — Slack, Discord, PagerDuty, or generic URL
19. **Prometheus** — metrics endpoint port
20. **Agent name** — identifier for alerts and metrics

The wizard produces `node.conf` and calls `generate-config.sh` to create all operational configs.

## Step 2: Review Generated Configuration

Generated files are placed in `$STORAGE_PATH/config/`:

| File | Description |
|------|-------------|
| `config.ini` | core_netd runtime configuration |
| `docker-compose.yml` | Container definition with volumes, networking, health checks |
| `genesis.json` | Chain genesis data |
| `logging.json` | Logging profile configuration |
| `nginx.conf` | API gateway config (if API_GATEWAY_ENABLED) |
| `lua/auth.lua` | API key auth + rate limiting (if API_GATEWAY_ENABLED) |
| `api_keys` | API key store (if API_GATEWAY_ENABLED) |

## Step 3: Start the Node

```bash
./scripts/node/start.sh
```

This will:
1. Build the Docker image if it doesn't exist
2. Look for an existing snapshot (local → S3 → custom URL → public providers)
3. Start the container via docker compose
4. Wait for the HTTP API to respond (non-seed roles)
5. Schedule periodic snapshots (producer role)

## Step 4: Verify

```bash
./scripts/node/status.sh
```

Shows container status, head block, last irreversible block, peer count, and block age.

## Non-Interactive Mode

If `node.conf` already exists, run the wizard in non-interactive mode:

```bash
./scripts/setup/wizard.sh --config node.conf
```

This skips all prompts and generates configs from the existing file. To change settings, edit `node.conf` directly and re-run.

## Updating Configuration

1. Edit `node.conf` (or re-run the wizard)
2. Regenerate configs: `./scripts/setup/generate-config.sh node.conf`
3. Restart: `./scripts/node/restart.sh`

## Validation

```bash
./scripts/setup/validate-config.sh node.conf
```

Checks: required keys (role-dependent), valid network/role values, IP format, port ranges, port conflicts, log profile, restart policy, and conditional keys (API gateway, TLS, API keys, CF tunnel, S3, webhooks, Prometheus).

## S3 Backup Setup

1. Install and configure rclone: `rclone config`
2. Set in node.conf:
   ```
   S3_ENABLED=true
   S3_REMOTE=myremote
   S3_BUCKET=mybucket
   S3_PREFIX=core-mainnet/
   S3_ARCHIVE_TYPE=full
   ```
3. Run a full backup: `./scripts/backup/full-backup.sh`

The full backup process:
1. Creates an chain snapshot (chain state checkpoint)
2. Waits 30 seconds for flush
3. Stops the node
4. Takes a read-only BTRFS filesystem snapshot
5. Starts the node back up
6. Uploads from the BTRFS snapshot to S3 (streaming tar+zstd via rclone)
7. Deletes the BTRFS snapshot

## API Gateway Setup

The OpenResty API gateway provides reverse proxying, TLS, API key auth, rate limiting, and WebSocket proxy for SHiP. Only for API roles (light-api, full-api, full-history).

1. Set in node.conf:
   ```
   API_GATEWAY_ENABLED=true
   GATEWAY_HTTP_PORT=443
   GATEWAY_SHIP_PORT=8443
   API_KEYS_ENABLED=true
   RATE_LIMIT_RPS=10
   RATE_LIMIT_BURST=20
   TLS_ENABLED=true
   TLS_DOMAIN=api.example.com
   TLS_EMAIL=admin@example.com
   ```
2. Regenerate configs: `./scripts/setup/generate-config.sh node.conf`
3. Create API keys: `./scripts/setup/manage-keys.sh add "my-app"`
4. Obtain TLS certificates: `certbot certonly --standalone -d api.example.com`
5. Restart: `./scripts/node/restart.sh`

### API Key Management

```bash
./scripts/setup/manage-keys.sh add "consumer-name"    # Create key
./scripts/setup/manage-keys.sh list                     # List keys
./scripts/setup/manage-keys.sh remove KEY               # Remove key
./scripts/setup/manage-keys.sh rotate OLD_KEY "label"   # Rotate key
./scripts/setup/manage-keys.sh reload                   # Hot-reload keys
```

### Cloudflare Zero Trust Tunnel

For secure ingress without opening public ports:

1. Set in node.conf:
   ```
   CF_TUNNEL_ENABLED=true
   CF_TUNNEL_TOKEN=your-tunnel-token
   TLS_ENABLED=false          # CF handles TLS termination
   API_KEYS_ENABLED=true      # Still require app-level auth
   ```
2. Regenerate and restart — a `cloudflared` sidecar container starts alongside the gateway

## Monitoring Setup

### Webhooks

```
WEBHOOK_ENABLED=true
WEBHOOK_TYPE=slack
WEBHOOK_URL=https://hooks.slack.com/services/...
```

Supported types: `slack`, `discord`, `pagerduty`, `generic`

Health checks (`scripts/monitoring/health-check.sh`) send alerts on: container down, API unresponsive, stale blocks, low peer count.

### Prometheus

```
PROMETHEUS_ENABLED=true
PROMETHEUS_PORT=9100
```

Metrics available via `scripts/monitoring/metrics.sh --serve` or one-shot via `--once`.
