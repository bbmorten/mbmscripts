#!/bin/bash
# Tests for mbm-list-folders-with-pdf.   Run:  tests/run.sh list-folders-with-pdf    or:  bash tests/commands/list-folders-with-pdf.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-list-folders-with-pdf"
echo "mbm-list-folders-with-pdf"

W="$TMP/w"
TAB="$(printf '\t')"
NLDIR="$(printf 'new\nline')"
mkdir -p "$W/t/a b" "$W/t/sub/deep" "$W/t/UPPER" "$W/t/none/folder.pdf" "$W/t/.hidden" "$W/t/linked" \
         "$W/t/it's \"q\"" "$W/t/$NLDIR" "$W/t/locked" "$W/-dash" "$W/empty"
cd "$W" || exit 1
: > "t/a b/one.pdf"; : > "t/a b/two.pdf"; : > "t/a b/three.Pdf"
: > t/sub/deep/r.pdf
: > t/UPPER/REPORT.PDF
: > t/none/x.txt; : > t/none/pdf; : > t/none/notpdf; : > t/none/folder.pdf/readme.txt; : > t/none/y.pdf.bak
: > t/.hidden/h.pdf
: > t/root.pdf
ln -s ../root.pdf t/linked/paper.pdf
: > "t/it's \"q\"/q.pdf"
: > "t/$NLDIR/n.pdf"
: > t/locked/l.pdf
: > "t/a b/letter.docx"; : > t/none/IMAGE.GIF; : > t/sub/archive.tar.gz; : > t/sub/plain.gz
: > ./-dash/d.pdf
ln -s t link

lines() { printf '%s\n' "$@"; }
ALL="$(lines t t/.hidden "t/a b" "t/it's \"q\"" t/linked "t/new?line" t/sub/deep t/UPPER)"

# ---- the main job
chmod 000 t/locked
run "$CMD" t
check "the folders with PDF files, sorted, and nothing else on standard output" "$ALL" "$OUT"
check "exit 0" "0" "$RC"
check "a folder that may not be read gives no message" "" "$ERR"
chmod 755 t/locked
has "an extension in capitals counts" "t/UPPER" "$OUT"
hasnt "a folder called something.pdf is not a PDF file" "t/none" "$OUT"

cd t || exit 1
run "$CMD"
has "without DIR: the current folder" "./a b" "$OUT"
check "without DIR: the current folder itself is the first line" "." "$(printf '%s\n' "$OUT" | head -n 1)"
cd "$W" || exit 1
run "$CMD" t///
check "trailing slashes on DIR do not change the paths" "$(lines "$ALL" t/locked | LC_ALL=C sort -f)" "$OUT"
run "$CMD" -- -dash
check "DIR that starts with a dash, after --" "./-dash" "$OUT"
run "$CMD" link
has "DIR that is a link to a folder is searched" "link/sub/deep" "$OUT"

# ---- -c
run "$CMD" -c t
check "-c: the number, a tab, the folder" \
  "$(lines "1${TAB}t" "1${TAB}t/.hidden" "3${TAB}t/a b" "1${TAB}t/it's \"q\"" "1${TAB}t/linked" "1${TAB}t/locked" "1${TAB}t/new?line" "1${TAB}t/sub/deep" "1${TAB}t/UPPER")" "$OUT"
run "$CMD" --count "t/a b"
check "--count" "3${TAB}t/a b" "$OUT"

# ---- -e
run "$CMD" -e docx t
check "-e docx" "t/a b" "$OUT"
run "$CMD" --ext .GIF t
check "--ext .GIF: a leading dot and capitals are fine" "t/none" "$OUT"
run "$CMD" -e tar.gz t
check "-e tar.gz" "t/sub" "$OUT"
run "$CMD" -c -e gz t
check "-c -e gz" "2${TAB}t/sub" "$OUT"
for bad in "" 'p*f' 'a/b' 'pd f' '.'; do
  run "$CMD" -e "$bad" t
  check "-e '$bad' is not an extension: exit 2" "2" "$RC"
done
run "$CMD" -e
check "-e without a value: exit 2" "2" "$RC"

# ---- the language of the user (Turkish: I and i are different letters there)
if locale -a 2>/dev/null | grep -qx 'tr_TR.UTF-8'; then
  run env LC_ALL=tr_TR.UTF-8 "$CMD" -e gif t
  check "Turkish locale: -e gif finds IMAGE.GIF" "t/none" "$OUT"
else
  skip "no tr_TR.UTF-8 locale here"
fi

# ---- a name that is not valid text (not every file system allows one)
BADDIR="$(printf 'bad\377name')"
if mkdir "empty/$BADDIR" 2>/dev/null && : > "empty/$BADDIR/x.pdf"; then
  run env LC_ALL=en_US.UTF-8 "$CMD" -c empty
  check "a folder name that is not valid UTF-8 is listed, not an error" "1${TAB}empty/$BADDIR" "$OUT"
  check "and nothing on standard error" "" "$ERR"
  rm -rf "empty/$BADDIR"
else
  skip "this file system refuses names that are not valid UTF-8"
fi

# ---- nothing found, wrong use
run "$CMD" empty
check "no such file: exit 0" "0" "$RC"
check "no such file: nothing on standard output" "" "$OUT"
has "no such file: a note on standard error" "no .pdf file under empty" "$ERR"
run "$CMD" "$W/nowhere"
check "DIR does not exist: exit 1" "1" "$RC"
has "DIR does not exist: says so" "not a folder: $W/nowhere" "$ERR"
check "DIR does not exist: nothing on standard output" "" "$OUT"
run "$CMD" t/root.pdf
check "a file as DIR: exit 1" "1" "$RC"
run "$CMD" t empty
check "two folders: exit 2" "2" "$RC"

# ---- the examples of the help
mkdir -p "$HOME/Documents/tax" "$HOME/Work/letters"
: > "$HOME/Documents/tax/2024.pdf"; : > "$HOME/Work/letters/offer.DOCX"
run "$CMD" ~/Documents
check "example: ~/Documents" "$HOME/Documents/tax" "$OUT"
cd "$HOME/Documents" || exit 1
run "$CMD" -c
check "example: -c" "1${TAB}./tax" "$OUT"
run "$CMD" -e docx ~/Work
check "example: -e docx ~/Work" "$HOME/Work/letters" "$OUT"

cd "$TMP" || exit 1
finish
