#!/bin/bash
# Tests for mbm-run-docker-web.   Run:  tests/run.sh run-docker-web    or:  bash tests/commands/run-docker-web.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-run-docker-web"
echo "mbm-run-docker-web"

# project DIR - a mkdocs project folder
project() { mkdir -p "$1"; echo "site_name: test" > "$1/mkdocs.yml"; }
# The fake mkdocs builds a one-page site in the folder it runs in.
BUILD="mkdir -p site && echo page > site/index.html"
stub mkdocs "$BUILD"
stub rsync
stub ssh
# remote DIR PORT - the command the remote shell is expected to get
remote() {
  printf 'cd %s || exit 1; docker rm -f docs-web-%s >/dev/null 2>&1; docker run -d --name docs-web-%s -p %s:80 -v "$PWD":/usr/share/nginx/html:ro nginx' "$1" "$2" "$2" "$2"
}
DEF="$HOME/git-repos/docker"
project "$DEF"

# --- the three steps, defaults
run "$CMD" web01
check "HOST alone: exit 0" "0" "$RC"
check "HOST alone: build, copy, start - with port 5500 (the old one sent an empty port)" "mkdocs build
rsync -avz $DEF/site/ vm@web01:docker/
ssh vm@web01 $(remote docker 5500)" "$(calls)"
check "the build ran in the project folder" "page" "$(cat "$DEF/site/index.html")"
has "the last line says where the site is" "http://web01:5500/" "$OUT"
check "nothing on standard error" "" "$ERR"

# --- PORT, USER, REMOTE_DIR, PROJECT_DIR
reset_calls
run "$CMD" web01 8080
check "HOST PORT, the old way of calling it" "ssh vm@web01 $(remote docker 8080)" "$(calls ssh)"
reset_calls
run "$CMD" -p 9000 web01
check "-p PORT" "ssh vm@web01 $(remote docker 9000)" "$(calls ssh)"
reset_calls
run "$CMD" --port 0443 web01
check "--port; leading zeros are dropped" "ssh vm@web01 $(remote docker 443)" "$(calls ssh)"
reset_calls
run "$CMD" -u deploy web01
check "-u USER: for rsync and for ssh" "rsync -avz $DEF/site/ deploy@web01:docker/
ssh deploy@web01 $(remote docker 5500)" "$(calls | sed 1d)"
reset_calls
run env MBM_DOCKER_WEB_USER=ops "$CMD" web01
check "MBM_DOCKER_WEB_USER" "ssh ops@web01 $(remote docker 5500)" "$(calls ssh)"
reset_calls
run env MBM_DOCKER_WEB_USER=ops "$CMD" --user deploy web01
check "--user wins over MBM_DOCKER_WEB_USER" "ssh deploy@web01 $(remote docker 5500)" "$(calls ssh)"
reset_calls
run "$CMD" me@web01
check "USER@HOST is taken as it is" "rsync -avz $DEF/site/ me@web01:docker/
ssh me@web01 $(remote docker 5500)" "$(calls | sed 1d)"
has "USER@HOST: the address shown has no user in it" "http://web01:5500/" "$OUT"
reset_calls
run "$CMD" -u "" web-alias
check "-u \"\" names no user" "rsync -avz $DEF/site/ web-alias:docker/
ssh web-alias $(remote docker 5500)" "$(calls | sed 1d)"
reset_calls
run "$CMD" -t sites/handbook web01
check "-t REMOTE_DIR: for rsync and for the container" "rsync -avz $DEF/site/ vm@web01:sites/handbook/
ssh vm@web01 $(remote sites/handbook 5500)" "$(calls | sed 1d)"
reset_calls
run env MBM_DOCKER_WEB_REMOTE_DIR=www "$CMD" web01
check "MBM_DOCKER_WEB_REMOTE_DIR" "ssh vm@web01 $(remote www 5500)" "$(calls ssh)"
reset_calls
# shellcheck disable=SC2088  # the tilde is meant to arrive unexpanded
run "$CMD" --to '~/docker/' web01
check "--to '~/docker/' means the folder docker in the remote home" "ssh vm@web01 $(remote docker 5500)" "$(calls ssh)"
P="$TMP/my handbook"
project "$P"
reset_calls
run "$CMD" -d "$P" web01
check "-d PROJECT_DIR with a space; the remote folder takes the name of the project" "rsync -avz $P/site/ vm@web01:my-handbook/|page" "$(calls rsync)|$(cat "$P/site/index.html")"
reset_calls
run env MBM_DOCKER_WEB_DIR="$P" "$CMD" web01
check "MBM_DOCKER_WEB_DIR" "rsync -avz $P/site/ vm@web01:my-handbook/" "$(calls rsync)"
reset_calls
run env MBM_DOCKER_WEB_DIR="$P" "$CMD" --dir "$DEF" web01
check "--dir wins over MBM_DOCKER_WEB_DIR" "rsync -avz $DEF/site/ vm@web01:docker/" "$(calls rsync)"
cd "$TMP" || exit 1
reset_calls
run "$CMD" web01 -d "my handbook" -p 81
check "a relative PROJECT_DIR, and options after HOST" "rsync -avz $P/site/ vm@web01:my-handbook/
ssh vm@web01 $(remote my-handbook 81)" "$(calls | sed 1d)"
cd "$HOME" || exit 1
project "$TMP/-çay (v2)"
reset_calls
run "$CMD" -d "$TMP/-çay (v2)" web01
check "a project name that makes no plain folder name: exit 1, nothing run" "1|" "$RC|$(calls)"
has "a project name that makes no plain folder name: asks for -t" "name it with -t" "$ERR"
run env LC_ALL=tr_TR.UTF-8 "$CMD" -d "$TMP/-çay (v2)" -t notlar web01
check "the same project with -t REMOTE_DIR, under a Turkish locale" "0|ssh vm@web01 $(remote notlar 5500)" "$RC|$(calls ssh)"
reset_calls
run env LC_ALL=tr_TR.UTF-8 "$CMD" -t "çay" web01
check "a REMOTE_DIR with a letter outside ASCII is refused under a Turkish locale too" "2|" "$RC|$(calls)"

