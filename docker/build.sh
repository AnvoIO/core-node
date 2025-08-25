#!/bin/bash

# Libre Blockchain Node Docker Build Script

set -e

echo "Building Libre Blockchain Node Docker image..."

# Build the Docker image
docker build -t libre-node:5.0.3 .

echo "✅ Docker image built successfully!"
echo ""
echo "Image: libre-node:5.0.3"
echo ""
echo "To start the nodes:"
echo "  ./start.sh"
echo ""
echo "To view build details:"
echo "  docker images libre-node:5.0.3" 