# GitHub Releases Deploy — Design Spec

**Date:** 2026-06-08
**Status:** Approved

## Goal

Replace SCP+flock deployment to remote server with GitHub Releases as the pacman repository backend.

## Motivation

- Eliminate dependency on external server (`dryam.ru`)
- Remove SSH secrets/key management
- Simplify deployment: no SCP, no flock, no race conditions
- Built-in GitHub CDN for package distribution
- Versioned repository via `latest` tag

## Design

### Architecture

```text
deploy-packages job (ubuntu-24.04-arm)
├── Docker container (lfdevs/archlinuxarm:base-devel)
│   ├── Install github-cli via pacman
│   ├── Auth: GH_TOKEN env var
│   ├── gh release download latest → repo.db.tar.gz + repo.files.tar.gz + *.sig
│   ├── repo-add -R -s repo.db.tar.gz *.pkg.tar.* (new packages only)
│   ├── gh release upload --clobber → updated db files + new packages
│   └── Generate and upload index.html
```text

### Flow

1. **Check/create release:** `gh release view latest` — if not found, create empty release tagged `latest`
2. **Download db:** `gh release download latest --pattern '*.db*' --pattern '*.files*'` — fetch current pacman database
3. **repo-add:** `repo-add -R -s -k GPG_KEY repo.db.tar.gz <new-packages>` — add new packages to existing db (old entries preserved)
4. **Upload db:** `gh release upload latest --clobber repo.db* repo.files* *.sig` — update db files in release
5. **Upload packages:** `gh release upload latest *.pkg.tar.*` — add new package files (skip existing)
6. **Upload index.html:** Generate HTML listing and upload with `--clobber`

### Pacman client config

```ini
[custom-repo]
SigLevel = Required TrustedOnly
Server = https://github.com/dryamovvv/pkgs/releases/latest/download
```text

### Removed vs kept

| Removed | Kept |
|---------|------|
| `SSH_HOST`, `SSH_PORT`, `SSH_USER` secrets | `GPG_PRIVATE_KEY`, `GPG_PASSPHRASE` secrets |
| `SSH_PRIVATE_KEY`, `SSH_REPO_PATH` secrets | `GPG_KEY_ID` variable |
| `Validate SSH secrets` step | |
| `Prepare SSH key and known_hosts` step | |
| `flock` locking code | |
| SCP commands | |
| Staging directory on remote server | |

### GH_TOKEN

Use `${{ secrets.GITHUB_TOKEN }}` — available in every workflow run, no extra setup needed.

### Release strategy: single `latest` release, overwritten

- Tag `latest` force-pushed to HEAD on each deploy
- `gh release upload --clobber` updates existing assets in-place
- No delete/recreate — atomic upload per file

### Edge cases

- **First deploy (no release):** create `latest` tag + empty release, repo-add creates fresh db
- **Package already in release:** `gh release upload` skips existing files (unless `--clobber` used for db)
- **Package removed from repo:** old `.pkg.tar.*` remains in release, old db entry stays (acceptable for now; will add `repo-remove` later if needed)
- **Concurrent deploys:** handled by `concurrency: deploy-${{ github.ref }}` (sequential, no cancel)
