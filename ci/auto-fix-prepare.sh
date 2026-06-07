#!/bin/bash
set -euo pipefail

REPO="${1:?Usage: auto-fix-prepare.sh <repo> <run_id> <run_url>}"
RUN_ID="${2:?}"
RUN_URL="${3:?}"

ISSUE_NUMBER=""
ATTEMPT=1
SKIP="true"

for PKG_CANDIDATE in $(gh api "repos/${REPO}/actions/runs/${RUN_ID}/jobs" --jq '.jobs[] | select(.conclusion == "failure") | .name' 2>/dev/null | grep -oP '(?<=build \()[\w.-]+(?=\))' | sort -u); do
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
  echo "skip=true" >>"$GITHUB_OUTPUT"
  exit 0
fi

echo "Found issue #${ISSUE_NUMBER}"

LABELS=$(gh issue view "$ISSUE_NUMBER" --repo "${REPO}" --json labels --jq '.labels[].name')
for i in 1 2 3; do
  if echo "$LABELS" | grep -q "fix-attempt-${i}"; then
    ATTEMPT=$i
  fi
done

ISSUE_URL="${GITHUB_SERVER_URL}/${REPO}/issues/${ISSUE_NUMBER}"

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

# Save prompt for opencode action
PROMPT_FILE="${PROMPT_FILE:-/tmp/auto-fix-prompt.txt}"
echo "$PROMPT" >"$PROMPT_FILE"

echo "issue_number=${ISSUE_NUMBER}" >>"$GITHUB_OUTPUT"
echo "attempt=${ATTEMPT}" >>"$GITHUB_OUTPUT"
echo "skip=false" >>"$GITHUB_OUTPUT"
