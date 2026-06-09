# Ideal Pacman Repo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the existing repository to the "ideal" architecture: AI-driven issue pipeline, nvchecker for update detection, proper code review, build retry loop, and notifications.

**Architecture:** Five workflow types: check-updates (nvchecker) → issues → AI agent (opencode on ARM, build retry) → PR → lint + AI review → auto-merge → build → deploy (GitHub Releases). Telegram alerts for critical failures.

**Tech Stack:** GitHub Actions, opencode, nvchecker/pkgctl, Docker, `ubuntu-24.04-arm` runners, Telegram API

---

## Task 1: Update opencode.yml — new-package handler

**Files:**

- Modify: `.github/workflows/opencode.yml`

**Changes:**

- Split `opencode-analysis` job: create `opencode-builder` job for `new-package` and `modify-package` handlers (runs on `ubuntu-24.04-arm` for Docker build capability)
- Update new-package prompt: add feature discovery, build retry (5 attempts), .nvchecker.toml creation, README.md + AGENTS.md per package
- Add build retry loop comments on issue

- [ ] **Step 1: Create `opencode-builder` job (ARM runner)**

Add a new job `opencode-builder` that runs on `ubuntu-24.04-arm` and handles `new-package` and `modify-package` issues:

```yaml
opencode-builder:
  if: |
    (github.event_name == 'issues' &&
     (contains(github.event.issue.labels.*.name, 'new-package') ||
      contains(github.event.issue.labels.*.name, 'modify-package'))) ||
    (github.event_name == 'issue_comment' &&
     !contains(github.event.comment.body, 'opencode[bot]') &&
     (contains(github.event.issue.labels.*.name, 'new-package') ||
      contains(github.event.issue.labels.*.name, 'modify-package')))
  runs-on: ubuntu-24.04-arm
permissions:
  id-token: write
  contents: write
  pull-requests: write
  issues: write
steps:
  - uses: actions/checkout@v6
    with:
      fetch-depth: 0
      persist-credentials: false

  - name: Configure git identity
    run: |
      git config user.name "opencode[bot]"
      git config user.email "opencode[bot]@users.noreply.github.com"

  - name: Clear checkout auth header
    run: |
      git config --local --unset-all http.https://github.com/.extraheader 2>/dev/null || true

  - name: Configure git credentials for push
    run: |
      git config --global credential.helper store
      echo "https://x-access-token:${{ github.token }}@github.com" > ~/.git-credentials
      chmod 600 ~/.git-credentials

  - name: Install uv (for arch-mcp)
    run: |
      curl -LsSf https://astral.sh/uv/install.sh | sh
      echo "$HOME/.local/bin" >> $GITHUB_PATH

  - name: Run opencode (new-package)
    if: contains(github.event.issue.labels.*.name, 'new-package')
    uses: anomalyco/opencode/github@latest
    env:
      OPENCODE_API_KEY: ${{ secrets.OPENCODE_API_KEY }}
      GITHUB_TOKEN: ${{ github.token }}
      CONTEXT7_API_KEY: ${{ secrets.CONTEXT7_API_KEY }}
      EXA_API_KEY: ${{ secrets.EXA_API_KEY }}
    with:
      model: ${{ vars.OPEncode_MODEL || 'opencode/deepseek-v4-flash-free' }}
      share: true
      use_github_token: true
      prompt: |
        You are an Arch Linux package maintainer adding a new package to an aarch64 RPi5-optimized repository.

        Issue title: ${{ github.event.issue.title }}
        Issue body: ${{ github.event.issue.body }}

        ## Research Phase
        1. Use arch-mcp: search_aur("<pkgname>"), get_official_package_info("<pkgname>"), search_archwiki("<pkgname>")
        2. Find upstream: GitHub releases, tags, or download URL from issue/arch-mcp
        3. Use Context7: query the build system docs for available build options
        4. Web search for any missing info

        ## Feature Discovery
        Run upstream's build system introspection:
        - CMake: search CMakeLists.txt for option() and add_feature_info()
        - Meson: read meson_options.txt
        - Cargo: cargo metadata --no-deps --features-list
        - Autotools: ./configure --help

        Enable ALL optional features by default. Disable tests. Enable docs.

        ## PKGBUILD Creation
        Create packages/<name>/PKGBUILD with:
        - ALL optional features enabled
        - Tests disabled: -DBUILD_TESTS=OFF, --disable-tests
        - Docs enabled: -DBUILD_DOCS=ON, --enable-docs
        - Debug stripped: options=(!debug)
        - RPi5 flags: CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe", LDFLAGS="-Wl,-z,max-page-size=0x4000"
        - sha256sums: download source, compute with sha256sum, write into PKGBUILD

        ## nvchecker Setup
        Run pkgctl version setup to create .nvchecker.toml in the package directory.

        ## Documentation
        Create packages/<name>/README.md: description, enabled features, build deps, notes
        Create packages/<name>/AGENTS.md: version tracked, build system, RPi5 flags, enabled options

        ## Build Verification (up to 5 attempts)
        1. Run makepkg -s --noconfirm in Docker
        2. If fail: read error, fix PKGBUILD, retry
        3. Log each attempt in issue comment
        4. After 5 failures: add label "failed", report error, stop

        ## Output
        Branch: add-package/<name>
        Commit: "feat: add <name> <version>"
        PR body: summarize enabled features, build system, notable choices
        Issue comment: PR link + list of enabled features

      - name: Run opencode (issue comment on new-package/modify-package)
        if: |
          github.event_name == 'issue_comment' &&
          !contains(github.event.comment.body, 'opencode[bot]')
        uses: anomalyco/opencode/github@latest
        env:
          OPENCODE_API_KEY: ${{ secrets.OPENCODE_API_KEY }}
          GITHUB_TOKEN: ${{ github.token }}
          CONTEXT7_API_KEY: ${{ secrets.CONTEXT7_API_KEY }}
          EXA_API_KEY: ${{ secrets.EXA_API_KEY }}
        with:
          model: ${{ vars.OPEncode_MODEL || 'opencode/deepseek-v4-flash-free' }}
          share: true
          use_github_token: true
          prompt: |
            A user commented on issue #${{ github.event.issue.number }}:
            Comment: ${{ github.event.comment.body }}
            1. Read FULL issue history via gh issue view <number> --comments
            2. If comment requests changes to a new/modified package (e.g. "disable X"),
               - Find existing branch add-package/<name> or modify-package/<name>
               - Checkout branch, make changes, commit, push
               - Comment confirming changes
            3. If all questions answered, proceed with PKGBUILD creation and PR

      - name: Run opencode (modify-package)
        if: |
          github.event_name == 'issues' &&
          contains(github.event.issue.labels.*.name, 'modify-package')
    uses: anomalyco/opencode/github@latest
    env:
      OPENCODE_API_KEY: ${{ secrets.OPENCODE_API_KEY }}
      GITHUB_TOKEN: ${{ github.token }}
      CONTEXT7_API_KEY: ${{ secrets.CONTEXT7_API_KEY }}
      EXA_API_KEY: ${{ secrets.EXA_API_KEY }}
    with:
      model: ${{ vars.OPEncode_MODEL || 'opencode/deepseek-v4-flash-free' }}
      share: true
      use_github_token: true
      prompt: |
        You are updating an existing package.

        Issue: ${{ github.event.issue.title }}
        Body: ${{ github.event.issue.body }}

        ## Steps
        1. Read current packages/<name>/PKGBUILD, README.md, AGENTS.md, .nvchecker.toml
        2. Extract package name and change request
        3. If updating version:
           a. Run pkgctl version upgrade <name> in the package directory
           b. This uses nvchecker + .nvchecker.toml to detect latest version
           c. Updates pkgver, resets pkgrel to 1, updates checksums
        4. If changing features:
           a. Re-run feature discovery (Context7 on build system)
           b. Update options in PKGBUILD
           c. Update README.md and AGENTS.md feature tables
        5. Build verification (up to 5 attempts, same as new-package flow)
        6. On success: branch modify-package/<name>, PR, comment
        7. On failure: fix and retry up to 5x, then report
```

