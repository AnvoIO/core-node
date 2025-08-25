#!/bin/bash
echo "Stopping Libre Blockchain nodes..."
cd "$(dirname "$0")/.."
docker-compose -f docker/docker-compose.yml down