# --- the project's virtual environment
V="$TMP/with venv"
project "$V"
mkdir -p "$V/.venv/bin"
printf '#!/bin/sh\necho "venv-mkdocs $*"\nmkdir -p site && echo venv-page > site/index.html\n' > "$V/.venv/bin/mkdocs"
chmod +x "$V/.venv/bin/mkdocs"
reset_calls
run "$CMD" -d "$V" web01
check "the mkdocs of PROJECT_DIR/.venv builds the site" "venv-page|" "$(cat "$V/site/index.html")|$(calls mkdocs)"

# --- dry run
N="$TMP/dry project"
project "$N"
reset_calls
before="$(find "$HOME" "$TMP/dry project" | sort)"
run "$CMD" -n -d "$N" web01 8080
check "--dry-run: exit 0" "0" "$RC"
check "--dry-run prints the three commands" "Would run:
  cd $(printf '%q' "$N") && mkdocs build
  rsync -avz $(printf '%q' "$N/site/") vm@web01:dry-project/
  ssh vm@web01 '$(remote dry-project 8080)'" "$OUT"
check "--dry-run runs nothing" "" "$(calls)"
check "--dry-run builds nothing" "$before" "$(find "$HOME" "$TMP/dry project" | sort)"

# --- a remote that really runs the command: rsync copies, ssh runs it in the remote home
R="$TMP/remote-home"
mkdir -p "$R"
stub rsync "dest='$R'/\"\${3#*:}\"; mkdir -p \"\$dest\" && cp -R \"\$2\". \"\$dest\""
stub ssh "cd '$R' && sh -c \"\$2\""
stub docker 'case "$1" in run) echo 0123abcd ;; esac'
reset_calls
run "$CMD" web01
check "on the remote: exit 0" "0" "$RC"
check "on the remote: the site arrived in ~/docker" "page" "$(cat "$R/docker/index.html" 2>/dev/null)"
check "on the remote: the old container goes, the new one mounts the folder by its real path (the old one fixed /home/vm/docker)" \
  "docker rm -f docs-web-5500
docker run -d --name docs-web-5500 -p 5500:80 -v $R/docker:/usr/share/nginx/html:ro nginx" "$(calls docker)"
has "on the remote: the container id is shown" "0123abcd" "$OUT"
reset_calls
run "$CMD" web01
check "a second run uses the same container name, so it replaces the first" \
  "docker rm -f docs-web-5500" "$(calls docker | head -n 1)"
stub rsync
reset_calls
run "$CMD" -t nowhere web01
check "on the remote: no such folder, so no container is started" "1|" "$RC|$(calls docker)"

# --- it stops at the first failing step (the old one went on)
stub ssh
stub mkdocs 'echo "config error" >&2; exit 1'
reset_calls
run "$CMD" web01
check "mkdocs build fails: exit 1" "1" "$RC"
has "mkdocs build fails: says that nothing was copied" "nothing was copied" "$ERR"
check "mkdocs build fails: no rsync, no ssh" "mkdocs build" "$(calls)"
stub mkdocs 'exit 0'
B="$TMP/no-site"
project "$B"
reset_calls
run "$CMD" -d "$B" web01
check "the build leaves no site folder: exit 1, no rsync, no ssh" "1|mkdocs build" "$RC|$(calls)"
stub mkdocs "$BUILD"
stub rsync 'exit 12'
reset_calls
run "$CMD" web01
check "rsync fails: exit 1" "1" "$RC"
has "rsync fails: says that the container was not touched" "was not touched" "$ERR"
check "rsync fails: no ssh" "" "$(calls ssh)"
stub rsync
stub ssh 'echo "port is already allocated" >&2; exit 125'
run "$CMD" web01 8080
check "the container does not start: exit 1" "1" "$RC"
has "the container does not start: shows how to see what holds the port" "docker ps --filter publish=8080" "$ERR"
stub ssh

