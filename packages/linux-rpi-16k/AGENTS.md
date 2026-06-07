# linux-rpi-16k

| Attribute    | Value                                    |
| ------------ | ---------------------------------------- |
| Version      | 6.18.34                                  |
| Build system | Make (Linux kernel)                      |
| Features     | bcm2712_defconfig + archarm.diffconfig   |
| Split        | `linux-rpi-16k`, `linux-rpi-16k-headers` |
| Base config  | bcm2712_defconfig (RPi5, 16K pages)      |

## RPi5 flags

Kernel uses KCFLAGS/KCPPFLAGS (not standard CFLAGS — would break kernel build):

```
KCFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
KCPPFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
```

## Notes

- **RPi5 ONLY** — 16K page size (`getconf PAGE_SIZE` → 16384). Incompatible with RPi4/3.
- Source is Raspberry Pi Foundation fork: https://github.com/raspberrypi/linux
- Pinned to commit `19a2939bed` (no version tag)
- Do NOT use CFLAGS/CXXFLAGS/LDFLAGS — kernel build system incompatible with user-space flags
- Split packages: `linux-rpi-16k` (kernel+modules) and `linux-rpi-16k-headers`
- `check()` not run (kernel builds take hours, no tests suit)
