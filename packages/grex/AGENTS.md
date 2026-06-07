# grex

| Attribute | Value |
|-----------|-------|
| Version | 1.4.6 |
| Build system | Cargo (Rust) |
| Features | cli (default), no Python bindings |

## RPi5 flags

```
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
LDFLAGS="-Wl,-z,max-page-size=0x4000"
RUSTFLAGS="-C target-cpu=cortex-a76 -C opt-level=2"
```

## Notes

- Standard Cargo build with --locked
