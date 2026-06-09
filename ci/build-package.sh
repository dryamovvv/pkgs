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
pacman -Sy --noconfirm --needed sudo ccache openssh pinentry

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
MAKEFLAGS="-j$(nproc)"
# -fomit-frame-pointer is default on AArch64 at -O2
EOF

# Create build user
useradd -m builder
echo "builder ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers

# Set up GPG signing
GPG_KEY="${GPG_KEY:-}"
GPG_IMPORT="${GPG_IMPORT:-}"
GPG_PASSPHRASE="${GPG_PASSPHRASE:-}"

if [ -n "$GPG_KEY" ] && [ -n "$GPG_IMPORT" ]; then
  echo "=== Setting up GPG signing ==="
  set +e

  # Import key for root (repo-add runs as root in deploy)
  echo "$GPG_IMPORT" | gpg --import --batch --no-tty 2>&1 || true
  echo "$GPG_IMPORT" | gpg --import --batch --no-tty 2>&1 || true

  # Import key for builder user (makepkg runs as builder)
  mkdir -p /home/builder/.gnupg
  chown builder:builder /home/builder/.gnupg
  chmod 700 /home/builder/.gnupg
  su builder -c "gpg --import --batch --no-tty" <<<"$GPG_IMPORT" 2>&1 || true
  su builder -c "gpg --import --batch --no-tty" <<<"$GPG_IMPORT" 2>&1 || true

  # Set up gpg-agent for non-interactive signing
  cat >/home/builder/.gnupg/gpg-agent.conf <<'GPGAGENT'
default-cache-ttl 3600
max-cache-ttl 7200
allow-loopback-pinentry
GPGAGENT
  chown -R builder:builder /home/builder/.gnupg
  chmod 700 /home/builder/.gnupg
  chmod 600 /home/builder/.gnupg/gpg-agent.conf
  gpgconf --kill gpg-agent 2>/dev/null || true
  GNUPGHOME=/home/builder/.gnupg gpgconf --kill gpg-agent 2>/dev/null || true

  # Configure makepkg signing
  echo "GPGKEY=$GPG_KEY" >>/etc/makepkg.conf
  if ! grep -q '^sign' /etc/makepkg.conf; then
    echo "sign=(pkg)" >>/etc/makepkg.conf
  fi

  # Pre-cache passphrase in gpg-agent
  if [ -n "$GPG_PASSPHRASE" ]; then
    su builder -c "GPG_PASSPHRASE='$GPG_PASSPHRASE' gpg --batch --yes \
			--passphrase '\$GPG_PASSPHRASE' --pinentry-mode loopback \
			--sign /dev/null" 2>/dev/null || true
  fi
  set -e
fi

# Build
chown -R builder:builder "$PKGDIR" /ccache /home/builder 2>/dev/null || true
cd "$PKGDIR"
if [ -n "$GPG_KEY" ] && [ -n "$GPG_IMPORT" ]; then
  su builder -c "GPGKEY=$GPG_KEY makepkg -s --noconfirm --sign"
else
  su builder -c "makepkg -s --noconfirm"
fi

# Show ccache stats
ccache -s >&2 || true

echo "=== Build complete ==="
