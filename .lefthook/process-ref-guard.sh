#!/usr/bin/env bash
# pre-commit hook: block the commit when staged ADDED lines contain process
# references (acceptance-criteria numbers, story or ticket IDs, decision-log
# numbers). Source should explain the why in plain words; the tracker holds
# the process metadata.
#
# Patterns: .lefthook/process-ref-patterns.txt, one extended regex per line.
# Only file content is scanned, never the commit message or branch name.
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
here="$root/.lefthook"
patterns_file="$here/process-ref-patterns.txt"
[ -f "$patterns_file" ] || exit 0
patterns=$(grep -Ev '^[[:space:]]*(#|$)' "$patterns_file" | paste -sd'|' -)
[ -z "$patterns" ] && exit 0

# Generated or vendored files, and prose docs that may legitimately cite tickets.
exclude='(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|uv\.lock|Cargo\.lock|go\.sum)$|\.lock$|\.min\.[a-z]+$|\.snap$|\.md$'

hits=$(cd "$root" && "$here/staged-added-lines.sh" "$exclude" | grep -E "$patterns" | head -20 || true)
[ -z "$hits" ] && exit 0

{
  echo "BLOCKED: staged changes contain process references (ticket, AC, or story IDs) banned from source."
  echo "Reword them to state intent, re-stage, and commit again."
  echo "Patterns file: .lefthook/process-ref-patterns.txt"
  echo "Hits (first 20):"
  printf '%s\n' "$hits" | sed 's/^/  /'
} >&2
exit 1
