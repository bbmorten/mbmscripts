#!/bin/bash
# Tests for mbm-logger.   Run:  tests/run.sh logger    or:  bash tests/commands/logger.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-logger"
echo "mbm-logger"

# `script` is always a fake here: it writes one line into the file it is given and notes what
# it found in its environment. The real one would start a shell.
fake_script() {
  stub script "echo \"SCRIPT=\$SCRIPT umask=\$(umask)\" > '$TMP/script.env'
echo recorded > \"\$1\" || exit 1
$1"
}
fake_script ''
DEF="$HOME/Documents/Temp/TerminalLogs"
NAME='terminal_[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].log'
# the_log DIR - the one file in DIR
the_log() { ls "$1" 2>/dev/null; }
mode() { ls -l "$1" | cut -c1-10; }

# --- a recording into the default folder, which does not exist yet
run "$CMD"
check "no arguments: exit 0 (the old one failed when the folder was missing)" "0" "$RC"
log="$(the_log "$DEF")"
# shellcheck disable=SC2254  # NAME is a pattern on purpose
case "$log" in
  $NAME) ok "the folder is created and the log is named terminal_YYYY-MM-DD_HHMMSS.log" ;;
  *) bad "the folder is created and the log is named terminal_YYYY-MM-DD_HHMMSS.log (got '$log')" ;;
esac
check "script gets the file and no option" "script $DEF/$log" "$(calls)"
has "says where the log goes" "recording this terminal to $DEF/$log" "$OUT"
has "says how to end the recording" "exit" "$OUT"
check "the log is readable by its owner only" "-rw-------" "$(mode "$DEF/$log")"
check "the new folder is closed to others" "drwx------" "$(ls -ld "$DEF" | cut -c1-10)"
check "the shell inside finds the log's name in SCRIPT" "SCRIPT=$DEF/$log umask=0077" "$(cat "$TMP/script.env")"

# --- the folder: -d, --dir, the setting
D="$TMP/my logs/deep"
reset_calls
run "$CMD" -d "$D"
check "-d DIR with a space, two levels deep: created and used" "script $D/$(the_log "$D")" "$(calls)"
run "$CMD" --dir "$TMP/long"
check "--dir DIR" "1" "$(the_log "$TMP/long" | wc -l | tr -d ' ')"
run env MBM_LOGGER_DIR="$TMP/from-env" "$CMD"
check "MBM_LOGGER_DIR" "1" "$(the_log "$TMP/from-env" | wc -l | tr -d ' ')"
run env MBM_LOGGER_DIR="$TMP/not-this" "$CMD" -d "$TMP/but-this"
check "-d wins over MBM_LOGGER_DIR" "1|no" "$(the_log "$TMP/but-this" | wc -l | tr -d ' ')|$([ -e "$TMP/not-this" ] && echo yes || echo no)"
cd "$TMP" || exit 1
reset_calls
run "$CMD" -d -dash
check "a relative folder whose name starts with a dash is not an option for script" "script ./-dash/$(the_log "$TMP/-dash")" "$(calls)"
cd "$HOME" || exit 1

# --- a fixed clock: the exact name, and a log of the same second is not overwritten
stub date 'echo 2026-01-02_030405'
run "$CMD" -d "$TMP/clock"
check "the name is made of the date and the time, apart" "terminal_2026-01-02_030405.log" "$(the_log "$TMP/clock")"
echo "an earlier session" > "$TMP/clock/terminal_2026-01-02_030405.log"
reset_calls
run "$CMD" -d "$TMP/clock"
check "a log of the same second exists: exit 1" "1" "$RC"
check "a log of the same second exists: it is kept and script is not started" "an earlier session|" "$(cat "$TMP/clock/terminal_2026-01-02_030405.log")|$(calls script)"
rm -f "$STUBS/date"

# --- the exit status of script; inside a recording
fake_script 'exit 5'
run "$CMD" -d "$TMP/status"
check "the exit status of script is passed on" "5" "$RC"
fake_script ''
reset_calls
run env SCRIPT="$DEF/terminal_x.log" "$CMD" -d "$TMP/nested"
check "inside a recording: exit 1" "1" "$RC"
has "inside a recording: names the running log" "already being recorded to $DEF/terminal_x.log" "$ERR"
check "inside a recording: no second one, and no folder made" "|no" "$(calls)|$([ -e "$TMP/nested" ] && echo yes || echo no)"

