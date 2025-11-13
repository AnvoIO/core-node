# Libre Blockchain Node Dockerfile
# Based on AntelopeIO Leap v5.0.3
# Built for x86_64/amd64 platform

FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV LEAP_VERSION=5.0.3

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download and install Leap directly (amd64 package)
RUN wget -O /tmp/leap.deb https://github.com/AntelopeIO/leap/releases/download/v${LEAP_VERSION}/leap_${LEAP_VERSION}_amd64.deb \
    && apt-get update \
    && apt-get install -y /tmp/leap.deb \
    && rm /tmp/leap.deb \
    && rm -rf /var/lib/apt/lists/*

# Create eosio user and directories
RUN useradd -m -s /bin/bash eosio \
    && mkdir -p /opt/eosio/{config,data,logs} \
    && mkdir -p /opt/eosio/data/state \
    && mkdir -p /opt/eosio/config/protocol_features \
    && chown -R eosio:eosio /opt/eosio

# Copy snapshot management script to container
COPY scripts/manage-snapshots.sh /usr/local/bin/manage-snapshots.sh
RUN chmod +x /usr/local/bin/manage-snapshots.sh

# Create entrypoint script to handle volume permissions and cron setup
RUN echo '#!/bin/bash\n\
# Ensure data directories exist and have correct permissions\n\
mkdir -p /opt/eosio/data/state\n\
mkdir -p /opt/eosio/data/state-history\n\
mkdir -p /opt/eosio/config/protocol_features\n\
mkdir -p /opt/eosio/data/snapshots\n\
chown -R eosio:eosio /opt/eosio/data\n\
chown -R eosio:eosio /opt/eosio/config\n\
\n\
# Set up cron jobs for snapshot management if producer mode is enabled\n\
if [ "$PRODUCER_MODE" = "true" ]; then\n\
    # Create cron job for snapshot creation at 00:00\n\
    echo "0 0 * * * /usr/local/bin/manage-snapshots.sh create $NETWORK >/var/log/snapshot-create.log 2>&1" > /etc/cron.d/snapshot-create\n\
    # Create cron job for snapshot pruning at 01:00\n\
    echo "0 1 * * * /usr/local/bin/manage-snapshots.sh prune $NETWORK --keep 1 >/var/log/snapshot-prune.log 2>&1" > /etc/cron.d/snapshot-prune\n\
    # Set permissions for cron files\n\
    chmod 0644 /etc/cron.d/snapshot-create\n\
    chmod 0644 /etc/cron.d/snapshot-prune\n\
    # Start cron service\n\
    service cron start\n\
fi\n\
\n\
# Find and use latest snapshot if available\n\
if [ "$1" = "nodeos" ] && [ "$PRODUCER_MODE" = "true" ]; then\n\
    # Look for latest snapshot in snapshots directory\n\
    LATEST_SNAPSHOT=$(find /opt/eosio/data/snapshots -name "*.bin" -type f 2>/dev/null | sort -r | head -n 1)\n\
    if [ -n "$LATEST_SNAPSHOT" ]; then\n\
        echo "Using latest snapshot: $(basename "$LATEST_SNAPSHOT")"\n\
        # Rebuild args array with correct snapshot path\n\
        NEW_ARGS=()\n\
        SKIP_NEXT=false\n\
        for arg in "$@"; do\n\
            if [ "$SKIP_NEXT" = "true" ]; then\n\
                NEW_ARGS+=("$LATEST_SNAPSHOT")\n\
                SKIP_NEXT=false\n\
            elif [ "$arg" = "--snapshot" ]; then\n\
                NEW_ARGS+=("$arg")\n\
                SKIP_NEXT=true\n\
            else\n\
                NEW_ARGS+=("$arg")\n\
            fi\n\
        done\n\
        set -- "${NEW_ARGS[@]}"\n\
    elif [ ! -f "/opt/eosio/data/snapshot.bin" ]; then\n\
        echo "No snapshots found and no fallback snapshot.bin - starting without snapshot"\n\
        # Remove snapshot arguments if no snapshot exists\n\
        NEW_ARGS=()\n\
        SKIP_NEXT=false\n\
        for arg in "$@"; do\n\
            if [ "$SKIP_NEXT" = "true" ]; then\n\
                SKIP_NEXT=false\n\
            elif [ "$arg" = "--snapshot" ]; then\n\
                SKIP_NEXT=true\n\
            else\n\
                NEW_ARGS+=("$arg")\n\
            fi\n\
        done\n\
        set -- "${NEW_ARGS[@]}"\n\
    else\n\
        echo "Using fallback snapshot: snapshot.bin"\n\
    fi\n\
fi\n\
\n\
# Switch to eosio user and execute the command\n\
exec gosu eosio "$@"' > /entrypoint.sh \
    && chmod +x /entrypoint.sh

# Install gosu for proper user switching and cron for snapshot automation
RUN apt-get update && apt-get install -y gosu cron && rm -rf /var/lib/apt/lists/*

# Switch back to root for entrypoint
USER root
WORKDIR /opt/eosio

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]

# Expose ports
EXPOSE 9888 9889 9876 9877 9080 9081

# Default command
CMD ["nodeos", "--help"] 