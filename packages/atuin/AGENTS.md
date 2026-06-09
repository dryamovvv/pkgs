# atuin package notes

## Build

Rust workspace with all features. Build command:

````text
cargo build --release --locked --all-features
```text

Two binaries produced: `atuin` (client) and `atuin-server` (sync server).

## Features

All features enabled per user request. Feature list in `crates/atuin/Cargo.toml`:

- client, sync, daemon, ai, pty-proxy, clipboard, check-update, hex

## RPi5 flags

```text
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
LDFLAGS="-Wl,-z,max-page-size=0x4000"
RUSTFLAGS="-C target-cpu=cortex-a76 -C opt-level=2"
```text

## Key dependencies

- sqlite (sqlx sqlite feature)
- wayland (arboard clipboard on Wayland)
- protobuf/protoc (tonic/prost for daemon gRPC)

## Completions

Generated at install time via `atuin gen-completions --shell {bash,zsh,fish}`.

## systemd

- `atuin-server.service` — sync server unit
- `atuin-server.sysusers` — creates `atuin` system user
- `atuin-server.tmpfiles` — creates `/etc/atuin` and `/var/lib/atuin`
````
