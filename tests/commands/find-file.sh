#!/bin/bash
# Tests for mbm-find-file.   Run:  tests/run.sh find-file    or:  bash tests/commands/find-file.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-find-file"
echo "mbm-find-file"

W="$TMP/w"
QNAME="it's \"quoted\".txt"
mkdir -p "$W/docs/My Notes" "$W/src/node_modules" "$W/-dash" "$W/empty" "$W/locked"
cd "$W" || exit 1
: > docs/notes.txt
: > "docs/My Notes/Meeting NOTES.md"
: > docs/REPORT.PDF
: > src/report.pdf
: > src/Makefile
: > src/Makefile.am
: > "Invoice 2024.pdf"
: > "-dash/$QNAME"
: > docs/FILE.GIF
: > locked/notes.txt
ln -s docs link

# sorted - the lines of OUT in a fixed order (find lists in the order of the disk)
sorted() { printf '%s\n' "$OUT" | LC_ALL=C sort; }
lines() { printf '%s\n' "$@"; }

# ---- the main job
chmod 000 locked
run "$CMD" notes
check "a part of the name, any case, files and folders, from the current folder" \
  "$(lines "./docs/My Notes" "./docs/My Notes/Meeting NOTES.md" "./docs/notes.txt")" "$(sorted)"
check "found: exit 0" "0" "$RC"
check "a folder that may not be read gives no message" "" "$ERR"
chmod 755 locked

run "$CMD" docs notes.txt
check "the old form, START NAME, finds what it found" "docs/notes.txt" "$OUT"
run "$CMD" docs/ notes.txt
check "a trailing slash on START does not change the paths" "docs/notes.txt" "$OUT"

run "$CMD" . '*.pdf'
check "a wildcard matches the whole name, in any case" \
  "$(lines "./Invoice 2024.pdf" "./docs/REPORT.PDF" "./src/report.pdf")" "$(sorted)"
run "$CMD" . 'make????'
check "? is a wildcard too" "./src/Makefile" "$OUT"
run "$CMD" . '[mn]otes.txt'
check "[ ] is a wildcard too" "$(lines "./docs/notes.txt" "./locked/notes.txt")" "$(sorted)"

# ---- the options
run "$CMD" -e . report.pdf
check "-e: the exact name in exactly this case" "./src/report.pdf" "$OUT"
run "$CMD" --exact . Makefile
check "--exact: the whole name, not a part" "./src/Makefile" "$OUT"
run "$CMD" -e . makefile
check "-e: another case is not found, exit 1" "1" "$RC"
run "$CMD" -f notes
check "-f: files only" "$(lines "./docs/My Notes/Meeting NOTES.md" "./docs/notes.txt" "./locked/notes.txt")" "$(sorted)"
run "$CMD" --files notes
check "--files: the same" "$(lines "./docs/My Notes/Meeting NOTES.md" "./docs/notes.txt" "./locked/notes.txt")" "$(sorted)"
run "$CMD" -d notes
check "-d: folders only" "./docs/My Notes" "$OUT"
run "$CMD" --dirs . 'node*'
check "--dirs with a wildcard" "./src/node_modules" "$OUT"
run "$CMD" -f -d notes
check "-f with -d: exit 2" "2" "$RC"

# ---- awkward names
run "$CMD" "it's"
check "a quote character in the name" "./-dash/$QNAME" "$OUT"
run "$CMD" '"quoted"'
check "a double quote in the pattern" "./-dash/$QNAME" "$OUT"
run "$CMD" "my notes"
check "a space in the pattern" "$(lines "./docs/My Notes")" "$OUT"
run "$CMD" -- -dash quoted
check "START that starts with a dash, after --" "./-dash/$QNAME" "$OUT"
run "$CMD" -- -das
check "PATTERN that starts with a dash, after --" "./-dash" "$OUT"
run "$CMD" -dash quoted
check "without --, it is an unknown option: exit 2" "2" "$RC"
run "$CMD" link notes.txt
check "START that is a link to a folder is searched" "link/notes.txt" "$OUT"

# ---- the language of the user (Turkish: I and i are different letters there)
if locale -a 2>/dev/null | grep -qx 'tr_TR.UTF-8'; then
  run env LC_ALL=tr_TR.UTF-8 "$CMD" . file.gif
  check "Turkish locale: file.gif finds FILE.GIF" "./docs/FILE.GIF" "$OUT"
  run env LC_ALL=tr_TR.UTF-8 "$CMD" -f . invoice
  check "Turkish locale: invoice finds Invoice" "./Invoice 2024.pdf" "$OUT"
  : > "$W/docs/ŞİRKET raporu.txt"
  run env LC_ALL=tr_TR.UTF-8 "$CMD" . şirket
  check "Turkish locale: letters outside A-Z are folded too" "./docs/ŞİRKET raporu.txt" "$OUT"
  rm -f "$W/docs/ŞİRKET raporu.txt"
else
  skip "no tr_TR.UTF-8 locale here"
fi

# ---- nothing found, wrong use
run "$CMD" nosuchname
check "nothing found: exit 1" "1" "$RC"
check "nothing found: nothing on standard output" "" "$OUT"
has "nothing found: a message that says what was looked for" "nosuchname" "$ERR"
run "$CMD" "$W/empty" x
check "an empty folder: exit 1" "1" "$RC"
run "$CMD" "$W/nowhere" x
check "START does not exist: exit 1" "1" "$RC"
has "START does not exist: says so" "not a folder: $W/nowhere" "$ERR"
run "$CMD" notes.txt docs
check "the arguments the wrong way round: exit 1" "1" "$RC"
has "the wrong way round: the message gives the order" "START PATTERN" "$ERR"
run "$CMD"
check "no argument: exit 2" "2" "$RC"
has "no argument: points to --help" "--help" "$ERR"
run "$CMD" a b c
check "three arguments: exit 2" "2" "$RC"
run "$CMD" . docs/notes.txt
check "a path as PATTERN: exit 2" "2" "$RC"
run "$CMD" . ""
check "an empty PATTERN: exit 2" "2" "$RC"

# ---- the examples of the help
mkdir -p "$HOME/Documents/sub" "$HOME/src/app/node_modules"
: > "$HOME/Documents/sub/a.PDF"; : > "$HOME/Documents/b.txt"; : > "$HOME/src/Makefile"; : > "$HOME/src/makefile.old"
run "$CMD" invoice
check "example: invoice" "./Invoice 2024.pdf" "$OUT"
run "$CMD" ~/Documents '*.pdf'
check "example: ~/Documents '*.pdf'" "$HOME/Documents/sub/a.PDF" "$OUT"
run "$CMD" -f -e ~/src Makefile
check "example: -f -e ~/src Makefile" "$HOME/src/Makefile" "$OUT"
run "$CMD" -d ~/src node_modules
check "example: -d ~/src node_modules" "$HOME/src/app/node_modules" "$OUT"

cd "$TMP" || exit 1
finish