- [ ] **Step 2: Update `opencode-analysis` job conditions — exclude new-package and modify-package**

Update the job condition and also the issue_comment handler to exclude labels handled by builder:

**Job condition:**

```yaml
opencode-analysis:
  if: |
    github.event_name != 'workflow_dispatch' &&
    github.event_name != 'pull_request' &&
    !contains(github.event.issue.labels.*.name || '', 'ci-failure') &&
    !contains(github.event.issue.labels.*.name || '', 'new-package') &&
    !contains(github.event.issue.labels.*.name || '', 'modify-package')
```

**Issue comment step condition** (the `Run opencode (issue comment — generic)` step):

```yaml
- name: Run opencode (issue comment — generic)
  if: |
    github.event_name == 'issue_comment' &&
    !contains(github.event.comment.body, 'opencode[bot]') &&
    !contains(github.event.issue.labels.*.name, 'new-package') &&
    !contains(github.event.issue.labels.*.name, 'modify-package') &&
    !contains(github.event.issue.labels.*.name, 'ci-failure')
```

**Remove** the `Run opencode (new-package comment)` step from opencode-analysis — it's now in opencode-builder.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/opencode.yml
git commit -m "feat(ci): add opencode-builder job with ARM runner and build retry"
```

---

## Task 2: Update opencode.yml — code-review job

**Files:**

- Modify: `.github/workflows/opencode.yml`

**Changes:**

- Replace auto-approve with structured review prompt
- Add critical/quality checklists
- Implement review loop (review → request changes → agent fixes → re-review)

- [ ] **Step 1: Replace code-review prompt with structured checklist**

In the `opencode-review` job, replace the "Auto-approve AI-generated PRs" step and the "Run opencode PR review" step with:

```yaml
- name: Run opencode PR review
  uses: anomalyco/opencode/github@latest
  env:
    OPENCODE_API_KEY: ${{ secrets.OPENCODE_API_KEY }}
    GITHUB_TOKEN: ${{ github.token }}
    BRANCH: ${{ github.event.pull_request.head.ref }}
  with:
    model: ${{ vars.OPEncode_MODEL_REVIEW || vars.OPEncode_MODEL || 'opencode/deepseek-v4-flash-free' }}
    share: true
    use_github_token: true
    prompt: |
      You are reviewing an Arch Linux PKGBUILD PR. Quality standards:

      ## Critical checks (fail = request changes)
      1. PKGBUILD syntax: bash -n must pass
      2. Required fields: pkgname, pkgver, pkgrel, pkgdesc, arch, url, license, depends, source, sha256sums
      3. sha256sums correct (not empty, not placeholder)
      4. Architecture: must include aarch64 (not x86_64 only)
      5. RPi5 flags: CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe", LDFLAGS="-Wl,-z,max-page-size=0x4000"
      6. Tests disabled: BUILD_TESTING=OFF, --disable-tests, etc.
      7. No absolute paths in source=()
      8. .nvchecker.toml present alongside PKGBUILD

      ## Quality checks (warn but don't block)
      1. namcap warnings on PKGBUILD
      2. pkgdesc is descriptive (>10 chars)
      3. License file included in package()
      4. README.md and AGENTS.md present with accurate content

      ## Review flow
      1. gh pr diff <number> — read the full diff
      2. Check each critical item
      3. If any critical fails: gh pr review --request-changes with specific line refs
      4. If only quality warnings: gh pr review --comment with suggestions
      5. If all clear: gh pr review --approve
      6. Comment summary of what was checked

      If this is a re-review (PR was updated after previous review), only check items that were flagged before.
