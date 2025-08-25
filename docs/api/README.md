# Libre Node API Documentation

This document provides information about the HTTP API endpoints available on Libre nodes.

## API Endpoints

### Mainnet

- **HTTP API:** `http://localhost:9888` (or configured IP:port)
- **State History:** `ws://localhost:9080` (or configured IP:port)

### Testnet

- **HTTP API:** `http://localhost:9889` (or configured IP:port)
- **State History:** `ws://localhost:9081` (or configured IP:port)

## Core API Endpoints

### Chain Information

```bash
# Get chain information
curl http://localhost:9888/v1/chain/get_info

# Response includes:
# - head_block_num: Current block number
# - last_irreversible_block_num: Last irreversible block
# - chain_id: Network identifier
# - head_block_time: Current block timestamp
```

### Network Information

```bash
# Get P2P connections
curl http://localhost:9888/v1/net/connections

# Get network status
curl http://localhost:9888/v1/net/status
```

### Block Information

```bash
# Get block by number
curl -X POST http://localhost:9888/v1/chain/get_block \
  -H "Content-Type: application/json" \
  -d '{"block_num_or_id": 12345}'

# Get block by ID
curl -X POST http://localhost:9888/v1/chain/get_block \
  -H "Content-Type: application/json" \
  -d '{"block_num_or_id": "0000303900000000000000000000000000000000000000000000000000000000"}'
```

### Account Information

```bash
# Get account information
curl -X POST http://localhost:9888/v1/chain/get_account \
  -H "Content-Type: application/json" \
  -d '{"account_name": "accountname"}'

# Get account permissions
curl -X POST http://localhost:9888/v1/chain/get_account \
  -H "Content-Type: application/json" \
  -d '{"account_name": "accountname"}'
```

### Transaction Information

```bash
# Get transaction by ID
curl -X POST http://localhost:9888/v1/history/get_transaction \
  -H "Content-Type: application/json" \
  -d '{"id": "transaction_id_here"}'

# Get transaction status
curl -X POST http://localhost:9888/v1/chain/get_transaction_status \
  -H "Content-Type: application/json" \
  -d '{"id": "transaction_id_here"}'
```

## State History API (WebSocket)

### Connection

```javascript
// Connect to state history endpoint
const ws = new WebSocket("ws://localhost:9080");

ws.onopen = function () {
  console.log("Connected to state history");
};

ws.onmessage = function (event) {
  const data = JSON.parse(event.data);
  console.log("Received:", data);
};
```

### Subscribing to Data

```javascript
// Subscribe to transaction traces
ws.send(
  JSON.stringify({
    type: "get_blocks_request_v0",
    max_messages_in_flight: 4,
    have_positions: [],
    irreversible_only: false,
    fetch_block: true,
    fetch_traces: true,
    fetch_deltas: false,
  })
);
```

## Health Check Endpoints

### Node Health

```bash
# Check if node is responding
curl -f http://localhost:9888/v1/chain/get_info

# Check node sync status
curl http://localhost:9888/v1/chain/get_info | jq '.head_block_num - .last_irreversible_block_num'
```

### P2P Health

```bash
# Check P2P connections
curl http://localhost:9888/v1/net/connections | jq 'length'

# Check peer status
curl http://localhost:9888/v1/net/connections | jq '.[].peer'
```

## Error Responses

### Common HTTP Status Codes

- **200 OK** - Request successful
- **400 Bad Request** - Invalid request format
- **404 Not Found** - Endpoint or resource not found
- **500 Internal Server Error** - Server error

### Error Response Format

```json
{
  "code": 500,
  "message": "Internal Service Error",
  "error": {
    "code": 3010001,
    "name": "name_type_exception",
    "what": "Invalid name",
    "details": [
      {
        "message": "Name should be less than 13 characters and only contains the following symbol .12345abcdefghijklmnopqrstuvwxyz",
        "file": "name.cpp",
        "line_number": 8,
        "method": "set"
      }
    ]
  }
}
```

## Rate Limiting

The API implements rate limiting to prevent abuse:

- **Default limit:** 1000 requests per minute per IP
- **Burst limit:** 2000 requests per minute per IP
- **Response headers:** Include rate limit information

## Authentication

Most endpoints are public, but some may require authentication:

- **Public endpoints:** Chain info, block data, account info
- **Protected endpoints:** Transaction submission, account modification

## CORS Support

The API supports Cross-Origin Resource Sharing (CORS):

- **Access-Control-Allow-Origin:** `*`
- **Access-Control-Allow-Headers:** `*`
- **Access-Control-Allow-Methods:** `GET, POST, OPTIONS`

## Examples

### Monitoring Script

```bash
#!/bin/bash

# Get current configuration
source ./scripts/config-utils.sh
mainnet_url=$(get_http_url "mainnet")

# Monitor node health
while true; do
    response=$(curl -s "$mainnet_url/v1/chain/get_info" 2>/dev/null)
    if [[ -n "$response" ]]; then
        head_block=$(echo "$response" | jq -r '.head_block_num')
        irreversible=$(echo "$response" | jq -r '.last_irreversible_block_num')
        sync_diff=$((head_block - irreversible))
        echo "$(date): Head: $head_block, Irreversible: $irreversible, Sync: $sync_diff"
    else
        echo "$(date): Node not responding"
    fi
    sleep 30
done
```

### Transaction Monitor

```bash
#!/bin/bash

# Monitor recent transactions
source ./scripts/config-utils.sh
mainnet_url=$(get_http_url "mainnet")

# Get recent block
block_info=$(curl -s -X POST "$mainnet_url/v1/chain/get_block" \
  -H "Content-Type: application/json" \
  -d '{"block_num_or_id": "head"}')

echo "$block_info" | jq '.transactions[] | {id: .trx.id, actions: .trx.trx.actions | length}'
```

## Troubleshooting

### Common Issues

1. **Connection Refused**

   - Check if node is running: `./scripts/status.sh`
   - Verify port configuration: `./scripts/config-utils.sh show`

2. **Slow Response**

   - Check node sync status
   - Monitor system resources
   - Check network connectivity

3. **Invalid Response**
   - Verify endpoint URL
   - Check request format
   - Review error messages

### Debug Commands

```bash
# Test API connectivity
curl -v http://localhost:9888/v1/chain/get_info

# Check response time
time curl http://localhost:9888/v1/chain/get_info

# Monitor API logs
./scripts/logs.sh mainnet | grep -i api
```

## Additional Resources

- [AntelopeIO API Reference](https://docs.eosnetwork.com/docs/latest/apis/chain_api/)
- [State History API Documentation](https://docs.eosnetwork.com/docs/latest/apis/state_history_api/)
- [Libre Network Documentation](https://libre.org/)
