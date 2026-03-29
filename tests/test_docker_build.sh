#!/bin/bash

# =============================================================================
# Core Node — Docker Build Smoke Test
# =============================================================================
# Builds the Docker image and verifies:
# - Image builds successfully
# - core_netd binary exists and runs --full-version
# - core-cli binary exists
# - core-util binary exists
# - core user exists with correct home
# - /opt/core directory structure is correct
# - Entrypoint is set correctly
#
# Usage:
#   tests/test_docker_build.sh
#
# Requires: docker
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Color output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAILURES=$((FAILURES + 1)); }

FAILURES=0
IMAGE_NAME="core-node:test-$$"

# ---------------------------------------------------------------------------
# Cleanup on exit
# ---------------------------------------------------------------------------
cleanup() {
    echo ""
    echo "Cleaning up test image..."
    docker rmi "$IMAGE_NAME" &>/dev/null || true
}
trap cleanup EXIT

echo "========================================="
echo "Docker Build Smoke Tests"
echo "========================================="
echo ""

# =============================================================================
# Test 1: Image builds successfully
# =============================================================================
echo "--- Building Docker image (this may take a few minutes) ---"
if docker build -t "$IMAGE_NAME" \
    -f "${PROJECT_DIR}/docker/Dockerfile" \
    "${PROJECT_DIR}/docker/" 2>&1; then
    pass "Docker image builds successfully"
else
    fail "Docker image build failed"
    echo "Cannot continue without a built image."
    exit 1
fi

echo ""
echo "--- Verifying image contents ---"

# =============================================================================
# Test 2: core_netd binary exists and reports version
# =============================================================================
VERSION_OUTPUT="$(docker run --rm "$IMAGE_NAME" core_netd --full-version 2>&1)" || true
if [[ -n "$VERSION_OUTPUT" ]]; then
    pass "core_netd --full-version: ${VERSION_OUTPUT}"
else
    fail "core_netd --full-version returned no output"
fi

# =============================================================================
# Test 3: core-cli binary exists
# =============================================================================
if docker run --rm "$IMAGE_NAME" which core-cli &>/dev/null; then
    pass "core-cli binary found"
else
    fail "core-cli binary not found"
fi

# =============================================================================
# Test 4: core-util binary exists
# =============================================================================
if docker run --rm "$IMAGE_NAME" which core-util &>/dev/null; then
    pass "core-util binary found"
else
    fail "core-util binary not found"
fi

# =============================================================================
# Test 5: core user exists
# =============================================================================
CORE_USER="$(docker run --rm "$IMAGE_NAME" id core 2>&1)" || true
if [[ "$CORE_USER" == *"uid="* ]]; then
    pass "core user exists: ${CORE_USER}"
else
    fail "core user does not exist"
fi

# =============================================================================
# Test 6: Directory structure
# =============================================================================
for dir in /opt/core/config /opt/core/data /opt/core/logs \
           /opt/core/data/state /opt/core/data/blocks \
           /opt/core/data/snapshots /opt/core/data/state-history; do
    if docker run --rm "$IMAGE_NAME" test -d "$dir"; then
        pass "Directory exists: ${dir}"
    else
        fail "Directory missing: ${dir}"
    fi
done

# =============================================================================
# Test 7: Directory ownership
# =============================================================================
OWNER="$(docker run --rm "$IMAGE_NAME" stat -c '%U:%G' /opt/core 2>&1)"
if [[ "$OWNER" == "core:core" ]]; then
    pass "Directory ownership: core:core"
else
    fail "Directory ownership: expected core:core, got ${OWNER}"
fi

# =============================================================================
# Test 8: Entrypoint is set
# =============================================================================
ENTRYPOINT="$(docker inspect --format='{{json .Config.Entrypoint}}' "$IMAGE_NAME" 2>/dev/null)"
if [[ "$ENTRYPOINT" == *"entrypoint.sh"* ]]; then
    pass "Entrypoint set to entrypoint.sh"
else
    fail "Entrypoint incorrect: ${ENTRYPOINT}"
fi

# =============================================================================
# Test 9: Working directory
# =============================================================================
WORKDIR="$(docker inspect --format='{{.Config.WorkingDir}}' "$IMAGE_NAME" 2>/dev/null)"
if [[ "$WORKDIR" == "/opt/core" ]]; then
    pass "Working directory: /opt/core"
else
    fail "Working directory: expected /opt/core, got ${WORKDIR}"
fi

# =============================================================================
# Test 10: Required system tools
# =============================================================================
for cmd in jq zstd gosu curl rclone cron; do
    if docker run --rm "$IMAGE_NAME" which "$cmd" &>/dev/null; then
        pass "System tool present: ${cmd}"
    else
        fail "System tool missing: ${cmd}"
    fi
done

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "========================================="
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}All Docker build tests passed${NC}"
else
    echo -e "${RED}${FAILURES} test(s) failed${NC}"
fi
echo "========================================="

exit "$FAILURES"
