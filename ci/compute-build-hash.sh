#!/usr/bin/env bash
set -euo pipefail

CI_DEBUG=${CI_DEBUG:-0}
if [ "$CI_DEBUG" = "1" ] || [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
  set -x
  echo "[ci-debug] compute-build-hash.sh starting (pwd=$(pwd))" >&2
fi

if [ "$#" -ne 1 ]; then
  echo "Usage: compute-build-hash.sh <package-dir>" >&2
  exit 2
fi
pkgdir="$1"
echo "[ci-debug] package dir: $pkgdir" >&2
cd "$pkgdir" || {
  echo "ERROR: cd $pkgdir failed" >&2
  exit 2
}

# Prepare temporary files
TMP_IN=/tmp/ci_build_hash_input_$$.txt
: >"$TMP_IN"

# Include PKGBUILD content
if [ -f PKGBUILD ]; then
  echo "---PKGBUILD---" >>"$TMP_IN"
  sed 's/\r$//' PKGBUILD >>"$TMP_IN"
fi

# Extract source and sha256sums blocks via safe, robust evaluation in an isolated bash subshell
bash -c 'source PKGBUILD >/dev/null 2>&1; for s in "${source[@]}"; do printf "%s\n" "$s"; done' >/tmp/ci_sources_$$.txt 2>/dev/null || true
bash -c 'source PKGBUILD >/dev/null 2>&1; for s in "${sha256sums[@]}"; do printf "%s\n" "$s"; done' >/tmp/ci_sums_$$.txt 2>/dev/null || true

# Handle declared sha256sums in PKGBUILD
if [ ! -s /tmp/ci_sums_$$.txt ]; then
  echo "WARNING: PKGBUILD missing sha256sums or sha256sums is empty in $pkgdir" >&2
  echo "---SHA256SUMS_DECLARED---" >>"$TMP_IN"
  echo "MISSING_SHA256S" >>"$TMP_IN"
else
  if [ -s /tmp/ci_sources_$$.txt ]; then
    echo "---SOURCES---" >>"$TMP_IN"
    cat /tmp/ci_sources_$$.txt >>"$TMP_IN"
  fi

  echo "---SHA256SUMS_DECLARED---" >>"$TMP_IN"
  cat /tmp/ci_sums_$$.txt >>"$TMP_IN"
fi

# Determine repo root early (needed for CI files and local source resolution)
REPO_ROOT=""
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi

# For local source files, compute their sha256 and include
# This ensures sources that reference repo-local files (patches, extras) are accounted for
echo "---LOCAL_SOURCE_FILES---" >>"$TMP_IN"
if [ -s /tmp/ci_sources_$$.txt ]; then
  while IFS= read -r src; do
    [ -z "$src" ] && continue
    # ignore URLs (scheme)
    if printf '%s' "$src" | grep -qE '^[a-zA-Z][a-zA-Z0-9+.-]*://'; then
      echo "URL:$src" >>"$TMP_IN"
      continue
    fi

    # 1) Try direct file relative to package dir
    if [ -f "$src" ]; then
      sha=$(sha256sum "$src" | awk '{print $1}')
      echo "$sha  $src" >>"$TMP_IN"
      continue
    fi

    # 2) Try searching upward from package dir up to repo root (covers ../patches, ../../common/ etc.)
    if [ -n "$REPO_ROOT" ]; then
      curr_dir="$(pwd)"
      found=""
      d="$curr_dir"
      while :; do
        if [ -f "$d/$src" ]; then
          sha=$(sha256sum "$d/$src" | awk '{print $1}')
          echo "$sha  $d/$src" >>"$TMP_IN"
          found=1
          break
        fi
        if [ "$d" = "$REPO_ROOT" ] || [ "$d" = "/" ]; then
          break
        fi
        d=$(dirname "$d")
      done
      if [ -n "$found" ]; then
        continue
      fi

      # 3) Try repo-root based glob expansion
      matches=$(compgen -G "$REPO_ROOT/$src" 2>/dev/null || true)
      if [ -n "$matches" ]; then
        for f in $matches; do
          if [ -f "$f" ]; then
            sha=$(sha256sum "$f" | awk '{print $1}')
            echo "$sha  $f" >>"$TMP_IN"
          fi
        done
        continue
      fi
    fi

    # 4) Try glob expansion relative to package dir
    matches=$(compgen -G "$src" 2>/dev/null || true)
    if [ -n "$matches" ]; then
      for f in $matches; do
        if [ -f "$f" ]; then
          sha=$(sha256sum "$f" | awk '{print $1}')
          echo "$sha  $f" >>"$TMP_IN"
        fi
      done
      continue
    fi

    # Not found locally
    echo "MISSING:$src" >>"$TMP_IN"
  done </tmp/ci_sources_$$.txt
fi

# Hash contents of local package directory files (deterministic order)
echo "---LOCAL_FILES---" >>"$TMP_IN"
find . -type f -not -path './.git/*' -not -path './packages-built/*' -print0 | sort -z | xargs -0 -I{} sh -c 'sha256sum "{}" 2>/dev/null || true; printf "  %s\n" "{}"' >>"$TMP_IN" || true

# Include CI build script (changes to build process must invalidate cache)
if [ -n "${REPO_ROOT:-}" ] && [ -f "$REPO_ROOT/ci/build-package.sh" ]; then
  echo "---CI_BUILD_SCRIPT---" >>"$TMP_IN"
  sha256sum "$REPO_ROOT/ci/build-package.sh" | awk '{print $1}' >>"$TMP_IN"
fi

# Force rebuild flag (ensures cache miss when force_rebuild_all is set)
FORCE_REBUILD="${FORCE_REBUILD_ALL:-false}"
if [ "$FORCE_REBUILD" = "true" ]; then
  echo "---FORCE_REBUILD---" >>"$TMP_IN"
  date +%s >>"$TMP_IN"
fi

# Compute final hash
HASH=$(sha256sum "$TMP_IN" | awk '{print $1}')
# Cleanup temp files
rm -f /tmp/ci_sources_$$.txt /tmp/ci_sums_$$.txt "$TMP_IN" 2>/dev/null || true

# Sanity check: ensure hash is non-empty
if [ -z "$HASH" ] || [ "$HASH" = "" ]; then
  echo "ERROR: computed build hash is empty" >&2
  exit 1
fi

# Output only the hash to stdout (suitable for capture)
printf "%s" "$HASH"
# cache stress test
# final cache verification
