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
CSV="$LOGS/stats.csv"
HEAD="timestamp,duration_sec,files_total,files_transferred,files_deleted,bytes_total,bytes_sent,bytes_received,transfer_rate,speedup,exit_code"
SRC="$HOME/git-msp"
EXC="--exclude=.git/ --exclude=node_modules/ --exclude=.next/ --exclude=.nuxt/ --exclude=dist/ --exclude=build/ --exclude=out/ --exclude=__pycache__/ --exclude=*.pyc --exclude=.venv/ --exclude=venv/ --exclude=.env --exclude=.env.local --exclude=vendor/ --exclude=.DS_Store --exclude=*.log --exclude=.idea/ --exclude=.vscode/ --exclude=coverage/ --exclude=.cache/"
ME_USER="${USER:-$(id -un)}"
count() { calls "$1" | grep -c -v -- '--version'; }
syncs() { calls rsync | grep -v -- '--version'; }
rows() { grep -c -v '^timestamp,' "$CSV"; }
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

# The fake rsync: --version prints $TMP/version; otherwise it writes its arguments, one per
# line, to $TMP/args, prints $TMP/output and ends with the status in $TMP/rc (0 without that
# file). With "openrsync" as its version it refuses --info=..., as the rsync of macOS does.
# With a file $TMP/slurp it reads its standard input to the end first, as ssh may.
stub rsync 'case "$1" in --version) cat "$TMP/version"; exit 0 ;; esac
printf "%s\n" "$@" > "$TMP/args"
[ -e "$TMP/slurp" ] && cat > /dev/null
if grep -q openrsync "$TMP/version"; then
  for a in "$@"; do
    case "$a" in --info=*) echo "rsync: unrecognized option $a" >&2; echo "usage: rsync [-0468BDFHIKLOPRSVWabcdghklnopqrtuvxz] ..." >&2; exit 1 ;; esac
  done
fi
cat "$TMP/output"
exit "$(cat "$TMP/rc" 2>/dev/null || echo 0)"'
stub ssh
modern_rsync() {   # what rsync 3.1 or newer prints: one progress line, numbers with commas
  echo "rsync  version 3.4.1  protocol version 32" > "$TMP/version"
  printf '\r         32,768   3%%   31.25kB/s    0:00:32\r      1,048,576 100%%    1.00MB/s    0:00:01 (xfr#5, to-chk=0/1234)\n' > "$TMP/output"
  cat >> "$TMP/output" <<'EOF_RSYNC3'
Number of files: 1,234 (reg: 1,000, dir: 234)
Number of created files: 2 (reg: 2)
Number of deleted files: 3 (reg: 2, dir: 1)
Number of regular files transferred: 5
Total file size: 12,345,678 bytes
Total transferred file size: 1,048,576 bytes
Literal data: 1,048,576 bytes
Matched data: 0 bytes
File list size: 0
Total bytes sent: 1,050,000
Total bytes received: 1,234

sent 1,050,000 bytes  received 1,234 bytes  700,822.67 bytes/sec
total size is 12,345,678  speedup is 11.74
EOF_RSYNC3
}
old_rsync() {      # the stats lines openrsync has (rsync 2.6.9 has the same first two)
  printf 'openrsync: protocol version 29\nrsync version 2.6.9 compatible\n' > "$TMP/version"
  printf 'a b/f.txt\n\r        2048 100%%    1.95MB/s    0:00:00 (xfer#1, to-check=0/3)\ndeleting old one.txt\ndeleting old two.txt\n' > "$TMP/output"
  cat >> "$TMP/output" <<'EOF_OPENRSYNC'
Number of files: 3
Number of files transferred: 1
Total file size: 4096
Total transferred file size: 2048
Total sent: 2200
Total received: 42

sent 2200 bytes  received 42 bytes  4484.00 bytes/sec
total size is 4096  speedup is 1.83
EOF_OPENRSYNC
}
modern_rsync

