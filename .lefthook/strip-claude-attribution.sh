#!/bin/sh
# commit-msg hook: strip Claude authoring attribution from the message.
# Removes any "Co-Authored-By: Claude ..." trailer and any
# "Generated with Claude Code" line, plus the blank line preceding them.
# Argument: path to the commit message file (passed by git, forwarded by lefthook).
[ -n "${1:-}" ] && [ -f "$1" ] || exit 0
perl -0pi -e '
  s/\n*^Co-Authored-By:[ \t]*Claude[^\n]*$//gim;
  s/\n*^(?:[^\x00-\x7F]+[ \t]*)?Generated with \[?Claude Code\]?[^\n]*$//gim;
' "$1"