# --- wrong use: nothing may run
reset_calls
run "$CMD"
check "no HOST: exit 2 (the old one built and copied to 'vm@')" "2" "$RC"
has "no HOST: says so and points to --help" "HOST is missing (see: mbm-run-docker-web --help)" "$ERR"
run "$CMD" web01 8080 extra
check "a third argument: exit 2" "2" "$RC"
run "$CMD" web01 http
check "PORT is not a number: exit 2" "2" "$RC"
run "$CMD" -p 0 web01
check "PORT 0: exit 2" "2" "$RC"
run "$CMD" -p 70000 web01
check "PORT 70000: exit 2" "2" "$RC"
run "$CMD" web01 -p
check "-p without a value: exit 2" "2" "$RC"
run "$CMD" -- -oProxyCommand=evil
check "a HOST that ssh would read as an option: exit 2" "2" "$RC"
run "$CMD" "web01 -v"
check "a HOST with a space: exit 2" "2" "$RC"
run "$CMD" web01:/etc
check "a HOST with a colon, which rsync would read as a path: exit 2" "2" "$RC"
run "$CMD" -t 'x; touch pwned' web01
check "a REMOTE_DIR with shell characters: exit 2" "2" "$RC"
run "$CMD" -u 'a b' web01
check "a USER with a space: exit 2" "2" "$RC"
run "$CMD" -d "$TMP/missing folder" web01
check "PROJECT_DIR does not exist: exit 1" "1" "$RC"
has "PROJECT_DIR does not exist: says so" "no such folder: $TMP/missing folder" "$ERR"
mkdir -p "$TMP/empty"
cd "$TMP/empty" || exit 1
run "$CMD" -d "$TMP/empty" web01
check "PROJECT_DIR without mkdocs.yml: exit 1" "1" "$RC"
has "PROJECT_DIR without mkdocs.yml: says so" "no mkdocs.yml in $TMP/empty" "$ERR"
run env HOME="$TMP/other-home" "$CMD" web01
check "the default project is missing: exit 1 (the old one built in the current folder and went on)" "1" "$RC"
cd "$HOME" || exit 1
check "none of the wrong uses ran anything" "" "$(calls)"

# --- what it needs (a PATH without the system folders, so the real rsync and ssh are out of reach)
mkdir -p "$TMP/p0" "$TMP/p1" "$TMP/p2"
cp "$STUBS/mkdocs" "$TMP/p1/"; cp "$STUBS/mkdocs" "$STUBS/rsync" "$TMP/p2/"
run env PATH="$TMP/p0" /bin/bash "$CMD" web01
has "mkdocs is not installed: says how to get it" "pip install mkdocs" "$ERR"
run env PATH="$TMP/p1" /bin/bash "$CMD" web01
check "rsync is not installed: exit 1" "1" "$RC"
has "rsync is not installed: says so" "rsync is not installed" "$ERR"
run env PATH="$TMP/p2" /bin/bash "$CMD" web01
has "ssh is not installed: says so" "ssh is not installed" "$ERR"
check "a missing program: nothing was built or copied" "" "$(calls)"

# --- the examples of the help
project "$HOME/projects/handbook"
reset_calls
run "$CMD" lab-vm
run "$CMD" lab-vm 8080
check "the first two examples of the help run" "ssh vm@lab-vm $(remote docker 5500)
ssh vm@lab-vm $(remote docker 8080)" "$(calls ssh)"
reset_calls
run "$CMD" -n -d "$HOME/projects/handbook" -u deploy -t sites/handbook -p 8080 docs.example.com
check "the dry-run example of the help" "0|  ssh deploy@docs.example.com '$(remote sites/handbook 8080)'|" "$RC|$(printf '%s\n' "$OUT" | tail -n 1)|$(calls)"

mkdir -p "$TMP/inst"
ln -s "$CMD" "$TMP/inst/zz-run-docker-web"
run "$TMP/inst/zz-run-docker-web"
has "called as zz-run-docker-web, the error carries that name" "zz-run-docker-web: HOST is missing (see: zz-run-docker-web --help)" "$ERR"

finish
