# marksman

A Language Server Protocol (LSP) server for Markdown that provides completion,
goto definition, find references, rename refactoring, diagnostics, and
wiki-link-style references (Zettelkasten). Optimized for Raspberry Pi 5
(Cortex-A76).

## Building

```bash
makepkg -s
```

## Dependencies

- **Runtime:** none (self-contained single-file binary)
- **Build:** dotnet-sdk-9.0

## Features

| Feature      | Enabled | Description |
|--------------|---------|-------------|
| Completion   | yes     | Auto-complete wiki-links, reference links, headings |
| Diagnostics  | yes     | Detect broken wiki-links, duplicate headings |
| Navigation   | yes     | Go-to definition, find references |
| Refactoring  | yes     | Rename symbols across documents |
| Document symbols | yes | List symbols in current document |
| Workspace symbols | yes | Search symbols across workspace |
| Code actions | yes     | Table of contents generation, more |
| Code lens    | yes     | Reference counts, TODO lens |
| Hover        | yes     | Preview link targets |
