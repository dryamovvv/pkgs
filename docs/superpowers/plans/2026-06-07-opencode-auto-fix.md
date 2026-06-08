# Opencode Auto-Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a package build fails in CI, automatically create a GitHub issue and trigger opencode to read logs, diagnose, fix, and push — up to 3 attempts.

**Architecture:** Dual-trigger: build.yml adds a `report-failure` job that creates/updates a GitHub issue with failure details and labels (`ci-failure`, `fix-attempt-N`). opencode.yml adds a `workflow_run` trigger + `auto-fix` job that fires when "Build and Deploy" concludes with failure, reads logs via `gh`, fixes the PKGBUILD, and pushes to main.

**Tech Stack:** GitHub Actions (workflow_run, issues API), `gh` CLI, opencode action

---

## Header to

### Task 1: Add `report-failure` job to build.yml

**Files:**

- Modify: `.github/workflows/build.yml` (after line 143, add new job)

- [ ] **Step 1: Add `report-failure` job at the end of build.yml**

Add the following job after the `build` job (after line 143). This job runs when the build matrix fails, finds which packages failed, and creates or updates a GitHub issue with labels tracking the attempt count.

````yaml
  report-failure:
    needs: [detect, build]
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
          REPO="${{ github.repository }}"
          RUN_URL="${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
          COMMIT_SHA="${{ github.sha }}"
          COMMIT_SHORT="$(echo "$COMMIT_SHA" | cut -c1-7)"

          # Collect failed package names from the matrix
          # Using the detect output to get all packages, then checking which failed
          PACKAGES='${{ needs.detect.outputs.matrix }}'

          # For each package in the matrix, check if it failed
          echo "Matrix packages: $PACKAGES"
          FAILED_PKGS=""

          for PKG in $(echo "$PACKAGES" | jq -r '.[]'); do
            # Check if the build job for this package failed
            # We use gh api to check the job status
            JOBS=$(gh api "repos/${REPO}/actions/runs/${{ github.run_id }}/jobs" --jq ".jobs[] | select(.name | test(\"build (.*)${PKG}\")) | .conclusion")
            if echo "$JOBS" | grep -q "failure"; then
              FAILED_PKGS="$FAILED_PKGS $PKG"
            fi
          done

          # If no specific failures detected, use all matrix packages
          if [ -z "$FAILED_PKGS" ]; then
            FAILED_PKGS=$(echo "$PACKAGES" | jq -r '.[]' | tr '\n' ' ')
          fi

          for PKG in $FAILED_PKGS; do
            echo "Processing failure for: $PKG"

            # Search for existing open issue with ci-failure label for this package
            EXISTING=$(gh issue list \
              --repo "${REPO}" \
              --label ci-failure \
              --search "CI Failure: ${PKG}" \
              --state open \
              --json number \
              --jq '.[0].number' 2>/dev/null || echo "")

            # Determine next attempt number
            ATTEMPT=1

            if [ -n "$EXISTING" ]; then
              echo "Found existing issue #${EXISTING} for ${PKG}"

              # Check current attempt by reading labels
              LABELS=$(gh issue view "$EXISTING" --repo "${REPO}" --json labels --jq '.labels[].name')
              echo "Current labels: $LABELS"

              # Find highest attempt number
              for i in 1 2 3; do
                if echo "$LABELS" | grep -q "fix-attempt-${i}"; then
                  ATTEMPT=$((i + 1))
                fi
              done

              # Remove old attempt labels
              for old_label in fix-attempt-1 fix-attempt-2 fix-attempt-3; do
                gh issue edit "$EXISTING" --repo "${REPO}" --remove-label "$old_label" 2>/dev/null || true
              done

              if [ "$ATTEMPT" -gt 3 ]; then
                echo "Attempt limit reached for ${PKG}, marking as unfixable"
                gh issue edit "$EXISTING" --repo "${REPO}" --add-label "unfixable"
                gh issue comment "$EXISTING" --repo "${REPO}" --body "🚨 **Attempt limit reached** (3/3). Auto-fix is disabled for this package. Manual intervention required.

Run URL: ${RUN_URL}
Commit: ${COMMIT_SHORT}"
                continue
              fi

              # Add comment with new failure details
              gh issue comment "$EXISTING" --repo "${REPO}" --body "🔴 **Build failed again** (attempt ${ATTEMPT}/3)

