# Ideal Pacman Repository Architecture

**Date:** 2026-06-09
**Status:** Draft

## Overview

Architecture for an Arch Linux aarch64 16K-first pacman repository hosted on GitHub, optimized for Raspberry Pi 5 (Cortex-A76). Fully automated: update detection → AI agent → PR → lint + AI review → auto-merge → build → deploy.

## Repository

- **Host:** GitHub (`github.com/dryamovvv/pkgs`)
- **Distribution:** GitHub Releases (single `latest` release)
- **Architecture:** aarch64, 16K pages, Cortex-A76 optimization
- **Scope:** Arch Linux ARM `base` group + custom packages (50-200)
- **Pacman config:**

  ```ini
  [custom-repo]
  SigLevel = Required TrustedOnly
  Server = https://github.com/dryamovvv/pkgs/releases/download/latest
  ```

## Architecture & Data Flow

```text
                    ┌─────────────────────────────┐
                    │  check-updates.yml           │
                    │  (scheduled every 4h)         │
                    └──────────┬──────────────────┘
                               │ new version detected
                               ▼
                    ┌─────────────────────────────┐
                    │  GitHub Issue                │
                    │  (modify-package label)       │
                    └──────────┬──────────────────┘
                               │ AI agent picks up
                               ▼
                    ┌─────────────────────────────┐
                    │  opencode-issue-agent        │
                    │  (ubuntu-24.04-arm runner)   │
                    │  1. Analyze issue            │
                    │  2. Update PKGBUILD           │
                    │  3. Run updpkgsums            │
                    │  4. Try build (up to 5x)      │
                    │  5. Create PR or report fail  │
                    └──────────┬──────────────────┘
                               │ success
                               ▼
                    ┌─────────────────────────────┐
                    │  GitHub PR (ai-generated)    │
                    │  triggers: lint + AI review   │
                    └──────────┬──────────────────┘
                               │ CI passes + review approved
                               ▼
                    ┌─────────────────────────────┐
                    │  auto-merge (to main)        │
                    └──────────┬──────────────────┘
                               │ push to main
                               ▼
                    ┌─────────────────────────────┐
                    │  build.yml + deploy          │
                    │  build (cache-aware)           │
                    │  repo-add → gh release upload │
                    └──────────┬──────────────────┘
                               ▼
                    ┌─────────────────────────────┐
                    │  GitHub Release "latest"     │
                    │  repo.db + .pkg.tar.zst      │
                    └─────────────────────────────┘
```

## Components

### 1. check-updates.yml — Update Detection Bot

- **Trigger:** `schedule (0 */4 * * *)` + `workflow_dispatch`
- **Runner:** `ubuntu-latest`
- **Behavior:**
  - Installs `devtools` (which includes `pkgctl` and `nvchecker`)
  - For each package with `.nvchecker.toml`: runs `pkgctl version check`
  - For packages without `.nvchecker.toml`: runs `pkgctl version setup` first
  - `pkgctl version check` uses nvchecker under the hood — supports GitHub releases/tags, GitLab, PyPI, SourceForge, generic git, and many more sources
  - If new version found & no open `modify-package` issue exists → creates one
  - `pkgctl version upgrade` is NOT run here — that's the AI agent's job

### 2. opencode.yml — AI Agent (Central)

- **Triggers:**
  - `issues: [opened]` for `new-package`, `modify-package`, `remove-package`, `bug`, `feature`
  - `issue_comment: [created]` for follow-up interactions
  - `pull_request: [opened, synchronize]` for AI code review
  - `workflow_dispatch` for auto-fix of CI failures
- **Runner:** `ubuntu-24.04-arm` (for build verification) / `ubuntu-latest` (for PR review)
- **See Section "Agent Architecture & Prompt Design" below for full prompt details and tool lists.**

### 3. lint.yml — PR Linting

- **Trigger:** `pull_request: [opened, synchronize, reopened]`
- **Runner:** `ubuntu-latest`
- **Checks:**
  - `namcap PKGBUILD` (Arch Linux PKGBUILD linter)
  - `bash -n PKGBUILD` syntax check
  - `shellcheck` on shell scripts
  - sha256sums validation
  - markdownlint on docs

### 4. opencode.yml (opencode-review job) — AI Code Review

