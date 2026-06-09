# fzf

| Attribute | Value |
|-----------|-------|
| Version | 0.73.1 |
| Build system | Go (Makefile-compatible) |
| Features | all built-in (no optional build tags), fzf-tmux, man pages, bash/zsh/fish completions & key bindings |

## RPi5 flags

```text
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
LDFLAGS="-Wl,-z,max-page-size=0x4000"
GOARCH=arm64 GOARM64=v8.2
```text

Go ldflags include `-extldflags=-Wl,-z,max-page-size=0x4000` for 16K ELF alignment.

## Notes

- Built with `go build` directly (not via Makefile) for full flag control
- `FZF_VERSION` and `FZF_REVISION` set explicitly since not in git repo
- `-a` flag forces full rebuild; `-trimpath` removes build paths
- `-s -w` strip debug info (combined with `!debug` option)
- pprof build tag omitted (profiling not useful on target)
