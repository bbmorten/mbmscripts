#!/bin/bash
# Tests for mbm-insert-date.   Run:  tests/run.sh insert-date    or:  bash tests/commands/insert-date.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-insert-date"
echo "mbm-insert-date"

W="$TMP/w"
mkdir -p "$W"
cd "$W" || exit 1

# snap - every name and every file's checksum below the working folder
snap() { find . | LC_ALL=C sort; find . -type f -exec cksum {} + | LC_ALL=C sort; }
# bytes FILE - the file, with its line ends and other unprintable bytes made visible
bytes() { od -c "$1" | sed 's/^[0-9]* *//' | tr -s ' \n' ' '; }

# ---- with the real date
printf 'Written on {{DATE}}.\n' > real.md
run "$CMD" real.md
check "the real date, in the default format YYYY-MM-DD" "Written on $(date +%Y-%m-%d)." "$(cat real.md)"

# From here on a fake date, so that the results are fixed: it answers by the format it is given.
stub date 'case "$1" in
  +%Y-%m-%d) echo 2024-02-29 ;;
  +%d.%m.%Y) echo 29.02.2024 ;;
  "+%A, %d %B %Y") echo "Thursday, 29 February 2024" ;;
  *) echo "FORMAT[$1]" ;;
esac'

# ---- the main job
printf 'Date: {{DATE}}\nagain {{DATE}} and {{DATE}}\nno placeholder here\n' > "my note.md"
chmod 640 "my note.md"
mode_before="$(ls -l "my note.md" | cut -c1-10)"
inode_before="$(ls -i "my note.md" | awk '{ print $1 }')"
run "$CMD" "my note.md"
check "replaces: exit 0" "0" "$RC"
check "every occurrence is replaced, the rest stays" "$(printf 'Date: 2024-02-29\nagain 2024-02-29 and 2024-02-29\nno placeholder here')" "$(cat "my note.md")"
check "one line says how many" "my note.md: 3 x {{DATE}} replaced with 2024-02-29" "$OUT"
check "the permissions stay (the old version left 0600)" "$mode_before" "$(ls -l "my note.md" | cut -c1-10)"
check "it is still the same file (inode)" "$inode_before" "$(ls -i "my note.md" | awk '{ print $1 }')"
check "date is asked once, with the format" "date +%Y-%m-%d" "$(calls date)"
check "nothing is left behind in the working folder" "$(printf 'my note.md\nreal.md')" "$(ls)"

printf 'x {{DATE}}\n' > target.md
ln -s target.md link.md
run "$CMD" link.md
[ -L link.md ] && ok "a symbolic link stays a link" || bad "a symbolic link stays a link"
check "and the file it points to is changed" "x 2024-02-29" "$(cat target.md)"

touch -t 202001010000 "my note.md"
stamp="$(ls -l "my note.md")"
run "$CMD" "my note.md"
check "a file without the placeholder: exit 0" "0" "$RC"
has "a file without the placeholder: says so" "my note.md: no {{DATE}} in it, not changed" "$OUT"
check "a file without the placeholder is not written (same time stamp)" "$stamp" "$(ls -l "my note.md")"

# ---- several files, line ends
reset_calls
printf '{{DATE}}' > nonl.md
printf 'a\r\n{{DATE}}\r\n' > crlf.md
printf 'q {{DATE}}\n' > "it's.md"
printf 'd {{DATE}}\n' > ./-dash.md
: > empty.md
run "$CMD" -- nonl.md crlf.md "it's.md" -dash.md empty.md
check "several files: exit 0" "0" "$RC"
check "a file without a final line end stays without one" "2 0 2 4 - 0 2 - 2 9 " "$(bytes nonl.md)"
check "CRLF line ends stay" "a \r \n 2 0 2 4 - 0 2 - 2 9 \r \n " "$(bytes crlf.md)"
check "a file name with a quote" "q 2024-02-29" "$(cat "it's.md")"
check "a file name with a leading dash, after --" "d 2024-02-29" "$(cat ./-dash.md)"
check "an empty file stays empty" "0" "$(wc -c < empty.md | tr -d ' ')"
check "one report line per file" "5" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
check "date is asked once for all the files" "1" "$(calls date | wc -l | tr -d ' ')"

printf 'one {{DATE}}\n' > one.md
printf 'two {{DATE}}\n' > two.md
run "$CMD" one.md missing.md two.md
check "a missing file among others: exit 1" "1" "$RC"
has "a missing file: the message names it" "not a file: missing.md" "$ERR"
[ ! -e missing.md ] && ok "a missing file among others is not created" || bad "a missing file among others is not created"
check "the file before it is done" "one 2024-02-29" "$(cat one.md)"
check "the file after it is done (the old version read only the first)" "two 2024-02-29" "$(cat two.md)"
run "$CMD" alone-missing.md
check "a missing file alone: exit 1" "1" "$RC"
[ ! -e alone-missing.md ] && ok "a missing file is not created (the old version left an empty one)" || bad "a missing file is not created (the old version left an empty one)"