Run URL: ${RUN_URL}
Commit: ${COMMIT_SHORT}"
            else
              echo "No existing issue for ${PKG}, creating new one"
              EXISTING=$(gh issue create \
                --repo "${REPO}" \
                --title "CI Failure: ${PKG}" \
                --body "## Build Failure: \`${PKG}\`

The automated build for \`${PKG}\` has failed.

- **Package:** \`${PKG}\`
- **Run URL:** ${RUN_URL}
- **Commit:** ${COMMIT_SHORT}
- **Attempt:** 1/3

opencode will attempt to auto-fix this issue." \
                --label "ci-failure" \
                --label "fix-attempt-1" \
                --jq '.number')
            fi

            # Add the new attempt label
            gh issue edit "$EXISTING" --repo "${REPO}" --add-label "fix-attempt-${ATTEMPT}"
          done
```text

- [ ] **Step 2: Verify YAML is valid**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build.yml'))"`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "feat(ci): add report-failure job to create issues on build failures"
```text

---

### Task 2: Add `workflow_run` trigger and `auto-fix` job to opencode.yml

**Files:**

- Modify: `.github/workflows/opencode.yml`

- [ ] **Step 1: Rewrite opencode.yml with new trigger and auto-fix job**

Replace the entire contents of `opencode.yml` with:

```yaml
name: opencode

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
  opencode:
    if: |
      github.event_name == 'issues' ||
      contains(github.event.comment.body, ' /oc') ||
      startsWith(github.event.comment.body, '/oc') ||
      contains(github.event.comment.body, ' /opencode') ||
      startsWith(github.event.comment.body, '/opencode')
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: write
      pull-requests: write
      issues: write
    steps:
      - name: Checkout repository
        uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - name: Run opencode
        uses: anomalyco/opencode/github@latest
        env:
          OPENCODE_API_KEY: ${{ secrets.OPENCODE_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          model: opencode-go/glm-5.1
          share: true
          use_github_token: true
          prompt: ${{ github.event.issue.body || github.event.comment.body }}

  auto-fix:
    if: >
      github.event_name == 'workflow_run' &&
      github.event.workflow_run.conclusion == 'failure'
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: write
      issues: write
    concurrency:
      group: auto-fix-${{ github.ref }}
      cancel-in-progress: false
    steps:
      - name: Checkout repository
        uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - name: Find failure issue and prepare prompt
        id: prepare
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          REPO="${{ github.repository }}"
          RUN_ID="${{ github.event.workflow_run.id }}"
          RUN_URL="${{ github.event.workflow_run.html_url }}"

          echo "Run URL: $RUN_URL"
          echo "Run ID: $RUN_ID"

          # Find open issues with ci-failure label that don't have unfixable
          ISSUE_NUMBER=""
          ATTEMPT=1

          for PKG_CANDIDATE in $(gh api "repos/${REPO}/actions/runs/${RUN_ID}/jobs" --jq '.jobs[] | select(.conclusion == "failure") | .name' 2>/dev/null | grep -oP '(?<=build \(|\b)[a-z0-9_-]+(?=\)|\b)' | sort -u); do
            echo "Checking failure for package: $PKG_CANDIDATE"
            FOUND=$(gh issue list \
              --repo "${REPO}" \
              --label ci-failure \
              --search "CI Failure: ${PKG_CANDIDATE}" \
              --state open \
              --json number,labels \
              --jq '.[] | select(.labels | all(.name != "unfixable")) | .number' \
              2>/dev/null | head -1)
            if [ -n "$FOUND" ]; then
              ISSUE_NUMBER="$FOUND"
              break
            fi
          done

          # Fallback: find any open ci-failure issue without unfixable
          if [ -z "$ISSUE_NUMBER" ]; then
            ISSUE_NUMBER=$(gh issue list \
              --repo "${REPO}" \
              --label ci-failure \
              --state open \
              --json number,labels \
              --jq '.[] | select(.labels | all(.name != "unfixable")) | .number' \
              2>/dev/null | head -1)
          fi

          if [ -z "$ISSUE_NUMBER" ]; then
            echo "No fixable ci-failure issue found. Skipping auto-fix."
            echo "skip=true" >> "$GITHUB_OUTPUT"
            exit 0
          fi

          echo "Found issue #${ISSUE_NUMBER}"

          # Check attempt count from labels
          LABELS=$(gh issue view "$ISSUE_NUMBER" --repo "${REPO}" --json labels --jq '.labels[].name')
          for i in 1 2 3; do
            if echo "$LABELS" | grep -q "fix-attempt-${i}"; then
              ATTEMPT=$i
            fi
          done

          ISSUE_URL="${{ github.server_url }}/${REPO}/issues/${ISSUE_NUMBER}"

          PROMPT="The CI build for one or more packages has failed.

Run URL: ${RUN_URL}
Issue: ${ISSUE_URL}
Attempt: ${ATTEMPT}/3

Steps:
1. Use \`gh run view ${RUN_ID} --log-failed\` to read the failure logs
2. Identify which package(s) failed and why
3. Fix the PKGBUILD or related files in the packages/ directory
4. Commit and push to main with message: fix(ci): auto-fix build failure (attempt ${ATTEMPT})
5. Comment on issue ${ISSUE_NUMBER} with a summary of what was fixed

Important: Only fix the package that failed. Do not modify other packages or CI scripts."

          echo "issue_number=${ISSUE_NUMBER}" >> "$GITHUB_OUTPUT"
          echo "attempt=${ATTEMPT}" >> "$GITHUB_OUTPUT"
          echo "skip=false" >> "$GITHUB_OUTPUT"

          # Save prompt to file since it may be long
          echo "$PROMPT" > /tmp/auto-fix-prompt.txt

      - name: Run opencode auto-fix
        if: steps.prepare.outputs.skip != 'true'
        uses: anomalyco/opencode/github@latest
        env:
          OPENCODE_API_KEY: ${{ secrets.OPENCODE_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          model: opencode-go/glm-5.1
          share: true
          use_github_token: true
          prompt-file: /tmp/auto-fix-prompt.txt

      - name: Comment on issue if fix was attempted
        if: steps.prepare.outputs.skip != 'true' && always()
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          ISSUE_NUMBER="${{ steps.prepare.outputs.issue_number }}"
          ATTEMPT="${{ steps.prepare.outputs.attempt }}"
          REPO="${{ github.repository }}"
          RUN_URL="${{ github.event.workflow_run.html_url }}"

          if [ -z "$ISSUE_NUMBER" ]; then
            echo "No issue number, skipping comment"
            exit 0
          fi

          # Check if this workflow run succeeded
          CONCLUSION="${{ github.event.workflow_run.conclusion }}"
          if [ "$CONCLUSION" = "success" ]; then
            gh issue comment "$ISSUE_NUMBER" --repo "${REPO}" --body "✅ **Auto-fix succeeded** (attempt ${ATTEMPT}/3). Closing this issue." || true
            gh issue close "$ISSUE_NUMBER" --repo "${REPO}" --reason completed || true
          else
            gh issue comment "$ISSUE_NUMBER" --repo "${REPO}" --body "🔄 **Auto-fix attempt ${ATTEMPT}/3 was triggered.** Results will be visible in the next build run.

Build run: ${RUN_URL}" || true
          fi
```text

- [ ] **Step 2: Verify YAML is valid**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/opencode.yml'))"`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/opencode.yml
git commit -m "feat(ci): add auto-fix job triggered by build failures via workflow_run"
```text

---

### Task 3: Create GitHub issue labels

**Files:** No file changes — GitHub API only

- [ ] **Step 1: Create labels in the repository**

Run:

```bash
gh label create ci-failure --color "B60205" --description "CI build failure — auto-fix eligible" --repo dryamovvv/pkgs || true
gh label create fix-attempt-1 --color "FBBC04" --description "Auto-fix attempt 1 of 3" --repo dryamovvv/pkgs || true
gh label create fix-attempt-2 --color "FBBC04" --description "Auto-fix attempt 2 of 3" --repo dryamovvv/pkgs || true
gh label create fix-attempt-3 --color "FBBC04" --description "Auto-fix attempt 3 of 3" --repo dryamovvv/pkgs || true
gh label create unfixable --color "000000" --description "Auto-fix failed after 3 attempts — manual fix needed" --repo dryamovvv/pkgs || true
```text

Expected: Labels created (or already exist)

- [ ] **Step 2: Verify labels exist**

Run: `gh label list --repo dryamovvv/pkgs`
Expected: ci-failure, fix-attempt-1, fix-attempt-2, fix-attempt-3, unfixable visible

---

### Task 4: Push and verify CI triggers

**Files:** No further file changes

- [ ] **Step 1: Push all commits**

```bash
git push origin main
```text

- [ ] **Step 2: Verify both workflow files are valid**

Run: `gh workflow list --repo dryamovvv/pkgs`
Expected: Both "Build and Deploy" and "opencode" workflows visible with valid status

- [ ] **Step 3: Verify `workflow_run` trigger is recognized**

Check that opencode.yml appears in the workflow list with its triggers properly configured. The `workflow_run` trigger should reference "Build and Deploy" by name.

---

## Self-Review Checklist

- [x] Spec coverage: `report-failure` job ✓, `auto-fix` job ✓, `workflow_run` trigger ✓, labels ✓, loop prevention ✓
- [x] No placeholders: All code is complete
- [x] Type consistency: Labels match between report-failure and auto-fix (ci-failure, fix-attempt-N, unfixable)
````
