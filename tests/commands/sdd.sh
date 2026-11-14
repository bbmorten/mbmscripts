#!/bin/bash
# Tests for mbm-sdd.   Run:  tests/run.sh sdd    or:  bash tests/commands/sdd.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-sdd"
echo "mbm-sdd"

# project DIR [FILE] - a mkdocs project folder
project() { mkdir -p "$1"; echo "site_name: test" > "$1/${2:-mkdocs.yml}"; }
# The fake mkdocs on the PATH says where it runs.
stub mkdocs 'echo "path-mkdocs in $(pwd)"'
DEF="$HOME/git-repos/docker"

# --- the default folder, no virtual environment
project "$DEF"
run "$CMD"
check "no arguments: exit 0" "0" "$RC"
check "no arguments: runs mkdocs serve and nothing else" "mkdocs serve" "$(calls)"
has "no arguments: runs in ~/git-repos/docker" "path-mkdocs in $DEF" "$OUT"
has "says what it serves and how to stop" "Ctrl-C" "$OUT"
check "a project without .venv gives no error text (the old one printed a shell error)" "" "$ERR"

# --- DIR: a name with a space, a relative name, the setting
reset_calls
project "$TMP/my docs"
run "$CMD" "$TMP/my docs"
has "DIR with a space: runs there" "path-mkdocs in $TMP/my docs" "$OUT"
cd "$TMP" || exit 1
run "$CMD" "my docs"
has "a relative DIR works" "path-mkdocs in $TMP/my docs" "$OUT"
cd "$HOME" || exit 1
run env MBM_SDD_DIR="$TMP/my docs" "$CMD"
has "MBM_SDD_DIR is the folder when no DIR is given" "path-mkdocs in $TMP/my docs" "$OUT"
run env MBM_SDD_DIR="$TMP/my docs" "$CMD" "$DEF"
has "DIR wins over MBM_SDD_DIR" "path-mkdocs in $DEF" "$OUT"
project "$TMP/yaml" mkdocs.yaml
run "$CMD" "$TMP/yaml"
check "mkdocs.yaml counts as a project too" "0" "$RC"

# --- arguments for mkdocs
reset_calls
run "$CMD" -- -a 127.0.0.1:8001
check "everything after -- goes to mkdocs serve" "mkdocs serve -a 127.0.0.1:8001" "$(calls)"
reset_calls
run "$CMD" "$TMP/my docs" -- --strict -h "two words"
check "DIR and mkdocs arguments together; -h after -- is for mkdocs" "mkdocs serve --strict -h two words" "$(calls)"
has "DIR and mkdocs arguments together: runs in DIR" "path-mkdocs in $TMP/my docs" "$OUT"
stub mkdocs 'exit 3'
run "$CMD"
check "the exit status of mkdocs is passed on" "3" "$RC"
stub mkdocs 'echo "path-mkdocs in $(pwd)"'

# --- the project's virtual environment
V="$TMP/with venv"
project "$V"
mkdir -p "$V/.venv/bin"
printf '#!/bin/sh\necho "venv-mkdocs $* VIRTUAL_ENV=$VIRTUAL_ENV"\n' > "$V/.venv/bin/mkdocs"
chmod +x "$V/.venv/bin/mkdocs"
reset_calls
run "$CMD" "$V" -- -q
has "the mkdocs of DIR/.venv is used, with VIRTUAL_ENV set" "venv-mkdocs serve -q VIRTUAL_ENV=$V/.venv" "$OUT"
check "the mkdocs of DIR/.venv is used: the one on the PATH is not" "" "$(calls)"
rm "$V/.venv/bin/mkdocs"
run "$CMD" "$V"
has "a .venv without mkdocs: the one on the PATH is used" "path-mkdocs in $V" "$OUT"

# --- the examples of the help
project "$HOME/projects/handbook"
reset_calls
run "$CMD" "$HOME/projects/handbook"
run "$CMD" "$HOME/projects/handbook" -- -a 127.0.0.1:8001
run "$CMD" -- --strict
check "the examples of the help run" "mkdocs serve
mkdocs serve -a 127.0.0.1:8001
mkdocs serve --strict" "$(calls)"

# --- wrong use
reset_calls
run "$CMD" "$TMP/missing folder"
check "a folder that does not exist: exit 1" "1" "$RC"
has "a folder that does not exist: says so" "no such folder: $TMP/missing folder" "$ERR"
mkdir -p "$TMP/empty"
run "$CMD" "$TMP/empty"
check "a folder without mkdocs.yml: exit 1" "1" "$RC"
has "a folder without mkdocs.yml: says so" "no mkdocs.yml in $TMP/empty" "$ERR"
run env HOME="$TMP/other-home" "$CMD"
check "the default folder is missing: exit 1" "1" "$RC"
has "the default folder is missing: names the setting" "MBM_SDD_DIR" "$ERR"
run "$CMD" "$DEF" "$TMP/my docs"
check "two folders: exit 2" "2" "$RC"
has "two folders: points to --help" "--help" "$ERR"
run "$CMD" --strict
check "an mkdocs option without --: exit 2" "2" "$RC"
check "none of the wrong uses ran mkdocs (the old one ignored its arguments and served the default folder)" "" "$(calls)"

mkdir -p "$TMP/nopath"
run env PATH="$TMP/nopath" /bin/bash "$CMD" "$DEF"
check "mkdocs is not installed: exit 1" "1" "$RC"
has "mkdocs is not installed: says how to get it" "pip install mkdocs" "$ERR"

mkdir -p "$TMP/inst"
ln -s "$CMD" "$TMP/inst/zz-sdd"
run "$TMP/inst/zz-sdd" "$TMP/empty"
has "called as zz-sdd, the error carries that name" "zz-sdd: no mkdocs.yml" "$ERR"

finish
