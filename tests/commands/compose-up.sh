#!/bin/bash
# Tests for mbm-compose-up.   Run:  tests/run.sh compose-up    or:  bash tests/commands/compose-up.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-compose-up"
echo "mbm-compose-up"

# project DIR [FILE] - a folder with a compose file
project() { mkdir -p "$1"; echo "services: {}" > "$1/${2:-compose.yaml}"; }
# The fake docker notes the folder it runs in and answers "compose ps".
fake_docker() {
  stub docker "pwd >> '$TMP/cwd.log'
case \"\$2\" in ps) echo 'NAME   STATUS' ;; esac
$1"
}
fake_docker ''
DEF="$HOME/git-repos/mydocs"
UP="docker compose version
docker compose up -d
docker compose ps"

# --- start: the default folder
project "$DEF"
run "$CMD"
check "no arguments: exit 0" "0" "$RC"
check "no arguments: compose up in the background, then the status" "$UP" "$(calls)"
check "no arguments: every docker call runs in ~/git-repos/mydocs" "$DEF" "$(sort -u "$TMP/cwd.log")"
has "no arguments: shows the status" "NAME   STATUS" "$OUT"
check "a project without .venv gives no error text (the old one printed a shell error)" "" "$ERR"

# --- start: DIR, the setting, the four compose file names
P="$TMP/my wiki"
project "$P"
: > "$TMP/cwd.log"; reset_calls
run "$CMD" "$P"
check "DIR with a space: compose up there" "$UP|$P" "$(calls)|$(sort -u "$TMP/cwd.log")"
: > "$TMP/cwd.log"
run env MBM_COMPOSE_UP_DIR="$P" "$CMD"
check "MBM_COMPOSE_UP_DIR is the folder when no DIR is given" "$P" "$(sort -u "$TMP/cwd.log")"
: > "$TMP/cwd.log"
run env MBM_COMPOSE_UP_DIR="$P" "$CMD" "$DEF"
check "DIR wins over MBM_COMPOSE_UP_DIR" "$DEF" "$(sort -u "$TMP/cwd.log")"
for f in compose.yml docker-compose.yml docker-compose.yaml; do
  project "$TMP/p-$f" "$f"
  run "$CMD" "$TMP/p-$f"
  check "$f counts as a compose file" "0" "$RC"
done
mkdir -p "$TMP/-odd"; project "$TMP/-odd"
cd "$TMP" || exit 1
: > "$TMP/cwd.log"
run "$CMD" -- -odd
check "after --, a folder whose name starts with a dash" "0|$TMP/-odd" "$RC|$(sort -u "$TMP/cwd.log")"
cd "$HOME" || exit 1

# --- dry run
reset_calls
run "$CMD" -n "$P"
check "--dry-run of a start: exit 0" "0" "$RC"
has "--dry-run of a start: shows compose up" "docker compose up -d" "$OUT"
has "--dry-run of a start: names the folder" "$P" "$OUT"
run "$CMD" --down --dry-run "$P"
has "--dry-run of --down: shows compose down" "docker compose down" "$OUT"
check "--dry-run starts and stops nothing" "docker compose version
docker compose version" "$(calls)"

# --- stop
reset_calls
run "$CMD" -d "$P"
check "--down without a terminal and without --yes: exit 1" "1" "$RC"
has "--down without a terminal: says why, and names --yes" "Add --yes" "$ERR"
check "--down without a terminal: nothing is stopped" "docker compose version" "$(calls)"
reset_calls
run "$CMD" -d -y "$P"
check "--down --yes: exit 0" "0" "$RC"
check "--down --yes: compose down, and no up" "docker compose version
docker compose down" "$(calls)"
reset_calls
: > "$TMP/cwd.log"
run "$CMD" "$P" --yes --down
check "options after DIR work too" "docker compose down|$P" "$(calls docker | tail -n 1)|$(sort -u "$TMP/cwd.log")"
reset_calls
if tty_run "n" "$CMD" -d "$P"; then
  # (tty_run's RC is the status of its own pipeline, not of the command: it is not checked.)
  has "on a terminal: the question names the folder" "Stop the Compose project in $P" "$OUT"
  has "on a terminal, answer n: says that nothing was stopped" "nothing was stopped" "$OUT"
  check "on a terminal, answer n: nothing is stopped" "docker compose version" "$(calls)"
  reset_calls
  tty_run "y" "$CMD" -d "$P"
  check "on a terminal, answer y: compose down" "docker compose down" "$(calls docker | tail -n 1)"
else
  skip "no expect: the question on a terminal is not tested"
fi

# --- the examples of the help
project "$HOME/projects/wiki"
reset_calls
run "$CMD" "$HOME/projects/wiki"
run "$CMD" -n "$HOME/projects/wiki"
run "$CMD" --down --yes "$HOME/projects/wiki"
check "the examples of the help run" "$UP
docker compose version
docker compose version
docker compose down" "$(calls)"

# --- what can go wrong
reset_calls
run "$CMD" "$TMP/missing folder"
check "a folder that does not exist: exit 1" "1" "$RC"
has "a folder that does not exist: says so" "no such folder: $TMP/missing folder" "$ERR"
mkdir -p "$TMP/empty"
run "$CMD" "$TMP/empty"
check "a folder without a compose file: exit 1" "1" "$RC"
has "a folder without a compose file: says which names count" "docker-compose.yml" "$ERR"
run env HOME="$TMP/other-home" "$CMD"
has "the default folder is missing: names the setting" "MBM_COMPOSE_UP_DIR" "$ERR"
run "$CMD" "$DEF" "$P"
check "two folders: exit 2" "2" "$RC"
run "$CMD" down
check "the word down is a folder name, not a command: exit 1" "1" "$RC"
check "none of these ran docker (the old one ran compose up whatever its arguments)" "" "$(calls)"

fake_docker 'case "$2" in version) exit 1 ;; esac'
run "$CMD" "$P"
check "docker without the compose plugin: exit 1" "1" "$RC"
has "docker without the compose plugin: says so" "no compose plugin" "$ERR"
reset_calls
fake_docker 'case "$2" in up) echo "daemon is not running" >&2; exit 1 ;; esac'
run "$CMD" "$P"
check "compose up fails: exit 1" "1" "$RC"
has "compose up fails: says so" "docker compose up failed" "$ERR"
check "compose up fails: no status listing after it" "docker compose version
docker compose up -d" "$(calls)"
fake_docker 'case "$2" in down) exit 1 ;; esac'
run "$CMD" -d -y "$P"
check "compose down fails: exit 1" "1" "$RC"
fake_docker ''

mkdir -p "$TMP/nopath"
run env PATH="$TMP/nopath" /bin/bash "$CMD" "$P"
check "docker is not installed: exit 1" "1" "$RC"
has "docker is not installed: says how to get it" "docs.docker.com" "$ERR"

mkdir -p "$TMP/inst"
ln -s "$CMD" "$TMP/inst/zz-compose-up"
run "$TMP/inst/zz-compose-up" "$TMP/empty"
has "called as zz-compose-up, the error carries that name" "zz-compose-up: no compose file" "$ERR"

finish
