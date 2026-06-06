#!/bin/bash
set -euo pipefail

# Detect changed packages relative to previous commit
# Outputs JSON array of package names for GitHub Actions matrix

if ! git rev-parse HEAD~1 >/dev/null 2>&1; then
  PKGS=$(ls -d packages/*/ 2>/dev/null | sed 's|packages/||;s|/||')
  if [ -z "$PKGS" ]; then
    echo '[]'
  else
    echo "$PKGS" | jq -R -s -c 'split("\n") | map(select(. != ""))'
  fi
  exit 0
fi

# If CI/CD files changed, rebuild all packages
if git diff --name-only HEAD~1 -- ci/ .github/workflows/ | grep -q .; then
  ALL=$(ls -d packages/*/ 2>/dev/null | sed 's|packages/||;s|/||')
  if [ -z "$ALL" ]; then
    echo '[]'
  else
    echo "$ALL" | jq -R -s -c 'split("\n") | map(select(. != ""))'
  fi
  exit 0
fi

# Check for package changes
CHANGED=$(git diff --name-only HEAD~1 -- packages/ | grep -oP 'packages/\K[^/]+' | sort -u)

if [ -z "$CHANGED" ]; then
  echo '[]'
else
  echo "$CHANGED" | jq -R -s -c 'split("\n") | map(select(. != ""))'
fi
