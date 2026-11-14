#!/bin/bash
# Tests for mbm-sync-git-msp.   Run:  tests/run.sh sync-git-msp    or:  bash tests/commands/sync-git-msp.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-sync-git-msp"
# TEST_CMD=/path/to/another/copy runs the same checks on that copy (for example the script
# as it was before the rework, to see which checks it fails).
[ -n "${TEST_CMD:-}" ] && CMD="$TEST_CMD"
echo "mbm-sync-git-msp"

# rsync, ssh and fswatch are fakes here; nothing connects anywhere. The hosts are made up.
export TMP
export TMPDIR="$TMP/tmp"
mkdir -p "$TMPDIR"
LOGS="$HOME/.local/log/sync-git-msp"
SRC="$HOME/git-msp"
EXC="--exclude=.git/ --exclude=node_modules/ --exclude=.next/ --exclude=.nuxt/ --exclude=dist/ --exclude=build/ --exclude=out/ --exclude=__pycache__/ --exclude=*.pyc --exclude=.venv/ --exclude=venv/ --exclude=.env --exclude=.env.local --exclude=vendor/ --exclude=.DS_Store --exclude=*.log --exclude=.idea/ --exclude=.vscode/ --exclude=coverage/ --exclude=.cache/"
ME_USER="${USER:-$(id -un)}"
count() { calls "$1" | wc -l | tr -d ' '; }
# only NAME... - a PATH folder with just these programs, to see what happens when one is missing
only() {
  local n d
  rm -rf "$TMP/only"; mkdir -p "$TMP/only"
  for n in bash env awk sed date tee ls id mkdir cat tr grep head tail rm mktemp wc dirname "$@"; do
    for d in "$STUBS" /usr/bin /bin; do
      [ -x "$d/$n" ] && { ln -s "$d/$n" "$TMP/only/$n"; break; }
    done
  done
}
# The fake rsync writes each argument on a line of its own to $TMP/args, prints two lines the
# way rsync -v does, and ends with the status in $TMP/rc (0 when there is no such file).
stub rsync 'printf "%s\n" "$@" > "$TMP/args"
echo "sending incremental file list"; echo "deleting old.txt"
exit "$(cat "$TMP/rc" 2>/dev/null || echo 0)"'
stub ssh

# --- help and wrong use: nothing is read, written or run
run "$CMD" --help
check "help: exit 0 although the source folder does not exist" "0" "$RC"
has "help: says that remote files are deleted" "DELETED" "$OUT"
has "help: names the log folder" "~/.local/log/sync-git-msp/" "$OUT"
has "help: points to the other command" "mbm-sync-git-msp-v2" "$OUT"
for o in --source --host --user --dest --exclude --dry-run --watch --yes MBM_SYNC_SOURCE_DIR MBM_REMOTE_HOST MBM_REMOTE_USER MBM_SYNC_REMOTE_DIR; do
  has "help: documents $o" "$o" "$OUT"
done
run "$CMD"
check "no host: exit 2" "2" "$RC"
has "no host: names the option" "--host" "$ERR"
has "no host: names the variable" "MBM_REMOTE_HOST" "$ERR"
run "$CMD" -H
check "an option without its value: exit 2" "2" "$RC"
run "$CMD" -H h.test extra
check "a surplus argument: exit 2" "2" "$RC"
has "a surplus argument: is named" "extra" "$ERR"
run "$CMD" -H h.test -y -- extra
check "a surplus argument after --: exit 2" "2" "$RC"
for d in "" . / "~" "~/"; do
  run "$CMD" -H h.test -y -d "$d"
  check "--dest '$d' (a whole home or root folder) is refused: exit 2" "2" "$RC"
done
run "$CMD" -H -oProxyCommand=x -y
check "a host that looks like an option is refused: exit 2" "2" "$RC"
run "$CMD" -H h.test -y
check "the source folder is missing: exit 1" "1" "$RC"
has "the source folder is missing: the message names it" "source folder not found: $SRC" "$ERR"
mkdir -p "$SRC"
run "$CMD" -H h.test -y
check "the source folder is empty: exit 1" "1" "$RC"
has "the source folder is empty: the message says why it stops" "would delete everything in $ME_USER@h.test:git-msp/" "$ERR"
check "so far no program was run" "" "$(calls)"
[ ! -e "$HOME/.local" ] && ok "so far no log folder was made" || bad "so far no log folder was made"