# --- help, history and wrong use: nothing is read, written or run
run "$CMD" --help
check "help: exit 0 although the source folder does not exist" "0" "$RC"
has "help: says that remote files are deleted" "DELETED" "$OUT"
has "help: names the history file" "stats.csv" "$OUT"
has "help: points to the plain command" "mbm-sync-git-msp " "$OUT"
for o in --source --host --user --dest --exclude --dry-run --watch --history --yes MBM_SYNC_SOURCE_DIR MBM_SYNC_REMOTE_HOST MBM_REMOTE_HOST MBM_REMOTE_USER MBM_SYNC_REMOTE_DIR; do
  has "help: documents $o" "$o" "$OUT"
done
run "$CMD" --history
check "--history before any run: exit 0, without a host or a source folder" "0" "$RC"
has "--history before any run: says so and names the file" "No run has been recorded yet ($CSV)" "$OUT"
run "$CMD" --history --watch
check "--history with --watch: exit 2" "2" "$RC"
run "$CMD"
check "no host: exit 2" "2" "$RC"
has "no host: names the option" "--host" "$ERR"
has "no host: names both variables" "MBM_SYNC_REMOTE_HOST or MBM_REMOTE_HOST" "$ERR"
run "$CMD" -H h.test extra
check "a surplus argument: exit 2" "2" "$RC"
run "$CMD" -H h.test -y -d "~"
check "--dest '~' (a whole home folder) is refused: exit 2" "2" "$RC"
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

# --- the main job with rsync 3.1 or newer
run "$CMD" -H h.test --yes
check "plain run: exit 0" "0" "$RC"
check "plain run: the rsync command, with one progress line for the whole run" \
  "rsync -az --stats --info=progress2 --delete $EXC -- $SRC/ $ME_USER@h.test:git-msp/" "$(syncs)"
has "plain run: the progress is shown" "1,048,576 100%" "$OUT"
has "plain run: the summary" "[STAT] 5 of 1234 files sent, 3 deleted, 1.0 MB sent, 1.2 KB received, 684.4 KB/s, in " "$OUT"
hasnt "plain run: no colour codes when the output is not a terminal" "$(printf '\033')" "$OUT"
check "plain run: nothing on standard error" "" "$ERR"
check "the history starts with the column names" "$HEAD" "$(head -n 1 "$CSV")"
check "the history has one row, with the numbers of the run" \
  "1234,5,3,12345678,1050000,1234,700822.67,11.74,0" "$(tail -n 1 "$CSV" | cut -d, -f3-)"
case "$(tail -n 1 "$CSV")" in
  "$(date +%Y-%m-%d) "[0-9][0-9]:[0-9][0-9]:[0-9][0-9],[0-9]*) ok "the row starts with the time and the seconds" ;;
  *) bad "the row starts with the time and the seconds ($(tail -n 1 "$CSV"))" ;;
esac
LOG="$LOGS/sync-$(date +%Y-%m-%d).log"
has "the log file has the command" "[RUN] rsync -az --stats --info=progress2" "$(cat "$LOG")"
has "the log file has rsync's numbers and the summary" "Number of regular files transferred: 5" "$(cat "$LOG")"
check "the log file has no progress lines" "0 0" "$(grep -c '100%' "$LOG") $(tr -cd '\r' < "$LOG" | wc -c | tr -d ' ')"
check "only the log and the history were written to HOME" "2" "$(find "$HOME/.local" -type f | wc -l | tr -d ' ')"
check "no temporary file is left behind" "" "$(ls -A "$TMPDIR")"

# (The dry run and --history are called the way the script was called before it had --host.)
reset_calls
BEFORE="$(rows)"
MBM_REMOTE_HOST=h.test run "$CMD" --dry-run
check "--dry-run: exit 0, and no --yes needed" "0" "$RC"
check "--dry-run: the rsync command lists the files instead of showing progress" \
  "rsync -az --stats -v --dry-run --delete $EXC -- $SRC/ $ME_USER@h.test:git-msp/" "$(syncs)"
has "--dry-run: says that nothing is changed" "dry run, nothing is changed" "$OUT"
check "--dry-run: adds nothing to the history" "$BEFORE" "$(rows)"

