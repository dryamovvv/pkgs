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
# Extract source and sha256sums blocks (if present)
awk '/^source=\(/,/^\)/{if(!/^source=\(|/^\)/) print}' PKGBUILD 2>/dev/null | tr -d '\r' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//' | sed 's/ /\n/g' > /tmp/ci_sources_$$.txt || true
awk '/^sha256sums=\(/,/^\)/{if(!/^sha256sums=\(|/^\)/) print}' PKGBUILD 2>/dev/null | tr -d '\r' | tr '\n' ' ' | sed 's/^ *//;s/ *$//' | sed 's/ /\n/g' > /tmp/ci_sums_$$.txt || true

if [ -s /tmp/ci_sources_$$.txt ]; then
  echo "---SOURCES---" >> "$TMP_IN"
  cat /tmp/ci_sources_$$.txt >> "$TMP_IN"
fi
if [ -s /tmp/ci_sums_$$.txt ]; then
  echo "---SHA256SUMS---" >> "$TMP_IN"
  cat /tmp/ci_sums_$$.txt >> "$TMP_IN"
fi

# Hash contents of local package directory files (deterministic order)
echo "---LOCAL_FILES---" >> "$TMP_IN"
# exclude .git and any build artifacts
find . -type f -not -path './.git/*' -not -path './packages-built/*' -print0 | sort -z | xargs -0 -n1 -I{} sh -c 'sha256sum "{}" 2>/dev/null || true; echo "  {}"' >> "$TMP_IN" || true

# Compute final hash
HASH=$(sha256sum "$TMP_IN" | awk '{print $1}')
# Cleanup
rm -f /tmp/ci_sources_$$.txt /tmp/ci_sums_$$.txt "$TMP_IN" 2>/dev/null || true

printf "%s" "$HASH"
