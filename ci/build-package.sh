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

# Sync databases and install sudo if not present
pacman -Sy --noconfirm --needed sudo

# Set up RPi5-optimized makepkg.conf (Cortex-A76)
cat >>/etc/makepkg.conf <<'EOF'

# Cortex-A76 optimizations for Raspberry Pi 5
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="${CFLAGS}"
# -fomit-frame-pointer is default on AArch64 at -O2
EOF

# Create build user
useradd -m builder
echo "builder ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers

# Build
chown -R builder:builder "$PKGDIR"
cd "$PKGDIR"
su builder -c "makepkg -s --noconfirm"

echo "=== Build complete ==="