MBM_REMOTE_HOST=h.test run "$CMD" --history
check "--history: exit 0" "0" "$RC"
check "--history: a heading, the column names and one line per run" "3" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
check "--history: the columns" "ENDED SECONDS SENT DELETED BYTES SENT RATE EXIT" "$(printf '%s\n' "$OUT" | sed -n 2p | tr -s ' ')"
check "--history: the run, with sizes a person can read" "5 3 1.0 MB 684.4 KB/s 0" "$(printf '%s\n' "$OUT" | sed -n 3p | tr -s ' ' | cut -d' ' -f4-)"

# --- an older rsync, and the openrsync of macOS: no --info=progress2
old_rsync
reset_calls
run "$CMD" -H h.test -y
check "old rsync: exit 0 (the fake fails when it gets --info=progress2)" "0" "$RC"
check "old rsync: the rsync command, with a progress line per file" \
  "rsync -az --stats --progress --delete $EXC -- $SRC/ $ME_USER@h.test:git-msp/" "$(syncs)"
check "old rsync: the row; deleted files are counted from the list" "3,1,2,4096,2200,42,4484.00,1.83,0" "$(tail -n 1 "$CSV" | cut -d, -f3-)"
has "old rsync: the log names the deleted files" "deleting old one.txt" "$(cat "$LOG")"
echo "something else" > "$TMP/version"
reset_calls
run "$CMD" -H h.test -y
has "an rsync whose version cannot be read gets --progress" " --progress " "$(syncs)"
modern_rsync
check "the column names are in the history once" "1" "$(grep -c '^timestamp,' "$CSV")"

# --- -v: the list of files instead of the progress line (what the plain command printed)
rows_before="$(grep -c . "$CSV")"
reset_calls
run "$CMD" -H h.test -y -v
check "-v: exit 0" "0" "$RC"
check "-v: rsync lists the files and gets no progress option" \
  "rsync -az --stats -v --delete $EXC -- $SRC/ $ME_USER@h.test:git-msp/" "$(syncs)"
check "-v: the run is still recorded in the history" "$((rows_before + 1))" "$(grep -c . "$CSV")"
reset_calls
run "$CMD" -H h.test -y --verbose --dry-run
check "--verbose with --dry-run: one -v, the dry run" \
  "rsync -az --stats -v --dry-run --delete $EXC -- $SRC/ $ME_USER@h.test:git-msp/" "$(syncs)"
run "$CMD" --history -v
check "--history with -v is wrong usage" "2" "$RC"
reset_calls
MBM_SYNC_REMOTE_HOST=sync.test MBM_REMOTE_HOST=env.test run "$CMD" -y
has "MBM_SYNC_REMOTE_HOST wins over MBM_REMOTE_HOST" "@sync.test:git-msp/" "$(syncs)"
reset_calls
MBM_REMOTE_HOST=env.test run "$CMD" -y
has "without it, MBM_REMOTE_HOST is the host" "@env.test:git-msp/" "$(syncs)"
reset_calls
MBM_SYNC_V2_REMOTE_HOST=old.test run "$CMD" -y
check "MBM_SYNC_V2_REMOTE_HOST (the retired -v2 command's setting) is no longer read" "2" "$RC"

# Numbers as rsync 3 writes them where the decimal sign is a comma (Turkish, German, ...).
sed -e 's/,/#/g' -e 's/\./,/g' -e 's/#/./g' "$TMP/output" > "$TMP/output.tr"
mv "$TMP/output.tr" "$TMP/output"
has "the fixture has the other number format" "700.822,67 bytes/sec" "$(cat "$TMP/output")"
run env LC_ALL=tr_TR.UTF-8 "$CMD" -H h.test -y
check "numbers with a decimal comma give the same row" \
  "1234,5,3,12345678,1050000,1234,700822.67,11.74,0" "$(tail -n 1 "$CSV" | cut -d, -f3-)"
has "numbers with a decimal comma: the summary has a decimal point" "1.0 MB sent" "$OUT"
modern_rsync

# --- settings and options
mkdir -p "$TMP/other dir/sub" "$TMP/env dir"
echo x > "$TMP/other dir/sub/f"
echo x > "$TMP/env dir/f"
reset_calls
MBM_SYNC_SOURCE_DIR="$TMP/env dir" MBM_REMOTE_HOST=env.test MBM_REMOTE_USER=envuser MBM_SYNC_REMOTE_DIR=backup/env/ \
  run "$CMD" -y