```

Remove the "Auto-approve AI-generated PRs" step entirely — approval now comes from the structured review.

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/opencode.yml
git commit -m "feat(ci): add structured PKGBUILD review with critical checks"
```

---

## Task 3: Replace check-updates.sh with pkgctl version check

**Files:**

- Modify: `.github/workflows/check-updates.yml`
- Modify: `ci/check-updates.sh`
- Delete: `ci/check-updates.sh` (or replace content)

- [ ] **Step 1: Restore check-updates.yml to install devtools + use pkgctl**

```yaml
name: Check upstream updates

on:
  schedule:
    - cron: "0 */4 * * *"
  workflow_dispatch:

permissions:
  contents: read
  issues: write

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Install devtools (pkgctl + nvchecker)
        run: |
          sudo apt-get update -y
          sudo apt-get install -y devtools python3-pip
          # nvchecker comes with devtools on Arch, but we're on Ubuntu
          # Pull arch container to run pkgctl
          docker pull lfdevs/archlinuxarm:base-devel

      - name: Check for updates via pkgctl
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          chmod +x ci/check-updates.sh
          bash ci/check-updates.sh
```

- [ ] **Step 2: Rewrite ci/check-updates.sh to use pkgctl**

```bash
#!/bin/bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-dryamovvv/pkgs}"

echo "=== Checking upstream updates via pkgctl ==="

WORKDIR=$(mktemp -d /tmp/pkgctl-check-XXXXXX)
trap 'rm -rf "$WORKDIR"' EXIT

for pkgdir in packages/*/; do
  pkg=$(basename "$pkgdir")
  pkgbuild="$pkgdir/PKGBUILD"
  [ -f "$pkgbuild" ] || continue

  nvchecker_file="$pkgdir/.nvchecker.toml"

  # If no .nvchecker.toml, auto-generate it via pkgctl version setup
  if [ ! -f "$nvchecker_file" ]; then
    echo "SETUP $pkg: no .nvchecker.toml, generating..."
    cp -r "$pkgdir" "$WORKDIR/$pkg"
    docker run --rm -v "$WORKDIR/$pkg:/workspace" lfdevs/archlinuxarm:base-devel \
      bash -c "cd /workspace && pkgctl version setup" 2>/dev/null || true
    if [ -f "$WORKDIR/$pkg/.nvchecker.toml" ]; then
      cp "$WORKDIR/$pkg/.nvchecker.toml" "$pkgdir/"
      echo "GENERATED $pkg: .nvchecker.toml created"
    else
      echo "SKIP $pkg: could not generate .nvchecker.toml"
      continue
    fi
  fi

  # Run pkgctl version check inside arch container
  cp -r "$pkgdir" "$WORKDIR/$pkg"
  result=$(docker run --rm -v "$WORKDIR/$pkg:/workspace" lfdevs/archlinuxarm:base-devel \
    bash -c "cd /workspace && pkgctl version check 2>&1" || true)

  current_ver=$(grep -oP '^pkgver=\K.*' "$pkgbuild" | head -1)

  # Parse pkgctl output for new version
  # Output format: "pkgname: <current> -> <latest>" or "pkgname: up to date"
  new_ver=$(echo "$result" | grep -oP "${pkg}:\s+\S+\s+->\s+\K\S+" || true)

  if [ -z "$new_ver" ]; then
    echo "OK   $pkg: $current_ver (up to date)"
    continue
  fi

  # Check for existing issue
  existing=$(gh issue list --repo "$REPO" --label modify-package \
    --search "Update ${pkg}" --state open --json number --jq '.[0].number' 2>/dev/null) || existing=""

  if [ -n "$existing" ]; then
    echo "SKIP $pkg: issue #${existing} already open ($current_ver → $new_ver)"
  else
    echo "NEW  $pkg: $current_ver → $new_ver"
    gh issue create --repo "$REPO" \
      --title "Update $pkg $current_ver → $new_ver" \
      --label modify-package \
      --body "**Package:** $pkg
**Current version:** $current_ver
**New version:** $new_ver
**Source:** \`$(grep -oP '^source=\(["'\'']?\K[^"'\'' )]+' "$pkgbuild" | head -1)\`"
  fi
done

echo "=== Done ==="
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/check-updates.yml ci/check-updates.sh
git commit -m "feat(ci): replace update check with pkgctl version (nvchecker)"
```