- **Trigger:** `pull_request: [opened, synchronize]`
- **Runner:** `ubuntu-latest`
- **Flow:**
  - AI reviews PR diff
  - If issues found → requests changes via `gh pr review --request-changes`
  - AI agent picks up the request (on PR synchronize), fixes issues
  - Re-review loop continues until approval
  - Auto-approve for `ai-generated` PRs after loop passes
- **See Section "Agent Architecture & Prompt Design" below for reviewer prompt and quality standards.**

### 5. build.yml — Build & Deploy

- **Trigger:** `push: [main]` + `workflow_dispatch`
- **Runner:** `ubuntu-24.04-arm`
- **Caching:** Docker image, ccache, Cargo, pacman, built artifacts (deterministic build-hash)
- **Matrix:** All packages (changed detected by caching — cache hit = skip)
- **Deploy:** `deploy-package.sh` → `repo-add -R` → `gh release upload latest --clobber`

### 6. auto-merge-on-ci-success.yml — Auto-Merge

- **Trigger:** `workflow_run: [completed]` on "Build and Deploy"
- **Runner:** `ubuntu-latest`
- **Behavior:** Merges AI-generated PRs after successful CI + lint + review

## Agent Architecture & Prompt Design

Each AI agent has a distinct role with its own tools, MCP servers, prompt, and quality gates. The system uses five agent types.

### Agent Roles Overview

| Agent              | Trigger                 | Runner             | Tools                                  |
| ------------------ | ----------------------- | ------------------ | -------------------------------------- |
| **new-package**    | Issue `new-package`     | `ubuntu-24.04-arm` | arch-mcp, Context7, web search, gh CLI |
| **modify-package** | Issue `modify-package`  | `ubuntu-24.04-arm` | arch-mcp, Context7, web search, gh CLI |
| **remove-package** | Issue `remove-package`  | `ubuntu-latest`    | gh CLI                                 |
| **bug-fix**        | Issue `bug`             | `ubuntu-24.04-arm` | arch-mcp, gh CLI (logs), web search    |
| **code-review**    | PR `opened/synchronize` | `ubuntu-latest`    | gh CLI (PR diff), arch-mcp (reference) |

### Shared Tools & MCP

Every build-capable agent has access to:

| Tool/MCP             | Purpose                                                                                                                                                                                                                                              |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **arch-mcp**         | Search AUR (`search_aur`), download PKGBUILD from AUR (`get_aur_package_info`), search Arch Wiki (`search_archwiki`), get official repo PKGBUILD (`get_official_package_info`). Used as reference for PKGBUILD structure, dependencies, and options. |
| **Context7**         | Query documentation for build systems: CMake (`CMakeLists.txt` options), Meson (`meson_options.txt`), Cargo features, configure scripts. Used to discover optional features.                                                                         |
| **Web Search (Exa)** | Find upstream docs, release notes, changelogs when Context7 lacks coverage.                                                                                                                                                                          |
| **gh CLI**           | Create/update issues, create PRs, read CI logs, comment.                                                                                                                                                                                             |
| **Bash**             | Run commands inside the container: `makepkg`, `updpkgsums`, `namcap`, git operations.                                                                                                                                                                |

### Prompt: new-package Agent

The agent receives this structured prompt:

