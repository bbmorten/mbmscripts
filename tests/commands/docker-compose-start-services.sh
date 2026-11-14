#!/bin/bash
# Tests for mbm-docker-compose-start-services.   Run:  tests/run.sh docker-compose-start-services    or:  bash tests/commands/docker-compose-start-services.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-docker-compose-start-services"
echo "mbm-docker-compose-start-services"

# Projects under the default base folder, one for each compose file name.
BASE="$HOME/git-repos"
mkdir -p "$BASE/blog" "$BASE/wiki" "$BASE/my app" "$BASE/yaml" "$BASE/failing" "$BASE/empty" "$BASE/-dash" "$TMP/cwd"
touch "$BASE/blog/docker-compose.yml" "$BASE/wiki/compose.yaml" "$BASE/my app/compose.yml" \
      "$BASE/yaml/docker-compose.yaml" "$BASE/failing/docker-compose.yml" "$BASE/-dash/compose.yaml" \
      "$BASE/not-a-folder"
# The fake engine logs the folder it was started in, and fails in the project "failing".
cat > "$TMP/engine" <<'EOF_ENGINE'
echo "  in ${PWD##*/}" >> "$STUB_LOG"
case "$PWD" in */failing) echo "yaml: line 3: mapping values are not allowed in this context" >&2; exit 15 ;; esac
exit 0
EOF_ENGINE
stub docker "$(cat "$TMP/engine")"
cd "$TMP/cwd" || exit 1

# ---- the main job
run "$CMD" blog
check "starts a project: exit 0" "0" "$RC"
check "runs 'docker compose up -d' inside the project folder" "docker compose up -d
  in blog" "$(calls)"
has "says what it starts" "Starting project blog ($BASE/blog)" "$OUT"

reset_calls
run "$CMD" wiki "my app" yaml
check "compose.yaml, compose.yml and docker-compose.yaml are found too; a name with a space works" \
"docker compose up -d
  in wiki
docker compose up -d
  in my app
docker compose up -d
  in yaml" "$(calls)"
check "three projects: exit 0" "0" "$RC"

# ---- missing and failing projects (the old version exited 0, or with the status of the last one)
reset_calls
run "$CMD" nosuch empty failing blog
check "a missing or failing project gives exit 1, also when the last one is fine" "1" "$RC"
has "no such folder: says which" "nosuch: no such folder: $BASE/nosuch" "$ERR"
has "no compose file: says which" "empty: no compose file" "$ERR"
has "compose failed: says which" 'failing: "docker compose up -d" failed' "$ERR"
has "the end names every project that was not started" "not started: nosuch empty failing" "$ERR"
has "the others are still started" "  in blog" "$(calls)"
check "nothing is run for a missing project" "2" "$(calls docker | wc -l | tr -d ' ')"

reset_calls
run "$CMD"
check "no project: exit 2" "2" "$RC"
has "no project: points to --help" "--help" "$ERR"
check "no project: runs nothing" "" "$(calls)"

# ---- -l
run "$CMD" -l
check "-l lists the folders with a compose file, one per line" "-dash
blog
failing
my app
wiki
yaml" "$(printf '%s\n' "$OUT" | LC_ALL=C sort)"
check "-l: exit 0" "0" "$RC"
check "-l runs nothing" "" "$(calls)"
mkdir -p "$TMP/bare/sub"
run "$CMD" --list -b "$TMP/bare"
check "-l with no project there: empty list, exit 0" "0:" "$RC:$OUT"
has "-l with no project there: says so" "no folder with a compose file under $TMP/bare" "$ERR"
run "$CMD" -l -b "$TMP/nowhere"
check "-l with a missing base folder: exit 1" "1" "$RC"
has "-l with a missing base folder: names the setting" "MBM_COMPOSE_BASE_DIR" "$ERR"
run "$CMD" -l blog
check "-l with a project: exit 2" "2" "$RC"

# ---- -n
reset_calls
run "$CMD" -n blog "my app"
check "-n prints the commands" "(cd $BASE/blog && docker compose up -d)
(cd $BASE/my\\ app && docker compose up -d)" "$OUT"
check "-n runs nothing" "" "$(calls)"
(eval "$OUT") >/dev/null
check "the printed commands can be pasted into a shell" "docker compose up -d
  in blog
docker compose up -d
  in my app" "$(calls)"
reset_calls
run "$CMD" blog --dry-run
check "an option after the project name is still an option" "" "$(calls)"
run "$CMD" -n nosuch blog
check "-n with a missing project: exit 1" "1" "$RC"

# ---- the base folder
mkdir -p "$HOME/work/blog" "$TMP/other/shop"
touch "$HOME/work/blog/compose.yaml" "$TMP/other/shop/compose.yaml"
reset_calls
run "$CMD" -n -b "$HOME/work" blog
check "-b names the base folder (the example with -n -b)" "(cd $HOME/work/blog && docker compose up -d)" "$OUT"
MBM_COMPOSE_BASE_DIR="$TMP/other" run "$CMD" -n shop
check "MBM_COMPOSE_BASE_DIR names the base folder" "(cd $TMP/other/shop && docker compose up -d)" "$OUT"
MBM_COMPOSE_BASE_DIR="$TMP/other" run "$CMD" -n --base-dir="$HOME/work" blog
check "the option wins over the setting" "(cd $HOME/work/blog && docker compose up -d)" "$OUT"

# ---- a path instead of a name
mkdir -p "$TMP/cwd/checkout/blog"
touch "$TMP/cwd/checkout/blog/compose.yml"
reset_calls
run "$CMD" ./checkout/blog
check "a relative path is a folder, not a name under the base folder" "0" "$RC"
has "a relative path: started there" "Starting project ./checkout/blog (./checkout/blog)" "$OUT"
run "$CMD" -n "$BASE/wiki"
check "an absolute path works" "(cd $BASE/wiki && docker compose up -d)" "$OUT"
OUT="$(cd "$BASE/blog" && "$CMD" -n . 2>&1)"
check "'.' is the current folder" "(cd . && docker compose up -d)" "$OUT"
reset_calls
run "$CMD" -- -dash
check "after --, a name with a leading dash is a project" "docker compose up -d
  in -dash" "$(calls)"

# ---- the engine
stub podman "$(cat "$TMP/engine")"
reset_calls
run "$CMD" -e podman blog
check "-e podman runs 'podman compose up -d'" "podman compose up -d
  in blog" "$(calls)"
reset_calls
MBM_CONTAINER_ENGINE=podman run "$CMD" wiki
has "MBM_CONTAINER_ENGINE names the engine" "podman compose up -d" "$(calls)"

# ---- wrong use, missing program
reset_calls
run "$CMD" -b
check "-b without a value: exit 2" "2" "$RC"
check "wrong use runs nothing" "" "$(calls)"
rm -f "$STUBS/docker"
run "$CMD" blog
check "docker missing: exit 1" "1" "$RC"
has "docker missing: says where to get it" "docker is not installed (Docker: https://docs.docker.com/get-docker/" "$ERR"
run "$CMD" -n blog
check "-n needs no docker" "0" "$RC"

finish
