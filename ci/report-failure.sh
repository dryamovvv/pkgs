#!/bin/bash
set -euo pipefail

REPO="${1:?Usage: report-failure.sh <repo> <run_url> <commit_sha> <run_id> <packages_json>}"
RUN_URL="${2:?}"
COMMIT_SHA="${3:?}"
RUN_ID="${4:?}"
PACKAGES_JSON="${5:-[]}"

COMMIT_SHORT="$(echo "$COMMIT_SHA" | cut -c1-7)"

FAILED_PKGS=""
JOBS_JSON=$(gh api "repos/${REPO}/actions/runs/${RUN_ID}/jobs" --jq '.jobs[] | select(.conclusion == "failure") | .name' 2>/dev/null || echo "")

if [ -n "$JOBS_JSON" ]; then
  FAILED_PKGS=$(echo "$JOBS_JSON" | grep -oP '(?<=build \()[\w.-]+(?=\))' | sort -u)
fi

if [ -z "$FAILED_PKGS" ]; then
  FAILED_PKGS=$(echo "$PACKAGES_JSON" | jq -r '.[]' | tr '\n' ' ')
fi

for PKG in $FAILED_PKGS; do
  echo "Processing failure for: $PKG"

  EXISTING=$(gh issue list \
    --repo "${REPO}" \
    --label ci-failure \
    --search "CI Failure: ${PKG} in:title" \
    --state open \
    --json number \
    --jq '.[0].number' 2>/dev/null || echo "")

  ATTEMPT=1

  if [ -n "$EXISTING" ]; then
    echo "Found existing issue #${EXISTING} for ${PKG}"

    LABELS=$(gh issue view "$EXISTING" --repo "${REPO}" --json labels --jq '.labels[].name')

    MAX_ATTEMPT=0
    for i in 1 2 3; do
      if echo "$LABELS" | grep -q "fix-attempt-${i}"; then
        if [ "$i" -gt "$MAX_ATTEMPT" ]; then
          MAX_ATTEMPT=$i
        fi
      fi
    done
    ATTEMPT=$((MAX_ATTEMPT + 1))

    for old_label in fix-attempt-1 fix-attempt-2 fix-attempt-3; do
      gh issue edit "$EXISTING" --repo "${REPO}" --remove-label "$old_label" 2>/dev/null || true
    done

    if [ "$ATTEMPT" -gt 3 ]; then
      echo "Attempt limit reached for ${PKG}, marking as unfixable"
      gh issue edit "$EXISTING" --repo "${REPO}" --add-label "unfixable"
      gh issue comment "$EXISTING" --repo "${REPO}" --body "$(
        cat <<EOF
Attempt limit reached (3/3). Auto-fix is disabled for this package. Manual intervention required.

Run URL: ${RUN_URL}
Commit: ${COMMIT_SHORT}
EOF
      )"
      continue
    fi

    gh issue comment "$EXISTING" --repo "${REPO}" --body "$(
      cat <<EOF
Build failed again (attempt ${ATTEMPT}/3)

Run URL: ${RUN_URL}
Commit: ${COMMIT_SHORT}
EOF
    )"
  else
    echo "No existing issue for ${PKG}, creating new one"
    ISSUE_URL=$(gh issue create \
      --repo "${REPO}" \
      --title "CI Failure: ${PKG}" \
      --body "$(
        cat <<EOF
## Build Failure: \`${PKG}\`

The automated build for \`${PKG}\` has failed.

- **Package:** \`${PKG}\`
- **Run URL:** ${RUN_URL}
- **Commit:** ${COMMIT_SHORT}
- **Attempt:** 1/3

opencode will attempt to auto-fix this issue.
EOF
      )" \
      --label "ci-failure" \
      --label "fix-attempt-1")
    EXISTING=$(echo "$ISSUE_URL" | grep -oP '\d+$')
  fi

  gh issue edit "$EXISTING" --repo "${REPO}" --add-label "fix-attempt-${ATTEMPT}"

  echo "Triggering auto-fix workflow for issue #${EXISTING}, attempt ${ATTEMPT}"
  gh workflow run opencode.yml \
    --repo "${REPO}" \
    --ref main \
    -f issue-number="${EXISTING}" \
    -f attempt="${ATTEMPT}" \
    -f run-url="${RUN_URL}" || echo "Warning: Failed to trigger auto-fix workflow"
done
