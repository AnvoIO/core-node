# Libre Node Examples

This directory contains practical examples and scripts for common Libre node operations.

## Example Scripts

### 1. Node Monitoring Script

**File:** `monitor-node.sh`

```bash
#!/bin/bash

# Libre Node Health Monitor
# Monitors node health and sends alerts

source ./scripts/config-utils.sh

# Configuration
ALERT_EMAIL="admin@example.com"
CHECK_INTERVAL=60  # seconds
SYNC_THRESHOLD=100 # blocks
MEMORY_THRESHOLD=80 # percentage

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to send alert
send_alert() {
    local message="$1"
    echo -e "${RED}ALERT: $message${NC}"
    # Add your alert mechanism here (email, Slack, etc.)
    # echo "$message" | mail -s "Libre Node Alert" $ALERT_EMAIL
}

# Function to check node health
check_node_health() {
    local network="$1"
    local http_url=$(get_http_url "$network")

    echo "Checking $network node..."

    # Check if node is responding
    local response=$(curl -s --max-time 10 "$http_url/v1/chain/get_info" 2>/dev/null)

    if [[ -z "$response" ]]; then
        send_alert "$network node is not responding"
        return 1
    fi

    # Parse response
    local head_block=$(echo "$response" | jq -r '.head_block_num')
    local irreversible=$(echo "$response" | jq -r '.last_irreversible_block_num')
    local sync_diff=$((head_block - irreversible))

    echo -e "${GREEN}✓ $network: Head: $head_block, Irreversible: $irreversible${NC}"

    # Check sync status
    if [[ $sync_diff -gt $SYNC_THRESHOLD ]]; then
        send_alert "$network sync difference: $sync_diff blocks"
    fi

    # Check P2P connections
    local peer_count=$(curl -s "$http_url/v1/net/connections" 2>/dev/null | jq 'length')
    if [[ $peer_count -lt 2 ]]; then
        send_alert "$network has only $peer_count P2P connections"
    fi

    return 0
}

# Function to check system resources
check_system_resources() {
    echo "Checking system resources..."

    # Check memory usage
    local memory_usage=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
    if [[ $memory_usage -gt $MEMORY_THRESHOLD ]]; then
        send_alert "High memory usage: ${memory_usage}%"
    fi

    # Check disk space
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 80 ]]; then
        send_alert "High disk usage: ${disk_usage}%"
    fi

    # Check Docker containers
local container_status=$(docker-compose -f docker/docker-compose.yml ps --format "table {{.Name}}\t{{.Status}}")
    echo "Container status:"
    echo "$container_status"
}

# Main monitoring loop
echo "Starting Libre Node Monitor..."
echo "Check interval: ${CHECK_INTERVAL}s"
echo "Sync threshold: ${SYNC_THRESHOLD} blocks"
echo "Memory threshold: ${MEMORY_THRESHOLD}%"
echo ""

while true; do
    echo "$(date): Running health checks..."

    # Check both nodes
    check_node_health "mainnet"
    check_node_health "testnet"

    # Check system resources
    check_system_resources

    echo "$(date): Health checks completed"
    echo "----------------------------------------"

    sleep $CHECK_INTERVAL
done
```

### 2. Automated Snapshot Manager

**File:** `auto-snapshot.sh`