mkdir -p "$SRC/a b"
echo x > "$SRC/a b/f.txt"

# --- the main job: the exact rsync command
run "$CMD" -H h.test --yes
check "plain run: exit 0" "0" "$RC"
check "plain run: the rsync command" \
  "rsync -avz --human-readable --stats --delete $EXC -- $SRC/ $ME_USER@h.test:git-msp/" "$(calls rsync)"
has "plain run: rsync's output is shown" "deleting old.txt" "$OUT"
hasnt "plain run: no colour codes when the output is not a terminal" "$(printf '\033')" "$OUT"
check "plain run: nothing on standard error" "" "$ERR"
LOG="$(ls "$LOGS"/sync-*.log 2>/dev/null)"
check "the log file is in the sandbox HOME, named by the day" "$LOGS/sync-$(date +%Y-%m-%d).log" "$LOG"
has "the log file has rsync's output" "deleting old.txt" "$(cat "$LOG")"
has "the log file has the command" "[RUN] rsync -avz" "$(cat "$LOG")"
check "nothing but the log file was written to HOME" "1" "$(find "$HOME/.local" -type f | wc -l | tr -d ' ')"

# (These three are called the way the script was called before it had --host.)
reset_calls
MBM_REMOTE_HOST=h.test run "$CMD" --dry-run
check "--dry-run: exit 0, and no --yes needed" "0" "$RC"
check "--dry-run: the rsync command" \
  "rsync -avz --human-readable --stats --delete $EXC --dry-run -- $SRC/ $ME_USER@h.test:git-msp/" "$(calls rsync)"
has "--dry-run: says that nothing is changed" "dry run, nothing is changed" "$OUT"
has "--dry-run: the files rsync would delete are shown" "deleting old.txt" "$OUT"
reset_calls
run "$CMD" -n -H h.test
has "-n is --dry-run" " --dry-run -- " "$(calls rsync)"

# --- settings and options
mkdir -p "$TMP/other dir/sub" "$TMP/env dir"
echo x > "$TMP/other dir/sub/f"
echo x > "$TMP/env dir/f"
reset_calls
MBM_SYNC_SOURCE_DIR="$TMP/env dir" MBM_REMOTE_HOST=env.test MBM_REMOTE_USER=envuser MBM_SYNC_REMOTE_DIR=backup/env/ \
  run "$CMD" -y
check "the four settings are used" "$TMP/env dir/ envuser@env.test:backup/env/" "$(calls rsync | sed 's/.* -- //')"
reset_calls
MBM_SYNC_SOURCE_DIR="$TMP/env dir" MBM_REMOTE_HOST=env.test MBM_REMOTE_USER=envuser MBM_SYNC_REMOTE_DIR=backup/env/ \
  run "$CMD" -y -s "$TMP/other dir" -H opt.test -u optuser -d /srv/site
check "options win over the settings" "$TMP/other dir/ optuser@opt.test:/srv/site" "$(calls rsync | sed 's/.* -- //')"
check "a source path with a space is one argument" "$TMP/other dir/" "$(tail -n 2 "$TMP/args" | head -n 1)"
check "the destination is the last argument" "optuser@opt.test:/srv/site" "$(tail -n 1 "$TMP/args")"
reset_calls
run "$CMD" -y --source="$TMP/other dir/" --host=opt.test --user=optuser --dest=x/
check "--option=value works, and a source with a slash keeps one slash" "$TMP/other dir/ optuser@opt.test:x/" "$(calls rsync | sed 's/.* -- //')"
reset_calls
run "$CMD" -y -H root@opt.test -u ignored
check "--host USER@HOST is taken as it is" "$SRC/ root@opt.test:git-msp/" "$(calls rsync | sed 's/.* -- //')"
mkdir -p "$TMP/work/-odd dir"
echo x > "$TMP/work/-odd dir/it's"
reset_calls
( cd "$TMP/work" && "$CMD" -y -H h.test -s "-odd dir" >/dev/null 2>&1 )
check "a relative source that starts with a dash becomes an absolute path" "$TMP/work/-odd dir/" "$(tail -n 2 "$TMP/args" | head -n 1)"
reset_calls
run "$CMD" -y -H h.test -x '*.tmp' --exclude 'my cache/'
has "-x adds patterns after the built-in ones" "--exclude=.cache/ --exclude=*.tmp --exclude=my cache/ -- " "$(calls rsync)"
check "a pattern with a space is one argument" "--exclude=my cache/" "$(grep -n 'my cache' "$TMP/args" | sed 's/^[0-9]*://')"

