# Core Blockchain Node Dockerfile — v3
# Based on AnvoIO Core (fork of AntelopeIO Spring)
# Multi-arch: x86_64/amd64 and ARM64/aarch64

FROM ubuntu:24.04

# Build argument for Core version (AnvoIO/core release version)
ARG CORE_VERSION=0.1.4-alpha

# TARGETARCH is injected by Docker buildx (amd64 or arm64)
ARG TARGETARCH

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV CORE_VERSION=${CORE_VERSION}

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    ca-certificates \
    jq \
    zstd \
    unzip \
    btrfs-progs \
    socat \
    gosu \
    cron \
    && rm -rf /var/lib/apt/lists/*

# Download and install AnvoIO Core
RUN wget -O /tmp/anvo-core.deb "https://github.com/AnvoIO/core/releases/download/v${CORE_VERSION}/anvo-core_${CORE_VERSION}-ubuntu24.04_${TARGETARCH}.deb" \
    && apt-get update \
    && apt-get install -y /tmp/anvo-core.deb \
    && rm /tmp/anvo-core.deb \
    && rm -rf /var/lib/apt/lists/*

# Install rclone for S3 backup support
RUN curl -fsSL https://rclone.org/install.sh | bash

# Create core user and directories
RUN useradd -m -s /bin/bash core \
    && mkdir -p /opt/core/config /opt/core/data /opt/core/logs \
    && mkdir -p /opt/core/data/state /opt/core/data/state-history /opt/core/data/blocks /opt/core/data/snapshots \
    && mkdir -p /opt/core/config/protocol_features \
    && chown -R core:core /opt/core

# Create v3 entrypoint script
# This handles:
# 1. Volume directory creation and permissions
# 2. Snapshot detection and auto-boot
# 3. Proper user switching
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER root
WORKDIR /opt/core

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 9888 9889 9876 9877 9080 9081

CMD ["core_netd", "--help"]
