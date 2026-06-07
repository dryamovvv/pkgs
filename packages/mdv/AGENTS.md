# mdv

| Attribute    | Value                             |
| ------------ | --------------------------------- |
| Version      | 0.1.1                             |
| Build system | Cargo (Rust)                      |
| Features     | none (no optional Cargo features) |

## RPi5 flags

```
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
LDFLAGS="-Wl,-z,max-page-size=0x4000"
RUSTFLAGS="-C target-cpu=cortex-a76 -C opt-level=2"
```

## Notes

- Source pinned to commit `739511e` (no upstream tags)
- Uses Kitty Graphics Protocol — interactive mode works in Kitty/Ghostty, plain text fallback on other terminals
- All dependencies are mandatory, no optional features
