#!/bin/bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-dryamovvv/pkgs}"

echo "=== Checking upstream updates via pkgctl ==="

WORKDIR=$(mktemp -d /tmp/pkgctl-check-XXXXXX)
trap 'rm -rf "$WORKDIR"' EXIT

for pkgdir in packages/*/; do
  pkg=$(basename "$pkgdir")
  pkgbuild="$pkgdir/PKGBUILD"
  [ -f "$pkgbuild" ] || continue

  nvchecker_file="$pkgdir/.nvchecker.toml"

  # If no .nvchecker.toml, auto-generate it via pkgctl version setup
  if [ ! -f "$nvchecker_file" ]; then
    echo "SETUP $pkg: no .nvchecker.toml, generating..."
    cp -r "$pkgdir" "$WORKDIR/$pkg"
    docker run --rm -v "$WORKDIR/$pkg:/workspace" lfdevs/archlinuxarm:base-devel \
      bash -c "cd /workspace && pkgctl version setup" 2>/dev/null || true
    if [ -f "$WORKDIR/$pkg/.nvchecker.toml" ]; then
      cp "$WORKDIR/$pkg/.nvchecker.toml" "$pkgdir/"
      echo "GENERATED $pkg: .nvchecker.toml created"
    else
      echo "SKIP $pkg: could not generate .nvchecker.toml"
      continue
    fi
  fi

  # Run pkgctl version check inside arch container
  cp -r "$pkgdir" "$WORKDIR/$pkg"
  result=$(docker run --rm -v "$WORKDIR/$pkg:/workspace" lfdevs/archlinuxarm:base-devel \
    bash -c "cd /workspace && pkgctl version check 2>&1" || true)

  current_ver=$(grep -oP '^pkgver=\K.*' "$pkgbuild" | head -1)

  # Parse pkgctl output for new version
  # Output format: "pkgname: <current> -> <latest>" or "pkgname: up to date"
  new_ver=$(echo "$result" | grep -oP "${pkg}:\s+\S+\s+->\s+\K\S+" || true)

  if [ -z "$new_ver" ]; then
    echo "OK   $pkg: $current_ver (up to date)"
    continue
  fi

  # Check for existing issue
  existing=$(gh issue list --repo "$REPO" --label modify-package \
    --search "Update ${pkg}" --state open --json number --jq '.[0].number' 2>/dev/null) || existing=""

  if [ -n "$existing" ]; then
    echo "SKIP $pkg: issue #${existing} already open ($current_ver → $new_ver)"
  else
    echo "NEW  $pkg: $current_ver → $new_ver"
    gh issue create --repo "$REPO" \
      --title "Update $pkg $current_ver → $new_ver" \
      --label modify-package \
      --body "**Package:** $pkg
**Current version:** $current_ver
**New version:** $new_ver
**Source:** \`$(grep -oP '^source=\(["'\'']?\K[^"'\'' )]+' "$pkgbuild" | head -1)\`"
  fi
done

echo "=== Done ==="
