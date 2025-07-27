# Libre Blockchain Node Dockerfile
# Based on AntelopeIO Leap v5.0.3
# Built for x86_64/amd64 platform

FROM --platform=linux/amd64 ubuntu:22.04

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

# Switch to eosio user
USER eosio
WORKDIR /opt/eosio

# Expose ports
EXPOSE 9888 9889 9876 9877 9080 9081

# Default command
CMD ["nodeos", "--help"] 