```bash
#!/bin/bash

# Automated Snapshot Manager
# Creates snapshots on schedule and manages retention

source ./scripts/config-utils.sh

# Configuration
SNAPSHOT_INTERVAL=86400  # 24 hours in seconds
RETENTION_DAYS=7         # Keep snapshots for 7 days
SNAPSHOT_DIR="/backup/snapshots"
LOG_FILE="/var/log/libre-snapshots.log"

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date): $message" | tee -a "$LOG_FILE"
}

# Function to create snapshot
create_snapshot() {
    local network="$1"

    log_message "Creating snapshot for $network..."

    # Create snapshot
    local result=$(./scripts/snapshot-manager.sh create "$network" 2>&1)

    if [[ $? -eq 0 ]]; then
        log_message "Snapshot created successfully for $network"
        return 0
    else
        log_message "ERROR: Failed to create snapshot for $network: $result"
        return 1
    fi
}

# Function to clean old snapshots
cleanup_old_snapshots() {
    local network="$1"
    local cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y%m%d)

    log_message "Cleaning up old snapshots for $network (older than $RETENTION_DAYS days)..."

    # Find and remove old snapshots
    find "$SNAPSHOT_DIR" -name "*${network}*" -type f -mtime +$RETENTION_DAYS -delete

    log_message "Cleanup completed for $network"
}

# Function to check snapshot directory
setup_snapshot_directory() {
    if [[ ! -d "$SNAPSHOT_DIR" ]]; then
        log_message "Creating snapshot directory: $SNAPSHOT_DIR"
        mkdir -p "$SNAPSHOT_DIR"
    fi
}

# Main snapshot management
main() {
    log_message "Starting automated snapshot manager"

    # Setup directory
    setup_snapshot_directory

    while true; do
        log_message "Running scheduled snapshot creation..."

        # Create snapshots for both networks
        create_snapshot "mainnet"
        create_snapshot "testnet"

        # Cleanup old snapshots
        cleanup_old_snapshots "mainnet"
        cleanup_old_snapshots "testnet"

        log_message "Snapshot management completed. Sleeping for $SNAPSHOT_INTERVAL seconds..."
        sleep $SNAPSHOT_INTERVAL
    done
}

# Run main function
main
```

### 3. Performance Benchmark Script

**File:** `benchmark.sh`

```bash
#!/bin/bash

# Libre Node Performance Benchmark
# Tests API performance and response times

source ./scripts/config-utils.sh

# Configuration
BENCHMARK_DURATION=300  # 5 minutes
REQUEST_INTERVAL=1      # 1 second between requests
CONCURRENT_REQUESTS=10  # Number of concurrent requests

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to run benchmark
run_benchmark() {
    local network="$1"
    local http_url=$(get_http_url "$network")

    echo -e "${BLUE}Starting benchmark for $network...${NC}"
    echo "Target: $http_url"
    echo "Duration: ${BENCHMARK_DURATION}s"
    echo "Concurrent requests: $CONCURRENT_REQUESTS"
    echo ""

    # Create temporary files for results
    local temp_file=$(mktemp)
    local start_time=$(date +%s)
    local end_time=$((start_time + BENCHMARK_DURATION))

    # Run concurrent requests
    for ((i=1; i<=CONCURRENT_REQUESTS; i++)); do
        (
            while [[ $(date +%s) -lt $end_time ]]; do
                local request_start=$(date +%s.%N)

                # Make API request
                local response=$(curl -s --max-time 10 "$http_url/v1/chain/get_info" 2>/dev/null)
                local request_end=$(date +%s.%N)

                # Calculate response time
                local response_time=$(echo "$request_end - $request_start" | bc -l)

                # Log result
                echo "$response_time" >> "$temp_file"

                sleep $REQUEST_INTERVAL
            done
        ) &
    done

    # Wait for all background processes
    wait

    # Calculate statistics
    local total_requests=$(wc -l < "$temp_file")
    local avg_response_time=$(awk '{sum+=$1} END {print sum/NR}' "$temp_file")
    local min_response_time=$(sort -n "$temp_file" | head -1)
    local max_response_time=$(sort -n "$temp_file" | tail -1)
    local requests_per_second=$(echo "scale=2; $total_requests / $BENCHMARK_DURATION" | bc -l)

    # Display results
    echo -e "${GREEN}Benchmark Results for $network:${NC}"
    echo "Total requests: $total_requests"
    echo "Requests per second: $requests_per_second"
    echo "Average response time: ${avg_response_time}s"
    echo "Min response time: ${min_response_time}s"
    echo "Max response time: ${max_response_time}s"
    echo ""

    # Cleanup
    rm "$temp_file"
}

# Function to check node health before benchmark
check_node_health() {
    local network="$1"
    local http_url=$(get_http_url "$network")

    echo -e "${YELLOW}Checking $network node health before benchmark...${NC}"

    local response=$(curl -s --max-time 10 "$http_url/v1/chain/get_info" 2>/dev/null)

    if [[ -z "$response" ]]; then
        echo -e "${RED}ERROR: $network node is not responding${NC}"
        return 1
    fi

    local head_block=$(echo "$response" | jq -r '.head_block_num')
    local irreversible=$(echo "$response" | jq -r '.last_irreversible_block_num')
    local sync_diff=$((head_block - irreversible))

    echo -e "${GREEN}✓ $network: Head: $head_block, Irreversible: $irreversible, Sync: $sync_diff${NC}"

    if [[ $sync_diff -gt 100 ]]; then
        echo -e "${YELLOW}WARNING: $network has high sync difference${NC}"
    fi

    return 0
}

# Main benchmark function
main() {
    echo -e "${BLUE}Libre Node Performance Benchmark${NC}"
    echo "======================================"
    echo ""

    # Check node health
    check_node_health "mainnet" || exit 1
    check_node_health "testnet" || exit 1

    echo ""
    echo -e "${YELLOW}Starting benchmarks in 5 seconds...${NC}"
    sleep 5

    # Run benchmarks
    run_benchmark "mainnet"
    run_benchmark "testnet"

    echo -e "${GREEN}Benchmark completed!${NC}"
}

# Run main function
main
```

