# Core Node

Docker-based deployment system for Core blockchain nodes using [AnvoIO Core](https://github.com/AnvoIO/core). Supports block producers, API nodes, seed relays, and full-history nodes with automated configuration, snapshot management, S3 archival, and monitoring. Multi-arch: runs on both x86_64 and ARM64 (Apple Silicon).

## Quick Start

```bash
# Run the interactive setup wizard
./scripts/setup/wizard.sh

# Start the node
./scripts/node/start.sh
```

The wizard walks through all configuration options and writes a `node.conf` file. All Docker, core_netd, and operational configs are generated from that single file.

For non-interactive setup, edit `node.conf` directly and run:

```bash
./scripts/setup/wizard.sh --config node.conf
```

## Node Roles

| Role | Description | Plugins |
|------|-------------|---------|
| **producer** | Block producer with signing keys | chain, chain_api, http, net, producer, producer_api |
| **seed** | P2P relay node (no HTTP API) | chain, http, net |
| **light-api** | API node with limited block history | chain, chain_api, http, net |
| **full-api** | Full API with state history (SHiP) | chain, chain_api, http, net, state_history |
| **full-history** | Complete chain history with traces | chain, chain_api, http, net, state_history, trace_api |

## Network Information

| Network | Chain ID |
|---------|----------|
| Mainnet | `38b1d7815474d0bf271d659c50b579893768b3b2c3dc6a14c4be6a7b3e14f2fb` |
| Testnet | `b64646740308df2ee06c6b72f34c0f7fa066d940e831f752db2006fcc2b78dee` |

Ports, bind IP, and other settings are fully configurable through the wizard.

## Prerequisites

- Docker and Docker Compose
- BTRFS filesystem on all storage volumes (required for filesystem snapshots)
- Sufficient RAM for your node role (4GB producer to 64GB+ full-history)
- Stable internet connection

## Architecture

### Configuration Flow

```
wizard.sh → node.conf → generate-config.sh → config.ini
                                            → docker-compose.yml
                                            → genesis.json
                                            → logging.json
                                            → nginx.conf    (if API gateway enabled)
                                            → lua/auth.lua  (if API gateway enabled)
                                            → api_keys      (if API gateway enabled)
```

`node.conf` is the single source of truth. All generated configs live in `$STORAGE_PATH/config/`.

### Key Features

- **State-in-memory (tmpfs)**: Chain state stored in RAM to protect SSDs from write wear. tmpfs size is auto-calculated from `CHAIN_STATE_DB_SIZE` + 10% headroom (allocated on use, not reserved).
- **chain snapshot scheduling**: Periodic chain snapshots via the producer API (`/v1/producer/schedule_snapshot`).
- **S3 archival**: Streaming backup and recovery to S3-compatible storage using rclone with zstd compression (`tar | zstd | rclone rcat` for upload, `rclone cat | zstd -d | tar -x` for download — no intermediate files).
- **BTRFS filesystem snapshots**: Consistent full-node backups with minimal downtime (stop → BTRFS snapshot → start → upload from snapshot).
- **API gateway**: OpenResty reverse proxy with API key authentication, per-key rate limiting, WebSocket proxy for SHiP, TLS termination, and optional Cloudflare Zero Trust tunnel.
- **Firewall**: docker-ufw integration for firewall rules that work with Docker's iptables.
- **Monitoring**: Webhook alerts (Slack, Discord, PagerDuty, generic) and Prometheus metrics endpoint.
- **Logging profiles**: production, standard, debug, minimal — applied via JSON logging config.
- **Host networking**: Direct port binding with configurable bind IP.

## Directory Structure

```
core-node/
├── node.conf                      # Your node configuration (single source of truth)
├── config/
│   ├── peers-mainnet.conf         # Mainnet peer list (independently updatable)
│   ├── peers-testnet.conf         # Testnet peer list
│   ├── snapshot-providers.conf    # Public snapshot provider URLs
│   └── templates/                 # Config generation templates
│       ├── config.ini.tmpl
│       ├── docker-compose.yml.tmpl
│       ├── nginx.conf.tmpl        # OpenResty gateway template
│       ├── lua/
│       │   └── auth.lua           # API key auth + rate limiting
│       └── logging-{production,standard,debug,minimal}.json
├── docker/
│   ├── Dockerfile                 # Node image (Ubuntu 24.04 + AnvoIO Core)
│   └── entrypoint.sh             # Container entrypoint with snapshot auto-detection
├── scripts/
│   ├── setup/
│   │   ├── wizard.sh             # Interactive configuration wizard
│   │   ├── generate-config.sh    # Template-based config generator
│   │   ├── validate-config.sh    # Configuration validator
│   │   └── manage-keys.sh        # API key CRUD (add, remove, list, rotate, reload)
│   ├── node/
│   │   ├── start.sh              # Start node (builds image, restores snapshot if needed)
│   │   ├── stop.sh               # Graceful shutdown with process polling
│   │   ├── restart.sh            # Stop then start
│   │   ├── status.sh             # Container, head block, LIB, peers, block age
│   │   └── logs.sh               # Docker log viewer (-f, -n, --since)
│   ├── snapshot/
│   │   ├── create.sh             # Create chain snapshot via producer API
│   │   ├── restore.sh            # Multi-source restore (local/S3/URL/providers)
│   │   ├── prune.sh              # Retention-based cleanup with --dry-run
│   │   └── schedule.sh           # Schedule/list/cancel via producer API
│   ├── backup/
│   │   ├── full-backup.sh        # BTRFS snapshot + S3 upload orchestration
│   │   ├── s3-push.sh            # Streaming tar+zstd+rclone upload
│   │   ├── s3-pull.sh            # Download and decompress from S3
│   │   ├── s3-list.sh            # List remote backups with manifests
│   │   └── s3-prune.sh           # Remote retention enforcement
│   ├── monitoring/
│   │   ├── health-check.sh       # Container, API, block age, peer checks + webhooks
│   │   └── metrics.sh            # Prometheus metrics (--serve or --once)
│   ├── maintenance/
│   │   ├── error-recovery.sh     # 7 diagnostic checks with automated recovery
│   │   └── reset.sh              # Safe reset with per-component confirmation
│   └── lib/
│       ├── common.sh             # Logging, prompts, validators, utilities
│       ├── config-utils.sh       # node.conf read/write (load, get, set, list)
│       └── network-defaults.sh   # Chain IDs, ports, plugins, resources per role
└── docs/                          # Documentation
```

## Scripts Reference

### Setup

| Script | Description |
|--------|-------------|
| `scripts/setup/wizard.sh` | Interactive wizard — configures all options, writes `node.conf` |
| `scripts/setup/wizard.sh --config node.conf` | Non-interactive mode — reads existing config, generates all files |
| `scripts/setup/generate-config.sh node.conf` | Generate Docker/core_netd configs from `node.conf` |
| `scripts/setup/validate-config.sh node.conf` | Validate `node.conf` for completeness and correctness |
| `scripts/setup/manage-keys.sh` | API key management: add, remove, list, rotate, reload |

### Node Operations

| Script | Description |
|--------|-------------|
| `scripts/node/start.sh` | Build image if needed, restore snapshot if needed, start container |
| `scripts/node/stop.sh` | Graceful shutdown with process polling |
| `scripts/node/restart.sh` | Stop then start |
| `scripts/node/status.sh` | Container status, head block, LIB, peer count, block age |
| `scripts/node/logs.sh` | View container logs (`-f`, `-n`, `--since`) |

### Snapshots

| Script | Description |
|--------|-------------|
| `scripts/snapshot/create.sh` | Create chain snapshot via `/v1/producer/create_snapshot` |
| `scripts/snapshot/restore.sh` | Restore from local, S3, URL, or public providers |
| `scripts/snapshot/prune.sh` | Prune old snapshots by retention count (`--dry-run` supported) |
| `scripts/snapshot/schedule.sh` | Schedule/list/cancel periodic snapshots via producer API |

### S3 Backup

| Script | Description |
|--------|-------------|
| `scripts/backup/full-backup.sh` | Full backup: chain snapshot → stop → BTRFS snapshot → start → S3 upload |
| `scripts/backup/s3-push.sh` | Stream `tar \| zstd \| rclone rcat` for blocks, state-history, state |
| `scripts/backup/s3-pull.sh` | Download and decompress from S3 (`--snapshots-only` supported) |
| `scripts/backup/s3-list.sh` | List remote backups with manifest parsing |
| `scripts/backup/s3-prune.sh` | Enforce remote retention policy |

### Monitoring

| Script | Description |
|--------|-------------|
| `scripts/monitoring/health-check.sh` | Check container, API, block age, peers; send webhook alerts |
| `scripts/monitoring/metrics.sh` | Prometheus metrics via socat (`--serve`) or stdout (`--once`) |

### Maintenance

| Script | Description |
|--------|-------------|
| `scripts/maintenance/error-recovery.sh` | 7 diagnostic checks with automated recovery options |
| `scripts/maintenance/reset.sh` | Safe reset with per-component confirmation prompts |

## Configuration Reference

All settings live in `node.conf` as `KEY=value` pairs. The wizard sets all of these interactively.

### Core Settings

| Key | Description | Example |
|-----|-------------|---------|
| `NETWORK` | `mainnet` or `testnet` | `mainnet` |
| `NODE_ROLE` | Node role (see table above) | `producer` |
| `CORE_VERSION` | AnvoIO Core version | `0.1.0-alpha` |
| `CONTAINER_NAME` | Docker container name | `core-mainnet-producer` |
| `STORAGE_PATH` | Base path for all node data | `/data/core-mainnet` |

### Network Settings

| Key | Description | Example |
|-----|-------------|---------|
| `BIND_IP` | IP address to bind services | `0.0.0.0` |
| `HTTP_PORT` | HTTP API port (not used for seed role) | `9888` |
| `P2P_PORT` | P2P network port | `9876` |
| `SHIP_PORT` | State History port (full-api/full-history) | `9080` |

### Performance Tuning

| Key | Description | Default by Role |
|-----|-------------|-----------------|
| `CHAIN_STATE_DB_SIZE` | Chain state DB size in MB | 16384 (producer) to 65536 (full-history) |
| `CHAIN_THREADS` | Chain processing threads | 2-4 |
| `HTTP_THREADS` | HTTP server threads | 2-6 |
| `MAX_CLIENTS` | Max P2P client connections | 50-250 |
| `MAX_TRANSACTION_TIME` | Max transaction time (ms) | 30-1000 |

### State-in-Memory

| Key | Description |
|-----|-------------|
| `STATE_IN_MEMORY` | `true` to use tmpfs for chain state |
| `STATE_TMPFS_SIZE` | Auto-calculated: `CHAIN_STATE_DB_SIZE` + 10% (optional override) |

### Operational Settings

| Key | Description | Default |
|-----|-------------|---------|
| `LOG_PROFILE` | Logging level: `production`, `standard`, `debug`, `minimal` | `production` |
| `AGENT_NAME` | Identifier for alerts and metrics | |
| `RESTART_POLICY` | Docker restart policy | `unless-stopped` |

### Snapshots

| Key | Description |
|-----|-------------|
| `SNAPSHOT_INTERVAL` | Blocks between chain snapshots (producer role) |
| `SNAPSHOT_RETENTION` | Number of local snapshots to retain |

### API Gateway

| Key | Description |
|-----|-------------|
| `API_GATEWAY_ENABLED` | Enable OpenResty API gateway |
| `GATEWAY_HTTP_PORT` | Public-facing HTTP/HTTPS port (default: `443`) |
| `GATEWAY_SHIP_PORT` | Public-facing WebSocket port for SHiP (default: `8443`) |
| `API_KEYS_ENABLED` | Require `X-API-Key` header for requests |
| `RATE_LIMIT_RPS` | Requests per second per API key (default: `10`) |
| `RATE_LIMIT_BURST` | Burst capacity per key (default: `20`) |
| `TLS_ENABLED` | Enable TLS with Let's Encrypt certificates |
| `TLS_DOMAIN` | Domain name for TLS certificates |
| `TLS_EMAIL` | Email for Let's Encrypt registration |
| `CF_TUNNEL_ENABLED` | Enable Cloudflare Zero Trust tunnel sidecar |
| `CF_TUNNEL_TOKEN` | Cloudflare tunnel token |

### S3 Backup

| Key | Description |
|-----|-------------|
| `S3_ENABLED` | Enable S3 backup (`true`/`false`) |
| `S3_REMOTE` | rclone remote name |
| `S3_BUCKET` | S3 bucket name |
| `S3_PREFIX` | Path prefix in bucket |
| `S3_ARCHIVE_TYPE` | `full` or `snapshots` |
| `BACKUP_RETENTION` | Number of remote backups to retain (default: `7`) |

### Producer Settings

| Key | Description |
|-----|-------------|
| `PRODUCER_NAME` | Registered producer account name |
| `SIGNATURE_PROVIDER` | `PUB_KEY=KEY:PRIV_KEY` format |

### Firewall

| Key | Description |
|-----|-------------|
| `FIREWALL_ENABLED` | Enable docker-ufw firewall rules |

### Webhooks

| Key | Description |
|-----|-------------|
| `WEBHOOK_ENABLED` | Enable webhook alerts |
| `WEBHOOK_TYPE` | `slack`, `discord`, `pagerduty`, `generic` |
| `WEBHOOK_URL` | Webhook endpoint URL |

### Prometheus

| Key | Description |
|-----|-------------|
| `PROMETHEUS_ENABLED` | Enable Prometheus metrics endpoint |
| `PROMETHEUS_PORT` | Metrics endpoint port |

## Running Multiple Nodes

To run both mainnet and testnet (or multiple nodes of the same network), run the wizard once per instance with unique `CONTAINER_NAME`, `STORAGE_PATH`, and non-conflicting ports:

```bash
# Mainnet: CONTAINER_NAME=core-mainnet, STORAGE_PATH=/data/core-mainnet, HTTP_PORT=9888
./scripts/setup/wizard.sh

# Testnet: CONTAINER_NAME=core-testnet, STORAGE_PATH=/data/core-testnet, HTTP_PORT=9889
./scripts/setup/wizard.sh
```

The wizard detects ports already in use on the host and warns before accepting a conflicting port. All operations accept a config path to target the correct instance:

```bash
./scripts/node/start.sh /data/core-mainnet/config/node.conf
./scripts/node/start.sh /data/core-testnet/config/node.conf
```

## Peer Lists

Peer lists are maintained in separate files for independent updates:

- `config/peers-mainnet.conf` — format: `Name|host:port|Location`
- `config/peers-testnet.conf` — same format

## Snapshot Providers

Public snapshot providers are configured in `config/snapshot-providers.conf`:

```
# provider | network | url
EOSUSA|mainnet|http://snapshots.eosusa.io/snapshots/libre/latest.zst
EOSUSA|testnet|http://seed01.eosusa.news/snaps/libretestnet/latest.zst
GenerEOS|mainnet|https://s3.us-east-1.amazonaws.com/genereos-snapshots/libre/latest.bin.zst
GenerEOS|testnet|https://s3.us-east-1.amazonaws.com/genereos-snapshots/core-testnet/latest.bin.zst
```

## Troubleshooting

```bash
# Check node status
./scripts/node/status.sh

# View recent logs
./scripts/node/logs.sh -n 100

# Run diagnostic checks
./scripts/maintenance/error-recovery.sh

# Validate configuration
./scripts/setup/validate-config.sh node.conf
```

## License

This project is licensed under the MIT License.