```text
You are an Arch Linux package maintainer adding a new package to an aarch64
RPi5-optimized repository.

## Input
Issue title: <title>
Issue body: <body>

## Research Phase (sequential, do NOT skip)
1. Use arch-mcp:
   - search_aur("<pkgname>") — find existing AUR PKGBUILD
   - get_official_package_info("<pkgname>") — official Arch repo PKGBUILD
   - search_archwiki("<pkgname>") — Arch Wiki for build info
2. Find upstream: GitHub releases, tags, or download URL from issue/arch-mcp
3. Use Context7: query the build system (CMake/Meson/Cargo/configure) docs
   for available build options. Search for "enabling features" or
   "build options" for this specific project.
4. Web search for any missing info (uncommon build systems, patches).

## Feature Discovery (MANDATORY)
Run the upstream's build system introspection:
- CMake: look for `CMakeLists.txt` — search for `option()` and `add_feature_info()`
- Meson: look for `meson_options.txt` — read all options
- Cargo: `cargo metadata --no-deps --features-list`
- Autotools: `./configure --help` parsing

Identify ALL optional features. For each one:
- What does it enable?
- What dependencies does it pull?
- Enable by default UNLESS user says otherwise in issue body.

## PKGBUILD Creation
Create packages/<name>/PKGBUILD with:
- ALL optional features enabled (features=(...), --enable-*)
- Tests disabled: -DBUILD_TESTS=OFF, --disable-tests, etc.
- Docs enabled: -DBUILD_DOCS=ON, --enable-docs, etc.
- Debug stripped: strip, options=(!debug)
- RPi5 flags: CFLAGS/CXXFLAGS/LDFLAGS from AGENTS.md
- sha256sums: download source, compute with sha256sum, write into PKGBUILD
- Reference AUR/official PKGBUILD for structure but adapt to RPi5 flags

## nvchecker Setup
Run pkgctl version setup in the package directory to auto-generate .nvchecker.toml
from the source=() array. This enables future update detection by CI.

## Build Verification (up to 5 attempts)
1. Run makepkg -s --noconfirm in Docker container
2. If fail: read error, fix PKGBUILD, retry
3. Log each attempt in issue comment
4. After 5 failures: add label "failed", report error to issue, stop

## Documentation
Create packages/<name>/README.md with:
- Description of the package
- Enabled features (with short descriptions)
- Build dependencies
- Special notes

Create packages/<name>/AGENTS.md with:
- Version tracked
- Build system used
- RPi5 flags applied
- All enabled options/flags with explanations
- Any known quirks or workarounds

## Output
- Branch: add-package/<name>
- git commit: "feat: add <name> <version>"
- PR body: summarize enabled features, build system, and any notable choices
- Issue comment: PR link + list of enabled features
```

### Prompt: modify-package Agent

```text
You are updating an existing package.

## Input
Issue: <title>
Body: <body>

## Steps
1. Read current packages/<name>/PKGBUILD, README.md, AGENTS.md, .nvchecker.toml
2. Extract package name and change request from issue
3. If updating version:
   a. Run pkgctl version upgrade <name> in the package directory.
      This uses nvchecker and the .nvchecker.toml config to:
      - Detect the latest upstream version
      - Update pkgver in PKGBUILD
      - Reset pkgrel to 1
      - Update checksums via updpkgsums
   b. If .nvchecker.toml is missing, run pkgctl version setup first
4. If changing features:
   a. Re-run feature discovery (Context7 on build system)
   b. Update options in PKGBUILD
   c. Update README.md and AGENTS.md feature tables
5. Build verification: same as new-package (up to 5 attempts)
6. On success: branch modify-package/<name>, PR, comment
7. On failure: fix and retry up to 5x, then report
```

### Prompt: remove-package Agent

Simple prompt: remove directory, remove from docs tables, create PR.

### Prompt: bug-fix Agent

```text
A CI build or package has failed.

1. Read the issue — get CI run URL and error description
2. Use `gh run view <run-id>` to read build logs
3. Identify root cause: PKGBUILD error? missing dep? upstream issue?
4. Fix the PKGBUILD or related files
5. Build verification (up to 5 attempts)
6. On success: PR
7. On failure: report detailed diagnosis to issue
```

### Prompt: code-review Agent

```text
You are reviewing an Arch Linux PKGBUILD PR. Your quality standards:

## Critical checks (fail = request changes)
1. PKGBUILD syntax: bash -n must pass
2. Required fields present: pkgname, pkgver, pkgrel, pkgdesc, arch, url, license, depends, source, sha256sums
3. sha256sums correct (not empty, not placeholder)
4. Architecture: must include aarch64 (not x86_64 only)
5. RPi5 flags present: CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe", LDFLAGS="-Wl,-z,max-page-size=0x4000"
6. No hardcoded /usr/lib — use /usr/lib on aarch64
7. Tests disabled: check for BUILD_TESTING=OFF, --disable-tests, etc.
8. No absolute paths in source=() — use $pkgname-$pkgver.tar.gz pattern

## Quality checks (warn but don't block)
1. namcap warnings: check PKGBUILD and .pkg.tar.zst if built
2. split packages: if multiple binaries, consider package_split()
3. install files: systemd services need .service files in source=()
4. License file included in package()
5. pkgdesc is descriptive (>10 chars, not "A tool")

## Review flow
1. gh pr diff <number> — read the full diff
2. Check each critical item above
3. If any critical fails: gh pr review --request-changes with specific line references
4. If only quality warnings: gh pr review --comment with suggestions
5. If all clear: gh pr review --approve
6. Comment: list what was checked and the result
```

