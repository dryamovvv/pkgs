#!/bin/bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-dryamovvv/pkgs}"
TOKEN="${GH_TOKEN:-}"

echo "=== Checking upstream updates ==="

for pkgdir in packages/*/; do
	pkg=$(basename "$pkgdir")
	pkgbuild="$pkgdir/PKGBUILD"
	[ -f "$pkgbuild" ] || continue

	pkgver=$(grep -oP '^pkgver=\K.*' "$pkgbuild" | head -1)
	[ -n "$pkgver" ] || continue

	source_url=$(grep -oP 'https://github\.com/\K[^/]+/[^/"'\'' ]+' "$pkgbuild" | head -1)
	[ -n "$source_url" ] || continue
	source_url="${source_url%.git}"

	# Use GitHub API: get latest release tag
	api_url="https://api.github.com/repos/${source_url}/releases/latest"
	if [ -n "$TOKEN" ]; then
		latest_tag=$(curl -sL -H "Authorization: Bearer $TOKEN" "$api_url" | jq -r '.tag_name // empty')
	else
		latest_tag=$(curl -sL "$api_url" | jq -r '.tag_name // empty')
	fi

	[ -n "$latest_tag" ] || {
		echo "SKIP $pkg: no release found via API"
		continue
	}

	# Normalize: strip leading 'v'
	latest_ver="${latest_tag#v}"

	# Normalize both for comparison: strip leading/trailing whitespace
	pkgver_norm=$(echo "$pkgver" | xargs)
	latest_norm=$(echo "$latest_ver" | xargs)

	if [ "$latest_norm" = "$pkgver_norm" ]; then
		echo "OK   $pkg: $pkgver (latest)"
	elif [ -n "$latest_norm" ]; then
		existing=$(gh issue list --repo "$REPO" --label modify-package \
			--search "Update ${pkg}" --state open --json number --jq '.[0].number' 2>/dev/null) || existing=""

		if [ -n "$existing" ]; then
			echo "SKIP $pkg: issue #${existing} already open ($pkgver → $latest_ver)"
		else
			echo "NEW  $pkg: $pkgver → $latest_ver"
			gh issue create --repo "$REPO" \
				--title "Update $pkg $pkgver → $latest_ver" \
				--label modify-package \
				--body "**Package:** $pkg
**Current version:** $pkgver
**New version:** $latest_ver
**Source:** https://github.com/$source_url/releases/latest" 2>/dev/null || true
		fi
	fi
done

echo "=== Done ==="
