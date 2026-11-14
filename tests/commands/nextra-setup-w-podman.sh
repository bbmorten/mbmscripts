#!/bin/bash
# Tests for mbm-nextra-setup-w-podman.   Run:  tests/run.sh nextra-setup-w-podman    or:  bash tests/commands/nextra-setup-w-podman.sh
#
# The command is "mbm-nextra-setup --podman" (tests/commands/nextra-setup.sh covers the
# generator). Here: that it really is the same, and the podman command lines of the
# podman-run.sh it writes, with a fake podman.
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-nextra-setup-w-podman"
echo "mbm-nextra-setup-w-podman"

GEN="$BIN/mbm-nextra-setup"
W="$TMP/w"
mkdir -p "$W"
cd "$W" || exit 1

state() { (cd "$1" && find . -type f -exec cksum {} + | LC_ALL=C sort); }

# ---- the same project as the generator's --podman
run "$CMD" "Team Handbook"
check "a project is created (exit 0)" "0" "$RC"
check "nothing on standard error" "" "$ERR"
[ -x "Team Handbook/podman-run.sh" ] && ok "it has an executable podman-run.sh" || bad "it has an executable podman-run.sh"
[ ! -e "Team Handbook/docker-compose.yml" ] && ok "and no docker-compose.yml" || bad "and no docker-compose.yml"
mkdir ref
(cd ref && "$GEN" --podman -q "Team Handbook")
check "the files are those of the generator with --podman" "" "$(diff -r "Team Handbook" "ref/Team Handbook" 2>&1)"
has "the next step is the runner" 'cd Team\ Handbook && ./podman-run.sh' "$OUT"

# ---- the options are passed on
before="$(ls -A "$W")"
run "$CMD" -n dry
has "--dry-run lists the runner" "  create   podman-run.sh" "$OUT"
check "--dry-run creates nothing" "$before" "$(ls -A "$W")"
run "$CMD" --port 8080 -q ported
check "--quiet prints nothing" "" "$OUT$ERR"
has "--port reaches the runner" 'PORT="${PORT:-8080}"' "$(cat ported/podman-run.sh)"
stub npm 'exit 0'
run "$CMD" -i installed
check "--install runs npm install" "npm install" "$(calls npm)"
guard npm
reset_calls
keep="$(state ported)"
run "$CMD" ported
check "a folder with files, no terminal, no --yes: refused (exit 1)" "1" "$RC"
check "refused: nothing changed" "$keep" "$(state ported)"
run "$CMD" -y -p 8081 ported
has "--yes writes into it" 'PORT="${PORT:-8081}"' "$(cat ported/podman-run.sh)"
for o in $("$GEN" --help | sed -n '/^Options:/,/^$/p' | grep -o -e '--[a-z][a-z-]*' | sort -u | grep -v -e '^--podman$'); do
  has "the help lists the generator's option $o" "$o" "$("$CMD" --help)"
done

# ---- wrong use is reported under this command's name; found through links (another prefix)
run "$CMD" one two
check "two folders: exit 2" "2" "$RC"
has "the message names this command" "mbm-nextra-setup-w-podman: more than one PROJECT_DIR" "$ERR"
has "and its help" "(see: mbm-nextra-setup-w-podman --help)" "$ERR"
mkdir links
ln -s "$CMD" links/zz-nextra-setup-w-podman
ln -s zz-nextra-setup-w-podman links/zz-pod          # a relative link to a link
run links/zz-nextra-setup-w-podman --port x linked
check "called through a link under another prefix: exit 2" "2" "$RC"
has "the message names the command as it was called" "zz-nextra-setup-w-podman: the port must be" "$ERR"
run links/zz-pod -q linked
check "a link to a link finds the generator (exit 0)" "0" "$RC"
[ -x linked/podman-run.sh ] && ok "and writes the project" || bad "and writes the project"
run links/zz-nextra-setup-w-podman --help
has "its help names the generator under that prefix" "zz-nextra-setup --podman" "$OUT"