## Per-Package Documentation

Every package in the repository has three files:

### `packages/<name>/PKGBUILD`

Standard Arch Linux PKGBUILD with:

- RPi5 CFLAGS/CXXFLAGS/LDFLAGS (cortex-a76+crypto, 16K page alignment)
- All optional features enabled
- Tests disabled
- Debug symbols stripped
- Docs enabled
- GPG signature enabled

### `packages/<name>/README.md`

User-facing documentation:

- Package description
- List of enabled features with brief explanations
- Build dependencies
- Any special notes (runtime config, file locations)

### `packages/<name>/.nvchecker.toml`

nvchecker config auto-generated by `pkgctl version setup`. Defines how to check for upstream updates:

```toml
[<pkgbase>]
source = "github"  # or gitlab, pypi, sourceforge, etc.
github = "owner/repo"
```

Created once by `pkgctl version setup`, used by `pkgctl version check` in CI.

### `packages/<name>/AGENTS.md`

AI-facing metadata for future updates:

- Upstream URL & version tracked
- Build system used (CMake/Meson/Cargo/Autotools)
- RPi5 flags applied
- All enabled build options with explanations
- Feature flags that were considered and rejected (and why)
- Known quirks, workarounds, patched files

This file is read by the modify-package agent to understand the existing build configuration before making changes.

## Agent Key Principles

1. **Always research before writing.** Use arch-mcp (AUR → official → Arch Wiki) then upstream docs.
2. **Always check for features.** Never assume defaults are optimal. Run build system introspection.
3. **Never leave sha256sums empty.** Compute them unconditionally.
4. **Build verification is mandatory.** No PR without a successful build attempt.
5. **Document everything.** README.md for users, AGENTS.md for future AI agents.
6. **Fail gracefully.** After 5 failed attempts, label `failed` and explain the problem to a human.
7. **Review with rigor.** The reviewer enforces Arch packaging quality standards, not just syntax.

## Build Caching (Critical)

Deterministic build hash computed from:

- PKGBUILD content
- Source files and their URLs
- SHA256 sums
- All files in package directory (alphabetical order)
- `ci/build-package.sh` script

Cache key: `build-artifact-{pkg}-{sanitized-hash}`

On cache hit → skip build entirely, use cached `.pkg.tar.*` and `.sig` files.

## CI/CD Pipeline Details

1. **detect-changed-packages** (ubuntu-latest): determines matrix
2. **build-packages-matrix** (ubuntu-24.04-arm): parallel per-package builds
3. **deploy-packages** (ubuntu-24.04-arm): single deploy job
4. **create-failure-issue** (ubuntu-latest): on failure

## Issue-Driven Workflow

Users interact with the repository via GitHub Issues:

| Issue Label      | Action                                 |
| ---------------- | -------------------------------------- |
| `new-package`    | AI adds package                        |
| `modify-package` | AI updates package (version, features) |
| `remove-package` | AI removes package                     |
| `bug`            | AI fixes bug                           |
| `feature`        | AI discusses/implements                |
| `failed`         | Human attention needed (AI gave up)    |

## Repository Structure

```
pkgs/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── add_new_package.md
│   │   ├── modify_package.md
│   │   ├── remove_package.md
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── workflows/
│       ├── check-updates.yml
│       ├── opencode.yml           (AI agent + PR review)
│       ├── lint.yml
│       ├── build.yml
│       ├── auto-merge-on-ci-success.yml
│       ├── auto-add-shasums.yml
│       └── auto-fix-finalize.yml
├── ci/
│   ├── build-package.sh
│   ├── deploy-package.sh
│   ├── compute-build-hash.sh
│   ├── run-compute-hash.sh
│   ├── detect-changes.sh
│   ├── check-updates.sh
│   ├── auto-add-sha256sums.sh
│   └── report-failure.sh
├── packages/<pkg>/
│   ├── PKGBUILD
│   ├── .nvchecker.toml  # Auto-generated by pkgctl version setup
│   ├── README.md        # User-facing: features, deps, notes
│   └── AGENTS.md        # AI-facing: build options, flags, quirks
├── packages/<pkg2>/
├── keys/pgp/
│   └── BB827D35.asc
├── docs/
├── AGENTS.md
├── opencode.json
└── README.md
```

## Notifications & Alerting

