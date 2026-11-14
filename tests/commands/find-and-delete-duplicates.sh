#!/bin/bash
# Tests for mbm-find-and-delete-duplicates.   Run:  tests/run.sh find-and-delete-duplicates    or:  bash tests/commands/find-and-delete-duplicates.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-find-and-delete-duplicates"
echo "mbm-find-and-delete-duplicates"

W="$TMP/w"
NLNAME="$(printf 'new\nline.txt')"
QNAME="it's \"q\".txt"

# The fixture. Sets of identical files, in the top folder:
#   a.txt  b.txt  "a copy.txt"  zz.txt   (13 bytes)  -> a.txt stays: shortest path, then first
#   -dash  it's "q".txt                  (5 bytes)   -> -dash stays
#   nl.txt  new<line break>line.txt      (3 bytes)   -> nl.txt stays
# and below it: sub dir/a.txt (a copy of a.txt), big.bin + sub dir/big.bin, deep/x/long-name.dat
# + deep/yy/n.dat. Everything else must never be touched.
mk() {
  cd "$TMP" || exit 1
  chmod -R u+rwx "$W" 2>/dev/null
  rm -rf "$W"
  mkdir -p "$W/sub dir" "$W/.git/objects" "$W/sub dir/.git" "$W/deep/x" "$W/deep/yy" "$W/empty"
  cd "$W" || exit 1
  printf 'same content\n' > a.txt
  cp a.txt b.txt; cp a.txt "a copy.txt"; cp a.txt zz.txt; cp a.txt "sub dir/a.txt"
  ln a.txt hard-a.txt                                   # a second name of a.txt, not a copy
  ln -s a.txt link.txt                                  # a symbolic link
  printf 'unique\n' > u.txt
  printf 'SAME SIZE 1\n' > s1.txt; printf 'SAME SIZE 2\n' > s2.txt
  : > e1; : > e2                                        # empty files
  printf 'dash\n' > ./-dash; printf 'dash\n' > "$QNAME"
  printf 'nl\n' > nl.txt; printf 'nl\n' > "$NLNAME"
  printf 'obj\n' > .git/objects/o1; cp .git/objects/o1 .git/objects/o2
  printf 'cfg\n' > "sub dir/.git/c1"; cp "sub dir/.git/c1" "sub dir/.git/c2"
  dd if=/dev/zero of=big.bin bs=1024 count=1536 2>/dev/null; cp big.bin "sub dir/big.bin"
  printf 'deep data\n' > deep/x/long-name.dat; cp deep/x/long-name.dat deep/yy/n.dat
}
# Every name under $W with the checksum of every file: equal before and after = untouched.
snap() { (cd "$W" && find . -print | LC_ALL=C sort && find . -type f -exec cksum {} + | LC_ALL=C sort); }
there() { if [ -e "$2" ] || [ -L "$2" ]; then ok "$1"; else bad "$1 (missing: $2)"; fi; }
gone()  { if [ -e "$2" ] || [ -L "$2" ]; then bad "$1 (still there: $2)"; else ok "$1"; fi; }
untouched() {   # the files no run may ever delete
  there "$1: the empty files stay" e1; there "$1: the empty files stay (2)" e2
  there "$1: files of equal size and other content stay" s1.txt
  there "$1: files of equal size and other content stay (2)" s2.txt
  there "$1: the symbolic link stays" link.txt
  there "$1: the second name (hard link) of the kept file stays" hard-a.txt
  check "$1: the kept file still has its content" "same content" "$(cat a.txt)"
  for f in .git/objects/o1 .git/objects/o2 "sub dir/.git/c1" "sub dir/.git/c2"; do
    there "$1: nothing in a .git folder is deleted ($f)" "$f"
  done
}

# ---- dry run
mk; before="$(snap)"
run "$CMD" -n
check "-n exits 0" "0" "$RC"
check "-n changes nothing" "$before" "$(snap)"
has "-n shows the file that stays" "  keep    ./a.txt" "$OUT"
has "-n shows what would go" "  delete  ./b.txt" "$OUT"
has "-n lists a name with a space" "  delete  ./a copy.txt" "$OUT"
has "-n lists a name with a quote, and keeps the shorter path" "  delete  ./$QNAME" "$OUT"
has "-n keeps the name that starts with a dash" "  keep    ./-dash" "$OUT"
has "-n finds the file with a line break in its name (shown as ?)" "  delete  ./new?line.txt" "$OUT"
has "-n says how many" "5 files in 3 sets could go" "$OUT"
has "-n says that nothing was deleted" "nothing was deleted" "$OUT"
hasnt "empty files are not duplicates" "e1" "$OUT"
hasnt "equal size, other content: not duplicates" "s1.txt" "$OUT"
hasnt "a symbolic link is not listed" "link.txt" "$OUT"
hasnt "a hard link of the kept file is not listed" "hard-a.txt" "$OUT"
hasnt "without -r the folders below are not checked" "sub dir" "$OUT"
hasnt "nothing from .git is listed" ".git" "$OUT"
check "-n writes nothing to standard error" "" "$ERR"

