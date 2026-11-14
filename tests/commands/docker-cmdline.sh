#!/bin/bash
# Tests for mbm-docker-cmdline.   Run:  tests/run.sh docker-cmdline    or:  bash tests/commands/docker-cmdline.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-docker-cmdline"
echo "mbm-docker-cmdline"

# The fake engine: "inspect ... NAME" prints the line of NAME from this table, in the format
# the real docker prints for '{{json .Config.Entrypoint}} {{json .Config.Cmd}}'.
export FIX="$TMP/fix"
mkdir -p "$FIX" "$TMP/work"
cat > "$FIX/table" <<'EOF_TABLE'
web	["docker-entrypoint.sh"] ["node","/app/server.mjs"]
vpn	["/usr/local/bin/vpn-connect"] null
cmdonly	null ["nginx","-g","daemon off;"]
opa	["/opa"] ["run","--server","--addr=0.0.0.0:8181","--log-level=error"]
glob	["sh","-c"] ["echo hello   world; ls *"]
tricky	["sh","-c","printf '%s\\n' \"$HOME\" && echo it's\ttab\nline2 \\\\ `id`",""] null
quote	["sh","-c","echo it's $1 \"x\""] null
nothing	null null
oldpodman	"/bin/tini" ["--","app"]
EOF_TABLE
# (Written to a file first: bash 3.2 cannot read a here-document with ")" inside $(...).)
cat > "$FIX/engine" <<'EOF_ENGINE'
case "$1" in
  ps) printf 'web\nvpn\n'; exit 0 ;;
esac
name="${!#}"
line="$(awk -F '\t' -v n="$name" '$1 == n { print $2 }' "$FIX/table")"
[ -n "$line" ] || { echo "Error response from daemon: No such object: $name" >&2; exit 1; }
printf '%s\n' "$line"
EOF_ENGINE
ENGINE_BODY="$(cat "$FIX/engine")"
stub docker "$ENGINE_BODY"
stub jq 'exit 97'
INSPECT='inspect --format {{json .Config.Entrypoint}} {{json .Config.Cmd}}'
cd "$TMP/work" || exit 1
touch "a file" other

# ---- the main job
run "$CMD" web
check "entrypoint plus command on one line" "docker-entrypoint.sh node /app/server.mjs" "$OUT"
check "exit 0" "0" "$RC"
check "one inspect call, asking for both parts" "docker $INSPECT web" "$(calls docker)"
check "jq is not used" "" "$(calls jq)"

run "$CMD" opa
check "plain arguments are not quoted" "/opa run --server --addr=0.0.0.0:8181 --log-level=error" "$OUT"

# ---- null for one part (the old version printed a jq error here)
run "$CMD" vpn
check "no command (null): the entrypoint alone" "/usr/local/bin/vpn-connect" "$OUT"
check "no command: nothing on standard error" "" "$ERR"
check "no command: exit 0" "0" "$RC"
run "$CMD" cmdonly
check "no entrypoint (null): the command, quoted" "nginx -g 'daemon off;'" "$OUT"
check "no entrypoint: nothing on standard error" "" "$ERR"

# ---- quoting (the old version let the shell expand * and squeezed the spaces)
run "$CMD" glob
check "an argument with spaces and * stays one quoted argument" "sh -c 'echo hello   world; ls *'" "$OUT"
hasnt "file names of the current folder do not leak in" "a file" "$OUT"

run "$CMD" tricky
check "an argument with a line break still gives one line" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
eval "set -- $OUT"
check "pasted into a shell: four arguments" "4" "$#"
check "pasted: quotes, \$HOME, &&, tab, line break, backslashes and backticks survive" \
  "$(printf 'printf \047%%s\\n\047 "$HOME" && echo it\047s\ttab\nline2 \\\\ `id`')" "${3:-}"
check "pasted: the empty last argument survives" "" "${4-missing}"
set --

run "$CMD" quote
check "a single quote inside an argument is written the shell way" "sh -c 'echo it'\\''s \$1 \"x\"'" "$OUT"
eval "set -- $OUT"
check "pasted: the single quote, \$1 and the double quotes survive" "echo it's \$1 \"x\"" "${3:-}"
set --

LC_ALL=tr_TR.UTF-8 run "$CMD" tricky
has "the same under a Turkish locale" '&& echo it' "$OUT"

run "$CMD" oldpodman
check "an entrypoint given as plain text (not a list) is read too" "/bin/tini -- app" "$OUT"

# ---- several containers
reset_calls
run "$CMD" web nosuch vpn
check "several: each line starts with the name; the others still print" \
  "web: docker-entrypoint.sh node /app/server.mjs
vpn: /usr/local/bin/vpn-connect" "$OUT"
check "several: one missing gives exit 1" "1" "$RC"
has "several: the engine's own message is shown" "No such object: nosuch" "$ERR"
check "several: one call per container" "3" "$(calls docker | wc -l | tr -d ' ')"

# ---- failures
run "$CMD" nosuch
check "no such container: exit 1" "1" "$RC"
check "no such container: nothing on standard output" "" "$OUT"
run "$CMD" nothing
check "neither entrypoint nor command: exit 1" "1" "$RC"
has "neither entrypoint nor command: says so" "nothing has neither an entrypoint nor a command" "$ERR"

# ---- the engine
reset_calls
stub podman "$ENGINE_BODY"
stub nerdctl "$ENGINE_BODY"
run "$CMD" -e podman web
check "-e podman asks podman" "podman $INSPECT web" "$(calls)"
check "-e podman: the same answer" "docker-entrypoint.sh node /app/server.mjs" "$OUT"
reset_calls
MBM_CONTAINER_ENGINE=podman run "$CMD" vpn
check "MBM_CONTAINER_ENGINE names the engine" "podman $INSPECT vpn" "$(calls)"
reset_calls
MBM_CONTAINER_ENGINE=podman run "$CMD" --engine=nerdctl web
check "the option wins over the setting" "nerdctl $INSPECT web" "$(calls)"
reset_calls
run "$CMD" web --engine nerdctl
check "an option after the name is still an option" "nerdctl $INSPECT web" "$(calls)"

# ---- the examples of the help
reset_calls
# shellcheck disable=SC2046  # the example is written with an unquoted $(...)
run "$CMD" $(docker ps -q)
check "example: every running container" "web: docker-entrypoint.sh node /app/server.mjs
vpn: /usr/local/bin/vpn-connect" "$OUT"
run "$CMD" -- web
check "-- ends the options" "docker-entrypoint.sh node /app/server.mjs" "$OUT"

# ---- wrong use
reset_calls
run "$CMD"
check "no container: exit 2" "2" "$RC"
has "no container: points to --help" "--help" "$ERR"
run "$CMD" -e
check "-e without a value: exit 2" "2" "$RC"
run "$CMD" -e "" web
check "an empty engine name: exit 2" "2" "$RC"
check "wrong use runs nothing" "" "$(calls)"

rm -f "$STUBS/docker"
run "$CMD" web
check "docker missing: exit 1" "1" "$RC"
has "docker missing: says where to get it" "docker is not installed (Docker: https://docs.docker.com/get-docker/" "$ERR"
run "$CMD" -e nosuchengine web
has "another engine missing: names it" "nosuchengine is not installed" "$ERR"

finish
