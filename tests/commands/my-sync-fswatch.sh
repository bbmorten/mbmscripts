#!/bin/bash
# Tests for mbm-my-sync-fswatch.   Run:  tests/run.sh my-sync-fswatch    or:  bash tests/commands/my-sync-fswatch.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-my-sync-fswatch"
echo "mbm-my-sync-fswatch"

# ssh, rsync, fswatch and inotifywait are fakes throughout: nothing connects anywhere.
export TEST_TMP="$TMP"
export TMPDIR="$TMP/tmpdir"          # where the command puts its pipe; must be empty afterwards
W="$TMP/work"
mkdir -p "$TMPDIR" "$W/my copy" "$W/-dash" "$HOME/site-copy"
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
# What the one ssh connection must be given, for REMOTE_FOLDER = $1 as the remote shell reads it.
watcher_call() {
  printf '%s\n' "ssh -T -o ServerAliveInterval=30 deploy@web1.example.com PATH=\"\$PATH:/opt/homebrew/bin:/usr/local/bin\"" \
    "if command -v fswatch >/dev/null 2>&1; then exec fswatch -o -r $1" \
    "elif command -v inotifywait >/dev/null 2>&1; then exec inotifywait -m -r -q -e modify -e create -e delete -e move -e attrib $1" \
    "else exit 44; fi"
}

# ---- wrong use
stub rsync
stub ssh
run "$CMD"
check "no arguments: exit 2" "2" "$RC"
has "no arguments: says what to give" "USER HOST REMOTE_FOLDER" "$ERR"
run "$CMD" deploy web1.example.com
check "two arguments: exit 2" "2" "$RC"
run "$CMD" deploy web1.example.com /a /b
check "four arguments: exit 2" "2" "$RC"
run "$CMD" deploy web1.example.com site -l
check "an option after the arguments is a surplus argument: exit 2" "2" "$RC"
run "$CMD" -l
check "-l without a folder: exit 2" "2" "$RC"
run "$CMD" -oProxyCommand=x web1.example.com site
check "a user name that looks like an ssh option: exit 2" "2" "$RC"
run "$CMD" -l nosuch deploy web1.example.com site
check "a local folder that does not exist: exit 1" "1" "$RC"
has "a local folder that does not exist: named" "no such folder: nosuch" "$ERR"
check "wrong use runs nothing" "" "$(calls)"

# ---- the dry run
run "$CMD" -l "$HOME/site-copy" -n deploy web1.example.com site/
check "-n (an example in the help): exit 0" "0" "$RC"
check "-n: one rsync --dry-run and no ssh connection" "rsync -avz --dry-run deploy@web1.example.com:site/ $HOME/site-copy/" "$(calls)"
reset_calls
run "$CMD" --dry-run --delete --local "my copy" deploy web1.example.com site/
check "-n -D: rsync shows the removals too, nobody is asked" "rsync -avz --delete --dry-run deploy@web1.example.com:site/ my copy/" "$(calls)"

# ---- first pull, then one pull per change line of the one ssh connection
# Two change lines two seconds apart, then the connection breaks; the pull after the first change fails.
reset_calls
stub rsync 'n=$(cat "$TEST_TMP/n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$TEST_TMP/n"; [ $n -ne 2 ]'
stub ssh 'echo 1; sleep 2; echo 1; exit 255'
run "$CMD" deploy web1.example.com /var/log/myapp
check "it pulls before it connects to watch" "rsync -avz deploy@web1.example.com:/var/log/myapp ./" "$(calls | head -n 1)"
check "one pull at the start and one per change" "3" "$(n_rsync)"
check "every pull is the same rsync, into the current folder, without --delete" \
  "rsync -avz deploy@web1.example.com:/var/log/myapp ./" "$(calls rsync | sort -u)"
check "one ssh connection, running a watcher on the other machine" "$(watcher_call "'/var/log/myapp'")" "$(calls | grep -v '^rsync ')"
hasnt "the host key check is not switched off" "StrictHostKeyChecking" "$(calls)"
has "a pull that fails is reported and the watching goes on" "runs again after the next change" "$ERR"
check "the connection ends: exit 1" "1" "$RC"
has "the connection ends: said" "the connection to web1.example.com ended" "$ERR"
check "nothing is left in the temporary folder" "0" "$(leftovers)"

reset_calls
stub rsync
stub ssh 'echo 1; echo 1; echo 1'
run "$CMD" -l "my copy" deploy web1.example.com "it's a folder"
check "three changes at once are pulled in one go" "2" "$(n_rsync)"
check "-l: the local folder, with a space in its name" "rsync -avz deploy@web1.example.com:it's a folder my copy/" "$(calls rsync | sort -u)"
has "the watcher on the other machine ends by itself: said" "the watcher on web1.example.com ended (exit 0)" "$ERR"
check "a quote in the remote folder is quoted for the remote shell" "$(watcher_call "'it'\\''s a folder'")" "$(calls | grep -v '^rsync ')"
reset_calls
run "$CMD" -l -dash deploy web1.example.com -odd
check "names that start with a dash are not read as options" "rsync -avz deploy@web1.example.com:./-odd ./-dash/" "$(calls rsync | sort -u)"

