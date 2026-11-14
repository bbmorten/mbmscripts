#!/bin/bash
# Tests for mbm-help.   Run:  tests/run.sh help    or:  bash tests/commands/help.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-help"
echo "mbm-help"

# ---------------------------------------------------------------- a small installation
# "$TMP/my repo" is laid out like the repository: bin/ with a copy of the command under
# test and a few empty commands, local/bin/ with a private one, and the descriptions.
# "$TMP/my repo/inst" is what the installer makes: links under another prefix (zz-).
R="$TMP/my repo"
I="$R/inst"
mkdir -p "$R/bin" "$R/libexec" "$R/local/bin" "$I"
cp "$CMD" "$R/bin/mbm-help"
for n in du dns-flush eth-conv my-sync both-systems nodesc notexec "odd name"; do
  printf '#!/bin/sh\n' > "$R/bin/mbm-$n"
  chmod +x "$R/bin/mbm-$n"
done
chmod -x "$R/bin/mbm-notexec"
printf '#!/bin/sh\n' > "$R/local/bin/mbm-mine"
chmod +x "$R/local/bin/mbm-mine"
for f in "$R"/bin/mbm-* "$R"/local/bin/mbm-*; do
  ln -s "$f" "$I/zz-${f##*/mbm-}"
done
ln -s "$R/bin/mbm-gone" "$I/zz-gone"          # a link whose file was removed
mkdir "$I/zz-folder"                          # not a command
: > "$I/other-thing"                          # another prefix

# The two forms of the list: name, description - and with what the command needs.
two_columns() {
  printf '%s\t%s\n' \
    "du" "Save the size of each subdirectory, largest first" \
    "dns-flush" "Flush the macOS DNS cache and restart the DNS service" \
    "eth-conv" "Count the Ethernet conversations in a capture file (tshark)" \
    "my-sync" "Rsync a folder each time it changes" \
    "both-systems" "Works on two systems" \
    "notexec" "A command that lost its x bit" \
    "odd name" "A file name with a space" \
    "help" "List these commands" > "$R/libexec/descriptions.txt"
}
three_columns() {
  printf '%s\t%s\t%s\n' \
    "du" "Save the size of each subdirectory, largest first" "" \
    "dns-flush" "Flush the macOS DNS cache and restart the DNS service" "fakeprog os:macos" \
    "eth-conv" "Count the Ethernet conversations in a capture file (tshark)" "nosuch-tshark" \
    "my-sync" "Rsync a folder each time it changes" "fakeprog nosuch-inotify nosuch-rsync os:linux" \
    "both-systems" "Works on two systems" "os:macos os:linux" \
    "notexec" "A command that lost its x bit" "" \
    "odd name" "A file name with a space" "*" \
    "help" "List these commands" "" > "$R/libexec/descriptions.txt"
}
printf 'mine\tMy own command\tfakeprog\n' > "$R/local/descriptions.txt"
stub fakeprog
stub uname 'echo Darwin'
H="$I/zz-help"
# line NAME - the line of OUT for that command, columns squeezed to one space
line() { printf '%s\n' "$OUT" | awk -v n="$1" 'index($0, n " ") == 1 || $0 == n { sub(/  +/, " "); print }'; }

echo " the list"
two_columns
run "$H"
check "exit 0" "0" "$RC"
check "nothing on standard error" "" "$ERR"
check "every command under the prefix it was called by, one per line" \
  "zz-both-systems zz-dns-flush zz-du zz-eth-conv zz-help zz-mine zz-my-sync zz-nodesc zz-notexec zz-odd" \
  "$(printf '%s\n' "$OUT" | awk '{ printf "%s%s", sep, $1; sep = " " }')"
check "name, then the description" "zz-dns-flush Flush the macOS DNS cache and restart the DNS service" "$(line zz-dns-flush)"
check "a private command gets its description from local/descriptions.txt" "zz-mine My own command" "$(line zz-mine)"
check "a command without a description is listed by name" "zz-nodesc" "$(line zz-nodesc)"
check "a name with a space" "zz-odd name A file name with a space" "$(line "zz-odd name")"
check "the descriptions start in the same column" "1" "$(printf '%s\n' "$OUT" | grep -v '^zz-nodesc$' | awk '{ match($0, /  +/); print RSTART + RLENGTH }' | sort -u | wc -l | tr -d ' ')"
hasnt "a broken link, a folder and other files are not commands" "zz-gone" "$OUT"
hasnt "... the folder" "zz-folder" "$OUT"
hasnt "... the other file" "other-thing" "$OUT"
three_columns
run "$H"
check "with a third column the list is the same: name and description only" "zz-eth-conv Count the Ethernet conversations in a capture file (tshark)" "$(line zz-eth-conv)"
hasnt "... what a command needs is not shown" "nosuch" "$OUT"
check "started by its path from another folder" "10" "$(cd "$TMP" && "my repo/inst/zz-help" | wc -l | tr -d ' ')"
check "found on the PATH" "10" "$(PATH="$I:$PATH" zz-help | wc -l | tr -d ' ')"
check "under the standard prefix, straight from bin/" "mbm-dns-flush" "$("$R/bin/mbm-help" dns | awk '{ print $1 }')"