# ---- -f and -p
printf 'on <TODAY>, cost $5 & [x] .* <TODAY>\n' > letter.md
run "$CMD" -f '%d.%m.%Y' -p '<TODAY>' letter.md
check "-f FORMAT and -p PLACEHOLDER" 'on 29.02.2024, cost $5 & [x] .* 29.02.2024' "$(cat letter.md)"
has "the report names the placeholder" "letter.md: 2 x <TODAY> replaced with 29.02.2024" "$OUT"
printf 'a.c abc a*c [a-z]\n' > pattern.md
run "$CMD" --placeholder 'a.c' pattern.md
check "the placeholder is text, not a pattern (a.c)" "2024-02-29 abc a*c [a-z]" "$(cat pattern.md)"
run "$CMD" -p '[a-z]' pattern.md
check "the placeholder is text, not a pattern ([a-z])" "2024-02-29 abc a*c 2024-02-29" "$(cat pattern.md)"
printf 'back\\slash \\n here\n' > backslash.md
run "$CMD" -p '\n' backslash.md
check "a backslash in the placeholder is a backslash" 'back\slash 2024-02-29 here' "$(cat backslash.md)"
printf 'x {{DATE}} y\n' > special.md
run "$CMD" --format '&/\1 %%' special.md
check "the date text is put in as it is (& / \\ in it)" 'x FORMAT[+&/\1 %%] y' "$(cat special.md)"
printf 'İstanbul «€» ğüş €\n' > utf8.md
run "$CMD" -p '€' utf8.md
check "a placeholder and text outside ASCII" "İstanbul «2024-02-29» ğüş 2024-02-29" "$(cat utf8.md)"

# ---- -n
printf 'first\nDate: {{DATE}}\nlast {{DATE}} {{DATE}}\n' > draft.md
before="$(snap)"
run "$CMD" -n draft.md
check "-n: exit 0" "0" "$RC"
check "-n changes nothing" "$before" "$(snap)"
check "-n shows the lines as they would be, then the count" \
  "$(printf 'draft.md:2: Date: 2024-02-29\ndraft.md:3: last 2024-02-29 2024-02-29\ndraft.md: 3 x {{DATE}} would be replaced with 2024-02-29')" "$OUT"
run "$CMD" draft.md --dry-run
check "--dry-run, given after the file, changes nothing either" "$before" "$(snap)"

# ---- wrong use
if [ "$(id -u)" != 0 ]; then
  printf '{{DATE}}\n' > locked.md
  chmod 444 locked.md
  run "$CMD" locked.md
  check "a file that cannot be written: exit 1" "1" "$RC"
  has "a file that cannot be written: the message names it" "no permission to change locked.md" "$ERR"
  check "a file that cannot be written stays as it is" "{{DATE}}" "$(cat locked.md)"
else
  skip "running as root: a read-only file cannot be made"
fi
mkdir folder
before="$(snap)"
run "$CMD" folder
check "a folder instead of a file: exit 1" "1" "$RC"
run "$CMD"
check "no file: exit 2" "2" "$RC"
has "no file: points to --help" "--help" "$ERR"
run "$CMD" draft.md -f
check "-f without a value: exit 2" "2" "$RC"
run "$CMD" -p "" draft.md
check "an empty placeholder: exit 2" "2" "$RC"
run "$CMD" -x draft.md
check "an unknown option: exit 2" "2" "$RC"
check "wrong use changes nothing" "$before" "$(snap)"

# ---- the examples in the help
mkdir notes
printf '# {{DATE}}\n' > notes/today.md
printf 'Ankara, <TODAY>\n' > letter.md
printf 'Invoice of <TODAY>\n' > invoice.md
printf 'Draft of {{DATE}}\n' > draft.md
run "$CMD" notes/today.md
check "example: FILE" "# 2024-02-29" "$(cat notes/today.md)"
run "$CMD" -f '%d.%m.%Y' -p '<TODAY>' letter.md invoice.md
check "example: -f -p FILE FILE" "Ankara, 29.02.2024|Invoice of 29.02.2024" "$(cat letter.md)|$(cat invoice.md)"
run "$CMD" -n -f '%A, %d %B %Y' draft.md
has "example: -n -f FILE shows the line" "draft.md:1: Draft of Thursday, 29 February 2024" "$OUT"
check "example: -n -f FILE changes nothing" "Draft of {{DATE}}" "$(cat draft.md)"

finish