# ---- the watcher command, run by a fake "other machine" that has only what $TMP/rbin holds
# The first line (it adds Homebrew's folder to the PATH) is checked above and not run here.
mkdir -p "$TMP/rbin"
ln -s "$BARE/sleep" "$TMP/rbin/sleep"
stub ssh 'for a in "$@"; do script="$a"; done
case "$(printf "%s\n" "$script" | sed -n 1p)" in "PATH=\"\$PATH:/opt/homebrew/bin:/usr/local/bin\"") ;; *) exit 99 ;; esac
PATH="$TEST_TMP/rbin" /bin/sh -c "$(printf "%s\n" "$script" | sed 1d)"'
stub fswatch 'echo "$#|$3" > "$TEST_TMP/watched"; echo 1'
stub inotifywait 'echo "$#|${14}" > "$TEST_TMP/watched"; echo "x MODIFY y"; echo "x MODIFY z"'
reset_calls
run "$CMD" deploy web1.example.com site
check "no watcher on the other machine: exit 1" "1" "$RC"
has "no watcher on the other machine: says what to install there (macOS)" "brew install fswatch" "$ERR"
has "no watcher on the other machine: says what to install there (Linux)" "apt install inotify-tools" "$ERR"
ln -s "$STUBS/inotifywait" "$TMP/rbin/inotifywait"
reset_calls
run "$CMD" deploy web1.example.com "it's a folder"
check "the other machine has inotifywait only: it is used, for changes only" \
  "inotifywait -m -r -q -e modify -e create -e delete -e move -e attrib it's a folder" "$(calls inotifywait)"
check "inotifywait: the folder name arrives as one argument" "14|it's a folder" "$(cat "$TMP/watched")"
check "inotifywait: two lines at once are one pull" "2" "$(n_rsync)"
ln -s "$STUBS/fswatch" "$TMP/rbin/fswatch"
reset_calls
run "$CMD" deploy web1.example.com "it's a folder"
check "the other machine has both: fswatch is used" "fswatch -o -r it's a folder" "$(calls | grep -E '^(fswatch|inotifywait)')"
check "fswatch: the folder name arrives as one argument" "3|it's a folder" "$(cat "$TMP/watched")"

# ---- --delete
stub ssh
reset_calls
run "$CMD" -D deploy web1.example.com site/
check "-D without --yes and without a terminal: exit 1" "1" "$RC"
has "-D without a terminal: says how to go ahead" "--yes" "$ERR"
check "-D without a terminal: nothing ran" "" "$(calls)"
run "$CMD" -D -y deploy web1.example.com site/
check "-D -y: rsync gets --delete" "rsync -avz --delete deploy@web1.example.com:site/ ./" "$(calls rsync)"
reset_calls
if on_tty "[y/N]" "n$CR" "$CMD" -l "$HOME/site-copy" -D deploy web1.example.com site/; then
  has "-D on a terminal (an example in the help): asks, naming both sides" \
    "Remove from $HOME/site-copy/ everything that is not in deploy@web1.example.com:site/? [y/N]" "$OUT"
  check "-D on a terminal, answer n: exit 1" "1" "$RC"
  check "-D on a terminal, answer n: nothing ran" "" "$(calls)"
  on_tty "[y/N]" "y$CR" "$CMD" -l "$HOME/site-copy" -D deploy web1.example.com site/
  check "-D on a terminal, answer y: pulled with --delete" \
    "rsync -avz --delete deploy@web1.example.com:site/ $HOME/site-copy/" "$(calls rsync)"
else
  skip "no expect: the question of -D is not tested"
fi

# ---- what it needs
reset_calls
run env PATH="$BARE" "$CMD" deploy web1.example.com site
check "no rsync: exit 1" "1" "$RC"
has "no rsync: said" "rsync is not installed" "$ERR"
ln -s "$STUBS/rsync" "$BARE/rsync"
run env PATH="$BARE" "$CMD" deploy web1.example.com site
check "no ssh: exit 1" "1" "$RC"
has "no ssh: said" "ssh is not installed" "$ERR"
check "no ssh: nothing ran" "" "$(calls)"

# ---- stopping
stub ssh 'echo $$ > "$TEST_TMP/watch.pid"; exec sleep 30'
stub rsync 'exit 12'
run "$CMD" deploy web1.example.com site
check "the first pull fails: exit 1" "1" "$RC"
has "the first pull fails: said" "rsync failed" "$ERR"
check "the first pull fails: no connection is opened" "" "$(calls ssh)"

reset_calls
rm -f "$TMP/watch.pid"
stub rsync
"$CMD" deploy web1.example.com site > "$TMP/term.out" 2> "$TMP/term.err" < /dev/null &
pid=$!
if wait_until 1 "$TMP/watch.pid"; then
  ok "it pulls once before anything changes"
  sleep 0.3
  kill -TERM "$pid"
  wait "$pid"
  check "stopped by a signal: exit 0" "0" "$?"
  has "stopped by a signal: said" "stopped" "$(cat "$TMP/term.err")"
  sleep 0.2
  kill -0 "$(cat "$TMP/watch.pid")" 2>/dev/null && bad "stopped: the ssh connection is closed" || ok "stopped: the ssh connection is closed"
  check "stopped: nothing is left in the temporary folder" "0" "$(leftovers)"
else
  kill "$pid" 2>/dev/null
  bad "it pulls once before anything changes (no rsync call within 10 seconds)"
fi

reset_calls
rm -f "$TMP/watch.pid"
if on_tty "stop with Ctrl-C" "$CTRL_C" "$CMD" deploy web1.example.com site; then
  check "Ctrl-C on a terminal: exit 0" "0" "$RC"
  has "Ctrl-C on a terminal: said" "stopped" "$OUT"
  sleep 0.2
  kill -0 "$(cat "$TMP/watch.pid" 2>/dev/null)" 2>/dev/null && bad "Ctrl-C: the ssh connection is closed" || ok "Ctrl-C: the ssh connection is closed"
  check "Ctrl-C: nothing is left in the temporary folder" "0" "$(leftovers)"
else
  skip "no expect: Ctrl-C on a terminal is not tested"
fi

finish
