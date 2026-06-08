# fzf

A command-line fuzzy finder, optimized for Raspberry Pi 5 (Cortex-A76).

## Building

```bash
makepkg -s
```

## Dependencies

- Runtime: glibc
- Build: go

## Features

| Feature | Enabled | Description |
|---------|---------|-------------|
| fzf binary | yes | Core fuzzy finder |
| fzf-tmux | yes | Tmux integration helper |
| Man pages | yes | fzf(1), fzf-tmux(1) |
| Bash completion | yes | Fuzzy completion and CTRL-T/CTRL-R/ALT-C key bindings |
| Zsh completion | yes | Fuzzy completion and key bindings |
| Fish completion | yes | Fuzzy completion and key bindings |
| Vim plugin | included | `fzf --vim` generates vim integration script |
