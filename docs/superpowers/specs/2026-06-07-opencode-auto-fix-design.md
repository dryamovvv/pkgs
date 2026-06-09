# Auto-fix CI Failures with Opencode

## Problem

When a package build fails in CI, someone has to manually investigate logs, identify the issue, fix the PKGBUILD, and push. This can take hours.

## Solution

Automate CI failure recovery: when a build fails, opencode is triggered to read the failure logs, diagnose the issue, fix the PKGBUILD (or related files), and push the fix to main.

## Architecture

### Trigger: Dual-path

1. **Issue creation** (visibility) — build.yml `report-failure` job creates/updates a GitHub issue with failure details
2. **workflow_run** (speed) — opencode.yml triggers on `workflow_run` event when "Build and Deploy" completes with failure

### Flow

```text
build.yml fails
  ├─ report-failure job ──► creates/updates GitHub issue (labels: ci-failure, fix-attempt-N)
  └─ workflow_run event ──► opencode.yml auto-fix job triggers
                              │
                              ├─ reads CI logs (gh run view)
                              ├─ finds corresponding issue
                              ├─ checks attempt count (labels)
                              ├─ if attempt < 3: fix + push to main
                              └─ if attempt >= 3: comment "unfixable" on issue
                                  │
main push ──► build.yml triggers again
  ├─ success ──► opencode comments "Fixed!" ──► issue closed
  └─ failure ──► report-failure increments attempt ──► repeat (up to 3)
      └─ attempt 3 failed ──► label "unfixable" ──► STOP
```text

## Components

### 1. build.yml: `report-failure` job

Added after the build matrix job:

```yaml
report-failure:
  needs: detect, build
  if: failure()
  runs-on: ubuntu-latest
  permissions:
    issues: write
  steps:
    - uses: actions/checkout@v6
    - name: Create or update failure issue
      env:
        GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      run: |
        FAILED_PKG="${{ needs.detect.outputs.matrix }}"
        # Simplified: uses first package in matrix
        # Real implementation: iterates failed jobs

        RUN_URL="${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
        COMMIT_SHA="${{ github.sha }}"

        # Check for existing open issue with ci-failure label for this package
        EXISTING=$(gh issue list --label ci-failure --search "CI Failure: ${FAILED_PKG}" --json number --jq '.[0].number' 2>/dev/null || echo "")

        if [ -n "$EXISTING" ]; then
          # Increment attempt by checking labels
          # Add comment with new failure details
          # If attempt >= 3, add unfixable label
        else
          # Create new issue
          # Labels: ci-failure, fix-attempt-1
        fi
```text

Key behaviors:

- Creates a new issue on first failure for a package
- On subsequent failures: comments on existing issue, increments attempt label
- After 3 attempts: adds `unfixable` label, does NOT trigger auto-fix
- Includes: package name, run URL, commit SHA, short error context

### 2. opencode.yml: `auto-fix` job

Added as a new job triggered by `workflow_run`:

```yaml
on:
  issues:
    types: [opened, edited]
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  workflow_run:
    workflows: ["Build and Deploy"]
    types: [completed]
    branches: [main]

jobs:
  # ... existing opencode job ...

  auto-fix:
    if: >
      github.event_name == 'workflow_run' &&
      github.event.workflow_run.conclusion == 'failure'
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: write
      issues: write
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - name: Find failure issue
        id: find-issue
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          # Find the issue created by report-failure for this run
          # Check it doesn't have unfixable label
          # Check attempt count < 3
          # Set issue number and prompt as outputs

      - name: Run opencode auto-fix
        uses: anomalyco/opencode/github@latest
        env:
          OPENCODE_API_KEY: ${{ secrets.OPENCODE_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          model: opencode-go/glm-5.1
          share: true
          use_github_token: true
          prompt: |
            The CI build for package(s) failed.
            Run URL: ${{ github.event.workflow_run.html_url }}
            Issue: ${{ steps.find-issue.outputs.issue_url }}

            Steps:
            1. Use `gh run view <run-id> --log-failed` to read the failure logs
            2. Identify which package(s) failed and why
            3. Fix the PKGBUILD or related files
            4. Commit and push to main with message "fix(ci): auto-fix <pkg> build failure"
            5. Comment on the issue with what was fixed
```text

### 3. Loop prevention

- **Attempt labels**: `fix-attempt-1`, `fix-attempt-2`, `fix-attempt-3`, `unfixable`
- **auto-fix job check**: Only runs if corresponding issue exists AND does NOT have `unfixable` label AND attempt < 3
- **Actor check**: `github.actor` check to prevent running on github-actions[bot] pushes (alternatively, skip if commit message starts with `fix(ci): auto-fix`)
- **Concurrency**: `concurrency: auto-fix-${{ github.ref }}` to prevent parallel auto-fix runs

### 4. Success handling

When opencode pushes a fix and the subsequent build succeeds:

- The `report-failure` job does NOT run (build succeeded)
- The next workflow_run event has `conclusion: success`
- opencode's commit comment or a separate `on-success` workflow handles closing the issue

A simpler approach: opencode comments on the issue when pushing. The user or a periodic check can close resolved issues. Alternatively, add a `close-on-success` workflow.

### 5. Design decisions

| Decision         | Choice                     | Rationale                            |
| ---------------- | -------------------------- | ------------------------------------ |
| Fix delivery     | Push to main               | User preference for speed            |
| Max attempts     | 3                          | Balance between persistence and cost |
| Trigger          | Both issue + workflow_run  | Visibility + speed                   |
| Attempt tracking | Issue labels               | Simple, visible in GitHub UI         |
| Loop prevention  | Label checks + actor check | Prevents infinite retry loops        |

## Implementation checklist

- [ ] Add `report-failure` job to build.yml
- [ ] Add `auto-fix` job to opencode.yml
- [ ] Add `workflow_run` trigger to opencode.yml
- [ ] Create issue labels: `ci-failure`, `fix-attempt-1/2/3`, `unfixable`
- [ ] Add loop prevention (label checks, actor checks)
- [ ] Test with a deliberately broken PKGBUILD
