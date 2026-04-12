# AGENTS.md

Guidance for AI coding assistants working on this repository.

## Project Overview

Docker-based deployment system for Core blockchain nodes using [AnvoIO Core](https://github.com/AnvoIO/core). Currently testing on the Libre blockchain (mainnet/testnet). Core network configuration will be added when those networks launch. A single `node.conf` file drives all configuration — an interactive wizard creates it, and a generator produces Docker Compose, core_netd config.ini, genesis.json, logging profiles, and OpenResty gateway configs from templates. Multi-arch: supports x86_64 and ARM64.

## Architecture

### Configuration Flow

```
wizard.sh → node.conf → generate-config.sh → config.ini
                                            → docker-compose.yml
                                            → genesis.json
                                            → logging.json
                                            → nginx.conf    (if API_GATEWAY_ENABLED)
                                            → lua/auth.lua  (if API_GATEWAY_ENABLED)
                                            → api_keys      (if API_GATEWAY_ENABLED)
```

`node.conf` is the single source of truth. Never hardcode values that should come from config.

### Shared Libraries

All scripts source from `scripts/lib/`:

- **common.sh** — Logging (log_info/warn/error/success/debug/header), user prompts (ask_yes_no/ask_input/ask_choice/ask_multi_select), validators (validate_ip/port/url/path/btrfs/not_empty), utilities (detect_interfaces/check_port_available/require_command/require_root). Has a double-source guard via `_COMMON_SH_LOADED`. Sets `PROJECT_DIR` to repo root. Uses `_COMMON_LIB_DIR` internally (not `SCRIPT_DIR`) to avoid overwriting the caller's SCRIPT_DIR.
- **config-utils.sh** — node.conf read/write: load_config, get_config, set_config, config_exists, remove_config, list_config, backup_config, new_config. Also works as CLI: `config-utils.sh -f node.conf get KEY`.
- **network-defaults.sh** — Network constants: get_chain_id, get_default_ports, get_genesis_json, get_default_plugins (per role), get_default_resources (per role). `RECOMMENDED_CORE_VERSION="0.1.3-alpha"`.

### Node Roles and Plugins

| Role | Plugins |
|------|---------|
| producer | chain, chain_api, http, net, producer, producer_api |
| seed | chain, http, net |
| light-api | chain, chain_api, http, net |
| full-api | chain, chain_api, http, net, state_history |
| full-history | chain, chain_api, http, net, state_history, trace_api |

### Key Design Decisions

- **Host networking** — containers use `network_mode: host`, bind IP is configurable
- **BTRFS required** — all storage volumes must be BTRFS for filesystem snapshot support
- **State-in-memory (`--database-map-mode locked`)** — when `STATE_IN_MEMORY=true`, core_netd is launched with chainbase's native `locked` mode: the chain state is copied at startup into an anonymous mmap with huge pages and `mlock2()`'d so it cannot be swapped. State is flushed to `shared_memory.bin` on clean shutdown and re-loaded on next start. After a hard crash the on-disk file is dirty-flagged; the docker entrypoint detects this and clears state so the snapshot-restore path runs. No tmpfs mount, no sizing calculation — the size comes from the existing `CHAIN_STATE_DB_SIZE` resource key.
- **One node per config** — each wizard run produces one node.conf for one node
- **Peer lists in separate files** — `config/peers-{mainnet,testnet}.conf` for independent updates
- **Templates use `{{PLACEHOLDER}}` syntax** — replaced by generate-config.sh using sed and awk
- **30m stop_grace_period** — allows core_netd to flush state cleanly on shutdown
- **CORE_COMMAND indentation** — must use 6-space indent for YAML folded style compatibility
- **API Gateway (OpenResty)** — optional reverse proxy with Lua-based API key auth + per-key token-bucket rate limiting. Auth logic in `config/templates/lua/auth.lua`, keys in flat file. WebSocket proxy for SHiP.
- **Cloudflare Zero Trust** — optional `cloudflared` tunnel sidecar in docker-compose, gated behind API_GATEWAY_ENABLED. CF tunnel provides network ingress; API keys still enforced at application level.
- **Streaming backup/restore** — `s3-push.sh` uses `tar | zstd -T0 | rclone rcat` (no intermediate files). `s3-pull.sh` uses `rclone cat | zstd -d | tar -x`. No local temp files or double-disk-space requirement.
- **Multi-instance support** — each node has its own node.conf, STORAGE_PATH, CONTAINER_NAME, and ports. Wizard warns on host port conflicts via `check_port_available` (ss-based).

## Directory Layout

```
scripts/
├── setup/          # wizard.sh, generate-config.sh, validate-config.sh, manage-keys.sh
├── node/           # start.sh, stop.sh, restart.sh, status.sh, logs.sh
├── snapshot/       # create.sh, restore.sh, prune.sh, schedule.sh
├── backup/         # full-backup.sh, s3-push.sh, s3-pull.sh, s3-list.sh, s3-prune.sh
├── monitoring/     # health-check.sh, metrics.sh
├── maintenance/    # error-recovery.sh, reset.sh
└── lib/            # common.sh, config-utils.sh, network-defaults.sh
config/
├── peers-mainnet.conf
├── peers-testnet.conf
├── snapshot-providers.conf
└── templates/      # config.ini.tmpl, docker-compose.yml.tmpl, nginx.conf.tmpl, lua/, logging-*.json
docker/
├── Dockerfile
└── entrypoint.sh
```

## Common Patterns

### Script Header Pattern

```bash
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/config-utils.sh"
source "${SCRIPT_DIR}/../lib/network-defaults.sh"
```

### Config Access Pattern

```bash
load_config "$conf"
NETWORK="$(get_config "NETWORK" "")"
set_config "KEY" "value"
```

### find_config Pattern

Most scripts locate node.conf via: explicit argument → $PWD/node.conf → $PROJECT_DIR/node.conf. Use `return 1` (not `exit 1`) for subshell compatibility.

## Network Constants

| Network | Chain ID |
|---------|----------|
| Mainnet | `38b1d7815474d0bf271d659c50b579893768b3b2c3dc6a14c4be6a7b3e14f2fb` |
| Testnet | `b64646740308df2ee06c6b72f34c0f7fa066d940e831f752db2006fcc2b78dee` |

## Known Constraints

- Seed nodes have no HTTP_PORT — skip HTTP validation for seed role
- `generate-config.sh` takes a positional path argument, not `--config` flag
- `common.sh` must not overwrite caller's SCRIPT_DIR (uses `_COMMON_LIB_DIR`)
- All scripts must pass `bash -n` syntax validation
- BTRFS validation happens at wizard time (validate_btrfs from common.sh)

## Testing

Infrastructure project — no unit test suite. Validate with:

```bash
# Syntax check all scripts
for f in scripts/**/*.sh; do bash -n "$f" && echo "OK: $f"; done

# Validate a config
./scripts/setup/validate-config.sh node.conf

# Check node status
./scripts/node/status.sh
```