check "the settings are used; MBM_REMOTE_HOST when there is no v2 host" "$TMP/env dir/ envuser@env.test:backup/env/" "$(syncs | sed 's/.* -- //')"
reset_calls
MBM_SYNC_REMOTE_HOST=v2.test MBM_REMOTE_HOST=env.test MBM_REMOTE_USER=envuser run "$CMD" -y
check "MBM_SYNC_REMOTE_HOST wins over MBM_REMOTE_HOST" "$SRC/ envuser@v2.test:git-msp/" "$(syncs | sed 's/.* -- //')"
reset_calls
MBM_SYNC_SOURCE_DIR="$TMP/env dir" MBM_SYNC_REMOTE_HOST=v2.test MBM_REMOTE_USER=envuser MBM_SYNC_REMOTE_DIR=backup/env/ \
  run "$CMD" -y -s "$TMP/other dir" -H opt.test -u optuser -d /srv/site -x '*.tmp' --exclude='my cache/'
check "options win over the settings" "$TMP/other dir/ optuser@opt.test:/srv/site" "$(syncs | sed 's/.* -- //')"
check "a source path with a space is one argument" "$TMP/other dir/" "$(tail -n 2 "$TMP/args" | head -n 1)"
has "-x adds patterns after the built-in ones" "--exclude=.cache/ --exclude=*.tmp --exclude=my cache/ -- " "$(syncs)"
reset_calls
run "$CMD" -y -H root@opt.test
check "--host USER@HOST is taken as it is" "$SRC/ root@opt.test:git-msp/" "$(syncs | sed 's/.* -- //')"

# --- it deletes on the remote side, so it asks first
BEFORE="$(rows)"
reset_calls
run "$CMD" -H h.test
check "no terminal and no --yes: exit 1" "1" "$RC"
has "no terminal and no --yes: says how to go ahead" "--yes" "$ERR"
check "no terminal and no --yes: rsync is not run, nothing is recorded" "0 $BEFORE" "$(count rsync) $(rows)"
# (tty_run's RC is the status of its own pipe, not of the command: the output is checked.)
if tty_run "n" "$CMD" -H h.test; then
  has "on a terminal: the question names both sides" "Mirror $SRC/ to $ME_USER@h.test:git-msp/?" "$OUT"
  has "on a terminal, answer n: says that nothing was synced" "nothing synced" "$OUT"
  check "on a terminal, answer n: rsync is not run, nothing is recorded" "0 $BEFORE" "$(count rsync) $(rows)"
  # (The answer y is tested for mbm-sync-git-msp, which has the same lines.)
else
  skip "no expect: the question on a terminal is not tested"
fi

# --- failures
echo 23 > "$TMP/rc"
run "$CMD" -H h.test -y
check "rsync fails: exit 1" "1" "$RC"
has "rsync fails: its exit code is reported on standard error" "rsync failed with exit code 23" "$ERR"
check "rsync fails: the history keeps rsync's exit code" "23" "$(tail -n 1 "$CSV" | cut -d, -f11)"
has "rsync fails: --history shows it" " 23" "$("$CMD" --history | tail -n 1)"
check "rsync fails: no temporary file is left behind" "" "$(ls -A "$TMPDIR")"
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
check "--watch without fswatch: nothing is synced" "0" "$(count rsync)"