### 4. Configuration Backup Script

**File:** `backup-config.sh`

```bash
#!/bin/bash

# Configuration Backup Script
# Creates timestamped backups of all configuration files

# Configuration
BACKUP_DIR="/backup/configs"
RETENTION_DAYS=30

# Function to create backup
create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/libre-config-$timestamp"

    echo "Creating configuration backup: $backup_path"

    # Create backup directory
    mkdir -p "$backup_path"

    # Backup mainnet configuration
    if [[ -d "mainnet/config" ]]; then
        cp -r mainnet/config "$backup_path/mainnet"
        echo "✓ Backed up mainnet configuration"
    fi

    # Backup testnet configuration
    if [[ -d "testnet/config" ]]; then
        cp -r testnet/config "$backup_path/testnet"
        echo "✓ Backed up testnet configuration"
    fi

    # Backup docker-compose file
if [[ -f "docker/docker-compose.yml" ]]; then
    cp docker/docker-compose.yml "$backup_path/"
    echo "✓ Backed up docker/docker-compose.yml"
fi

    # Create backup info file
    cat > "$backup_path/backup-info.txt" << EOF
Backup created: $(date)
Libre Node Configuration Backup
Version: $(git describe --tags 2>/dev/null || echo "unknown")
System: $(uname -a)
Docker version: $(docker --version)
EOF

    echo "✓ Created backup info file"

    # Compress backup
    tar -czf "$backup_path.tar.gz" -C "$BACKUP_DIR" "libre-config-$timestamp"
    rm -rf "$backup_path"

    echo "✓ Compressed backup: $backup_path.tar.gz"
}

# Function to cleanup old backups
cleanup_old_backups() {
    echo "Cleaning up backups older than $RETENTION_DAYS days..."

    find "$BACKUP_DIR" -name "libre-config-*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete

    echo "✓ Cleanup completed"
}

# Function to list backups
list_backups() {
    echo "Available backups:"
    echo "=================="

    if [[ -d "$BACKUP_DIR" ]]; then
        ls -la "$BACKUP_DIR"/libre-config-*.tar.gz 2>/dev/null || echo "No backups found"
    else
        echo "Backup directory does not exist"
    fi
}

# Function to restore backup
restore_backup() {
    local backup_file="$1"

    if [[ ! -f "$backup_file" ]]; then
        echo "ERROR: Backup file not found: $backup_file"
        exit 1
    fi

    echo "Restoring from backup: $backup_file"
    echo "WARNING: This will overwrite current configuration!"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Stop nodes
        ./scripts/stop.sh

        # Extract backup
        local temp_dir=$(mktemp -d)
        tar -xzf "$backup_file" -C "$temp_dir"

        # Restore configuration
        local config_dir=$(find "$temp_dir" -name "libre-config-*" -type d | head -1)

        if [[ -d "$config_dir/mainnet" ]]; then
            rm -rf mainnet/config
            cp -r "$config_dir/mainnet/config" mainnet/
            echo "✓ Restored mainnet configuration"
        fi

        if [[ -d "$config_dir/testnet" ]]; then
            rm -rf testnet/config
            cp -r "$config_dir/testnet/config" testnet/
            echo "✓ Restored testnet configuration"
        fi

        if [[ -f "$config_dir/docker-compose.yml" ]]; then
    cp "$config_dir/docker-compose.yml" docker/
    echo "✓ Restored docker/docker-compose.yml"
fi

        # Cleanup
        rm -rf "$temp_dir"

        echo "✓ Configuration restored successfully"
        echo "You can now start the nodes with: ./scripts/start.sh"
    else
        echo "Restore cancelled"
    fi
}

# Main function
main() {
    case "${1:-backup}" in
        "backup")
            mkdir -p "$BACKUP_DIR"
            create_backup
            cleanup_old_backups
            ;;
        "list")
            list_backups
            ;;
        "restore")
            if [[ -z "$2" ]]; then
                echo "Usage: $0 restore <backup-file>"
                exit 1
            fi
            restore_backup "$2"
            ;;
        *)
            echo "Usage: $0 {backup|list|restore <file>}"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
```

