#!/bin/bash
# Tests for mbm-find-files-over-100m.   Run:  tests/run.sh find-files-over-100m    or:  bash tests/commands/find-files-over-100m.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-find-files-over-100m"
echo "mbm-find-files-over-100m"

W="$TMP/w"
TAB="$(printf '\t')"
NLNAME="$(printf 'new\nline.bin')"
mkdir -p "$W/a b" "$W/sub" "$W/empty" "$W/-dash" "$W/locked" "$W/small"
cd "$W" || exit 1
# sized BYTES FILE - a file of that length that takes no room on the disk (a sparse file)
sized() { dd if=/dev/zero of="$2" bs=1 count=0 seek="$1" 2>/dev/null; }
sized 1610612736 sub/huge.bin          # 1.5 GB
sized 209715200 "a b/big one.bin"      # 200 MB
sized 104857600 sub/exactly-100m.bin   # exactly 100 MB: not "larger than"
sized 104857601 "-dash/it's just over.bin"
sized 157286400 "sub/$NLNAME"          # 150 MB
sized 614400 sub/mid.bin               # 600 KB
sized 3000 small/s3000
sized 1025 small/s1025
sized 1024 small/s1024
sized 314572800 locked/hidden.bin
ln -s sub link

lines() { printf '%s\n' "$@"; }
ALL="$(lines "1.5G${TAB}./sub/huge.bin" "200M${TAB}./a b/big one.bin" "150M${TAB}./sub/new?line.bin" "100M${TAB}./-dash/it's just over.bin")"

# ---- the main job
chmod 000 locked
before="$(ls -A)"
run "$CMD"
check "the files over 100 MB under the current folder, largest first" "$ALL" "$OUT"
check "exit 0" "0" "$RC"
check "a folder that may not be read gives no message" "" "$ERR"
check "no file is written into the current folder" "$before" "$(ls -A)"
chmod 755 locked

run "$CMD" "$W/a b"
check "DIR with a space in its name" "200M${TAB}$W/a b/big one.bin" "$OUT"
run "$CMD" sub/
check "a trailing slash on DIR does not change the paths" \
  "$(lines "1.5G${TAB}sub/huge.bin" "150M${TAB}sub/new?line.bin")" "$OUT"
run "$CMD" -- -dash
check "DIR that starts with a dash, after --" "100M${TAB}./-dash/it's just over.bin" "$OUT"
run "$CMD" link
check "DIR that is a link to a folder is searched" "$(lines "1.5G${TAB}link/huge.bin" "150M${TAB}link/new?line.bin")" "$OUT"

# ---- -s
run "$CMD" -s 1G
check "-s 1G" "1.5G${TAB}./sub/huge.bin" "$OUT"
run "$CMD" --size 500K sub
check "--size 500K" "$(lines "1.5G${TAB}sub/huge.bin" "150M${TAB}sub/new?line.bin" "100M${TAB}sub/exactly-100m.bin" "600K${TAB}sub/mid.bin")" "$OUT"
run "$CMD" -s 500k sub
has "-s in lower case" "600K${TAB}sub/mid.bin" "$OUT"
run "$CMD" -s 1gb
check "-s 1gb" "1.5G${TAB}./sub/huge.bin" "$OUT"
run "$CMD" -s 1K small
check "-s 1K: larger than, not equal; small sizes with one decimal" "$(lines "2.9K${TAB}small/s3000" "1.0K${TAB}small/s1025")" "$OUT"
run "$CMD" -s 1000 small
check "-s with a number alone is bytes" "$(lines "2.9K${TAB}small/s3000" "1.0K${TAB}small/s1025" "1.0K${TAB}small/s1024")" "$OUT"
run "$CMD" -s 0600K sub
check "-s with leading zeros is still decimal" "$(lines "1.5G${TAB}sub/huge.bin" "150M${TAB}sub/new?line.bin" "100M${TAB}sub/exactly-100m.bin")" "$OUT"
run "$CMD" -s 100MB sub
check "-s 100MB: a B after the letter is fine" "$(lines "1.5G${TAB}sub/huge.bin" "150M${TAB}sub/new?line.bin")" "$OUT"
for bad in 1.5G abc "" 5X -3M 9999999T 12345678901234567890; do
  run "$CMD" -s "$bad"
  check "-s '$bad' is not a size: exit 2" "2" "$RC"
done
run "$CMD" -s
check "-s without a value: exit 2" "2" "$RC"

# ---- -o
run "$CMD" -o "$TMP/out list.txt"
check "-o: nothing on standard output" "" "$OUT"
check "-o: the list is in the file, the folder that can be read now included" \
  "$(lines "1.5G${TAB}./sub/huge.bin" "300M${TAB}./locked/hidden.bin" "200M${TAB}./a b/big one.bin" "150M${TAB}./sub/new?line.bin" "100M${TAB}./-dash/it's just over.bin")" "$(cat "$TMP/out list.txt")"
run "$CMD" --output "$TMP/out list.txt" -s 1G
check "--output: an existing file is replaced" "1.5G${TAB}./sub/huge.bin" "$(cat "$TMP/out list.txt")"
run "$CMD" -o "$TMP/nowhere/x.txt"
check "-o in a folder that does not exist: exit 1" "1" "$RC"
has "-o that cannot be written: says so" "cannot write $TMP/nowhere/x.txt" "$ERR"
run "$CMD" -o
check "-o without a value: exit 2" "2" "$RC"

# ---- the language of the user (the decimal sign must stay a point)
if locale -a 2>/dev/null | grep -qx 'tr_TR.UTF-8'; then
  run env LC_ALL=tr_TR.UTF-8 "$CMD" -s 1G
  check "Turkish locale: 1.5G, not 1,5G" "1.5G${TAB}./sub/huge.bin" "$OUT"
else
  skip "no tr_TR.UTF-8 locale here"
fi

# ---- nothing found, wrong use
run "$CMD" "$W/empty"
check "nothing that large: exit 0" "0" "$RC"
check "nothing that large: nothing on standard output" "" "$OUT"
has "nothing that large: a note on standard error" "no file under $W/empty is larger than 100M" "$ERR"
run "$CMD" -s 10T -o "$TMP/none.txt"
check "nothing that large with -o: the file is empty" "" "$(cat "$TMP/none.txt")"
run "$CMD" "$W/nowhere"
check "DIR does not exist: exit 1" "1" "$RC"
has "DIR does not exist: says so" "not a folder: $W/nowhere" "$ERR"
run "$CMD" sub/mid.bin
check "a file as DIR: exit 1" "1" "$RC"
run "$CMD" sub small
check "two folders: exit 2" "2" "$RC"

# ---- the examples of the help
mkdir -p "$HOME/Downloads" "$HOME/Documents"
sized 209715200 "$HOME/Downloads/movie.mp4"; sized 2147483648 "$HOME/Downloads/disk.img"; sized 600000 "$HOME/Documents/scan.pdf"
run "$CMD" ~/Downloads
check "example: ~/Downloads" "$(lines "2.0G${TAB}$HOME/Downloads/disk.img" "200M${TAB}$HOME/Downloads/movie.mp4")" "$OUT"
run "$CMD" -s 1G ~
check "example: -s 1G ~" "2.0G${TAB}$HOME/Downloads/disk.img" "$OUT"
cd "$W/empty" || exit 1
run "$CMD" -s 500K -o big.txt ~/Documents
check "example: -s 500K -o big.txt ~/Documents" "586K${TAB}$HOME/Documents/scan.pdf" "$(cat big.txt)"

cd "$TMP" || exit 1
finish
