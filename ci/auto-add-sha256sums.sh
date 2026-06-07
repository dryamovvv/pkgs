#!/usr/bin/env bash
set -euo pipefail

# Usage: ci/auto-add-sha256sums.sh [max_prs] [branch_prefix] [commit_author]
# Example: ci/auto-add-sha256sums.sh 10 ci/add-shasums "CI Bot <ci-bot@example.com>"

MAX_PRS=${1:-20}
BRANCH_PREFIX=${2:-ci/add-shasums}
COMMIT_AUTHOR=${3:-"CI Bot <ci-bot@example.com>"}

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
count=0

for pkgdir in packages/*; do
  [ $count -ge $MAX_PRS ] && break
  [ -d "$pkgdir" ] || continue
  PKGBUILD="$pkgdir/PKGBUILD"
  [ -f "$PKGBUILD" ] || continue

  # Detect existing non-empty sha256sums block
  if sed -n '/^sha256sums=(/,/)/p' "$PKGBUILD" | grep -q '\\S'; then
    echo "[skip] $pkgdir already has sha256sums"
    continue
  fi

  echo "[work] $pkgdir: missing sha256sums — attempting to compute"
  branch="${BRANCH_PREFIX}/${pkgdir##*/}-shasums"

  # Try updpkgsums if available
  if command -v updpkgsums >/dev/null 2>&1; then
    echo "Running updpkgsums in $pkgdir"
    (cd "$pkgdir" && updpkgsums) || true
  else
    # Fallback: use makepkg -g and try to extract sha256sums block
    echo "updpkgsums not found — running makepkg -g"
    genfile="/tmp/ci_makepkg_${RANDOM}.out"
    (cd "$pkgdir" && makepkg -g > "$genfile") || true
    # Extract generated sha256sums block and append to PKGBUILD if present
    # check generated output for sha256sums block
    if sed -n '/^sha256sums=(/,/)/p' "$genfile" | grep -q '\\S'; then
      echo "Appending generated sha256sums to $PKGBUILD"
      sed -n '/^sha256sums=(/,/)/p' "$genfile" >> "$PKGBUILD" || true
    else
      echo "makepkg -g didn't produce checksums; attempting manual download+sha256 computation"
      # try to source PKGBUILD to get 'source' array (note: PKGBUILD evaluated in subshell)
      pushd "$pkgdir" >/dev/null 2>&1 || true
      mapfile -t _SOURCES < <(bash -c 'source PKGBUILD >/dev/null 2>&1; for s in "${source[@]}"; do printf "%s\n" "$s"; done') || true
      if [ "${#_SOURCES[@]}" -eq 0 ]; then
        echo "No sources discovered for $pkgdir; skipping"
        popd >/dev/null 2>&1 || true
        git checkout main >/dev/null 2>&1 || true
        continue
      fi
      TMPD=$(mktemp -d)
      declare -a _SUMS=()
      failed=0
      for s in "${_SOURCES[@]}"; do
        if [ -z "$s" ]; then
          _SUMS+=("MISSING")
          continue
        fi
        # support 'file::url' source syntax
        src="$s"
        if printf '%s' "$s" | grep -q '::'; then
          src="${s#*::}"
        fi
        if printf '%s' "$src" | grep -qE '^[a-zA-Z][a-zA-Z0-9+.-]*://'; then
          fname=$(basename "$src")
          echo "Downloading $src"
          attempt=0
          success=0
          while [ $attempt -lt 3 ]; do
            if curl -L --fail -s -o "$TMPD/$fname" "$src"; then
              success=1
              break
            fi
            attempt=$((attempt+1))
            sleep $((attempt*2))
          done
          if [ $success -ne 1 ]; then
            echo "Download failed after retries: $src"
            failed=1
            break
          fi
          sha=$(sha256sum "$TMPD/$fname" | cut -d' ' -f1)
          _SUMS+=("$sha")
        else
          # local file relative to package dir or repo
          if [ -f "$src" ]; then
            sha=$(sha256sum "$src" | cut -d' ' -f1)
            _SUMS+=("$sha")
          elif [ -f "../$src" ]; then
            sha=$(sha256sum "../$src" | cut -d' ' -f1)
            _SUMS+=("$sha")
          elif [ -f "$REPO_ROOT/$src" ]; then
            sha=$(sha256sum "$REPO_ROOT/$src" | cut -d' ' -f1)
            _SUMS+=("$sha")
          else
            echo "Local source not found: $src"
            failed=1
            break
          fi
        fi
      done
      if [ "$failed" -eq 1 ]; then
        echo "Manual checksum generation failed for $pkgdir; cleaning up"
        rm -rf "$TMPD" || true
        popd >/dev/null 2>&1 || true
        git checkout main >/dev/null 2>&1 || true
        continue
      fi
      # append sha256sums block to absolute PKGBUILD path
      PKGBUILD_ABS="$REPO_ROOT/$pkgdir/PKGBUILD"
      printf '\nsha256sums=(\n' >> "$PKGBUILD_ABS"
      for v in "${_SUMS[@]}"; do
        printf '  %s\n' "$v" >> "$PKGBUILD_ABS"
      done
      printf ')\n' >> "$PKGBUILD_ABS"
      rm -rf "$TMPD" || true
      popd >/dev/null 2>&1 || true
    fi
  fi

  # Verify we added something
  if ! sed -n '/^sha256sums=(/,/)/p' "$PKGBUILD" | grep -q '\\S'; then
    echo "Failed to add sha256sums for $pkgdir — skipping"
    git checkout main >/dev/null 2>&1 || true
    continue
  fi

  # Commit and push
  # create feature branch for this package (overwrite if exists locally)
  git checkout -B "$branch" >/dev/null 2>&1 || true
  git add "$PKGBUILD"
  # parse commit author "Name <email>"
  NAME="${COMMIT_AUTHOR%% <*}"
  EMAIL="${COMMIT_AUTHOR##*<}"
  EMAIL="${EMAIL%>}"
  git -c user.name="$NAME" -c user.email="$EMAIL" commit -m "ci: add sha256sums for ${pkgdir##*/}" -m "Automated: compute and add sha256sums to improve CI caching" || true

  if command -v gh >/dev/null 2>&1; then
    git push --set-upstream origin "$branch" --quiet || true
    gh pr create --title "ci: add sha256sums for ${pkgdir##*/}" --body "This PR adds computed sha256sums for ${pkgdir##*/} to enable deterministic build hashing and CI caching." --head "$branch" --base main || true
    echo "PR opened for ${pkgdir##*/}"
  else
    echo "gh CLI not available — branch created locally: $branch"
  fi

  count=$((count+1))
done

echo "Done. Processed $count packages (limit $MAX_PRS)."
