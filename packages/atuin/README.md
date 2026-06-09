# atuin

Magical shell history for Raspberry Pi 5 (Cortex-A76, aarch64).

## Features

All features enabled:

- **sync** — encrypted history sync via Atuin server
- **daemon** — daemon mode for background sync
- **ai** — AI-powered features (with tree-sitter shell parsing)
- **clipboard** — clipboard integration (X11 + Wayland)
- **check-update** — update notification
- **pty-proxy** — PTY proxy with hex mode

## Binaries

- `atuin` — shell history client
- `atuin-server` — self-hosted sync server

## Installation

````bash
sudo pacman -S atuin
```text

Then add to your shell:

```bash
# bash
echo 'eval "$(atuin init bash)"' >> ~/.bashrc

# zsh
echo 'eval "$(atuin init zsh)"' >> ~/.zshrc

# fish
echo 'atuin init fish | source' >> ~/.config/fish/config.fish
```text

## Self-hosted server

```bash
sudo systemctl enable --now atuin-server
```text

Configure at `/etc/atuin/server.toml`.

## Repository

```text
[custom-repo]
SigLevel = Optional TrustedOnly
Server = https://dryamovvv.github.io/pkgs/aarch64
````
