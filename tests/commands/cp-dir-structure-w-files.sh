#!/bin/bash
# Tests for mbm-cp-dir-structure-w-files.   Run:  tests/run.sh cp-dir-structure-w-files    or:  bash tests/commands/cp-dir-structure-w-files.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-cp-dir-structure-w-files"
echo "mbm-cp-dir-structure-w-files"

W="$TMP/w"
mkdir -p "$W"
cd "$W" || exit 1

# names DIR - everything below DIR, one name per line, sorted
names() { (cd "$1" 2>/dev/null && find . | LC_ALL=C sort); }
# files DIR - the files and links below DIR
files() { (cd "$1" 2>/dev/null && find . ! -type d | LC_ALL=C sort); }
# snap - every name and every file's checksum below the working folder
snap() { find . | LC_ALL=C sort; find . -type f -exec cksum {} + | LC_ALL=C sort; }
# counts TEXT - the numbers of the summary line
counts() { printf '%s\n' "$1" | tail -n 1 | sed 's/^.* - //' | tr -cd '0-9,\n'; }

mkdir -p src/sub/deeper "src/sp ace" src/empty src/-dash
echo one > src/a.md
echo two > "src/sp ace/b c.txt"
echo three > src/sub/c.md
echo idx > src/sub/index.md
echo png > src/sub/deeper/p.png
echo quote > "src/it's.md"
echo dash > src/-dash/-x.md
printf '#!/bin/sh\n' > src/run.sh
chmod 755 src/run.sh
ln -s a.md src/link.md
WANT="$(names src)"

# ---- the main job
run "$CMD" src dst
check "DST does not exist: exit 0" "0" "$RC"
check "DST does not exist: the content of SRC is in DST" "$WANT" "$(names dst)"
check "the files hold the same" "" "$(diff -r src dst 2>&1)"
[ -L dst/link.md ] && check "a symbolic link is copied as a link" "a.md" "$(readlink dst/link.md)" || bad "a symbolic link is copied as a link"
[ -x dst/run.sh ] && ok "a file keeps its permissions" || bad "a file keeps its permissions"
has "the summary counts folders and files" "folders made: 6, files copied: 9, index.md added: 0, files there already: 0" "$OUT"
check "without -v the summary is the only line" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"

mkdir there
run "$CMD" src there
check "DST exists: the same result, the content of SRC in DST" "$WANT" "$(names there)"
[ ! -e there/src ] && ok "DST exists: SRC is not put inside it as a folder" || bad "DST exists: SRC is not put inside it as a folder"

run "$CMD" src/ dst/
check "a second run (with trailing slashes): exit 0" "0" "$RC"
has "a second run copies nothing" "files copied: 0, index.md added: 0, files there already: 9" "$OUT"

# ---- an existing file is never overwritten
echo changed > dst/a.md
rm dst/sub/c.md
run "$CMD" src dst
check "a file that differs: exit 1" "1" "$RC"
check "a file that differs is kept" "changed" "$(cat dst/a.md)"
has "a file that differs is listed" "kept    dst/a.md" "$OUT"
has "a file that differs: the message says why" "never overwritten" "$ERR"
check "a file that was missing is copied all the same" "three" "$(cat dst/sub/c.md)"

# ---- -i
run "$CMD" -i '*.md' src only-md
check "-i: exit 0" "0" "$RC"
check "-i '*.md' copies only those files" "$(printf './-dash/-x.md\n./a.md\n./it'"'"'s.md\n./link.md\n./sub/c.md\n./sub/index.md')" "$(files only-md)"
check "-i still makes every folder" "$(cd src && find . -type d | LC_ALL=C sort)" "$(cd only-md && find . -type d | LC_ALL=C sort)"
run "$CMD" -i '*.png' --include 'b c.*' src two-patterns
check "-i twice, --include, a pattern with a space" "$(printf './sp ace/b c.txt\n./sub/deeper/p.png')" "$(files two-patterns)"
run "$CMD" -i 'nothing-matches' src none
check "-i that matches nothing copies no file" "" "$(files none)"

# ---- -c
mkdir -p idx/empty
echo mine > idx/empty/index.md
run "$CMD" -c src idx
check "-c: exit 0" "0" "$RC"
check "-c: an index.md in every folder" "" "$(cd idx && find . -type d | while IFS= read -r d; do [ -e "$d/index.md" ] || echo "$d"; done)"
check "-c: a new index.md is empty" "0" "$(wc -c < idx/sub/deeper/index.md | tr -d ' ')"
check "-c: the index.md that SRC brings is the copy" "idx" "$(cat idx/sub/index.md)"
check "-c: an index.md that DST had stays" "mine" "$(cat idx/empty/index.md)"
has "-c: the summary counts them" "index.md added: 4" "$OUT"
run "$CMD" --index src idx
has "--index, a second time: nothing to add" "index.md added: 0" "$OUT"

