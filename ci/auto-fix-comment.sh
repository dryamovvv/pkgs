#!/bin/bash
set -euo pipefail

ISSUE_NUMBER="${1:?Usage: auto-fix-comment.sh <issue_number> <attempt> <repo> <run_url>}"
ATTEMPT="${2:?}"
REPO="${3:?}"
RUN_URL="${4:?}"

if [ -z "$ISSUE_NUMBER" ]; then
  echo "No issue number, skipping comment"
  exit 0
fi

gh issue comment "$ISSUE_NUMBER" --repo "${REPO}" --body "$(
  cat <<EOF
🔄 **Auto-fix attempt ${ATTEMPT}/3 was triggered.** Results will be visible in the next build run.

Build run: ${RUN_URL}
EOF
)" || true
