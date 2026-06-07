#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: compute-build-hash.sh <package-dir>" >&2
  exit 2
fi
pkgdir="$1"
cd "$pkgdir"

# Prepare temporary files
TMP_IN=/tmp/ci_build_hash_input_$$.txt
: > "$TMP_IN"

# Include PKGBUILD content
if [ -f PKGBUILD ]; then
  echo "---PKGBUILD---" >> "$TMP_IN"
  sed 's/\r$//' PKGBUILD >> "$TMP_IN"
fi

# Extract source and sha256sums blocks (if present)
awk '/^source=\(/,/^\)/{if(!/^source=\(|/^\)/) print}' PKGBUILD 2>/dev/null | tr -d '\r' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//' | sed 's/ /\n/g' > /tmp/ci_sources_$$.txt || true
awk '/^sha256sums=\(/,/^\)/{if(!/^sha256sums=\(|/^\)/) print}' PKGBUILD 2>/dev/null | tr -d '\r' | tr '\n' ' ' | sed 's/^ *//;s/ *$//' | sed 's/ /\n/g' > /tmp/ci_sums_$$.txt || true

# Enforce presence of declared sha256sums in PKGBUILD
if [ ! -s /tmp/ci_sums_$$.txt ]; then
  echo "ERROR: PKGBUILD missing sha256sums or sha256sums is empty in $pkgdir" >&2
  rm -f /tmp/ci_sources_$$.txt /tmp/ci_sums_$$.txt "$TMP_IN" || true
  exit 3
fi

if [ -s /tmp/ci_sources_$$.txt ]; then
  echo "---SOURCES---" >> "$TMP_IN"
  cat /tmp/ci_sources_$$.txt >> "$TMP_IN"
fi

echo "---SHA256SUMS_DECLARED---" >> "$TMP_IN"
cat /tmp/ci_sums_$$.txt >> "$TMP_IN"

# For local source files, compute their sha256 and include
# This ensures sources that reference repo-local files (patches, extras) are accounted for
echo "---LOCAL_SOURCE_FILES---" >> "$TMP_IN"
if [ -s /tmp/ci_sources_$$.txt ]; then
  while IFS= read -r src; do
    [ -z "$src" ] && continue
    # ignore URLs (scheme)
    if printf '%s' "$src" | grep -qE '^[a-zA-Z][a-zA-Z0-9+.-]*://'; then
      echo "URL:$src" >> "$TMP_IN"
      continue
    fi
    # Try direct file relative to package dir
    if [ -f "$src" ]; then
      sha=$(sha256sum "$src" | awk '{print $1}')
      echo "$sha  $src" >> "$TMP_IN"
      continue
    fi
    # Try file relative to repo root (one level up and further)
    if [ -f "../$src" ]; then
      sha=$(sha256sum "../$src" | awk '{print $1}')
      echo "$sha  ../$src" >> "$TMP_IN"
      continue
    fi
    # Glob expansion using compgen
    matches=$(compgen -G "$src" || true)
    if [ -n "$matches" ]; then
      for f in $matches; do
        if [ -f "$f" ]; then
          sha=$(sha256sum "$f" | awk '{print $1}')
          echo "$sha  $f" >> "$TMP_IN"
        fi
      done
      continue
    fi
    # Not found locally
    echo "MISSING:$src" >> "$TMP_IN"
  done < /tmp/ci_sources_$$.txt
fi

# Hash contents of local package directory files (deterministic order)
echo "---LOCAL_FILES---" >> "$TMP_IN"
find . -type f -not -path './.git/*' -not -path './packages-built/*' -print0 | sort -z | xargs -0 -n1 -I{} sh -c 'sha256sum "{}" 2>/dev/null || true; echo "  {}"' >> "$TMP_IN" || true

# Compute final hash
HASH=$(sha256sum "$TMP_IN" | awk '{print $1}')
# Cleanup
rm -f /tmp/ci_sources_$$.txt /tmp/ci_sums_$$.txt "$TMP_IN" 2>/dev/null || true

printf "%s" "$HASH"