# --- it deletes on the remote side, so it asks first
rm -rf "$HOME/.local"
reset_calls
run "$CMD" -H h.test
check "no terminal and no --yes: exit 1" "1" "$RC"
has "no terminal and no --yes: says how to go ahead" "--yes" "$ERR"
has "no terminal and no --yes: says what would be deleted" "not in the local folder are deleted" "$ERR"
check "no terminal and no --yes: rsync is not run" "" "$(calls rsync)"
[ ! -e "$HOME/.local" ] && ok "no terminal and no --yes: no log is written" || bad "no terminal and no --yes: no log is written"
# (tty_run's RC is the status of its own pipe, not of the command: the output is checked.)
if tty_run "n" "$CMD" -H h.test; then
  has "on a terminal: the question names both sides" "Mirror $SRC/ to $ME_USER@h.test:git-msp/?" "$OUT"
  has "on a terminal, answer n: says that nothing was synced" "nothing synced" "$OUT"
  check "on a terminal, answer n: rsync is not run" "" "$(calls rsync)"
  [ ! -e "$HOME/.local" ] && ok "on a terminal, answer n: no log is written" || bad "on a terminal, answer n: no log is written"
  tty_run "y" "$CMD" -H h.test
  has "on a terminal, answer y: the sync is done" "[OK] done" "$OUT"
  check "on a terminal, answer y: rsync runs once" "1" "$(count rsync)"
else
  skip "no expect: the question on a terminal is not tested"
fi

# --- failures
reset_calls
echo 23 > "$TMP/rc"
run "$CMD" -H h.test -y
check "rsync fails: exit 1" "1" "$RC"
has "rsync fails: its exit code is reported on standard error" "rsync failed with exit code 23" "$ERR"
has "rsync fails: the log has it too" "[ERROR] rsync failed with exit code 23" "$(cat "$LOGS"/sync-*.log)"
rm -f "$TMP/rc"
only ssh
run env PATH="$TMP/only" "$CMD" -H h.test -y
check "rsync is missing: exit 1" "1" "$RC"
has "rsync is missing: says so" "rsync is not installed" "$ERR"
only rsync
run env PATH="$TMP/only" "$CMD" -H h.test -y
has "ssh is missing: says so" "ssh is not installed" "$ERR"
only rsync ssh
reset_calls
run env PATH="$TMP/only" "$CMD" -H h.test -y --watch
check "--watch without fswatch: exit 1" "1" "$RC"
has "--watch without fswatch: says how to get it" "brew install fswatch" "$ERR"
check "--watch without fswatch: nothing is synced" "" "$(calls rsync)"

# --- watch mode
reset_calls
stub fswatch 'echo 1; echo 1'
run "$CMD" -H h.test -y --watch
check "--watch: ends cleanly when fswatch ends" "0" "$RC"
check "--watch: one sync at the start and one for two changes that came together" "2" "$(count rsync)"
check "--watch: the fswatch command" \
  "fswatch -o -r -E --exclude=/\\.git(/|\$) --exclude=/node_modules(/|\$) --exclude=/\\.next(/|\$) --exclude=/\\.nuxt(/|\$) --exclude=/dist(/|\$) --exclude=/build(/|\$) --exclude=/out(/|\$) --exclude=/__pycache__(/|\$) --exclude=/[^/]*\\.pyc(/|\$) --exclude=/\\.venv(/|\$) --exclude=/venv(/|\$) --exclude=/\\.env(/|\$) --exclude=/\\.env\\.local(/|\$) --exclude=/vendor(/|\$) --exclude=/\\.DS_Store(/|\$) --exclude=/[^/]*\\.log(/|\$) --exclude=/\\.idea(/|\$) --exclude=/\\.vscode(/|\$) --exclude=/coverage(/|\$) --exclude=/\\.cache(/|\$) $SRC/" \
  "$(calls fswatch)"
