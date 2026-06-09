# mdv

Browser-quality Markdown viewer for the terminal. Uses Kitty Graphics Protocol for rich rendering in Kitty/Ghostty terminals.

## Building

```bash
makepkg -s
```text

## Dependencies

- `gcc-libs`, `glibc` (runtime)
- `cargo` (build)

## Features

| Feature                 | Enabled | Description                                                 |
| ----------------------- | ------- | ----------------------------------------------------------- |
| Kitty Graphics Protocol | yes     | Renders Markdown with images, diagrams, syntax highlighting |
| Watch mode              | yes     | `--watch` auto-reloads on file change                       |
| Mermaid                 | yes     | Diagrams via `mmdc` or `npx @mermaid-js/mermaid-cli`        |
