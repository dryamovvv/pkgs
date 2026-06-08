#!/bin/bash
set -euo pipefail

# Check all packages for upstream updates via GitHub releases.atom
# Creates modify-package issues when new versions are found

REPO="${GITHUB_REPOSITORY:-dryamovvv/pkgs}"

echo "=== Checking upstream updates ==="

for pkgdir in packages/*/; do
	pkg=$(basename "$pkgdir")
	pkgbuild="$pkgdir/PKGBUILD"
	[ -f "$pkgbuild" ] || continue

	# Extract pkgver
	pkgver=$(grep -oP '^pkgver=\K.*' "$pkgbuild" | head -1)
	[ -n "$pkgver" ] || continue

	# Extract GitHub source (owner/repo from URL)
	source_url=$(grep -oP 'https://github\.com/\K[^/]+/[^/"'\'' ]+' "$pkgbuild" | head -1)
	[ -n "$source_url" ] || continue
	source_url="${source_url%.git}"

	# Fetch latest release from Atom feed
	raw_title=$(
		curl -sL "https://github.com/${source_url}/releases.atom" 2>/dev/null |
			grep -oP '<title>\K[^<]+' |
			grep -vi 'releases\|Release\|Tags\|Changelog' |
			head -1
	) || raw_title=""
	[ -n "$raw_title" ] || continue

	# Clean version: strip package name prefix, strip leading 'v', take first word
	latest_ver=$(echo "$raw_title" | sed -E 's/^[A-Za-z0-9_.-]+ //; s/^v//; s/ .*//')

	# Compare versions (simple string compare — works for semver)
	if [ "$latest_ver" != "$pkgver" ] && [ -n "$latest_ver" ]; then
		# Check if issue already exists
		existing=$(gh issue list \
			--repo "$REPO" \
			--label modify-package \
			--search "Update ${pkg}" \
			--state open \
			--json number \
			--jq '.[0].number' 2>/dev/null) || existing=""

		if [ -n "$existing" ]; then
			echo "SKIP $pkg: issue #${existing} already open ($pkgver → $latest_ver)"
		else
			echo "NEW  $pkg: $pkgver → $latest_ver"
			gh issue create \
				--repo "$REPO" \
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
