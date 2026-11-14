#!/bin/bash
# Tests for mbm-replace-heading.   Run:  tests/run.sh replace-heading    or:  bash tests/commands/replace-heading.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-replace-heading"
echo "mbm-replace-heading"

W="$TMP/w"
mkdir -p "$W"
cd "$W" || exit 1

# snap - every name and every file's checksum below the working folder
snap() { find . | LC_ALL=C sort; find . -type f -exec cksum {} + | LC_ALL=C sort; }
# bytes FILE - the file, with its line ends and other unprintable bytes made visible
bytes() { od -c "$1" | sed 's/^[0-9]* *//' | tr -s ' \n' ' '; }
# first FILE - its first line
first() { head -n 1 "$1"; }

mkdir -p "h/sub dir" "h/it's"
printf '# 25122023 Meeting notes\nbody 25122023\n# 25122023 again\n' > h/a.md
printf '#25122023\nbody\n' > h/nospace.md
printf '#\t25122023 tab\n' > h/tab.md
printf '# 25122023 a/b & c \\1 %%s "q" $HOME\nbody\n' > "h/sub dir/special.md"
printf '# 07081999 quote\n' > "h/it's/-dash.md"
printf '# 25122023   two  spaces\r\nx\r\n' > h/crlf.md
printf '# 01022003' > h/nonl.md
printf '# 29022024 leap\n' > h/leap.md
printf '# 99999999 not a date\n' > h/notdate.md
printf '# 31022024 not a date\n' > h/feb31.md
printf '# 20231225 done already\n' > h/iso.md
printf '# 251220231 nine digits\n' > h/nine.md
printf '# Title\n# 25122023\n' > h/second.md
printf '## 25122023\n' > h/h2.md
printf '#  25122023 two spaces before\n' > h/twospaces.md
printf ' # 25122023 indented\n' > h/indented.md
: > h/empty.md
printf '# 25122023 a text file\n' > h/other.txt
chmod 640 h/a.md
mode_before="$(ls -l h/a.md | cut -c1-10)"
inode_before="$(ls -i h/a.md | awk '{ print $1 }')"

# ---- -n
before="$(snap)"
run "$CMD" -n h
check "-n: exit 0" "0" "$RC"
check "-n changes nothing" "$before" "$(snap)"
has "-n shows file, old and new heading" "h/a.md: # 25122023 Meeting notes -> # 20231225 Meeting notes" "$OUT"
has "-n counts" "Headings that would be rewritten in h: 8." "$OUT"
run "$CMD" h --dry-run
check "--dry-run, given after the folder, changes nothing either" "$before" "$(snap)"

# ---- the main job
run "$CMD" h
check "rewrites: exit 0" "0" "$RC"
has "one line per file" "h/sub dir/special.md: " "$OUT"
has "the last line counts" "Headings rewritten in h: 8." "$OUT"
check "# DDMMYYYY text becomes # YYYYMMDD text" "# 20231225 Meeting notes" "$(first h/a.md)"
check "only line 1 is touched" "$(printf 'body 25122023\n# 25122023 again')" "$(tail -n +2 h/a.md)"
check "the permissions stay" "$mode_before" "$(ls -l h/a.md | cut -c1-10)"
check "it is still the same file (inode)" "$inode_before" "$(ls -i h/a.md | awk '{ print $1 }')"
check "#DDMMYYYY without a space gets one" "# 20231225" "$(first h/nospace.md)"
check "a tab after the # counts as the space" "# 20231225 tab" "$(first h/tab.md)"
check "a leap day is a date" "# 20240229 leap" "$(first h/leap.md)"
check "a file name with a quote and a leading dash" "# 19990807 quote" "$(first "h/it's/-dash.md")"

# ---- defects of the old version
check "/ & \\1 %s in the rest of the heading stay as they are" '# 20231225 a/b & c \1 %s "q" $HOME' "$(first "h/sub dir/special.md")"
check "the body below such a heading stays" "body" "$(tail -n 1 "h/sub dir/special.md")"
check "CRLF line ends stay" "# 2 0 2 3 1 2 2 5 t w o s p a c e s \r \n x \r \n " "$(bytes h/crlf.md)"
check "a single line without a line end stays without one" "# 2 0 0 3 0 2 0 1 " "$(bytes h/nonl.md)"
check "99999999 is not a date: left alone" "# 99999999 not a date" "$(first h/notdate.md)"
check "31 February is not a date: left alone" "# 31022024 not a date" "$(first h/feb31.md)"
check "a heading that is YYYYMMDD already: left alone" "# 20231225 done already" "$(first h/iso.md)"
check "nine digits: left alone" "# 251220231 nine digits" "$(first h/nine.md)"
check "a date heading on line 2: left alone" "$(printf '# Title\n# 25122023')" "$(cat h/second.md)"
check "a ## heading: left alone" "## 25122023" "$(first h/h2.md)"
check "two spaces after the #: left alone" "#  25122023 two spaces before" "$(first h/twospaces.md)"
check "an indented heading: left alone" " # 25122023 indented" "$(first h/indented.md)"
check "a file that is not .md: left alone" "# 25122023 a text file" "$(first h/other.txt)"
check "an empty file stays empty" "0" "$(wc -c < h/empty.md | tr -d ' ')"
check "no file is left behind in the working folder" "h" "$(ls)"

