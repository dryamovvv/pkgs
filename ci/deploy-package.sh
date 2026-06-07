#!/bin/bash
set -euo pipefail

echo "=== Deploy via GitHub Releases ==="

WORKDIR=$(mktemp -d /tmp/repo-work-XXXXXX)
cd "$WORKDIR"

GPG_KEY="${GPG_KEY:-}"
GPG_IMPORT="${GPG_IMPORT:-}"
GPG_PASSPHRASE="${GPG_PASSPHRASE:-}"

# ── Set up GPG signing ──
if [ -n "$GPG_KEY" ] && [ -n "$GPG_IMPORT" ]; then
	echo "=== Setting up GPG signing ==="
	echo "$GPG_IMPORT" | gpg --import --batch --no-tty 2>&1 || true
	if [ -n "$GPG_PASSPHRASE" ]; then
		gpg --batch --yes --passphrase "$GPG_PASSPHRASE" --pinentry-mode loopback \
			--edit-key "$GPG_KEY" trust quit 2>&1 <<EOF || true
5
y
EOF
	fi
fi

# ── Ensure latest release exists ──
if ! gh release view latest --repo "$GITHUB_REPOSITORY" &>/dev/null; then
	echo "=== Creating latest release ==="
	gh release create latest \
		--target main \
		--title "Latest packages" \
		--notes "Arch Linux aarch64 packages optimized for Raspberry Pi 5 (Cortex-A76)" \
		--repo "$GITHUB_REPOSITORY"
else
	echo "=== Latest release exists ==="
fi

# ── Download existing db from release ──
echo "=== Downloading existing repo database ==="
gh release download latest \
	--repo "$GITHUB_REPOSITORY" \
	--pattern '*.db*' \
	--pattern '*.files*' \
	--dir "$WORKDIR" 2>/dev/null || echo "No existing db found (first deploy)"

# ── Gather new packages ──
echo "=== Gathering new packages ==="
NEW_PKGS=()
for pkgdir in /workspace/packages/*/; do
	[ -d "$pkgdir" ] || continue
	for f in "$pkgdir"/*.pkg.tar.*; do
		[ -f "$f" ] || continue
		basename="${f##*/}"
		# skip .sig files for now (handled below)
		[[ "$basename" == *.sig ]] && continue
		cp "$f" "$WORKDIR/"
		NEW_PKGS+=("$WORKDIR/$basename")
	done
done

if [ ${#NEW_PKGS[@]} -eq 0 ]; then
	echo "No new packages to deploy"
	exit 0
fi

echo "New packages: ${NEW_PKGS[*]}"

# ── Update repo database ──
echo "=== Running repo-add ==="
REPO_DB="$WORKDIR/repo.db.tar.gz"

if [ -f "$REPO_DB" ]; then
	# Existing db: add new packages
	if [ -n "$GPG_KEY" ]; then
		repo-add -R -s -k "$GPG_KEY" "$REPO_DB" "${NEW_PKGS[@]}"
	else
		repo-add -R "$REPO_DB" "${NEW_PKGS[@]}"
	fi
else
	# Fresh db
	if [ -n "$GPG_KEY" ]; then
		repo-add -s -k "$GPG_KEY" "$REPO_DB" "${NEW_PKGS[@]}"
	else
		repo-add "$REPO_DB" "${NEW_PKGS[@]}"
	fi
fi

# ── Generate index.html ──
echo "=== Generating index.html ==="
{
	printf '<!DOCTYPE html>\n<html lang="en">\n<head><meta charset="UTF-8"><title>aarch64 Repository</title></head>\n<body>\n'
	printf '<h1>Arch Linux aarch64 Package Repository</h1>\n<p>Optimized for Raspberry Pi 5 (Cortex-A76)</p>\n<hr>\n<pre>\n'
	for f in "$WORKDIR"/*.pkg.tar.*; do
		[ -f "$f" ] || continue
		n=$(basename "$f")
		[[ "$n" == *.sig ]] && continue
		ne=$(printf '%s\n' "$n" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
		printf '<a href="aarch64/%s">%s</a>\n' "$n" "$ne"
	done
	printf '</pre>\n</body>\n</html>\n'
} >"$WORKDIR/index.html"

# ── Upload to release ──
echo "=== Uploading to GitHub Releases ==="

# Upload db files (clobber existing)
for f in "$WORKDIR"/repo.db "$WORKDIR"/repo.db.tar.gz "$WORKDIR"/repo.files "$WORKDIR"/repo.files.tar.gz; do
	[ -f "$f" ] || continue
	gh release upload latest "$f" --repo "$GITHUB_REPOSITORY" --clobber
done

# Upload db signatures
for f in "$WORKDIR"/repo.db.tar.gz.sig "$WORKDIR"/repo.files.tar.gz.sig; do
	[ -f "$f" ] || continue
	gh release upload latest "$f" --repo "$GITHUB_REPOSITORY" --clobber 2>/dev/null || true
done

# Upload package signatures and index
for f in "$WORKDIR"/*.sig "$WORKDIR"/index.html; do
	[ -f "$f" ] || continue
	gh release upload latest "$f" --repo "$GITHUB_REPOSITORY" --clobber 2>/dev/null || true
done

# Upload new packages
for pkg in "${NEW_PKGS[@]}"; do
	if gh release upload latest "$pkg" --repo "$GITHUB_REPOSITORY" 2>/dev/null; then
		echo "Uploaded: $(basename "$pkg")"
	else
		echo "Skipped (already exists): $(basename "$pkg")"
	fi
done

echo "=== Deploy complete ==="
rm -rf "$WORKDIR"