### Critical Events

| Event                           | Detection                                            | Action                                             |
| ------------------------------- | ---------------------------------------------------- | -------------------------------------------------- |
| AI agent exhausted retries      | Issue labeled `failed` after 5 failed build attempts | GitHub issue notification + Telegram alert         |
| CI pipeline timeout             | Workflow timeout-minutes exceeded (90 min)           | `report-failure.sh` creates issue + Telegram alert |
| API token budget low            | Check remaining quota in workflow step               | Telegram alert to admin                            |
| Build failure (auto-fix failed) | `auto-fix-finalize.yml` detects unresolved failure   | Issue created + Telegram alert                     |
| Any abnormal event              | Unexpected workflow failure                          | `report-failure.sh` handles it                     |

### Channels

1. **GitHub Issues** — primary channel. AI self-organizes around issues: detects problems, opens issues, resolves them, closes. Already implemented via `report-failure.sh` and `create-failure-issue` job.
2. **Telegram** — additional notification for urgent events requiring admin attention:
   - GitHub Action `telegram-notify` step in critical workflows
   - Requires secrets: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
   - Triggered when: retry exhausted, timeout, token low, CI fails
3. **GitHub Email Notifications** — built-in, always active as secondary channel

### Implementation

Telegram notification helper step (added to critical workflow jobs):

```yaml
- name: Notify admin on failure
  if: failure() && env.TELEGRAM_BOT_TOKEN != ''
  uses: appleboy/telegram-action@master
  with:
    to: ${{ secrets.TELEGRAM_CHAT_ID }}
    token: ${{ secrets.TELEGRAM_BOT_TOKEN }}
    message: |
      ❌ Critical: ${{ github.workflow }}
      Repo: ${{ github.repository }}
      Run: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
      Event: ${{ github.event_name }}
```

## Security

- **GPG signing:** All packages and repo.db signed with RSA-4096 key
- **Key fingerprint:** `0F98FE406BB366EB10AFAD8D90B35929BB827D35`
- **Secrets:** `GPG_PRIVATE_KEY`, `GPG_PASSPHRASE`, `GPG_KEY_ID`
- **Runner isolation:** Docker containers for build isolation

## Changes from Current Implementation

1. **opencode.yml (new-package handler):**
   - Add `arch-mcp` installation step (uv + arch-mcp)
   - Add Context7 API key to env
   - Update prompt: add research phase (AUR → official → Arch Wiki → upstream docs)
   - Add feature discovery phase (CMake/Meson/Cargo/configure introspection)
   - Add build verification loop (up to 5 attempts) with Docker container
   - Add README.md and AGENTS.md creation per package
   - Switch runner to `ubuntu-24.04-arm` for build verification
   - Add retry logging to issue comments

2. **opencode.yml (modify-package handler):**
   - Same tooling upgrades (arch-mcp, Context7)
   - Add build verification loop (up to 5 attempts)
   - Add feature re-discovery when changing features
   - Switch runner to `ubuntu-24.04-arm` for build verification
   - Update AGENTS.md and README.md on changes

3. **opencode.yml (code-review job):**
   - Replace simple auto-approve with structured review prompt
   - Add critical checks checklist (syntax, fields, arch, flags, sha256sums, tests)
   - Add quality checks checklist (namcap, split packages, install files, license)
   - Implement review loop: review → request changes → agent fixes → re-review

4. **check-updates.sh → replace with pkgctl:**
   - Replace homemade GitHub API parsing with `pkgctl version check` (nvchecker)
   - Supports GitHub releases, GitHub tags, GitLab, PyPI, SourceForge, generic git out of the box
   - Each package gets `.nvchecker.toml` auto-generated by `pkgctl version setup`
   - Fallback: keep creating `modify-package` issues as before

5. **lint.yml:**
   - Add `namcap` PKGBUILD check
   - Add sha256sums validation

6. **deploy-package.sh:**
   - Ensure `repo-add -R` handles version replacement (already uses `-R`)
   - No cleanup of old files for now (deferred to next iteration)

7. **build.yml:**
   - Build all packages on push to main (not just changed — cache handles skip)
   - Already supports `force_rebuild_all`

8. **New: Telegram notifications:**
   - Add `appleboy/telegram-action` step to critical workflows
   - Notify on: retry exhausted, timeout, CI failure, token budget low
   - Secrets: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
