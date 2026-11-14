#!/bin/bash
# Tests for mbm-my-sync.   Run:  tests/run.sh my-sync    or:  bash tests/commands/my-sync.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-my-sync"
echo "mbm-my-sync"

# rsync, fswatch and inotifywait are fakes throughout: nothing is copied or watched for real.
export TEST_TMP="$TMP"
export TMPDIR="$TMP/tmpdir"          # where the command puts its pipe; must be empty afterwards
W="$TMP/work"
mkdir -p "$TMPDIR" "$W/my src/sub" "$W/dst" "$W/-dash" "$W/it's" "$HOME/notes" "$HOME/site"
echo hi > "$W/my src/a b.txt"
cd "$W" || exit 1

n_rsync() { calls rsync | wc -l | tr -d ' '; }
leftovers() { find "$TMPDIR" -mindepth 1 | wc -l | tr -d ' '; }
# wait_until N FILE - up to 10 seconds, until rsync was called N times and FILE exists
wait_until() {
  local i=0
  while [ "$i" -lt 100 ]; do
    [ "$(n_rsync)" -ge "$1" ] && [ -e "$2" ] && return 0
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}
# A PATH with the system tools the command uses and nothing it has to look for.
BARE="$TMP/bare"
mkdir -p "$BARE"
for t in bash awk sed mktemp mkfifo rm sleep cat; do
  p="$(command -v "$t")" && ln -s "$p" "$BARE/$t"
done
# on_tty WAIT_FOR KEYS CMD [ARG...] - run CMD on a pseudo-terminal, as a person would, and
# type KEYS once it has printed WAIT_FOR. Sets OUT (what the terminal showed) and RC (the
# exit status of CMD; 98 when WAIT_FOR never came). False when `expect` is not installed.
# (tty_run of lib.sh cannot press Ctrl-C, and it does not report the exit status.)
CTRL_C=$'\003'
CR=$'\r'
on_tty() {
  local exp
  exp="$(command -v expect 2>/dev/null)" || return 1
  cat > "$TMP/on_tty.exp" <<'EOF_ON_TTY_EXP'
set timeout 15
spawn -noecho {*}[lrange $argv 2 end]
expect {
    -ex [lindex $argv 0] {}
    timeout { exit 98 }
    eof { exit 99 }
}
send -- [lindex $argv 1]
expect {
    eof {}
    timeout { exit 97 }
}
catch wait result
exit [lindex $result 3]
EOF_ON_TTY_EXP
  "$exp" -f "$TMP/on_tty.exp" -- "$@" > "$TMP/on_tty.out" 2>&1
  RC=$?
  OUT="$(tr -d '\r' < "$TMP/on_tty.out")"
  ERR=""
}
BLOCKING='echo $$ > "$TEST_TMP/watch.pid"; exec sleep 30'   # a watcher that never reports

# ---- wrong use
stub rsync
stub fswatch
run "$CMD"
check "no arguments: exit 2" "2" "$RC"
has "no arguments: says what to give" "SRC DST" "$ERR"
run "$CMD" "my src" dst alice
check "three arguments: exit 2" "2" "$RC"
run "$CMD" nosuch dst
check "a folder that does not exist: exit 1" "1" "$RC"
has "a folder that does not exist: named" "no such folder: nosuch" "$ERR"
check "wrong use runs nothing" "" "$(calls)"

# ---- the dry run
run "$CMD" -n "my src" dst
check "-n: exit 0" "0" "$RC"
check "-n: one rsync --dry-run, without --delete, and no watcher" "rsync -avz --inplace --dry-run my src dst" "$(calls)"
reset_calls
run "$CMD" --dry-run --delete "$HOME/site/" deploy@web1.example.com:/var/www/site
check "-n -D (an example in the help): rsync shows the removals too, nobody is asked" \
  "rsync -avz --inplace --delete --dry-run $HOME/site/ deploy@web1.example.com:/var/www/site" "$(calls)"
stub rsync 'exit 23'
run "$CMD" -n "my src" dst
check "-n: rsync fails: exit 1" "1" "$RC"
has "-n: rsync fails: said" "rsync failed" "$ERR"

# ---- first copy, then one copy per change
# Two changes two seconds apart; the copy after the first change fails.
reset_calls
stub rsync 'n=$(cat "$TEST_TMP/n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$TEST_TMP/n"; echo "$USER" > "$TEST_TMP/user"; [ $n -ne 2 ]'
stub fswatch 'echo 1; sleep 2; echo 1'
USER=me run "$CMD" "my src" dst
check "the watcher is fswatch, on the folder, started before the first copy" "fswatch -o -r my src" "$(calls | head -n 1)"
check "one copy at the start and one per change" "3" "$(n_rsync)"
check "every copy is the same rsync, without --delete" "rsync -avz --inplace my src dst" "$(calls rsync | sort -u)"
has "a copy that fails is reported and the watching goes on" "runs again after the next change" "$ERR"
check "the watcher ends: exit 1" "1" "$RC"
has "the watcher ends: said" "fswatch ended" "$ERR"
check "nothing is left in the temporary folder" "0" "$(leftovers)"

reset_calls
stub rsync 'echo "$USER" > "$TEST_TMP/user"'
stub fswatch 'echo 1; echo 1; echo 1'
run "$CMD" "my src/" dst
check "three changes at once are copied in one go" "2" "$(n_rsync)"
check "SRC/ is handed to rsync as written" "rsync -avz --inplace my src/ dst" "$(calls rsync | sort -u)"

