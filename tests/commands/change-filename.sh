#!/bin/bash
# Tests for mbm-change-filename.   Run:  tests/run.sh change-filename    or:  bash tests/commands/change-filename.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-change-filename"
echo "mbm-change-filename"

W="$TMP/w"
mkdir -p "$W"
cd "$W" || exit 1

# snap - every name and every file's checksum below the working folder
snap() { find . | LC_ALL=C sort; find . -type f -exec cksum {} + | LC_ALL=C sort; }
# is FILE TEXT NAME - the file exists and holds TEXT
is() { check "$3" "$2" "$(cat "$1" 2>/dev/null || echo '<no such file>')"; }

mkdir -p "notes/sub dir" "notes/it's"
for f in 25122023 99999999 31022024 29022024 29022023 01012024 20101231 20102010 00012024 15132024 \
         2023-12-25 readme 251220231 2512202 "sub dir/05032022" "it's/07081999"; do
  echo "$f" > "notes/$f.md"
done
echo "was here first" > notes/20240101.md
echo "a txt file" > notes/25122023.txt

# ---- -n
before="$(snap)"
run "$CMD" -n notes
check "-n changes nothing" "$before" "$(snap)"
has "-n shows a rename" "notes/25122023.md -> notes/20231225.md" "$OUT"
has "-n shows a rename in a folder with a space" "notes/sub dir/05032022.md -> notes/sub dir/20220305.md" "$OUT"
has "-n counts" "Would be renamed: 5;" "$OUT"
check "-n: exit 1 because one file would be skipped" "1" "$RC"
dry="$(printf '%s\n' "$OUT" | tail -n 1 | tr -cd '0-9;')"
run "$CMD" notes --dry-run
check "--dry-run, given after the folder, changes nothing either" "$before" "$(snap)"

# ---- the main job
run "$CMD" notes
check "-n counted what the real run then did" "$dry" "$(printf '%s\n' "$OUT" | tail -n 1 | tr -cd '0-9;')"
is notes/20231225.md "25122023" "DDMMYYYY.md becomes YYYYMMDD.md, with its content"
[ ! -e notes/25122023.md ] && ok "the old name is gone" || bad "the old name is gone"
is "notes/sub dir/20220305.md" "sub dir/05032022" "a file in a folder with a space"
is "notes/it's/19990807.md" "it's/07081999" "a file in a folder with a quote"
is notes/20240229.md "29022024" "29 February of a leap year is a date"
is notes/20101020.md "20102010" "20 October 2010 (20102010) is a date"
has "one line per rename" "notes/29022024.md -> notes/20240229.md" "$OUT"
has "the last line counts" "Renamed: 5; skipped because the new name is taken: 1; eight-digit names that are not DDMMYYYY dates: 7." "$OUT"

# ---- what must not be renamed (the old version renamed all of these)
is notes/99999999.md "99999999" "99999999 is not a date: left alone"
is notes/31022024.md "31022024" "31 February: left alone"
is notes/29022023.md "29022023" "29 February of a common year: left alone"
is notes/00012024.md "00012024" "day 00: left alone"
is notes/15132024.md "15132024" "month 13: left alone"
is notes/20101231.md "20101231" "a name that is YYYYMMDD already: left alone"
is notes/2023-12-25.md "2023-12-25" "a name with dashes: left alone"
is notes/251220231.md "251220231" "nine digits: left alone"
is notes/2512202.md "2512202" "seven digits: left alone"
is notes/readme.md "readme" "another name: left alone"
is notes/25122023.txt "a txt file" "another extension: left alone"

# ---- never overwrite
check "the new name is taken: exit 1" "1" "$RC"
has "the new name is taken: the message names both files" "skipped notes/01012024.md: notes/20240101.md exists already" "$ERR"
is notes/20240101.md "was here first" "the file that had the name keeps its content"
is notes/01012024.md "01012024" "the file that was skipped is still there"

# ---- a second run
rm notes/01012024.md
before="$(snap)"
run "$CMD" notes
check "a second run: exit 0" "0" "$RC"
check "a second run renames nothing" "$before" "$(snap)"
has "a second run says so" "Renamed: 0;" "$OUT"

# ---- -e
run "$CMD" -e txt notes
is notes/20231225.txt "a txt file" "-e txt renames the .txt file"
echo x > notes/01022003.log
run "$CMD" --ext .log notes/
is notes/20030201.log "x" "--ext .log (with the dot, and a trailing slash on the folder)"
echo x > notes/02022003.md.bak
run "$CMD" -e md.bak notes
is notes/20030202.md.bak "x" "-e with a double extension"
echo x > "notes/03022003.m*"
echo x > notes/03022003.mx
run "$CMD" -e 'm*' notes
is "notes/20030203.m*" "x" "-e is taken letter for letter"
is notes/03022003.mx "x" "-e is not a pattern"

# ---- awkward folders
mkdir -p ./-dash "real folder"
echo x > ./-dash/04022003.md
echo x > "real folder/05022003.md"
ln -s "real folder" link
run "$CMD" -- -dash
is ./-dash/20030204.md "x" "-- then a folder whose name starts with a dash"
run "$CMD" link
is "real folder/20030205.md" "x" "a symbolic link to a folder"
mkdir empty
run "$CMD" empty
check "an empty folder: exit 0" "0" "$RC"
has "an empty folder: nothing renamed" "Renamed: 0;" "$OUT"

# ---- wrong use
echo x > 06022003.md
before="$(snap)"
run_in "notes
" "$CMD"
check "no folder: exit 2 (the old version asked for one)" "2" "$RC"
has "no folder: points to --help" "--help" "$ERR"
hasnt "no folder: no question is asked" "Enter" "$OUT$ERR"
run "$CMD" nope
check "a folder that does not exist: exit 1" "1" "$RC"
has "a folder that does not exist: the message names it" "not a folder: nope" "$ERR"
run "$CMD" 06022003.md
check "a file instead of a folder: exit 1" "1" "$RC"
run "$CMD" notes empty
check "two folders: exit 2" "2" "$RC"
run "$CMD" notes -e
check "-e without a value: exit 2" "2" "$RC"
run "$CMD" -e "" notes
check "an empty extension: exit 2" "2" "$RC"
run "$CMD" -x notes
check "an unknown option: exit 2" "2" "$RC"
check "wrong use changes nothing" "$before" "$(snap)"

# ---- the examples in the help
mkdir -p "$HOME/Notes/daily" journal
echo x > "$HOME/Notes/daily/09112026.md"
echo x > journal/10112026.txt
run "$CMD" "$HOME/Notes/daily"
[ "$RC" = 0 ] && [ -e "$HOME/Notes/daily/20261109.md" ] && ok "example: DIR" || bad "example: DIR"
run "$CMD" -n -e txt journal
[ "$RC" = 0 ] && [ -e journal/10112026.txt ] && ok "example: -n -e txt DIR" || bad "example: -n -e txt DIR"
has "example: the dry run shows the rename" "journal/10112026.txt -> journal/20261110.txt" "$OUT"

finish
