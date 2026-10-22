#!/usr/bin/env bash
# Prints every ADDED line of the index as "file:line: content".
# Shared by the pre-commit guards so the diff walking lives in one place.
#
# Argument 1: extended regex of file paths to skip (lockfiles, minified assets).
# Env INCLUDE_UNSTAGED=1 also scans unstaged changes (for `git commit -a`).
set -uo pipefail
exclude="${1:-}"

# core.quotePath=false keeps non-ASCII paths readable instead of C-quoted.
diff=$(git -c core.quotePath=false diff --cached -U0 --diff-filter=d 2>/dev/null || true)
if [ "${INCLUDE_UNSTAGED:-0}" = "1" ]; then
  diff+=$'\n'$(git -c core.quotePath=false diff -U0 --diff-filter=d 2>/dev/null || true)
fi
[ -z "$diff" ] && exit 0

# Track "+++ b/<file>" and "@@ +N" hunk headers so each added line gets its
# post-commit line number. File headers only occur between "diff --git" and
# the first "@@", so an added line whose content starts with "++ " is not
# mistaken for one. Git appends a tab to the header path when it contains a
# space, so that tab is stripped.
printf '%s\n' "$diff" | awk -v exclude="$exclude" '
  /^diff --git/          { file=""; skip=1; header=1; next }
  header && /^\+\+\+ /   { file=substr($0, 5); sub(/^b\//, "", file); sub(/\t$/, "", file); skip=(exclude != "" && file ~ exclude); next }
  /^@@/                  { header=0; if (match($0, /\+[0-9]+/)) line=substr($0, RSTART+1, RLENGTH-1)+0; next }
  !header && /^\+/       { if (file != "" && !skip) print file ":" line ": " substr($0, 2); line++; next }
'