---

## Task 4: Update lint.yml — add namcap PKGBUILD check

**Files:**

- Modify: `.github/workflows/lint.yml`

- [ ] **Step 1: Add namcap step after shellcheck**

Add after the "ShellCheck" step:

```yaml
- name: Install namcap
  run: |
    # namcap is an Arch Linux tool; run in container
    docker pull lfdevs/archlinuxarm:base-devel

- name: Run namcap on changed PKGBUILDs
  run: |
    for f in $(echo "${{ steps.files.outputs.changed }}" | tr ' ' '\n' | grep 'PKGBUILD$'); do
      [ -f "$f" ] || continue
      dir=$(dirname "$f")
      echo "::group::namcap $f"
      docker run --rm -v "$(pwd)/$dir:/workspace" lfdevs/archlinuxarm:base-devel \
        bash -c "cd /workspace && namcap PKGBUILD 2>&1" || true
      echo "::endgroup::"
    done
```

- [ ] **Step 2: Add sha256sums validation step**

```yaml
- name: Validate sha256sums in PKGBUILDs
  run: |
    for f in $(echo "${{ steps.files.outputs.changed }}" | tr ' ' '\n' | grep 'PKGBUILD$'); do
      [ -f "$f" ] || continue
      echo "::group::sha256sums check $f"
      # Check that sha256sums array is not empty
      if grep -q '^sha256sums=' "$f"; then
        sums_line=$(grep '^sha256sums=' "$f")
        if echo "$sums_line" | grep -qP 'SKIP|\(\s*\)'; then
          echo "::warning::sha256sums is SKIP or empty in $f"
        else
          echo "sha256sums present in $f"
        fi
      else
        echo "::error::Missing sha256sums in $f"
      fi
      echo "::endgroup::"
    done
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/lint.yml
git commit -m "feat(ci): add namcap and sha256sums validation to lint"
```