run "$CMD" -r -n -y
check "-n together with -y is still a dry run: nothing changes" "$before" "$(snap)"
has "-n together with -y: says that nothing was deleted" "nothing was deleted" "$OUT"

cd "$TMP" || exit 1
run "$CMD" --dry-run "$W"
has "--dry-run DIR: the folder argument is used" "  keep    $W/a.txt" "$OUT"
check "--dry-run DIR changes nothing" "$before" "$(snap)"
run "$CMD" -n "$W/"
has "a trailing slash on DIR does not change the paths" "  delete  $W/b.txt" "$OUT"

cd "$W" || exit 1
run "$CMD" -rn
check "-rn (letters together) exits 0" "0" "$RC"
check "-rn changes nothing" "$before" "$(snap)"
has "-r checks the folders below" "  delete  ./sub dir/a.txt" "$OUT"
has "-r: the shortest path stays, also across folders" "  keep    ./deep/yy/n.dat" "$OUT"
has "-r: the longer path goes" "  delete  ./deep/x/long-name.dat" "$OUT"
hasnt "-r lists nothing from any .git folder" ".git" "$OUT"
has "-r counts" "8 files in 5 sets could go" "$OUT"
check "the largest set comes first" "3 identical files, 1.5M each:" "$(printf '%s\n' "$OUT" | grep identical | head -n 1 | sed 's/^2 /3 /')"
check "the smallest set comes last" "2 identical files, 3B each:" "$(printf '%s\n' "$OUT" | grep identical | tail -n 1)"

# ---- no terminal: refuse instead of guessing
run "$CMD"
check "no terminal, no --yes: exit 1" "1" "$RC"
has "no terminal: says what to add" "--yes" "$ERR"
check "no terminal, no --yes: nothing changed" "$before" "$(snap)"
run_in "$(printf 'y\ny\ny\ny\n')" "$CMD" -r
check "answers from a pipe are not taken: exit 1" "1" "$RC"
check "answers from a pipe: nothing changed" "$before" "$(snap)"

# ---- --yes
run "$CMD" -y
check "-y exits 0" "0" "$RC"
has "-y reports the number" "Deleted 5 files, 47B in all." "$OUT"
gone "-y deletes the later name of equal length" b.txt
gone "-y deletes the name with a space" "a copy.txt"
gone "-y deletes the longer name" zz.txt
gone "-y deletes the name with a quote" "$QNAME"
gone "-y deletes the name with a line break" "$NLNAME"
there "-y keeps the documented file" a.txt
there "-y keeps the name that starts with a dash" ./-dash
there "-y keeps nl.txt" nl.txt
there "-y without -r leaves the folders below alone" "sub dir/a.txt"
there "-y without -r leaves the folders below alone (2)" "sub dir/big.bin"
untouched "-y"
run "$CMD" --yes
check "a second run finds nothing: exit 0" "0" "$RC"
has "a second run says so" "No duplicate files found" "$OUT"
has "and points to -r" "add -r" "$OUT"

mk
run "$CMD" -r -y
check "-r -y exits 0" "0" "$RC"
has "-r -y reports number and size" "Deleted 8 files, 1.5M in all." "$OUT"
gone "-r -y deletes the copy in the folder below" "sub dir/a.txt"
gone "-r -y deletes the larger copy below" "sub dir/big.bin"
there "-r -y keeps the shorter path of the pair" big.bin
gone "-r -y deletes the longer path" deep/x/long-name.dat
there "-r -y keeps the shorter path" deep/yy/n.dat
untouched "-r -y"
mk
run "$CMD" --recursive --yes .
check "--recursive --yes DIR exits 0" "0" "$RC"
gone "--recursive --yes deletes below" "sub dir/a.txt"
mk
run "$CMD" -ry
gone "-ry (letters together) deletes below" "sub dir/a.txt"

