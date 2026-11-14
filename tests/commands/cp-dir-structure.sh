#!/bin/bash
# Tests for mbm-cp-dir-structure.   Run:  tests/run.sh cp-dir-structure    or:  bash tests/commands/cp-dir-structure.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-cp-dir-structure"
echo "mbm-cp-dir-structure"

W="$TMP/w"
mkdir -p "$W"
cd "$W" || exit 1

# folders DIR - the folders below DIR, one per line, sorted
folders() { (cd "$1" 2>/dev/null && find . -type d | LC_ALL=C sort); }
# snap - every name and every file's checksum below the working folder
snap() { find . | LC_ALL=C sort; find . -type f -exec cksum {} + | LC_ALL=C sort; }

mkdir -p src/a/b "src/with space/deep" src/empty "src/trail " 'src/back\slash' "src/it's" src/-dash/x
echo text > src/a/file.txt
echo text > "src/with space/f.md"
WANT="$(folders src)"

# ---- the main job
run "$CMD" src dst
check "copies a tree: exit 0" "0" "$RC"
check "every folder is there (space, trailing space, backslash, quote, leading dash)" "$WANT" "$(folders dst)"
check "no file is copied" "" "$(find dst -type f)"
has "says how many folders were made" "Folders made in dst: 11; there already: 0." "$OUT"
check "without -v the summary is the only line" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"

run "$CMD" src dst
check "a second run: exit 0" "0" "$RC"
has "a second run makes nothing" "Folders made in dst: 0; there already: 11." "$OUT"

mkdir -p keep/a
echo mine > keep/a/mine.txt
run "$CMD" src keep
check "what is in DST already stays" "mine" "$(cat keep/a/mine.txt)"
check "and DST gets the tree" "$WANT" "$(folders keep)"

run "$CMD" "$W/src" "$W/abs"
check "absolute paths" "$WANT" "$(folders abs)"

# ---- defects of the old version
run "$CMD" src/ slash/
check "a trailing slash on SRC and DST gives the same tree" "$WANT" "$(folders slash)"
check "a trailing slash scatters nothing next to DST" "" "$(find . -maxdepth 1 -name 'slash?*')"

mkdir -p "s[1]/x/y" "s*/q"
run "$CMD" "s[1]" glob1
[ -d glob1/x/y ] && ok "SRC with [ ] in its name" || bad "SRC with [ ] in its name"
run "$CMD" "s*" glob2
[ -d glob2/q ] && ok "SRC with * in its name" || bad "SRC with * in its name"

mkdir -p rep/a/a/a
( cd rep && "$CMD" a ../rep-out >/dev/null 2>&1 )
[ -d rep-out/a/a ] && ok "the name of SRC occurring again deeper in the tree" || bad "the name of SRC occurring again deeper in the tree"

mkdir -p in/a/b
run "$CMD" in in/copy
run "$CMD" in in/copy
check "DST inside SRC: exit 0" "0" "$RC"
check "DST inside SRC is not copied into itself" "$(printf '.\n./a\n./a/b')" "$(folders in/copy)"

run "$CMD" nope made-for-nothing
check "a missing SRC: exit 1" "1" "$RC"
has "a missing SRC: the message names it" "not a folder: nope" "$ERR"
[ ! -e made-for-nothing ] && ok "a missing SRC: DST is not made" || bad "a missing SRC: DST is not made"

run "$CMD" src/a/file.txt from-file
check "SRC is a file: exit 1" "1" "$RC"
run "$CMD" src src/a/file.txt
check "DST is a file: exit 1" "1" "$RC"
has "DST is a file: the message says so" "exists and is not a folder" "$ERR"
run "$CMD" src ./src/
check "SRC and DST the same folder: exit 1" "1" "$RC"

# ---- options
before="$(snap)"
run "$CMD" -n src new/deep
check "-n: exit 0" "0" "$RC"
check "-n changes nothing" "$before" "$(snap)"
has "-n lists DST itself" "$(printf 'new/deep\n')" "$OUT"
has "-n lists a folder with a space" "new/deep/with space/deep" "$OUT"
has "-n says how many" "folders that would be made in new/deep: 11" "$OUT"
check "-n lists one line per folder, and the summary" "12" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
run "$CMD" --dry-run src new2
[ ! -e new2 ] && ok "--dry-run is the same" || bad "--dry-run is the same"
run "$CMD" src new3 -n
[ "$RC" = 0 ] && [ ! -e new3 ] && ok "-n given after the names still counts" || bad "-n given after the names still counts"

run "$CMD" -v src verbose
has "-v lists the folders it makes" "verbose/a/b" "$OUT"
check "-v: the tree is made" "$WANT" "$(folders verbose)"
run "$CMD" --verbose src verbose2
has "--verbose is the same" "verbose2/with space/deep" "$OUT"

mkdir -p ./-s/sub
run "$CMD" -- -s -t
[ -d ./-t/sub ] && ok "-- then names that start with a dash" || bad "-- then names that start with a dash (rc $RC: $ERR)"

mkdir -p sl
ln -s ../src sl/link
ln -s src/a to-a
run "$CMD" sl sl-out
check "a symbolic link inside SRC is not followed" "." "$(folders sl-out)"
run "$CMD" to-a link-out
check "SRC itself may be a symbolic link to a folder" "$(printf '.\n./b')" "$(folders link-out)"

if [ "$(id -u)" != 0 ]; then
  mkdir -p locked/ok locked/shut/in
  chmod 000 locked/shut
  run "$CMD" locked locked-out
  chmod 755 locked/shut
  check "a folder that cannot be read: exit 1" "1" "$RC"
  [ -d locked-out/ok ] && ok "a folder that cannot be read: the rest is copied" || bad "a folder that cannot be read: the rest is copied"
else
  skip "running as root: an unreadable folder cannot be made"
fi

# ---- wrong use
before="$(snap)"
run "$CMD"
check "no argument: exit 2" "2" "$RC"
has "no argument: points to --help" "--help" "$ERR"
run "$CMD" src
check "one argument: exit 2" "2" "$RC"
run "$CMD" src one two
check "three arguments: exit 2" "2" "$RC"
run "$CMD" src ""
check "an empty DST: exit 2" "2" "$RC"
run "$CMD" -x src bad-option
check "an unknown option: exit 2" "2" "$RC"
check "wrong use changes nothing" "$before" "$(snap)"

# ---- the examples in the help
mkdir -p "$HOME/Projects/site/css" "$HOME/Projects/site/img/icons" photos/2024/01 photos/2024/02
run "$CMD" "$HOME/Projects/site" "$HOME/Projects/site-skeleton"
[ "$RC" = 0 ] && [ -d "$HOME/Projects/site-skeleton/img/icons" ] && ok "example: SRC DST" || bad "example: SRC DST"
run "$CMD" -n photos/2024 photos/2025
[ "$RC" = 0 ] && [ ! -e photos/2025 ] && ok "example: -n SRC DST" || bad "example: -n SRC DST"
has "example: -n lists the folders" "photos/2025/02" "$OUT"

finish
