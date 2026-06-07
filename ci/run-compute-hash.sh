#!/usr/bin/env bash
set -euo pipefail

pkgdir="$1"
GITHUB_OUTPUT_FILE=${GITHUB_OUTPUT:-/tmp/github_output_dummy}

compute_failed=0
hash=""
err=""

if ! hash=$(ci/compute-build-hash.sh "$pkgdir" 2> /tmp/compute_err.log); then
  compute_failed=1
  err=$(sed -n '1,200p' /tmp/compute_err.log || true)
fi

if [ "$compute_failed" -eq 1 ]; then
  echo "[ci-run-compute] compute-build-hash failed: $err" >&2
  # Fallback: use PKGBUILD sha + git sha if available
  pkgfile="$pkgdir/PKGBUILD"
  if [ -f "$pkgfile" ]; then
    pkghash=$(sha256sum "$pkgfile" | cut -d' ' -f1)
  else
    pkghash="no-pkgfile"
  fi
  gitsha="$(git rev-parse --short HEAD 2>/dev/null || echo no-git)"
  ts=$(date -u +%s)
  hash="FALLBACK-${gitsha}-${pkghash:0:8}-${ts}"
  echo "[ci-run-compute] using fallback build_hash=$hash" >&2
fi

# If compute succeeded, ensure hash is non-empty
if [ -z "$hash" ]; then
  echo "ERROR: empty hash after compute" >&2
  exit 1
fi

# Compute sanitized hash safe for cache keys: keep alnum and -
sanitized=$(printf "%s" "$hash" | tr -cs 'A-Za-z0-9-' '-' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//')

# Write outputs for GitHub Actions
# Prefer using GITHUB_OUTPUT file if provided
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "build_hash=$hash" >> "$GITHUB_OUTPUT"
  echo "build_hash_sanitized=$sanitized" >> "$GITHUB_OUTPUT"
  echo "compute_failed=$compute_failed" >> "$GITHUB_OUTPUT"
else
  # Fallback for local testing
  echo "build_hash=$hash"
  echo "build_hash_sanitized=$sanitized"
  echo "compute_failed=$compute_failed"
fi

# Also print computed hash
echo "Computed build_hash=$hash (sanitized=$sanitized)"
exit 0