echo " one word"
run "$H" dns
check "a word in the name: exactly that command" "zz-dns-flush Flush the macOS DNS cache and restart the DNS service" "$(printf '%s\n' "$OUT" | sed 's/  */ /')"
run "$H" RSYNC
check "a word in the description, in capitals" "zz-my-sync" "$(printf '%s\n' "$OUT" | awk '{ print $1 }')"
run "$H" "(tshark)"
check "the word is taken as it is, not as a pattern" "zz-eth-conv" "$(printf '%s\n' "$OUT" | awk '{ print $1 }')"
run "$H" "s.*c"
check "... so a pattern matches nothing: exit 1" "1" "$RC"
run "$H" -- -flush
check "a word with a leading dash, after --" "zz-dns-flush" "$(printf '%s\n' "$OUT" | awk '{ print $1 }')"
run "$H" nosuch
check "the third column is not searched: exit 1" "1" "$RC"
run "$H" kubernetes
check "no command matches: exit 1" "1" "$RC"
has "... it says so" 'no command matches "kubernetes"' "$ERR"
check "... nothing on standard output" "" "$OUT"
LC_ALL=tr_TR.UTF-8 run "$H" FILE
check "capitals match under a Turkish locale (I is not turned into a dotless i)" "zz-eth-conv zz-odd" "$(printf '%s\n' "$OUT" | awk '{ printf "%s%s", sep, $1; sep = " " }')"

echo " --check"
run "$H" --check
check "--check: exit 0" "0" "$RC"
check "one line per command, the broken link included" "11" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
check "needs nothing" "zz-du ok" "$(line zz-du)"
check "its program is installed and this is its system" "zz-dns-flush ok" "$(line zz-dns-flush)"
check "a program that is not installed is named" "zz-eth-conv missing: nosuch-tshark" "$(line zz-eth-conv)"
check "another system, and every missing program" "zz-my-sync for linux only; missing: nosuch-inotify nosuch-rsync" "$(line zz-my-sync)"
check "a command for both systems" "zz-both-systems ok" "$(line zz-both-systems)"
check "a private command is checked from local/descriptions.txt" "zz-mine ok" "$(line zz-mine)"
check "a command without a line in the list" "zz-nodesc unknown: no line for it in descriptions.txt" "$(line zz-nodesc)"
check "a file that is not executable" "zz-notexec not executable" "$(line zz-notexec)"
check "a link whose file is gone" "zz-gone broken link" "$(line zz-gone)"
check "a need is a program name, never a file pattern" "zz-odd name missing: *" "$(line "zz-odd name")"
check "--check runs none of the programs it looks for" "" "$(calls fakeprog)"
stub uname 'echo Linux'
run "$H" -c
check "on Linux: a macOS command" "zz-dns-flush for macos only" "$(line zz-dns-flush)"
check "on Linux: a Linux command with missing programs" "zz-my-sync missing: nosuch-inotify nosuch-rsync" "$(line zz-my-sync)"
check "on Linux: a command for both systems" "zz-both-systems ok" "$(line zz-both-systems)"
stub uname 'echo SunOS'
run "$H" -c both
check "on another system: it names the systems the command is for" "zz-both-systems for macos linux only" "$(line zz-both-systems)"
stub uname 'echo Darwin'
run "$H" -c sync
check "-c WORD: only the matching command" "zz-my-sync for linux only; missing: nosuch-inotify nosuch-rsync" "$(printf '%s\n' "$OUT" | sed 's/  */ /')"
run "$H" sync --check
check "the option may follow the word" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
run "$H" -c missing
check "-c WORD looks at names and descriptions, not at the result: exit 1" "1" "$RC"
two_columns
run "$H" --check
check "a list without the third column: the commands need nothing" "zz-eth-conv ok" "$(line zz-eth-conv)"
check "... and a command without a line is still unknown" "zz-nodesc unknown: no line for it in descriptions.txt" "$(line zz-nodesc)"

echo " no descriptions at all"
mv "$R/libexec" "$R/libexec.away"
mv "$R/local/descriptions.txt" "$R/local/descriptions.away"
run "$H"
check "the names alone: exit 0" "0" "$RC"
check "... all of them" "10" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
check "... nothing on standard error" "" "$ERR"
mv "$R/libexec.away" "$R/libexec"
mv "$R/local/descriptions.away" "$R/local/descriptions.txt"

echo " wrong use"
run "$H" --all
check "an unknown option: exit 2 (the old version searched for it and printed nothing)" "2" "$RC"
has "... the message points to the help" "zz-help --help" "$ERR"
check "... nothing on standard output" "" "$OUT"
run "$H" dns du
check "two words: exit 2" "2" "$RC"
run "$H" --help
check "--help under another prefix names the commands by that prefix" "zz-du --help" "$(printf '%s\n' "$OUT" | grep -o 'zz-du --help')"
hasnt "... and no longer says mbm-" "mbm-" "$OUT"

echo " the real collection, and the examples of the help"
rm -f "$STUBS/uname"
run "$CMD"
check "the list: exit 0" "0" "$RC"
has "the list holds mbm-dns-flush" "mbm-dns-flush " "$OUT"
check "one line per file in bin/" "$(ls "$BIN" | grep -c '^mbm-')" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
run "$CMD" dns
check "mbm-help dns prints exactly one line" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
run "$CMD" docker
check "mbm-help docker: exit 0" "0" "$RC"
has "... the docker commands" "mbm-docker-cmdline" "$OUT"
run "$CMD" --check
check "mbm-help --check: exit 0" "0" "$RC"
check "... one line per file in bin/" "$(ls "$BIN" | grep -c '^mbm-')" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
run "$CMD" -c pdf
check "mbm-help -c pdf: the one command" "mbm-list-folders-with-pdf" "$(printf '%s\n' "$OUT" | awk '{ print $1 }')"

finish
