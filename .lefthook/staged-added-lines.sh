#!/usr/bin/env bash
# Prints every ADDED line of the index as "file:line: content".
# Shared by the pre-commit guards so the diff walking lives in one place.
#
# Argument 1: extended regex of file paths to skip (lockfiles, minified assets).
# Env INCLUDE_UNSTAGED=1 also scans unstaged changes (for `git commit -a`).
set -uo pipefail
exclude="${1:-}"

diff=$(git diff --cached -U0 --diff-filter=AM 2>/dev/null || true)
if [ "${INCLUDE_UNSTAGED:-0}" = "1" ]; then
  diff+=$'\n'$(git diff -U0 --diff-filter=AM 2>/dev/null || true)
fi
[ -z "$diff" ] && exit 0

# Track "+++ b/<file>" and "@@ +N" hunk headers so each added line gets its
# post-commit line number.
printf '%s\n' "$diff" | awk -v exclude="$exclude" '
  /^diff --git/ { file=""; skip=1; next }
  /^\+\+\+ /    { file=substr($0, 5); sub(/^b\//, "", file); skip=(exclude != "" && file ~ exclude); next }
  /^@@/         { if (match($0, /\+[0-9]+/)) line=substr($0, RSTART+1, RLENGTH-1)+0; next }
  /^\+/         { if (file != "" && !skip) print file ":" line ": " substr($0, 2); line++; next }
'
