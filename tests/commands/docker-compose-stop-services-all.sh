#!/bin/bash
# Tests for mbm-docker-compose-stop-services-all.   Run:  tests/run.sh docker-compose-stop-services-all    or:  bash tests/commands/docker-compose-stop-services-all.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-docker-compose-stop-services-all"
echo "mbm-docker-compose-stop-services-all"

# The fake engine: "compose ls -q" prints the names in $FIX/running (the real one prints one
# name per line); "compose ls" prints the table; down and stop fail for the project "badone".
export FIX="$TMP/fix"
mkdir -p "$FIX"
cat > "$FIX/engine" <<'EOF_ENGINE'
case "$*" in
  "compose ls -q") [ -f "$FIX/down" ] && { echo "Cannot connect to the Docker daemon" >&2; exit 1; }
                   cat "$FIX/running" ;;
  "compose ls") echo "NAME                STATUS              CONFIG FILES"
                sed 's|$|            running(2)          /path/to/compose.yaml|' "$FIX/running" ;;
  *badone*) echo "boom" >&2; exit 1 ;;
esac
exit 0
EOF_ENGINE
stub docker "$(cat "$FIX/engine")"
printf 'ndfc-mcp\nweb\n' > "$FIX/running"

# ---- asked for help, it must not stop anything (the old version did)
run "$CMD" --help
check "--help runs nothing" "" "$(calls)"

# ---- nothing is changed without a yes
run "$CMD"
check "no terminal and no --yes: exit 1" "1" "$RC"
has "no terminal and no --yes: says how to go ahead" "Add --yes" "$ERR"
check "no terminal and no --yes: only the list was read" "docker compose ls -q" "$(calls)"
has "the projects are listed before the question" "Running Compose projects (2):
  ndfc-mcp
  web" "$OUT"

reset_calls
run "$CMD" -n
check "-n: exit 0" "0" "$RC"
has "-n prints the commands" "  docker compose -p ndfc-mcp down
  docker compose -p web down" "$OUT"
check "-n changes nothing" "docker compose ls -q" "$(calls)"
reset_calls
run "$CMD" -n -y -s
has "-n -s prints the stop commands" "  docker compose -p web stop" "$OUT"
check "-n wins over -y" "docker compose ls -q" "$(calls)"

reset_calls
if tty_run "n" "$CMD"; then
  # (tty_run cannot report the exit status: its RC is that of the tr at the end of its pipe.)
  has "answer n: the question says what down does" "remove its containers and networks? [y/N]" "$OUT"
  has "answer n: says nothing was changed" "cancelled; nothing was changed" "$OUT"
  check "answer n: nothing was stopped" "docker compose ls -q" "$(calls)"
  reset_calls
  tty_run "y" "$CMD"
  check "answer y: every project is taken down" "docker compose ls -q
docker compose -p ndfc-mcp down
docker compose -p web down" "$(calls)"
else
  skip "no expect: the terminal answers are not tested"
fi

# ---- with a yes
reset_calls
run "$CMD" -y
check "--yes: exit 0" "0" "$RC"
check "--yes: names from 'compose ls -q', then down for each" "docker compose ls -q
docker compose -p ndfc-mcp down
docker compose -p web down" "$(calls)"
reset_calls
run "$CMD" --stop --yes
check "-s stops the containers instead (they are kept)" "docker compose ls -q
docker compose -p ndfc-mcp stop
docker compose -p web stop" "$(calls)"

# ---- failures
printf 'ndfc-mcp\nbadone\nweb\n' > "$FIX/running"
reset_calls
run "$CMD" -y
check "a project that fails: exit 1, also when the last one is fine" "1" "$RC"
has "a project that fails: named at the end" '"compose down" failed for: badone' "$ERR"
has "a project that fails: the others are still done" "docker compose -p web down" "$(calls)"

: > "$FIX/running"
reset_calls
run "$CMD"
check "nothing is running: exit 0, without a question" "0" "$RC"
check "nothing is running: says so" "No Compose project is running." "$OUT"

printf 'web\n' > "$FIX/running"
touch "$FIX/down"
reset_calls
run "$CMD" -y
check "the list cannot be read: exit 1" "1" "$RC"
has "the list cannot be read: says so" "could not list the Compose projects (is docker running?)" "$ERR"
check "the list cannot be read: nothing else is run" "docker compose ls -q" "$(calls)"
rm -f "$FIX/down"

# ---- the engine
stub podman "$(cat "$FIX/engine")"
reset_calls
run "$CMD" -e podman -y
check "-e podman runs podman" "podman compose ls -q
podman compose -p web down" "$(calls)"
reset_calls
MBM_CONTAINER_ENGINE=podman run "$CMD" -s -y
check "MBM_CONTAINER_ENGINE names the engine" "podman compose ls -q
podman compose -p web stop" "$(calls)"

# ---- wrong use, missing program
reset_calls
run "$CMD" web
check "an argument: exit 2" "2" "$RC"
run "$CMD" -y -- web
check "an argument after --: exit 2" "2" "$RC"
run "$CMD" -e
check "-e without a value: exit 2" "2" "$RC"
check "wrong use runs nothing" "" "$(calls)"
rm -f "$STUBS/docker"
run "$CMD" -y
check "docker missing: exit 1" "1" "$RC"
has "docker missing: says where to get it" "docker is not installed (Docker: https://docs.docker.com/get-docker/" "$ERR"

finish