# Two changes two seconds apart are two syncs. This rsync reads its standard input, as ssh
# may: it must not get the lines fswatch writes.
stub rsync 'cat > /dev/null'
stub fswatch 'echo 1; sleep 2; echo 1'
reset_calls
run "$CMD" -H h.test -y -w
check "-w: changes that are apart get a sync each (1 + 2)" "3" "$(count rsync)"
stub fswatch 'exit 3'
reset_calls
run "$CMD" -H h.test -y -w
check "--watch: fswatch fails: exit 1" "1" "$RC"
has "--watch: fswatch fails: its status is reported" "fswatch stopped with exit status 3" "$ERR"
stub fswatch 'echo 1'
reset_calls
MBM_REMOTE_HOST=h.test run "$CMD" --dry-run --watch
check "--dry-run with --watch: both are honoured, and no --yes needed" "2 1" "$(calls rsync | grep -c -- ' --dry-run ') $(count fswatch)"
stub rsync 'echo "deleting old.txt"'

# A watch that is stopped from outside (kill, a closed terminal) takes fswatch with it.
stub fswatch 'echo $$ > "$TMP/watcher.pid"; exec sleep 20'
rm -f "$TMP/watcher.pid"
{
  "$CMD" -H h.test -y -w > /dev/null 2>&1 &
  pid=$!
  i=0
  while [ ! -s "$TMP/watcher.pid" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  sleep 0.3
  kill -TERM "$pid"
  wait "$pid"
  rc=$?
  i=0
  while kill -0 "$(cat "$TMP/watcher.pid")" && [ "$i" -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
} 2>/dev/null
check "--watch, stopped with TERM: ends with the status of the signal" "143" "$rc"
if kill -0 "$(cat "$TMP/watcher.pid")" 2>/dev/null; then
  kill "$(cat "$TMP/watcher.pid")"
  bad "--watch, stopped with TERM: fswatch is stopped too"
else
  ok "--watch, stopped with TERM: fswatch is stopped too"
fi
check "--watch, stopped with TERM: no temporary file is left behind" "" "$(ls -A "$TMPDIR")"

# --- the examples in the help, and another prefix
mkdir -p "$HOME/Projects/site"
echo x > "$HOME/Projects/site/index.html"
stub fswatch
export CMD
"$CMD" --help | sed -n '/^Examples:/,/^$/p' | sed -e 1d -e '/^$/d' -e 's/^ *mbm-sync-git-msp /"$CMD" /' > "$TMP/examples"
check "the help has four examples" "4" "$(wc -l < "$TMP/examples" | tr -d ' ')"
# An example that would ask first gets --yes here: there is no terminal (and each tty_run
# takes five seconds).
while IFS= read -r ex; do
  reset_calls
  case "$ex" in
    *--dry-run*|*--yes*) run bash -c "$ex" ;;
    *) run bash -c "$ex --yes" ;;
  esac
  check "example runs: ${ex#* }" "0 1" "$RC $(calls rsync | grep -c 'example\.com:')"
  hasnt "example runs without a complaint: ${ex#* }" "sync-git-msp: " "$OUT$ERR"
done < "$TMP/examples"
ln -s "$CMD" "$TMP/zz-sync-git-msp"
run "$TMP/zz-sync-git-msp"
has "another prefix: the message names the command as it was called" "zz-sync-git-msp: no remote host" "$ERR"
has "another prefix: the help names the other command with it" "zz-sync-git-msp-v2" "$("$TMP/zz-sync-git-msp" --help)"
check "no temporary file is left behind" "" "$(ls -A "$TMPDIR")"

finish
