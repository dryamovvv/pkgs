# Contributing

## AI-Driven Workflow

This repository is designed for AI-agent-assisted maintenance. All operations — adding packages, updating versions, fixing builds — are driven through GitHub Issues with structured labels:

| Label            | Purpose                                         |
| ---------------- | ----------------------------------------------- |
| `new-package`    | Request to add a new package                    |
| `modify-package` | Request to update/rebuild an existing package   |
| `ci-failure`     | Build failure detected — auto-fix eligible      |
| `backlog`        | Tracked for future consideration, not immediate |

The AI agent (`opencode`) picks up labeled issues, researches upstream build options, creates PKGBUILDs, verifies builds in CI, and submits PRs — all autonomously. Manual intervention is only needed for:

- Security vulnerability reports (see `SECURITY.md`)
- Issues that reach `unfixable` status after 3 auto-fix attempts
- Design decisions about optional features

## How to Contribute

### Report a Bug

Open a GitHub Issue with the `bug` label. Include:

- Package name and version
- Error message and relevant log output
- Steps to reproduce

### Request a New Package

Open a GitHub Issue with the `new-package` label. The AI agent will:

1. Research the upstream project (build system, features, dependencies)
2. Create a PKGBUILD with all features enabled
3. Build and verify in CI
4. Submit a PR

### Request a Package Update

Open a GitHub Issue with the `modify-package` label. Alternatively, updates are also automatically detected by the `check-updates` workflow via `pkgctl version check`.

## Development

### Branch Naming

- Feature branches: `feat/<description>`
- Bug fixes: `fix/<description>`
- CI changes: `ci/<description>`

### Commit Style

```text
<type>(<scope>): <description>

- feat: new feature
- fix: bug fix
- ci: CI/CD changes
- docs: documentation
- refactor: code restructuring
```

### PR Process

1. AI agent creates PR from a labeled issue
2. `opencode-review` runs structured PKGBUILD checks:
   - Critical: syntax, required fields, sha256sums, arch, CFLAGS, MAKEFLAGS, tests disabled
   - Quality: namcap warnings, pkgdesc, license, README/AGENTS accuracy
3. After approval, the PR is auto-merged on CI success

## Local Setup

```bash
git clone https://github.com/dryamovvv/pkgs.git
cd pkgs
```

For building packages locally, you need an Arch Linux ARM environment (see `ci/build-package.sh` for the containerized approach).
