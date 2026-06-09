# linux-rpi-16k

Linux kernel and modules (RPi Foundation fork) with 16K pagesize for bcm2712/RPi5 ONLY.

## Building

```bash
makepkg -s
```text

## Dependencies

- `bc`, `kmod`, `inetutils` (build)
- `coreutils`, `firmware-raspberrypi`, `kmod`, `mkinitcpio`, `raspberrypi-bootloader` (runtime)

## Features

| Feature            | Enabled | Description                                             |
| ------------------ | ------- | ------------------------------------------------------- |
| RPi5 16K page size | yes     | bcm2712_defconfig — 16KB pages, optimized for BCM2712   |
| Kernel headers     | yes     | Split package `linux-rpi-16k-headers` for module builds |
| WireGuard          | yes     | Built-in WireGuard module                               |
| KSMBD              | yes     | Built-in SMB3 kernel server module                      |
| btrfs              | yes     | btrfs filesystem support                                |
| Landlock LSM       | yes     | Landlock security module                                |
