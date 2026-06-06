#!/bin/bash
set -euo pipefail

PKG="$1"
PKGDIR="packages/$PKG"

if [ ! -d "$PKGDIR" ]; then
  echo "ERROR: Package directory $PKGDIR not found"
  exit 1
fi

echo "=== Building package: $PKG ==="

# Initialize pacman keyring
pacman-key --init
pacman-key --populate archlinuxarm

# Install build essentials
pacman -Sy --noconfirm --needed sudo ccache

# Set up ccache
export CCACHE_DIR=/ccache
export CCACHE_MAXSIZE=5G
export PATH=/usr/lib/ccache/bin:$PATH
ccache -z >/dev/null 2>&1 || true

# Set up RPi5-optimized makepkg.conf (Cortex-A76, 16K-page ELF alignment)
cat >>/etc/makepkg.conf <<'EOF'

# Cortex-A76 optimizations for Raspberry Pi 5
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="${CFLAGS}"
LDFLAGS="-Wl,-z,max-page-size=0x4000"
# -fomit-frame-pointer is default on AArch64 at -O2
EOF

# Create build user
useradd -m builder
echo "builder ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers

# Build
chown -R builder:builder "$PKGDIR"
cd "$PKGDIR"
su builder -c "makepkg -s --noconfirm"

# Show ccache stats
ccache -s >&2 || true

echo "=== Build complete ==="
