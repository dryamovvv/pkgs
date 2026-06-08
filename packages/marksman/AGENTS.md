# marksman

| Attribute | Value |
|-----------|-------|
| Version | 2026-02-08 |
| Build system | .NET 9 (F#) |
| Features | Self-contained single-file binary, trimmed, compressed |

## RPi5 flags

```text
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
LDFLAGS="-Wl,-z,max-page-size=0x4000"
```text

## Notes

- Built as single-file self-contained .NET binary (no runtime dependency on the target system)
- VersionString is passed explicitly to skip `git describe --tags` (which fails without git history in the source archive)
- Uses `linux-arm64` RID for native ARM64 publish
- No runtime dependencies