# ---- on a terminal: asked set by set
# ask_run ANSWERS CMD [ARG...] - like tty_run of lib.sh (a pseudo-terminal, one answer per
# line), but it waits for the "[y/N] " of this command, which makes it immediate; RC is the
# exit status of the command; and a command that asks more often than there are answers is
# stopped after 10 seconds (RC 98 or 99) instead of hanging. False when `expect` is not
# installed.
ask_run() {
  local answers="$1" exp
  shift
  exp="$(export PATH="$REAL_PATH"; command -v expect 2>/dev/null)" || return 1
  cat > "$TMP/ask.exp" <<'EOF_ASK_EXP'
set timeout 10
set ended 0
spawn -noecho {*}[lrange $argv 1 end]
foreach a [split [lindex $argv 0] "\n"] {
    expect {
        -re {y/N. $} {}
        timeout { catch close; catch wait; exit 98 }
        eof { set ended 1; break }
    }
    send -- "$a\r"
}
if {!$ended} {
    expect {
        eof {}
        timeout { catch close; catch wait; exit 99 }
    }
}
catch wait result
exit [lindex $result 3]
EOF_ASK_EXP
  OUT="$("$exp" -f "$TMP/ask.exp" -- "$answers" "$@" 2>&1)"
  RC=$?
  OUT="$(printf '%s' "$OUT" | tr -d '\r')"
  ERR=""
  return 0
}
mk; before="$(snap)"
if ask_run "$(printf 'n\nn\nn')" "$CMD"; then
  check "terminal, answer n: exit 0" "0" "$RC"
  has "terminal: it asks" "Delete 3 files? [y/N]" "$OUT"
  check "terminal, answer n: nothing changed" "$before" "$(snap)"
  has "terminal, answer n: says so" "Nothing deleted from this set." "$OUT"
  ask_run "$(printf 'x\nmaybe\nno')" "$CMD"
  check "terminal, any other answer: nothing changed" "$before" "$(snap)"
  # The sets come largest first: a.txt (13 bytes), -dash (5), nl.txt (3).
  ask_run "$(printf 'y\nn\ny')" "$CMD"
  check "terminal, y n y: exit 0" "0" "$RC"
  gone "terminal, y for the first set: deleted" b.txt
  gone "terminal, y for the first set: deleted (2)" "a copy.txt"
  there "terminal, n for the second set: kept" "$QNAME"
  gone "terminal, y for the third set: deleted" "$NLNAME"
  has "terminal: the total counts only what was deleted" "Deleted 4 files" "$OUT"
  untouched "terminal"
  mk; before="$(snap)"; mkdir -p "$TMP/tt"
  ask_run "$(printf '\003')" env TMPDIR="$TMP/tt" "$CMD"
  check "terminal, Ctrl-C at the question: nothing changed" "$before" "$(snap)"
  check "terminal, Ctrl-C at the question: no temporary folder is left" "" "$(ls -A "$TMP/tt")"
  mkdir -p "$HOME/Downloads"; printf 'dl\n' > "$HOME/Downloads/one"; cp "$HOME/Downloads/one" "$HOME/Downloads/one (1)"
  ask_run "y" "$CMD" ~/Downloads
  gone "example: DIR, ask, then delete" "$HOME/Downloads/one (1)"
  there "example: the shorter name stays" "$HOME/Downloads/one"
else
  skip "expect is not installed: the questions on a terminal are not tested"
fi

# ---- the last check before deleting
mk; before="$(snap)"
stub cmp 'exit 1'
run "$CMD" -r -y
check "a file that no longer equals the kept one: exit 1" "1" "$RC"
has "it is named" "not deleted" "$ERR"
check "and nothing is deleted" "$before" "$(snap)"
has "the byte-by-byte comparison is against the kept file" "cmp -s -- ./a.txt ./b.txt" "$(calls cmp)"
rm -f "$STUBS/cmp"; reset_calls

if [ "$(id -u)" != 0 ]; then
  mk
  chmod 555 "sub dir"
  run "$CMD" -r -y
  check "a file that cannot be removed: exit 1" "1" "$RC"
  has "it is named" "not deleted" "$ERR"
  there "it is still there" "sub dir/a.txt"
  gone "the others are deleted" b.txt
  chmod 755 "sub dir"
  mk
  chmod 000 b.txt
  run "$CMD" -y
  check "an unreadable file: exit 1" "1" "$RC"
  has "it is counted" "1 file could not be read" "$ERR"
  there "and never deleted" b.txt
  gone "the readable duplicates are still handled" zz.txt
  chmod 644 b.txt