---

## Task 5: Add Telegram notifications to critical workflows

**Files:**

- Modify: `.github/workflows/opencode.yml`
- Modify: `.github/workflows/build.yml`
- Modify: `.github/workflows/check-updates.yml`

**Add Telegram notification step to each critical workflow on failure:**

- [ ] **Step 1: Add Telegram notification to opencode.yml (opencode-builder job)**

Add as the last step in the `opencode-builder` job:

```yaml
- name: Notify admin on critical failure
  if: failure() && env.TELEGRAM_BOT_TOKEN != ''
  uses: appleboy/telegram-action@master
  with:
    to: ${{ secrets.TELEGRAM_CHAT_ID }}
    token: ${{ secrets.TELEGRAM_BOT_TOKEN }}
    message: |
      ❌ AI Agent failed: ${{ github.event.issue.title }}
      Repo: ${{ github.repository }}
      Label: ${{ join(github.event.issue.labels.*.name, ', ') }}
      Run: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
```

- [ ] **Step 2: Add Telegram notification to build.yml (deploy job)**

Add to the `deploy-packages` job:

```yaml
- name: Notify admin on deploy failure
  if: failure() && env.TELEGRAM_BOT_TOKEN != ''
  uses: appleboy/telegram-action@master
  with:
    to: ${{ secrets.TELEGRAM_CHAT_ID }}
    token: ${{ secrets.TELEGRAM_BOT_TOKEN }}
    message: |
      ❌ Build/Deploy failed: ${{ github.repository }}
      Run: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/opencode.yml .github/workflows/build.yml
git commit -m "feat(ci): add Telegram notifications for critical failures"
```

---

## Task 6: Ensure all secrets and vars are documented

**Files:**

- Modify: `README.md`

- [ ] **Step 1: Add required secrets section to README**

```markdown
## Required GitHub Secrets

| Secret               | Description                                       |
| -------------------- | ------------------------------------------------- |
| `GPG_PRIVATE_KEY`    | ASCII-armored GPG private key for package signing |
| `GPG_PASSPHRASE`     | Passphrase for the GPG key                        |
| `GPG_KEY_ID`         | GPG key fingerprint                               |
| `OPENCODE_API_KEY`   | API key for opencode AI agent                     |
| `CONTEXT7_API_KEY`   | API key for Context7 library docs                 |
| `EXA_API_KEY`        | API key for Exa web search                        |
| `TELEGRAM_BOT_TOKEN` | (Optional) Telegram bot token for notifications   |
| `TELEGRAM_CHAT_ID`   | (Optional) Telegram chat ID for notifications     |

## Required GitHub Variables

| Variable         | Description                                                                   |
| ---------------- | ----------------------------------------------------------------------------- |
| `OPEncode_MODEL` | (Optional) LLM model for opencode, default: `opencode/deepseek-v4-flash-free` |
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add required secrets and vars documentation"
```