# --- watch mode
BEFORE="$(rows)"
reset_calls
stub fswatch 'echo 1; echo 1'
run "$CMD" -H h.test -y --watch
check "--watch: ends cleanly when fswatch ends" "0" "$RC"
check "--watch: one sync at the start and one for two changes that came together" "2" "$(count rsync)"
check "--watch: each sync is in the history" "$((BEFORE + 2))" "$(rows)"
check "--watch: the fswatch command; the log folder is left out as well" \
  "fswatch -o -r -E --exclude=^$LOGS/ --exclude=/\\.git(/|\$) --exclude=/node_modules(/|\$) --exclude=/\\.next(/|\$) --exclude=/\\.nuxt(/|\$) --exclude=/dist(/|\$) --exclude=/build(/|\$) --exclude=/out(/|\$) --exclude=/__pycache__(/|\$) --exclude=/[^/]*\\.pyc(/|\$) --exclude=/\\.venv(/|\$) --exclude=/venv(/|\$) --exclude=/\\.env(/|\$) --exclude=/\\.env\\.local(/|\$) --exclude=/vendor(/|\$) --exclude=/\\.DS_Store(/|\$) --exclude=/[^/]*\\.log(/|\$) --exclude=/\\.idea(/|\$) --exclude=/\\.vscode(/|\$) --exclude=/coverage(/|\$) --exclude=/\\.cache(/|\$) $SRC/" \
  "$(calls fswatch)"
# Two changes two seconds apart are two syncs, even when rsync reads its standard input.
stub fswatch 'echo 1; sleep 2; echo 1'
touch "$TMP/slurp"
reset_calls
run "$CMD" -H h.test -y -w
check "-w: changes that are apart get a sync each (1 + 2)" "3" "$(count rsync)"
rm -f "$TMP/slurp"
stub fswatch 'exit 3'
run "$CMD" -H h.test -y -w
check "--watch: fswatch fails: exit 1" "1" "$RC"
has "--watch: fswatch fails: its status is reported" "fswatch stopped with exit status 3" "$ERR"
check "--watch: no temporary file is left behind" "" "$(ls -A "$TMPDIR")"

# --- the history
printf '%s\n' "$HEAD" > "$CSV"
run "$CMD" --history
has "--history with only the column names: says that there is no run yet" "No run has been recorded yet" "$OUT"
i=1
while [ "$i" -le 25 ]; do
  echo "2026-01-$(printf '%02d' "$i") 10:00:00,$i,100,$i,0,5000,2048,10,1024.00,2.44,0" >> "$CSV"
  i=$((i + 1))
done
MBM_REMOTE_HOST=h.test run "$CMD" --history
check "--history: the last 20 of 25 runs" "20 2026-01-06 2026-01-25" \
  "$(printf '%s\n' "$OUT" | grep -c '^2026-') $(printf '%s\n' "$OUT" | sed -n 3p | cut -d' ' -f1) $(printf '%s\n' "$OUT" | tail -n 1 | cut -d' ' -f1)"
check "--history: a row: seconds, files sent and deleted, bytes sent, rate, exit code" "25 25 0 2.0 KB 1.0 KB/s 0" "$(printf '%s\n' "$OUT" | tail -n 1 | tr -s ' ' | cut -d' ' -f3-)"
run "$CMD" -H h.test -y
check "a run adds to a history that is there: 25 rows become 26, the first one stays" "26 2026-01-01 10:00:00,1,100,1,0,5000,2048,10,1024.00,2.44,0" \
  "$(rows) $(sed -n 2p "$CSV")"

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
check "the help has five examples" "5" "$(wc -l < "$TMP/examples" | tr -d ' ')"
# An example that would ask first gets --yes here: there is no terminal (and each tty_run
# takes five seconds).
while IFS= read -r ex; do
  reset_calls
  case "$ex" in
    *--dry-run*|*--yes*|*--history*) run bash -c "$ex" ;;
    *) run bash -c "$ex --yes" ;;
  esac
  case "$ex" in
    *--history*) check "example runs: ${ex#* }" "0 0" "$RC $(count rsync)" ;;
    *) check "example runs: ${ex#* }" "0 1" "$RC $(syncs | grep -c 'example\.com:')" ;;
  esac
  hasnt "example runs without a complaint: ${ex#* }" "sync-git-msp: " "$OUT$ERR"
done < "$TMP/examples"
ln -s "$CMD" "$TMP/zz-sync-git-msp"
run "$TMP/zz-sync-git-msp"
has "another prefix: the message names the command as it was called" "zz-sync-git-msp: no remote host" "$ERR"
has "another prefix: the help shows the command with it" "zz-sync-git-msp -H nas.example.com" "$("$TMP/zz-sync-git-msp" --help)"

finish
