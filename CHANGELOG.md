# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `opencode-builder` job: AI agent for new-package and modify-package issues on ARM runner
- `opencode-review` job: structured PKGBUILD review with critical and quality checks
- `check-updates` workflow: automatic version check via `pkgctl version` (nvchecker)
- namcap linting and sha256sums validation in `lint.yml`
- Telegram notifications for critical CI failures
- `CONTRIBUTING.md`, `SECURITY.md`, `llms.txt`
- Backlog issues for known improvements (#167–#170)

### Changed

- Switched update checking from GitHub API to `pkgctl version check` (nvchecker)
- Consolidated review documentation into `docs/review.md`

### Removed

- Dead files: `1`, `.repos.txt`, `install.sh`, `.github/actionlint.yaml`
- `CI_REVIEW.md` (merged into `docs/review.md`)
- Brainstorming artifacts from `docs/superpowers/` (plans/specs)
- Fix markdown auto-fix step (false green)
- `packages/{helix,mozillavpn}/TODO.md`