## Example Configurations

### 1. High-Performance Configuration

**File:** `high-performance.ini`

```ini
# High-Performance Libre Node Configuration
# Optimized for maximum throughput

# Network Configuration
http-server-address = 0.0.0.0:9888
p2p-listen-endpoint = 0.0.0.0:9876
state-history-endpoint = 0.0.0.0:9080

# Performance Settings
chain-threads = 8
http-threads = 12
max-transaction-time = 3000
abi-serializer-max-time-ms = 20000

# Database Settings
chain-state-db-size-mb = 8192
reversible-blocks-db-size-mb = 1024
contracts-console = false

# Network Settings
max-clients = 50
connection-cleanup-period = 30
max-cleanup-time-msec = 10

# Logging
log-level-net-plugin = info
log-level-chain-plugin = info
log-level-http-plugin = info
```

### 2. Development Configuration

**File:** `development.ini`

```ini
# Development Libre Node Configuration
# Optimized for debugging and development

# Network Configuration
http-server-address = 0.0.0.0:9888
p2p-listen-endpoint = 0.0.0.0:9876
state-history-endpoint = 0.0.0.0:9080

# Development Settings
contracts-console = true
verbose-http-errors = true
max-transaction-time = 5000
abi-serializer-max-time-ms = 30000

# Performance Settings (lower for development)
chain-threads = 2
http-threads = 4

# Database Settings
chain-state-db-size-mb = 2048
reversible-blocks-db-size-mb = 512

# Logging (verbose for development)
log-level-net-plugin = debug
log-level-chain-plugin = debug
log-level-http-plugin = debug
log-level-producer-plugin = debug
```

### 3. Production Configuration

**File:** `production.ini`

```ini
# Production Libre Node Configuration
# Optimized for stability and reliability

# Network Configuration
http-server-address = 0.0.0.0:9888
p2p-listen-endpoint = 0.0.0.0:9876
state-history-endpoint = 0.0.0.0:9080

# Security Settings
contracts-console = false
verbose-http-errors = false
max-transaction-time = 1000
abi-serializer-max-time-ms = 10000

# Performance Settings
chain-threads = 4
http-threads = 6

# Database Settings
chain-state-db-size-mb = 4096
reversible-blocks-db-size-mb = 1024

# Network Settings
max-clients = 25
connection-cleanup-period = 60
max-cleanup-time-msec = 5

# Logging (production level)
log-level-net-plugin = warn
log-level-chain-plugin = warn
log-level-http-plugin = warn
```

## Usage Examples

### Running the Monitor

```bash
# Make script executable
chmod +x docs/examples/monitor-node.sh

# Run monitor
./docs/examples/monitor-node.sh
```

### Running Benchmarks

```bash
# Make script executable
chmod +x docs/examples/benchmark.sh

# Run benchmark
./docs/examples/benchmark.sh
```

### Creating Backups

```bash
# Make script executable
chmod +x docs/examples/backup-config.sh

# Create backup
./docs/examples/backup-config.sh backup

# List backups
./docs/examples/backup-config.sh list

# Restore backup
./docs/examples/backup-config.sh restore /backup/configs/libre-config-20241201_143022.tar.gz
```

### Using Configuration Templates

```bash
# Copy configuration template
cp docs/examples/high-performance.ini mainnet/config/config.ini

# Restart node to apply changes
./scripts/restart.sh
```

## Customization

These examples can be customized for your specific needs:

1. **Modify alert mechanisms** in monitor scripts
2. **Adjust thresholds** for your environment
3. **Change backup retention** policies
4. **Customize performance settings** for your hardware
5. **Add additional monitoring** metrics

## Best Practices

1. **Test scripts** in a development environment first
2. **Monitor resource usage** when running benchmarks
3. **Regular backup testing** to ensure restore procedures work
4. **Document customizations** for your environment
5. **Set up automated monitoring** for production deployments