else
  skip "running as root: the permission cases are not tested"
fi

# ---- what the old version got wrong
mk; before="$(snap)"
mkdir -p "$TMP/other"; printf 'p\n' > "$TMP/other/p1"; printf 'p\n' > "$TMP/other/p2"
cd "$TMP/other" || exit 1
run "$CMD" -y "$W"
there "DIR is checked, not the current folder" p2
gone "DIR is checked, not the current folder (2)" "$W/b.txt"
cd "$W" || exit 1
mk; before="$(snap)"
run "$CMD" --help
check "--help changes nothing" "$before" "$(snap)"
hasnt "--help does not look for duplicates" "identical files" "$OUT"

# ---- .git, links
run "$CMD" -r -y .git
check "DIR is a .git folder: exit 1" "1" "$RC"
has "DIR is a .git folder: says why" ".git folder" "$ERR"
cd "$W/.git/objects" || exit 1
run "$CMD" -y
check "inside a .git folder: exit 1" "1" "$RC"
cd "$W" || exit 1
check ".git is untouched" "$before" "$(snap)"

mkdir -p "$TMP/outside"; printf 'out\n' > "$TMP/outside/o1"; printf 'out\n' > "$TMP/outside/o2"
ln -s "$TMP/outside" "$W/outlink"
run "$CMD" -r -y
there "a linked folder below DIR is not entered" "$TMP/outside/o2"
ln -s "$TMP/outside" "$TMP/dirlink"
run "$CMD" -n "$TMP/dirlink"
has "a DIR that is itself a link to a folder is checked" "  delete  $TMP/dirlink/o2" "$OUT"

# ---- nothing to do, wrong use
run "$CMD" -r "$W/empty"
check "an empty folder without --yes and without a terminal: exit 1" "1" "$RC"
run "$CMD" -rn "$W/empty"
check "an empty folder: exit 0" "0" "$RC"
has "an empty folder: no duplicates" "No duplicate files found in: $W/empty" "$OUT"
run "$CMD" -n "$TMP/nowhere"
check "a folder that does not exist: exit 1" "1" "$RC"
has "a folder that does not exist: says so" "not a folder: $TMP/nowhere" "$ERR"
run "$CMD" -n a.txt
check "a file instead of a folder: exit 1" "1" "$RC"
run "$CMD" -n . "$W/empty"
check "two folders: exit 2" "2" "$RC"
mk; before="$(snap)"
run "$CMD" -yx
check "an unknown letter among known ones: exit 2" "2" "$RC"
check "and nothing is deleted" "$before" "$(snap)"
mkdir -p "$W/-d"; printf 'k\n' > "$W/-d/k1"; printf 'k\n' > "$W/-d/k2"
run "$CMD" -n -- -d
has "a folder name that starts with a dash, after --" "  delete  ./-d/k2" "$OUT"

# ---- the checksum program
mkdir -p "$TMP/minbin"
ln -s "$(command -v bash)" "$TMP/minbin/bash"
run env PATH="$TMP/minbin" "$CMD" -n "$W"
check "no checksum program: exit 1" "1" "$RC"
has "no checksum program: says which are needed" "neither shasum nor sha256sum is installed" "$ERR"
if command -v sha256sum >/dev/null 2>&1; then
  for p in find xargs stat awk paste sort wc tr mktemp rm cmp sha256sum; do ln -s "$(command -v "$p")" "$TMP/minbin/$p"; done
  rm -f "$W/$NLNAME"      # the BSD sha256sum does not keep such a name on one line
  run env PATH="$TMP/minbin" "$CMD" -n "$W"
  has "sha256sum is used when shasum is missing" "  delete  $W/b.txt" "$OUT"
else
  skip "no sha256sum here: only shasum is tested"
fi

# ---- the other examples of the help
mkdir -p "$HOME/Pictures/2024"; printf 'img\n' > "$HOME/Pictures/a.jpg"; cp "$HOME/Pictures/a.jpg" "$HOME/Pictures/2024/a (1).jpg"
run "$CMD" -rn ~/Pictures
has "example: -rn ~/Pictures" "  delete  $HOME/Pictures/2024/a (1).jpg" "$OUT"
there "example: -rn deletes nothing" "$HOME/Pictures/2024/a (1).jpg"
run "$CMD" -r -y ~/Pictures
gone "example: -r -y ~/Pictures" "$HOME/Pictures/2024/a (1).jpg"

cd "$TMP" || exit 1
finish