# ---- -n
before="$(snap)"
run "$CMD" -n -c -i '*.md' src new
check "-n: exit 0" "0" "$RC"
check "-n changes nothing" "$before" "$(snap)"
has "-n lists a folder" "folder  new/sp ace" "$OUT"
has "-n lists a file" "file    new/sub/c.md" "$OUT"
hasnt "-n does not list a file the pattern leaves out" "p.png" "$OUT"
has "-n lists an index.md it would add" "index   new/empty/index.md" "$OUT"
hasnt "-n -c: no index.md where SRC brings one" "index   new/sub/index.md" "$OUT"
dry="$(counts "$OUT")"
run "$CMD" -c -i '*.md' src new
check "-n counted what the real run then did" "$dry" "$(counts "$OUT")"
run "$CMD" --dry-run -c -i '*.txt' src new3
has "-n -c: an index.md where the one of SRC is not copied" "index   new3/sub/index.md" "$OUT"
[ ! -e new3 ] && ok "--dry-run is the same" || bad "--dry-run is the same"
run "$CMD" src new4 -n
[ "$RC" = 0 ] && [ ! -e new4 ] && ok "-n given after the names still counts" || bad "-n given after the names still counts"
echo other > dst/a.md
run "$CMD" -n src dst
check "-n with a file that differs: exit 1, as the real run" "1" "$RC"
check "-n leaves that file alone" "other" "$(cat dst/a.md)"

# ---- -v
run "$CMD" -v src verbose
has "-v lists the folders" "folder  verbose/sub/deeper" "$OUT"
has "-v lists the files" "file    verbose/sp ace/b c.txt" "$OUT"
run "$CMD" --verbose src verbose2
has "--verbose is the same" "file    verbose2/a.md" "$OUT"

# ---- awkward places
mkdir -p ./-s/sub
echo x > ./-s/sub/-f
run "$CMD" -- -s -t
check "-- then names that start with a dash" "x" "$(cat ./-t/sub/-f 2>/dev/null)"

mkdir -p in/a
echo x > in/a/f
run "$CMD" in in/bak
run "$CMD" in in/bak
check "DST inside SRC: exit 0" "0" "$RC"
check "DST inside SRC is not copied into itself" "$(printf '.\n./a\n./a/f')" "$(names in/bak)"

# ---- wrong use, and what the old version let through
before="$(snap)"
run "$CMD" nope made-for-nothing
check "a missing SRC: exit 1" "1" "$RC"
has "a missing SRC: the message names it" "not a folder: nope" "$ERR"
run "$CMD" src/a.md from-file
check "SRC is a file: exit 1" "1" "$RC"
run "$CMD" src src/a.md
check "DST is a file: exit 1" "1" "$RC"
run "$CMD" src ./src
check "SRC and DST the same folder: exit 1" "1" "$RC"
run "$CMD" -t src old-option
check "the old -t is gone: exit 2" "2" "$RC"
has "the old -t: points to --help" "--help" "$ERR"
run "$CMD"
check "no argument: exit 2" "2" "$RC"
run "$CMD" src
check "one argument: exit 2" "2" "$RC"
run "$CMD" src one two
check "three arguments: exit 2" "2" "$RC"
run "$CMD" src -i
check "-i without a pattern: exit 2" "2" "$RC"
run "$CMD" -i
check "-i as the last word: exit 2" "2" "$RC"
check "wrong use changes nothing" "$before" "$(snap)"

# ---- the examples in the help
mkdir -p "$HOME/Projects/site/css" docs/img course-2024/week1
echo body > "$HOME/Projects/site/css/main.css"
echo text > docs/readme.md
echo pic > docs/img/logo.png
echo data > docs/img/raw.psd
echo w1 > course-2024/week1/notes.md
run "$CMD" "$HOME/Projects/site" "$HOME/Projects/site-copy"
check "example: SRC DST" "body" "$(cat "$HOME/Projects/site-copy/css/main.css" 2>/dev/null)"
run "$CMD" -i '*.md' -i '*.png' docs docs-text-only
check "example: -i '*.md' -i '*.png' SRC DST" "$(printf './img/logo.png\n./readme.md')" "$(files docs-text-only)"
run "$CMD" -n -c -i '*.md' course-2024 course-2025
[ "$RC" = 0 ] && [ ! -e course-2025 ] && ok "example: -n -c -i '*.md' SRC DST" || bad "example: -n -c -i '*.md' SRC DST"
has "example: the dry run lists the index.md" "index   course-2025/week1/index.md" "$OUT"

finish
