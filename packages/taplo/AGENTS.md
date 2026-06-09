# taplo

| Attribute | Value |
|-----------|-------|
| Version | 0.10.0 |
| Build system | Cargo (Rust) |
| Features | none (no optional Cargo features) |

## RPi5 flags

```text
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
LDFLAGS="-Wl,-z,max-page-size=0x4000"
RUSTFLAGS="-C target-cpu=cortex-a76 -C opt-level=2"
```text

## Notes

- Standard Cargo build with --locked