before="$(snap)"
run "$CMD" h
check "a second run: exit 0" "0" "$RC"
check "a second run changes nothing" "$before" "$(snap)"
has "a second run says so" "Headings rewritten in h: 0." "$OUT"

# ---- where the folder comes from
mkdir -p envdir argdir here
printf '# 01022003 env\n' > envdir/x.md
printf '# 01022003 arg\n' > argdir/x.md
printf '# 01022003 here\n' > here/x.md
MBM_REPLACE_HEADING_DIR=envdir run "$CMD"
check "without DIR, MBM_REPLACE_HEADING_DIR is used" "# 20030201 env" "$(first envdir/x.md)"
printf '# 01022003 env\n' > envdir/x.md
MBM_REPLACE_HEADING_DIR=envdir run "$CMD" argdir
check "DIR wins over MBM_REPLACE_HEADING_DIR" "# 20030201 arg" "$(first argdir/x.md)"
check "and the folder of the setting is not touched then" "# 01022003 env" "$(first envdir/x.md)"

before="$(snap)"
cd here || exit 1
run_in "../envdir
" "$CMD"
cd "$W" || exit 1
check "no DIR and no setting: exit 2" "2" "$RC"
has "no DIR and no setting: the message names the setting and --help" "MBM_REPLACE_HEADING_DIR is not set (see: mbm-replace-heading --help)" "$ERR"
hasnt "no DIR and no setting: no question is asked" "Enter" "$OUT$ERR"
check "no DIR and no setting: neither the current folder nor a typed one is touched" "$before" "$(snap)"

# ---- awkward folders
mkdir -p ./-dash "real folder"
printf '# 02022003 x\n' > ./-dash/x.md
printf '# 03022003 x\n' > "real folder/x.md"
ln -s "real folder" link
run "$CMD" -- -dash
check "-- then a folder whose name starts with a dash" "# 20030202 x" "$(first ./-dash/x.md)"
run "$CMD" link/
check "a symbolic link to a folder" "# 20030203 x" "$(first "real folder/x.md")"

if [ "$(id -u)" != 0 ]; then
  mkdir ro
  printf '# 04022003 locked\n' > ro/locked.md
  printf '# 04022003 open\n' > ro/open.md
  chmod 444 ro/locked.md
  run "$CMD" ro
  check "a file that cannot be written: exit 1" "1" "$RC"
  has "a file that cannot be written: the message names it" "could not rewrite ro/locked.md" "$ERR"
  check "a file that cannot be written stays as it is" "# 04022003 locked" "$(first ro/locked.md)"
  check "the other files are still done" "# 20030204 open" "$(first ro/open.md)"
  has "and the count is honest" "Headings rewritten in ro: 1." "$OUT"
else
  skip "running as root: a read-only file cannot be made"
fi

# ---- wrong use
before="$(snap)"
run "$CMD" nope
check "a folder that does not exist: exit 1" "1" "$RC"
has "a folder that does not exist: the message names it" "not a folder: nope" "$ERR"
run "$CMD" h/a.md
check "a file instead of a folder: exit 1" "1" "$RC"
run "$CMD" argdir envdir
check "two folders: exit 2" "2" "$RC"
run "$CMD" -x argdir
check "an unknown option: exit 2" "2" "$RC"
check "wrong use changes nothing" "$before" "$(snap)"

# ---- the examples in the help
mkdir -p "$HOME/Notes/daily"
printf '# 09112026 Monday\n' > "$HOME/Notes/daily/a.md"
run "$CMD" -n "$HOME/Notes/daily"
[ "$RC" = 0 ] && [ "$(first "$HOME/Notes/daily/a.md")" = "# 09112026 Monday" ] && ok "example: -n DIR" || bad "example: -n DIR"
has "example: -n shows the change" "# 09112026 Monday -> # 20261109 Monday" "$OUT"
run "$CMD" "$HOME/Notes/daily"
[ "$RC" = 0 ] && [ "$(first "$HOME/Notes/daily/a.md")" = "# 20261109 Monday" ] && ok "example: DIR" || bad "example: DIR"

finish
