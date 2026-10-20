#!/usr/bin/env bash
# Claude Code PreToolUse guard for Bash: before Claude runs `git commit`, run
# the repo's own pre-commit process-reference guard and turn a failure into a
# blocking message the agent can read. The git hook still runs on the commit
# itself; this only gives the agent the explanation up front.
#
# The scan itself lives in .lefthook/process-ref-guard.sh so the two paths
# cannot drift. Only staged file content is checked, never the -m text.
set -uo pipefail
set -f

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || exit 0
[ -z "$cmd" ] && exit 0

case "$cmd" in
  *git*commit*) ;;
  *) exit 0 ;;
esac

resolve_dir() {
  local base="$1" target="$2"
  target="${target%\"}"; target="${target#\"}"
  target="${target%\'}"; target="${target#\'}"
  target="${target/#\~/$HOME}"
  if [[ "$target" == /* ]]; then
    printf '%s' "$target"
  else
    (cd "$base" 2>/dev/null && cd "$target" 2>/dev/null && pwd) || printf '%s/%s' "$base" "$target"
  fi
}

# Find the directory the `git commit` segment runs in: walk the compound
# command tracking cd targets; a `git -C <dir>` on the commit segment wins.
segs="${cmd//&&/$'\n'}"
segs="${segs//\|\|/$'\n'}"
segs="${segs//;/$'\n'}"
segs="${segs//\|/$'\n'}"

dir="$cwd"
repodir=""
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  [ -z "$seg" ] && continue
  if [[ "$seg" =~ ^cd[[:space:]]+([^[:space:]]+) ]]; then
    dir=$(resolve_dir "$dir" "${BASH_REMATCH[1]}")
    continue
  fi
  if [[ "$seg" =~ git([[:space:]]+-C[[:space:]]+([^[:space:]]+))?[[:space:]].*commit ]]; then
    if [ -n "${BASH_REMATCH[2]:-}" ]; then
      repodir=$(resolve_dir "$dir" "${BASH_REMATCH[2]}")
    else
      repodir="$dir"
    fi
    break
  fi
done <<< "$segs"

[ -z "$repodir" ] && exit 0
root=$(git -C "$repodir" rev-parse --show-toplevel 2>/dev/null) || exit 0
guard="$root/.lefthook/process-ref-guard.sh"
[ -x "$guard" ] || exit 0

include_unstaged=0
[[ "$cmd" =~ [[:space:]](-a|--all)([[:space:]]|$) ]] && include_unstaged=1

out=$(cd "$root" && INCLUDE_UNSTAGED=$include_unstaged "$guard" 2>&1) && exit 0

jq -n --arg out "$out" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $out
  }
}'
exit 0
