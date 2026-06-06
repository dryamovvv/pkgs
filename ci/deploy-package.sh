#!/bin/bash
# Deploy a single package to gh-pages with retry-based conflict resolution.
# Runs inside the Arch Linux container. Requires GITHUB_TOKEN env var.
set -euo pipefail

PKGDIR="$1"
GH_REPO="dryamovvv/pkgs"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: GITHUB_TOKEN not set"
  exit 1
fi

cd /workspace

# Find package file
PKGFILE=$(ls "$PKGDIR"/*.pkg.tar.* 2>/dev/null | head -1)
if [ -z "$PKGFILE" ]; then
  echo "ERROR: No package file found in $PKGDIR"
  exit 1
fi
PKGNAME=$(basename "$PKGFILE")
echo "=== Deploying $PKGNAME ==="

# Git auth for github.com
git config --global http.https://github.com/.extraheader "Authorization: Bearer ${GITHUB_TOKEN}"

for attempt in $(seq 1 10); do
  echo "=== Deploy attempt $attempt/10 ==="

  rm -rf /tmp/repo

  # Clone existing gh-pages or create fresh
  if git ls-remote --heads "https://github.com/${GH_REPO}.git" gh-pages 2>/dev/null | grep -q gh-pages; then
    git clone --depth 1 -b gh-pages "https://github.com/${GH_REPO}.git" /tmp/repo || {
      echo "Clone failed, retrying..."
      sleep 3
      continue
    }
    cd /tmp/repo
  else
    git clone --depth 1 "https://github.com/${GH_REPO}.git" /tmp/repo || {
      echo "Clone failed, retrying..."
      sleep 3
      continue
    }
    cd /tmp/repo
    git checkout --orphan gh-pages
    git rm -rf . 2>/dev/null || true
    mkdir -p aarch64
    git add aarch64
    git commit -m "init: gh-pages branch for aarch64 repository" || true
    git push origin gh-pages || {
      echo "Push failed (another job created gh-pages?), retrying..."
      sleep 3
      continue
    }
  fi

  # Copy new package in (idempotent: overwrites same version)
  cp "$PKGFILE" /tmp/repo/aarch64/

  # Rebuild repo database with all packages
  cd /tmp/repo/aarch64
  repo-add -R repo.db.tar.gz *.pkg.tar.* 2>/dev/null || true
  cd /tmp/repo

  # Generate index.html
  {
    echo '<!DOCTYPE html>'
    echo '<html lang="en">'
    echo '<head><meta charset="UTF-8"><title>aarch64 Repository</title></head>'
    echo '<body>'
    echo '<h1>Arch Linux aarch64 Package Repository</h1>'
    echo '<p>Optimized for Raspberry Pi 5 (Cortex-A76)</p><hr><pre>'
    for f in aarch64/*.pkg.tar.*; do
      [ -f "$f" ] && echo "<a href=\"$f\">$(basename $f)</a>"
    done
    echo '</pre></body></html>'
  } >index.html

  # Commit and push
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
  git add -A
  git diff --cached --quiet || git commit -m "deploy: $PKGNAME"

  if git push origin gh-pages 2>&1; then
    echo "=== Deploy successful ==="
    exit 0
  fi

  echo "Push conflict (another job deployed), retrying..."
  sleep 3
done

echo "ERROR: Deploy failed after 10 attempts"
exit 1
