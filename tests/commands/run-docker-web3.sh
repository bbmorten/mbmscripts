#!/bin/bash
# Tests for mbm-run-docker-web3.   Run:  tests/run.sh run-docker-web3    or:  bash tests/commands/run-docker-web3.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-run-docker-web3"
echo "mbm-run-docker-web3"

# The options and the failure paths belong to mbm-run-docker-web and are tested there. Here:
# the two defaults that differ, and that every argument reaches the other command.

project() { mkdir -p "$1"; echo "site_name: test" > "$1/mkdocs.yml"; }
BUILD="mkdir -p site && echo page > site/index.html"
stub mkdocs "$BUILD"
stub rsync
stub ssh
remote() {
  printf 'cd %s || exit 1; docker rm -f docs-web-%s >/dev/null 2>&1; docker run -d --name docs-web-%s -p %s:80 -v "$PWD":/usr/share/nginx/html:ro nginx' "$1" "$2" "$2" "$2"
}
V1="$HOME/git-repos/docker"
V3="$HOME/git-repos/docker-v3"
project "$V1"
project "$V3"

# --- its own defaults
run "$CMD" web01
check "HOST alone: exit 0" "0" "$RC"
check "HOST alone: the project docker-v3, the remote folder docker-v3, port 5500 (the old one sent an empty port, and copied into the folder of the first site)" \
  "mkdocs build
rsync -avz $V3/site/ vm@web01:docker-v3/
ssh vm@web01 $(remote docker-v3 5500)" "$(calls)"
check "the build ran in docker-v3 and not in docker" "page|no" "$(cat "$V3/site/index.html")|$([ -e "$V1/site" ] && echo yes || echo no)"
reset_calls
run "$CMD" web01 5501
check "HOST PORT, the old way of calling it" "ssh vm@web01 $(remote docker-v3 5501)" "$(calls ssh)"

# --- the settings
P="$TMP/third site"
project "$P"
reset_calls
run env MBM_DOCKER_WEB3_DIR="$P" MBM_DOCKER_WEB3_REMOTE_DIR=v3 "$CMD" web01
check "MBM_DOCKER_WEB3_DIR and MBM_DOCKER_WEB3_REMOTE_DIR" "rsync -avz $P/site/ vm@web01:v3/
ssh vm@web01 $(remote v3 5500)" "$(calls | sed 1d)"
reset_calls
run env MBM_DOCKER_WEB3_DIR="$P" "$CMD" web01
check "MBM_DOCKER_WEB3_DIR alone: the remote folder takes the name of that project" "rsync -avz $P/site/ vm@web01:third-site/" "$(calls rsync)"
reset_calls
run env MBM_DOCKER_WEB_DIR="$V1" MBM_DOCKER_WEB_REMOTE_DIR=docker "$CMD" web01
check "the settings of the first site do not move this one" "rsync -avz $V3/site/ vm@web01:docker-v3/" "$(calls rsync)"
reset_calls
run env MBM_DOCKER_WEB_USER=ops "$CMD" web01
check "MBM_DOCKER_WEB_USER is shared with the first site" "ssh ops@web01 $(remote docker-v3 5500)" "$(calls ssh)"

# --- every option reaches the other command
reset_calls
run "$CMD" -d "$P" -u deploy -t sites/v3 -p 8443 web01
check "-d, -u, -t and -p win over the defaults" "rsync -avz $P/site/ deploy@web01:sites/v3/
ssh deploy@web01 $(remote sites/v3 8443)" "$(calls | sed 1d)"
reset_calls
rm -rf "$V3/site"
before="$(find "$HOME" | sort)"
run "$CMD" -n lab-vm 5501
check "--dry-run (an example of the help) prints the three commands" "Would run:
  cd $V3 && mkdocs build
  rsync -avz $V3/site/ vm@lab-vm:docker-v3/
  ssh vm@lab-vm '$(remote docker-v3 5501)'" "$OUT"
check "--dry-run runs nothing and builds nothing" "|$before" "$(calls)|$(find "$HOME" | sort)"
run "$CMD" lab-vm 5501
check "the first example of the help runs" "0|ssh vm@lab-vm $(remote docker-v3 5501)" "$RC|$(calls ssh)"

# --- a failing step stops it here too
stub rsync 'exit 12'
reset_calls
run "$CMD" web01
check "rsync fails: exit 1 and no ssh" "1|" "$RC|$(calls ssh)"
stub rsync

# --- wrong use
reset_calls
run "$CMD"
check "no HOST: exit 2 (the old one built and copied to 'vm@')" "2" "$RC"
has "no HOST: its own name in the message" "mbm-run-docker-web3: HOST is missing (see: mbm-run-docker-web3 --help)" "$ERR"
run "$CMD" -n
check "an option but no HOST: exit 2" "2" "$RC"
run "$CMD" web01 5501 extra
check "a third argument: exit 2" "2" "$RC"
run env HOME="$TMP/other-home" "$CMD" web01
check "the default project is missing: exit 1" "1" "$RC"
has "the default project is missing: names the folder" "no such folder: $TMP/other-home/git-repos/docker-v3" "$ERR"
check "none of the wrong uses ran anything" "" "$(calls)"
run "$CMD" -n --help
has "--help after another option still shows this command's help" "mbm-run-docker-web3 - " "$OUT"

# --- installed under another name: a link in another folder, reached through a second, relative link
mkdir -p "$TMP/inst/bin" "$TMP/inst/links"
ln -s "$CMD" "$TMP/inst/bin/zz-run-docker-web3"
( cd "$TMP/inst/links" && ln -s ../bin/zz-run-docker-web3 zz-run-docker-web3 )
reset_calls
run "$TMP/inst/links/zz-run-docker-web3" web01 5501
check "through two links it still finds the other command, which is not on the PATH" \
  "0|ssh vm@web01 $(remote docker-v3 5501)" "$RC|$(calls ssh)"
run "$TMP/inst/bin/zz-run-docker-web3"
has "called as zz-run-docker-web3, the error carries that name" "zz-run-docker-web3: HOST is missing (see: zz-run-docker-web3 --help)" "$ERR"
run "$TMP/inst/bin/zz-run-docker-web3" --help
has "called as zz-run-docker-web3, the help names the other command with that prefix" "zz-run-docker-web --help" "$OUT"

finish
