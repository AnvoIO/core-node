#!/bin/bash

# =============================================================================
# Core Node — ShellCheck Linter
# =============================================================================
# Runs ShellCheck on all shell scripts in the repository.
#
# Usage:
#   tests/shellcheck.sh
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

pass() { echo -e "${GREEN}PASS${NC} $1"; }
fail() { echo -e "${RED}FAIL${NC} $1"; }

# ---------------------------------------------------------------------------
# Check dependencies
# ---------------------------------------------------------------------------
if ! command -v shellcheck &>/dev/null; then
    echo "shellcheck not found. Install with: apt-get install shellcheck" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Find all shell scripts
# ---------------------------------------------------------------------------
mapfile -t scripts < <(find "$PROJECT_DIR" -name '*.sh' -not -path '*/.git/*' | sort)

if [[ ${#scripts[@]} -eq 0 ]]; then
    echo "No shell scripts found"
    exit 1
fi

echo "Running ShellCheck on ${#scripts[@]} scripts..."
echo ""

# ---------------------------------------------------------------------------
# Run ShellCheck
# ---------------------------------------------------------------------------
failed=0
passed=0

for script in "${scripts[@]}"; do
    rel_path="${script#"$PROJECT_DIR"/}"

    # SC1091: Not following sourced files (they're in a different dir)
    # SC2034: Variable appears unused (config vars are used by sourced scripts)
    # SC1090: Can't follow non-constant source
    # SC2154: Variable referenced but not assigned (assigned via source/load_config)
    if shellcheck -x -e SC1091,SC2034,SC1090,SC2154 -S warning "$script" 2>&1; then
        pass "$rel_path"
        passed=$((passed + 1))
    else
        fail "$rel_path"
        failed=$((failed + 1))
    fi
done

echo ""
echo "========================================="
echo "ShellCheck: ${passed} passed, ${failed} failed (${#scripts[@]} total)"
echo "========================================="

exit "$failed"