# ---- the runner it writes: the podman command lines
P="$W/Team Handbook"
R="$P/podman-run.sh"
NAME=team-handbook-site
run /bin/bash -n "$R"
check "podman-run.sh parses under bash 3.2" "0" "$RC"

run "$R" help
check "runner help: exit 0" "0" "$RC"
has "runner help lists the commands" "prod      build the production image" "$OUT"
run "Team Handbook/podman-run.sh" --help
has "runner help, called by a relative path" "prod      build the production image" "$OUT"
check "runner help writes nothing to standard error" "" "$ERR"
run "$R" nonsense
check "runner: an unknown command exits 2" "2" "$RC"
check "runner: help and an unknown command do not run podman" "" "$(calls)"

rm -f "$STUBS/podman"
if command -v podman >/dev/null 2>&1; then
  skip "podman is in a system folder here: the missing-podman message is not tested"
else
  run "$R" start
  check "runner without podman: exit 1" "1" "$RC"
  has "runner without podman: says where to get it" "podman is not installed (https://podman.io" "$ERR"
fi

stub podman 'exit 0'
stub getenforce 'echo Disabled'
mkdir elsewhere
OUT="$(cd elsewhere && "$R" start 2>&1 </dev/null)"; RC=$?
check "runner start: exit 0" "0" "$RC"
check "runner start: replaces the container, then runs the dev server on the project folder (from any folder)" \
"podman rm -f $NAME
podman run -d --name $NAME -p 3000:3000 -v $P:/app -v $NAME-modules:/app/node_modules -w /app -e NEXT_TELEMETRY_DISABLED=1 node:24-slim sh -c npm install && npm run dev" "$(calls podman)"
has "runner start: says where the site is" "http://localhost:3000" "$OUT"

reset_calls
run "$R"
has "runner without a command: the dev server in the foreground, no terminal" "podman run --rm -i --name $NAME -p 3000:3000" "$(calls podman)"
reset_calls
run "Team Handbook/podman-run.sh" dev
has "runner dev, called by a relative path: the same" "podman run --rm -i --name $NAME -p 3000:3000" "$(calls podman)"

reset_calls
run env PORT=4000 "$R" start
has "runner: PORT changes the port of this machine only" "-p 4000:3000 " "$(calls podman)"
has "runner: and the address it prints" "http://localhost:4000" "$OUT"

reset_calls
stub getenforce 'echo Enforcing'
run "$R" start
has "runner on SELinux: the project folder is relabelled" "-v $P:/app:Z " "$(calls podman)"
stub getenforce 'echo Disabled'

reset_calls
run "$R" prod
check "runner prod: builds the image, replaces the container, runs the image" \
"podman build -t $NAME .
podman rm -f $NAME
podman run -d --name $NAME -p 3000:3000 -e HOSTNAME=0.0.0.0 $NAME" "$(calls podman)"

reset_calls
stub podman 'case "$1" in build) exit 1 ;; esac; exit 0'
run "$R" prod
[ "$RC" != 0 ] && ok "runner prod: a failed build is an error" || bad "runner prod: a failed build is an error"
check "runner prod: and nothing is started after a failed build" "podman build -t $NAME ." "$(calls podman)"
stub podman 'exit 0'

reset_calls
run "$R" logs
check "runner logs" "podman logs -f $NAME" "$(calls podman)"
reset_calls
run "$R" status
check "runner status" "podman ps -a --filter name=^$NAME\$" "$(calls podman)"
reset_calls
run "$R" stop
check "runner stop" "podman rm -f $NAME" "$(calls podman)"

reset_calls
run "$R" cleanup
check "runner cleanup: removes its own container, volume and image" \
"podman rm -f $NAME
podman volume rm -f $NAME-modules
podman rmi -f $NAME" "$(calls podman)"
hasnt "runner cleanup: never prunes other volumes or images (the old one did)" "prune" "$(calls podman)"

# Two projects do not share a container name (the old runner called every container nextra-docs).
has "another project has its own container name" "NAME=ported-site" "$(cat ported/podman-run.sh)"

guard podman
reset_calls
finish
