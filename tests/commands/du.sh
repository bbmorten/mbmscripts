#!/bin/bash
# Tests for mbm-du.   Run:  tests/run.sh du    or:  bash tests/commands/du.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-du"
echo "mbm-du"

W="$TMP/w"
mkdir -p "$W/d/x y/deep/deeper" "$W/d/z" "$W/d/it's small" "$W/-dash/in" "$W/out"
cd "$W" || exit 1
# Sizes far enough apart that the order is the same on every file system.
dd if=/dev/zero of="d/x y/deep/deeper/f" bs=1024 count=1536 2>/dev/null
dd if=/dev/zero of=d/z/g bs=1024 count=200 2>/dev/null
dd if=/dev/zero of="d/it's small/h" bs=1024 count=20 2>/dev/null
dd if=/dev/zero of=./-dash/in/f bs=1024 count=20 2>/dev/null
printf 'keep me\n' > precious.txt
ln -s d link

lines() { printf '%s\n' "$@"; }
# paths - the second column of OUT
paths() { printf '%s\n' "$OUT" | cut -f 2; }

# ---- the main job
before="$(ls -A)"
run "$CMD" d
check "the folder and the folders in it, largest first" "$(lines d "d/x y" d/z "d/it's small")" "$(paths)"
check "exit 0" "0" "$RC"
check "nothing on standard error" "" "$ERR"
check "no file is written into the current folder" "$before" "$(ls -A)"
if printf '%s\n' "$OUT" | head -n 1 | grep -Eq "^ *[0-9.]+[KMG]	d\$"; then ok "each line is a size, a tab and the folder"; else bad "each line is a size, a tab and the folder (got: $(printf '%s\n' "$OUT" | head -n 1))"; fi
case "$(printf '%s\n' "$OUT" | head -n 1)" in *1.[5-9]M*) ok "sizes are shown the short way (1.5M)" ;; *) bad "sizes are shown the short way (got: $OUT)" ;; esac

cd d || exit 1
run "$CMD"
check "without DIR: the current folder" "$(lines . "./x y" ./z "./it's small")" "$(paths)"
cd "$W" || exit 1
run "$CMD" d///
check "trailing slashes on DIR do not change the paths" "$(lines d "d/x y" d/z "d/it's small")" "$(paths)"
run "$CMD" -- -dash
check "DIR that starts with a dash, after --" "$(lines ./-dash ./-dash/in)" "$(paths)"
run "$CMD" link
check "DIR that is a link to a folder is measured, not the link" "$(lines link "link/x y" link/z "link/it's small")" "$(paths)"

# ---- -d
run "$CMD" -d 0 d
check "-d 0: the total only" "d" "$(paths)"
run "$CMD" -d 2 d
check "-d 2: two levels" "$(lines d "d/x y" "d/x y/deep" d/z "d/it's small")" "$(paths)"
run "$CMD" --depth 3 d
has "--depth 3: three levels" "d/x y/deep/deeper" "$OUT"
for bad in abc -1 1.5 ""; do
  run "$CMD" -d "$bad" d
  check "-d '$bad' is not a depth: exit 2" "2" "$RC"
done
run "$CMD" -d
check "-d without a value: exit 2" "2" "$RC"

# ---- -o
run "$CMD" -o "out/sizes of d.txt" d
check "-o: nothing on standard output" "" "$OUT"
check "-o: exit 0" "0" "$RC"
OUT="$(cat "out/sizes of d.txt")"
check "-o: the table is in the file" "$(lines d "d/x y" d/z "d/it's small")" "$(paths)"
run "$CMD" --output "out/sizes of d.txt" -d 0 d
check "--output: an existing file is replaced" "1" "$(wc -l < "out/sizes of d.txt" | tr -d ' ')"
run "$CMD" -o "$W/nowhere/x.txt" d
check "-o in a folder that does not exist: exit 1" "1" "$RC"
has "-o that cannot be written: says so" "cannot write $W/nowhere/x.txt" "$ERR"
run "$CMD" -o
check "-o without a value: exit 2" "2" "$RC"

# ---- the language of the user (the decimal sign must stay a point)
if locale -a 2>/dev/null | grep -qx 'tr_TR.UTF-8'; then
  run env LC_ALL=tr_TR.UTF-8 "$CMD" d
  hasnt "Turkish locale: no decimal comma" "," "$OUT"
  check "Turkish locale: still largest first" "$(lines d "d/x y" d/z "d/it's small")" "$(paths)"
else
  skip "no tr_TR.UTF-8 locale here"
fi

# ---- wrong use, and what the old version did with it
run "$CMD" d precious.txt
check "a second argument (the old way to name the output file): exit 2" "2" "$RC"
has "a second argument: the message names -o" "-o FILE" "$ERR"
check "a second argument: that file is not overwritten" "keep me" "$(cat precious.txt)"
run "$CMD" -o out/never.txt "$W/nowhere"
check "DIR does not exist: exit 1" "1" "$RC"
has "DIR does not exist: says so" "not a folder: $W/nowhere" "$ERR"
if [ -e out/never.txt ]; then bad "DIR does not exist: no output file is left behind"; else ok "DIR does not exist: no output file is left behind"; fi
run "$CMD" d/z/g
check "a file as DIR: exit 1" "1" "$RC"

if [ "$(id -u)" != 0 ]; then
  chmod 000 "d/it's small"
  run "$CMD" d
  check "a folder that may not be read: exit 1" "1" "$RC"
  has "a folder that may not be read: the table is still shown" "d/x y" "$OUT"
  has "a folder that may not be read: says that the sums are too small" "the sums are too small" "$ERR"
  chmod 755 "d/it's small"
else
  skip "running as root: the permission case is not tested"
fi

# ---- the examples of the help
mkdir -p "$HOME/Downloads/iso" "$HOME/Projects/app/src" "$HOME/Documents/tax"
: > "$HOME/Downloads/iso/a"; : > "$HOME/Projects/app/src/a"; : > "$HOME/Documents/tax/a"
run "$CMD" ~/Downloads
check "example: ~/Downloads" "$(lines "$HOME/Downloads" "$HOME/Downloads/iso")" "$(paths | LC_ALL=C sort)"
run "$CMD" -d 2 ~/Projects
has "example: -d 2 ~/Projects" "$HOME/Projects/app/src" "$OUT"
cd "$W/out" || exit 1
run "$CMD" -o sizes.txt ~/Documents
has "example: -o sizes.txt ~/Documents" "$HOME/Documents/tax" "$(cat sizes.txt)"

cd "$TMP" || exit 1
finish