# ---- another machine
stub fswatch
reset_calls
USER=me run "$CMD" "$HOME/notes" notes deploy web1.example.com
check "SRC DST USER HOST (an example in the help)" "rsync -avz --inplace $HOME/notes deploy@web1.example.com:notes" "$(calls rsync)"
check "the shell's own USER is not changed for the programs it starts" "me" "$(cat "$TMP/user")"
reset_calls
run "$CMD" "$HOME/notes" /Volumes/backup
check "a local folder (an example in the help)" "rsync -avz --inplace $HOME/notes /Volumes/backup" "$(calls rsync)"

# ---- names
reset_calls
run "$CMD" -- -dash "it's"
check "a folder that starts with a dash is not read as an option" "rsync -avz --inplace ./-dash it's" "$(calls rsync)"
check "the watcher gets the same name" "fswatch -o -r ./-dash" "$(calls fswatch)"

# ---- --delete
reset_calls
run "$CMD" -D "my src" dst
check "-D without --yes and without a terminal: exit 1" "1" "$RC"
has "-D without a terminal: says how to go ahead" "--yes" "$ERR"
check "-D without a terminal: nothing ran" "" "$(calls)"
run "$CMD" -D -y "$HOME/site/" deploy@web1.example.com:/var/www/site
check "-D -y (an example in the help): rsync gets --delete" \
  "rsync -avz --inplace --delete $HOME/site/ deploy@web1.example.com:/var/www/site" "$(calls rsync)"
reset_calls
if on_tty "[y/N]" "n$CR" "$CMD" --delete "my src" dst; then
  has "-D on a terminal: asks, naming both folders" "Remove from dst everything that is not in my src? [y/N]" "$OUT"
  check "-D on a terminal, answer n: exit 1" "1" "$RC"
  check "-D on a terminal, answer n: nothing ran" "" "$(calls)"
  on_tty "[y/N]" "y$CR" "$CMD" --delete "my src" dst
  has "-D on a terminal, answer y: it goes on" "watching my src" "$OUT"
  check "-D on a terminal, answer y: copied with --delete" "rsync -avz --inplace --delete my src dst" "$(calls rsync)"
else
  skip "no expect: the question of -D is not tested"
fi

# ---- what it needs
reset_calls
run env PATH="$BARE" "$CMD" "my src" dst
check "no rsync: exit 1" "1" "$RC"
has "no rsync: said" "rsync is not installed" "$ERR"
ln -s "$STUBS/rsync" "$BARE/rsync"
run env PATH="$BARE" "$CMD" "my src" dst
check "no watcher: exit 1" "1" "$RC"
has "no watcher: says how to get one on macOS" "brew install fswatch" "$ERR"
has "no watcher: says how to get one on Linux" "apt install inotify-tools" "$ERR"
check "no watcher: nothing was copied" "" "$(calls)"
run env PATH="$BARE" "$CMD" -n "my src" dst
check "-n needs no watcher" "0" "$RC"
reset_calls
# (It reports one change and succeeds once only, so that a loop around it ends.)
stub inotifywait 'echo "my src/ MODIFY a b.txt"; [ ! -e "$TEST_TMP/inotify.ran" ] && : > "$TEST_TMP/inotify.ran"'
ln -s "$STUBS/inotifywait" "$BARE/inotifywait"
run env PATH="$BARE" "$CMD" "my src" dst
check "without fswatch it watches with inotifywait (Linux), changes only" \
  "inotifywait -m -r -q -e modify -e create -e delete -e move -e attrib my src" "$(calls inotifywait)"
check "inotifywait: one copy at the start and one for the change" "2" "$(n_rsync)"

# ---- stopping
reset_calls
rm -f "$TMP/watch.pid"
stub fswatch "$BLOCKING"
stub rsync 'exit 12'
run "$CMD" "my src" dst
check "the first copy fails: exit 1" "1" "$RC"
has "the first copy fails: said" "rsync failed" "$ERR"
sleep 0.2
kill -0 "$(cat "$TMP/watch.pid")" 2>/dev/null && bad "the first copy fails: the watcher is stopped" || ok "the first copy fails: the watcher is stopped"

reset_calls
rm -f "$TMP/watch.pid"
stub rsync
"$CMD" "my src" dst > "$TMP/term.out" 2> "$TMP/term.err" < /dev/null &
pid=$!
if wait_until 1 "$TMP/watch.pid"; then
  ok "it copies once before anything changes"
  sleep 0.3
  kill -TERM "$pid"
  wait "$pid"
  check "stopped by a signal: exit 0" "0" "$?"
  has "stopped by a signal: said" "stopped" "$(cat "$TMP/term.err")"
  sleep 0.2
  kill -0 "$(cat "$TMP/watch.pid")" 2>/dev/null && bad "stopped: the watcher is gone" || ok "stopped: the watcher is gone"
  check "stopped: nothing is left in the temporary folder" "0" "$(leftovers)"
else
  kill "$pid" 2>/dev/null
  bad "it copies once before anything changes (no rsync call within 10 seconds)"
fi

reset_calls
rm -f "$TMP/watch.pid"
if on_tty "stop with Ctrl-C" "$CTRL_C" "$CMD" "my src" dst; then
  check "Ctrl-C on a terminal: exit 0" "0" "$RC"
  has "Ctrl-C on a terminal: said" "stopped" "$OUT"
  sleep 0.2
  kill -0 "$(cat "$TMP/watch.pid" 2>/dev/null)" 2>/dev/null && bad "Ctrl-C: the watcher is gone" || ok "Ctrl-C: the watcher is gone"
  check "Ctrl-C: nothing is left in the temporary folder" "0" "$(leftovers)"
else
  skip "no expect: Ctrl-C on a terminal is not tested"
fi

finish