# --- the list
L="$TMP/list dir"
mkdir -p "$L"
for n in terminal_2026-11-14_171500.log terminal_2025-03-01_090000.log terminal_2026-11-14_080000.log \
         terminal_2024-12-31235959.log notes.txt terminal_x.txt; do
  echo "$n" > "$L/$n"
done
mkdir "$L/terminal_folder.log"
reset_calls
run "$CMD" -l -d "$L"
check "-l: exit 0" "0" "$RC"
check "-l: the logs with their folder, newest first; old-style names too; nothing else" \
"$L/terminal_2026-11-14_171500.log
$L/terminal_2026-11-14_080000.log
$L/terminal_2025-03-01_090000.log
$L/terminal_2024-12-31235959.log" "$OUT"
run env MBM_LOGGER_DIR="$L" "$CMD" --list
check "--list with MBM_LOGGER_DIR" "$L/terminal_2026-11-14_171500.log" "$(printf '%s\n' "$OUT" | head -n 1)"
run env LC_ALL=tr_TR.UTF-8 "$CMD" -l -d "$L"
check "-l: the same order under a Turkish locale" "$L/terminal_2024-12-31235959.log" "$(printf '%s\n' "$OUT" | tail -n 1)"
run env SCRIPT=/some/log "$CMD" -l -d "$L"
check "-l works inside a recording" "4" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
run "$CMD" -l -d "$TMP/no such folder"
check "-l on a missing folder: exit 0, nothing listed, a note on standard error" "0||mbm-logger: no logs in $TMP/no such folder" "$RC|$OUT|$ERR"
check "-l does not create the folder" "no" "$([ -e "$TMP/no such folder" ] && echo yes || echo no)"
mkdir -p "$TMP/empty"
run "$CMD" -l -d "$TMP/empty"
check "-l on an empty folder: exit 0 and nothing listed" "0|" "$RC|$OUT"
check "-l never starts script" "" "$(calls)"
# the last example of the help: less -R "$(mbm-logger -l | head -n 1)"
if command -v less >/dev/null 2>&1; then
  run env MBM_LOGGER_DIR="$L" /bin/bash -c 'less -R "$("$0" -l | head -n 1)"' "$CMD"
  check "the newest log can be handed to less, as the help shows" "terminal_2026-11-14_171500.log" "$OUT"
else
  skip "less is not installed: that example of the help is not run"
fi

# --- wrong use
reset_calls
run "$CMD" somefile
check "an argument: exit 2" "2" "$RC"
has "an argument: points to --help" "--help" "$ERR"
run "$CMD" -d
check "-d without a folder: exit 2" "2" "$RC"
run "$CMD" -d ""
check "-d with an empty name: exit 2" "2" "$RC"
echo "a file" > "$TMP/a-file"
run "$CMD" -d "$TMP/a-file/logs"
check "the folder cannot be created: exit 1" "1" "$RC"
has "the folder cannot be created: says so" "cannot create the folder $TMP/a-file/logs" "$ERR"
check "none of these started script" "" "$(calls)"

# A PATH without any folder: the real /usr/bin/script is out of reach, as on a machine without it.
mkdir -p "$TMP/nopath"
run env PATH="$TMP/nopath" /bin/bash "$CMD" -d "$TMP/unused"
check "script is not installed: exit 1" "1" "$RC"
has "script is not installed: says where it comes from" "util-linux" "$ERR"
check "script is not installed: no folder made" "no" "$([ -e "$TMP/unused" ] && echo yes || echo no)"

mkdir -p "$TMP/inst"
ln -s "$CMD" "$TMP/inst/zz-logger"
run "$TMP/inst/zz-logger" -l -d "$TMP/empty"
check "called as zz-logger, the note carries that name" "zz-logger: no logs in $TMP/empty" "$ERR"

finish
