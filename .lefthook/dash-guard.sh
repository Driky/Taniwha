#!/usr/bin/env bash
# pre-commit hook: block the commit when staged ADDED lines contain an em dash
# (U+2014) or en dash (U+2013). Typographic dashes read as machine-generated
# copy; restructure the sentence instead of swapping the dash for "-" or ";".
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
here="$root/.lefthook"

# Generated or vendored files only. Docs and UI strings are in scope.
exclude='(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|uv\.lock|Cargo\.lock|go\.sum)$|\.lock$|\.min\.[a-z]+$|\.snap$'

hits=$(cd "$root" && "$here/staged-added-lines.sh" "$exclude" \
  | perl -CSD -ne 'print if /[\x{2014}\x{2013}]/' | head -20 || true)
[ -z "$hits" ] && exit 0

{
  echo "BLOCKED: staged changes contain an em dash or en dash."
  echo "Restructure the sentence (two sentences, a colon, parentheses) rather than substituting '-' or ';'."
  echo "Hits (first 20):"
  printf '%s\n' "$hits" | sed 's/^/  /'
} >&2
exit 1
