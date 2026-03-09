# Libre Blockchain Node Dockerfile — v3
# Based on AntelopeIO Leap
# Built for x86_64/amd64 platform

FROM ubuntu:22.04

# Build argument for Leap version (overridable at build time)
ARG LEAP_VERSION=5.0.3

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV LEAP_VERSION=${LEAP_VERSION}

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    ca-certificates \
    jq \
    zstd \
    btrfs-progs \
    socat \
    gosu \
    cron \
    && rm -rf /var/lib/apt/lists/*

# Download and install Leap
RUN wget -O /tmp/leap.deb "https://github.com/AntelopeIO/leap/releases/download/v${LEAP_VERSION}/leap_${LEAP_VERSION}_amd64.deb" \
    && apt-get update \
    && apt-get install -y /tmp/leap.deb \
    && rm /tmp/leap.deb \
    && rm -rf /var/lib/apt/lists/*

# Install rclone for S3 backup support
RUN curl -fsSL https://rclone.org/install.sh | bash

# Create eosio user and directories
RUN useradd -m -s /bin/bash eosio \
    && mkdir -p /opt/eosio/{config,data,logs} \
    && mkdir -p /opt/eosio/data/{state,state-history,blocks,snapshots} \
    && mkdir -p /opt/eosio/config/protocol_features \
    && chown -R eosio:eosio /opt/eosio

# Create v3 entrypoint script
# This handles:
# 1. Volume directory creation and permissions
# 2. Snapshot detection and auto-boot
# 3. Proper user switching
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER root
WORKDIR /opt/eosio

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 9888 9889 9876 9877 9080 9081

CMD ["nodeos", "--help"]
