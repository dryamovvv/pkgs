#!/bin/bash
set -euo pipefail

find . -name "*.md" -type f ! -path "./.git/*" ! -path "./node_modules/*" | while read -r file; do
  echo "Processing: $file"

  # Fix bare code blocks (add 'text' language tag)
  perl -i -pe 's/^```$/```text/g' "$file"
done

git add -A
if [ -n "$(git status --porcelain)" ]; then
  git commit -m "fix(lint): add language tags to markdown code blocks"
fi
