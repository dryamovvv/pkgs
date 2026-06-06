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

# Find package file (store absolute path — CWD changes to /tmp/repo later)
PKGFILE=$(realpath "$(ls "$PKGDIR"/*.pkg.tar.* 2>/dev/null | head -1)" 2>/dev/null || echo "/workspace/$(ls "$PKGDIR"/*.pkg.tar.* 2>/dev/null | head -1)")
if [ -z "$PKGFILE" ]; then
  echo "ERROR: No package file found in $PKGDIR"
  exit 1
fi
PKGNAME=$(basename "$PKGFILE")
echo "=== Deploying $PKGNAME ==="

# Configure git credential helper (avoids token in process args/urls)
git config --global credential.helper store
echo "https://x-access-token:${GITHUB_TOKEN}@github.com" >~/.git-credentials
chmod 600 ~/.git-credentials

for attempt in $(seq 1 10); do
  echo "=== Deploy attempt $attempt/10 ==="

  cd /workspace

  # Git identity
  git config --global user.email "github-actions[bot]@users.noreply.github.com"
  git config --global user.name "github-actions[bot]"
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
    # Create a placeholder so git can commit (empty dirs aren't tracked)
    echo "aarch64 repository" >aarch64/.gitkeep
    git add aarch64
    git commit -m "init: gh-pages branch for aarch64 repository"
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
      [ -f "$f" ] || continue
      name=$(basename "$f")
      name_esc=$(printf '%s\n' "$name" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
      echo "<a href=\"$f\">${name_esc}</a>"
    done
    echo '</pre></body></html>'
  } >index.html

  # Commit and push
  git add -A
  git diff --cached --quiet || git commit -m "deploy: $PKGNAME"

  if git push origin gh-pages 2>&1; then
    echo "=== Deploy successful ==="
    rm -f ~/.git-credentials
    exit 0
  fi

  echo "Push conflict (another job deployed), retrying..."
  sleep 3
done

echo "ERROR: Deploy failed after 10 attempts"
exit 1
