# API Reference

Core nodes expose the standard AntelopeIO HTTP API. The port and bind IP are configured via `HTTP_PORT` and `BIND_IP` in `node.conf`.

Seed nodes (`NODE_ROLE=seed`) do not expose an HTTP API.

## API Gateway

When `API_GATEWAY_ENABLED=true`, an OpenResty reverse proxy sits in front of the nodeos API and provides:

- **TLS termination** (optional, via Let's Encrypt)
- **API key authentication** — pass `X-API-Key` header or `?api_key=` query parameter
- **Per-key rate limiting** — token bucket at `RATE_LIMIT_RPS` with `RATE_LIMIT_BURST` capacity
- **WebSocket proxy** for State History (SHiP) on `GATEWAY_SHIP_PORT`
- **Health endpoint** at `/health` (no auth required)

```bash
# With API key via header
curl -H "X-API-Key: YOUR_KEY" https://api.example.com/v1/chain/get_info

# Health check (no key required)
curl https://api.example.com/health
```

Manage keys with `scripts/setup/manage-keys.sh` (see [Configuration](../CONFIGURATION.md)).

## Chain API

```bash
# Node info
curl http://localhost:8888/v1/chain/get_info

# Get block
curl -X POST http://localhost:8888/v1/chain/get_block \
  -H "Content-Type: application/json" \
  -d '{"block_num_or_id": 12345}'

# Get account
curl -X POST http://localhost:8888/v1/chain/get_account \
  -H "Content-Type: application/json" \
  -d '{"account_name": "accountname"}'
```

## Net API

```bash
# List P2P connections
curl http://localhost:8888/v1/net/connections

# Connection count
curl -s http://localhost:8888/v1/net/connections | jq 'length'
```

## Producer API (producer role only)

```bash
# Create snapshot
curl -X POST http://localhost:8888/v1/producer/create_snapshot

# Schedule periodic snapshots
curl -X POST http://localhost:8888/v1/producer/schedule_snapshot \
  -H "Content-Type: application/json" \
  -d '{"block_spacing": 1000, "start_block_num": 0, "end_block_num": 0}'

# List scheduled snapshots
curl http://localhost:8888/v1/producer/get_snapshot_requests

# Cancel scheduled snapshots
curl -X POST http://localhost:8888/v1/producer/unschedule_snapshot \
  -H "Content-Type: application/json" \
  -d '{"request_id": 0}'
```

## State History (full-api, full-history)

Direct WebSocket endpoint at `ws://BIND_IP:SHIP_PORT`.

When the API gateway is enabled, connect via `ws[s]://DOMAIN:GATEWAY_SHIP_PORT` with an API key:

```javascript
// Via gateway (with API key as query param — WebSocket clients can't set headers during handshake)
const ws = new WebSocket("wss://api.example.com:8443/?api_key=YOUR_KEY");

// Direct (no gateway)
// const ws = new WebSocket("ws://localhost:8080");

ws.onopen = () => {
  ws.send(JSON.stringify({
    type: "get_blocks_request_v0",
    max_messages_in_flight: 4,
    have_positions: [],
    irreversible_only: false,
    fetch_block: true,
    fetch_traces: true,
    fetch_deltas: false
  }));
};
```

## Health Check

```bash
# Quick health check
curl -sf http://localhost:8888/v1/chain/get_info > /dev/null && echo "OK" || echo "DOWN"

# Block age (seconds behind)
curl -s http://localhost:8888/v1/chain/get_info | jq '
  (now - (.head_block_time | sub("T"; " ") | strptime("%Y-%m-%d %H:%M:%S") | mktime)) | floor'
```

## Additional Resources

- [AntelopeIO Chain API](https://docs.eosnetwork.com/docs/latest/apis/chain_api/)
- [AntelopeIO State History API](https://docs.eosnetwork.com/docs/latest/apis/state_history_api/)
- [Libre Network](https://libre.org/)
