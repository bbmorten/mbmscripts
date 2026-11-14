#!/bin/bash
# tests/run.sh - offline checks. Everything runs inside the sandbox of tests/lib.sh: nothing
# here connects anywhere, uses sudo, docker or a VPN, reads your real Messages database,
# touches the Keychain or writes outside a temporary folder.
#
# Usage:
#   tests/run.sh               every check
#   tests/run.sh NAME...       only the checks of these commands (names without the prefix)
#   tests/run.sh -v NAME...    the same, showing every line of their test files
#
# What it checks:
#   Syntax        every script parses (bash -n / zsh -n, by its first line)
#   Conventions   every command answers --help the standard way, also under another prefix,
#                 refuses an unknown option, and passes shellcheck (see README, For developers)
#   Commands      the test file of each command, tests/commands/<name>.sh
#   and, without names: the descriptions list, a scan for personal values, the installer and
#   uninstaller in a throw-away HOME, the SMS code reader and the route hook of the VPN tools.
#
# Examples:
#   tests/run.sh
#   tests/run.sh du find-file

. "$(dirname "$0")/lib.sh"

VERBOSE=0
case "${1:-}" in
  -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
  -v) VERBOSE=1; shift ;;
esac
ONLY=" $* "
ALL=1
[ $# -gt 0 ] && ALL=0
wanted() { [ "$ALL" = 1 ] && return 0; case "$ONLY" in *" $1 "*) return 0 ;; esac; return 1; }

# mbm-btvpn and mbm-multivpn are kept exactly as published in bbmorten/btvpn-multivpn; their
# own checks are at the end of this file.
EXEMPT=" btvpn multivpn "
exempt() { case "$EXEMPT" in *" $1 "*) return 0 ;; esac; return 1; }

SHELLCHECK="$(export PATH="$REAL_PATH"; command -v shellcheck 2>/dev/null)"
RUN_BASH=/bin/bash
[ -x "$RUN_BASH" ] || RUN_BASH=bash

# limited SECONDS CMD [ARG...] - run CMD, stop it after SECONDS (a script that waits for
# something must not hang the checks).
limited() {
  local secs="$1" pid killer rc
  shift
  "$@" &
  pid=$!
  # The watchdog ends its own sleep when it is told to stop, so nothing lingers.
  ( trap 'kill "$_s" 2>/dev/null; exit 0' TERM
    sleep "$secs" & _s=$!
    wait "$_s" && kill -TERM "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  killer=$!
  wait "$pid" 2>/dev/null
  rc=$?
  kill -TERM "$killer" 2>/dev/null
  wait "$killer" 2>/dev/null
  return "$rc"
}

for name in "$@"; do
  [ -f "$BIN/mbm-$name" ] || { echo "run.sh: no such command: mbm-$name" >&2; exit 2; }
done

# ---------------------------------------------------------------- syntax

echo "Syntax"
n=0; broken=""
parses() {
  case "$(head -n 1 "$1")" in
    *zsh*) if command -v zsh >/dev/null 2>&1; then zsh -n "$1" 2>/dev/null; fi ;;
    *) bash -n "$1" 2>/dev/null ;;
  esac
}
for f in "$BIN"/mbm-*; do
  wanted "${f##*/mbm-}" || continue
  n=$((n + 1))
  parses "$f" || broken="$broken ${f#"$ROOT"/}"
  [ -x "$f" ] || broken="$broken ${f##*/}(not-executable)"
done
for f in "$ROOT"/tests/commands/*.sh; do
  [ -f "$f" ] || continue
  b="${f##*/}"
  wanted "${b%.sh}" || continue
  n=$((n + 1))
  bash -n "$f" 2>/dev/null || broken="$broken ${f#"$ROOT"/}"
done
if [ "$ALL" = 1 ]; then
  for f in "$LIBEXEC"/btvpn-sms-code "$LIBEXEC"/multivpn-proxy "$LIBEXEC"/multivpn-routes \
           "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/tests/run.sh" "$ROOT/tests/lib.sh" "$ROOT/tests/sandbox.sh"; do
    n=$((n + 1))
    parses "$f" || broken="$broken ${f#"$ROOT"/}"
  done
fi
if [ -z "$broken" ]; then ok "$n files parse and the commands are executable"; else bad "problems:$broken"; fi

# ---------------------------------------------------------------- lists

if [ "$ALL" = 1 ]; then
  echo "Descriptions"
  check "every command has one description, and the reverse" "" \
    "$(diff <(cut -f1 "$LIBEXEC/descriptions.txt" | sort) <(ls "$BIN" | sed 's/^mbm-//' | sort))"

  echo "Personal values"
  found="$(grep -rn -E '/Users/[A-Za-z]|/home/[a-z]+/[a-z]' "$BIN" "$LIBEXEC" "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/README.md")"
  check "no home-folder path of a real person in the published files" "" "$found"

  echo "Sandbox"
  # A program named by its full path escapes the sandbox PATH, and with it the guards.
  names="$(printf '%s' "$GUARDED" | tr -s ' \\\n' '|' | sed 's/^|//; s/|$//')"
  found="$(grep -n -E "(^|[^A-Za-z0-9_./-])(/usr/local|/opt/homebrew|/usr)?/s?bin/($names)([^A-Za-z0-9_-]|\$)" "$BIN"/mbm-* \
            | grep -v -E '^[^:]+/mbm-(btvpn|multivpn):' | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*#')"
  check "no command calls a guarded program by its full path" "" "$found"
fi

# ---------------------------------------------------------------- conventions

# One line per command: ok, or FAIL with every rule it breaks.
conventions() {
  local name="$1" f="$BIN/mbm-$1" out out2 outz rc why=""
  mkdir -p "$TMP/zz"
  ln -sf "$f" "$TMP/zz/zz-$name"
  rm -rf "$TMP/cwd"
  mkdir -p "$TMP/cwd"
  : > "$STUB_LOG"

  out="$(cd "$TMP/cwd" && limited 10 "$f" --help 2>"$TMP/stderr" </dev/null)"
  rc=$?
  [ "$rc" = 0 ] || why="$why; --help exits $rc"
  case "$out" in "mbm-$name - "*) ;; *) why="$why; --help does not start with 'mbm-$name - '" ;; esac
  [ -s "$TMP/stderr" ] && why="$why; --help writes to standard error"
  printf '%s\n' "$out" | grep -q '^Usage:' || why="$why; no 'Usage:' section"
  printf '%s\n' "$out" | grep -Eq '^Examples?:' || why="$why; no 'Examples:' section"

  out2="$(cd "$TMP/cwd" && limited 10 "$f" -h 2>/dev/null </dev/null)"
  [ "$out2" = "$out" ] || why="$why; -h differs from --help"

  outz="$(cd "$TMP/cwd" && limited 10 "$TMP/zz/zz-$name" --help 2>/dev/null </dev/null)"
  case "$outz" in "zz-$name - "*) ;; *) why="$why; called as zz-$name, the help does not start with 'zz-$name - '" ;; esac
  case "$outz" in *mbm-*) why="$why; called as zz-$name, the help still says mbm-" ;; esac

  ( cd "$TMP/cwd" && limited 10 "$f" --no-such-option >/dev/null 2>"$TMP/stderr" </dev/null )
  rc=$?
  [ "$rc" = 2 ] || why="$why; an unknown option exits $rc, not 2"
  grep -q -- '--help' "$TMP/stderr" || why="$why; an unknown option does not point to --help"
  [ -z "$(ls -A "$TMP/cwd")" ] || why="$why; help or an unknown option created files"
  [ -s "$STUB_LOG" ] && why="$why; help or an unknown option ran: $(head -n 2 "$STUB_LOG" | tr '\n' ',')"
  : > "$STUB_LOG"

  case "$(head -n 1 "$f")" in
    *zsh*) ;;
    *) if [ -n "$SHELLCHECK" ] && ! "$SHELLCHECK" -S warning "$f" >/dev/null 2>&1; then
         why="$why; shellcheck -S warning reports problems"
       fi ;;
  esac

  if [ -z "$why" ]; then ok "mbm-$name"; else bad "mbm-$name${why}"; fi
}

echo "Conventions (--help, -h, another prefix, unknown option, shellcheck)"
[ -n "$SHELLCHECK" ] || skip "shellcheck is not installed: that rule is not checked"
for f in "$BIN"/mbm-*; do
  name="${f##*/mbm-}"
  wanted "$name" || continue
  if exempt "$name"; then
    [ "$ALL" = 1 ] && skip "mbm-$name (kept as published in btvpn-multivpn)"
    continue
  fi
  conventions "$name"
done

# ---------------------------------------------------------------- command tests

echo "Commands (tests/commands/<name>.sh)"
for f in "$BIN"/mbm-*; do
  name="${f##*/mbm-}"
  wanted "$name" || continue
  exempt "$name" && continue
  t="$ROOT/tests/commands/$name.sh"
  if [ ! -r "$t" ]; then
    bad "mbm-$name: no test file"
    continue
  fi
  out="$(limited 300 "$RUN_BASH" "$t" 2>&1)"
  rc=$?
  last="$(printf '%s\n' "$out" | tail -n 1)"
  if [ "$rc" = 0 ]; then
    ok "mbm-$name: $last"
  else
    bad "mbm-$name: $last (exit $rc)"
  fi
  if [ "$VERBOSE" = 1 ]; then
    printf '%s\n' "$out" | sed 's/^/      /'
  elif [ "$rc" != 0 ]; then
    printf '%s\n' "$out" | grep -E '^ *FAIL' | sed 's/^/      /'
  fi
done

if [ "$ALL" = 0 ]; then
  echo
  finish
  exit
fi

# ---------------------------------------------------------------- installer

echo "Installer (throw-away HOME, defaults)"
FAKE="$TMP/fakehome"
mkdir -p "$FAKE"
printf '# my own line\n' > "$FAKE/.zshrc"
run_install() { HOME="$FAKE" PATH="/usr/bin:/bin:/usr/sbin:/sbin" "$ROOT/install.sh" "$@" 2>&1 </dev/null; }
out="$(run_install --yes)"; rc=$?
check "install exits 0" "0" "$rc"
check "one link per command" "$(ls "$BIN" "$ROOT/local/bin" 2>/dev/null | grep -c '^mbm-')" "$(find "$FAKE/.mbmscripts/bin" -type l | wc -l | tr -d ' ')"
check "from a checkout the links point at the checkout" "$BIN/mbm-help" "$(readlink "$FAKE/.mbmscripts/bin/mbm-help")"
check "~/.zshrc keeps its own content" "# my own line" "$(head -n 1 "$FAKE/.zshrc")"
check "the block is in ~/.zshrc once" "1" "$(grep -c '^# >>> mbmscripts >>>' "$FAKE/.zshrc")"
check "the block is in ~/.bashrc once" "1" "$(grep -c '^# >>> mbmscripts >>>' "$FAKE/.bashrc")"
check "a login bash is covered (no profile existed, one was made)" "1" "$(grep -c '^# >>> mbmscripts >>>' "$FAKE/.bash_profile")"
check "the changed ~/.zshrc was copied first" "1" "$(find "$FAKE" -maxdepth 1 -name '.zshrc.bak-mbmscripts-*' | wc -l | tr -d ' ')"
run_install --yes >/dev/null
check "a second run adds no second block" "1" "$(grep -c '^# >>> mbmscripts >>>' "$FAKE/.zshrc")"
check "bash finds the command" "$FAKE/.mbmscripts/bin/mbm-help" \
  "$(HOME="$FAKE" PATH="/usr/bin:/bin" bash -c '. "$HOME/.bashrc"; command -v mbm-help')"
check "a login bash finds the command" "$FAKE/.mbmscripts/bin/mbm-help" \
  "$(HOME="$FAKE" PATH="/usr/bin:/bin" bash -lc 'command -v mbm-help' 2>/dev/null)"
if command -v zsh >/dev/null 2>&1; then
  check "zsh finds the command" "$FAKE/.mbmscripts/bin/mbm-help" \
    "$(HOME="$FAKE" PATH="/usr/bin:/bin" zsh -c '. "$HOME/.zshrc"; command -v mbm-help')"
fi
check "loading env.sh twice adds the folder once" "1" \
  "$(HOME="$FAKE" PATH="/usr/bin:/bin" bash -c '. "$HOME/.mbmscripts/env.sh"; . "$HOME/.mbmscripts/env.sh"; echo "$PATH" | tr ":" "\n" | grep -c mbmscripts')"
check "the folder goes to the end of the PATH" "$FAKE/.mbmscripts/bin" \
  "$(HOME="$FAKE" PATH="/usr/bin:/bin" bash -c '. "$HOME/.mbmscripts/env.sh"; echo "${PATH##*:}"')"
printf 'export MBM_TEST_VALUE=from-local-env\n' > "$FAKE/.mbmscripts/local.env"
check "local.env is loaded" "from-local-env" \
  "$(HOME="$FAKE" bash -c '. "$HOME/.mbmscripts/env.sh"; echo "$MBM_TEST_VALUE"')"
has "the help command lists the commands" "mbm-dns-flush" "$("$FAKE/.mbmscripts/bin/mbm-help")"
check "the help command filters by a word" "1" "$("$FAKE/.mbmscripts/bin/mbm-help" dns | wc -l | tr -d ' ')"

echo "Installer (custom name and prefix, copied scripts)"
out="$(run_install --name acme --prefix ax- --copy)"; rc=$?
check "install exits 0" "0" "$rc"
check "commands carry the chosen prefix" "0" "$(ls "$FAKE/.acme/bin" | grep -vc '^ax-')"
check "the links point at the copied scripts" "$FAKE/.acme/src/bin/mbm-help" "$(readlink "$FAKE/.acme/bin/ax-help")"
check "the first installation is untouched" "$BIN/mbm-help" "$(readlink "$FAKE/.mbmscripts/bin/mbm-help")"
has "help of a command shows the chosen prefix" "ax-btvpn connect" "$("$FAKE/.acme/bin/ax-btvpn" help)"
has "multivpn's help names btvpn with the chosen prefix" "ax-btvpn setup" "$("$FAKE/.acme/bin/ax-multivpn" help)"
has "the list shows the chosen prefix" "ax-dns-flush" "$("$FAKE/.acme/bin/ax-help")"
has "dns-flush help shows the chosen prefix" "ax-dns-flush - " "$("$FAKE/.acme/bin/ax-dns-flush" --help)"
out="$(BTVPN_CONF="$TMP/none.conf" BTVPN_HOST_SPLIT="" "$FAKE/.acme/bin/ax-btvpn" connect 2>&1)"
case "$out" in
  *"Run: ax-btvpn setup"*|*"not installed"*) ok "an error names the command as it was called" ;;
  *) bad "an error names the command as it was called (got: $out)" ;;
esac
run_install --name acme --prefix bx- --copy >/dev/null
check "choosing another prefix replaces the old commands" "0" "$(ls "$FAKE/.acme/bin" | grep -c '^ax-')"
out="$(run_install --name 'bad name' --yes)"; rc=$?
check "a name with a space is refused" "1" "$rc"
out="$(run_install --prefix 'a/b' --yes)"; rc=$?
check "a prefix with a slash is refused" "1" "$rc"

echo "Uninstaller"
HOME="$FAKE" "$ROOT/uninstall.sh" --name acme >/dev/null 2>&1
[ ! -e "$FAKE/.acme" ] && ok "the custom installation is gone" || bad "the custom installation is gone"
check "its block left ~/.zshrc" "0" "$(grep -c 'acme' "$FAKE/.zshrc")"
check "the other installation's block stayed" "1" "$(grep -c '^# >>> mbmscripts >>>' "$FAKE/.zshrc")"
HOME="$FAKE" "$ROOT/uninstall.sh" >/dev/null 2>&1
check "~/.zshrc is back to its own content" "# my own line" "$(cat "$FAKE/.zshrc")"
[ -e "$FAKE/.mbmscripts/local.env" ] && ok "your local.env is kept without --purge" || bad "your local.env is kept without --purge"
HOME="$FAKE" "$ROOT/uninstall.sh" --purge >/dev/null 2>&1
[ ! -e "$FAKE/.mbmscripts" ] && ok "--purge removes the rest" || bad "--purge removes the rest"

# ---------------------------------------------------------------- the VPN tools (kept as published)

echo "SMS code reader (btvpn)"
DB="$TMP/chat.db"
NOW="$(date +%s)"
# Messages stores dates as nanoseconds since 2001-01-01.
apple() { echo $(( ($1 - 978307200) * 1000000000 )); }
new_db() {
  rm -f "$DB"
  sqlite3 "$DB" "create table handle (ROWID integer primary key, id text);
    create table message (ROWID integer primary key, text text, attributedBody blob,
                          handle_id integer, is_from_me integer, date integer);
    insert into handle values (1, 'VPNCORP'), (2, 'MYBANK');"
}
# add_sms HANDLE AGE_SECONDS TEXT
add_sms() {
  sqlite3 "$DB" "insert into message (text, handle_id, is_from_me, date)
                 values ('$3', $1, 0, $(apple $((NOW - $2))));"
}
reader() { BTVPN_CHAT_DB="$DB" "$LIBEXEC/btvpn-sms-code" "$@" 2>/dev/null; }
SINCE=$((NOW - 60))
if command -v sqlite3 >/dev/null 2>&1; then
  new_db; add_sms 1 10 "Dear user@example.com, Your One-Time Password is: 450657 B043"
  check "one-time password wording" "450657" "$(reader "$SINCE")"
  new_db; add_sms 1 10 "Your verification code is 482913"
  check "number after a code word" "482913" "$(reader "$SINCE")"
  new_db; add_sms 1 10 "Call 482913 today"
  reader "$SINCE" >/dev/null; check "a lone number is not a code by default (exit 1)" "1" "$?"
  check "a lone number is a code with BTVPN_SMS_REGEX=any" "482913" "$(BTVPN_SMS_REGEX=any reader "$SINCE")"
  new_db; add_sms 2 5 "MYBANK code 111111"; add_sms 1 10 "Your One-Time Password is: 222222"
  check "sender filter skips the other sender" "222222" "$(BTVPN_SMS_FROM=vpncorp reader "$SINCE")"
  new_db; add_sms 1 600 "Your One-Time Password is: 333333"
  reader "$SINCE" >/dev/null; check "an SMS older than the login is ignored (exit 1)" "1" "$?"
  BTVPN_CHAT_DB="$TMP/missing.db" "$LIBEXEC/btvpn-sms-code" "$SINCE" >/dev/null 2>&1
  check "unreadable database (exit 3)" "3" "$?"
else
  skip "sqlite3 is not installed"
fi

echo "Route hook (multivpn, dry run)"
out="$(reason=connect TUNDEV=utun9 INTERNAL_IP4_ADDRESS=10.99.0.5 MULTIVPN_DRYRUN=1 \
       MULTIVPN_STATE="$TMP/routes.state" MULTIVPN_ROUTES="10.10.20.0/24 0.0.0.0/0 10.10.21.7/32" \
       "$LIBEXEC/multivpn-routes")"
has "adds a network route" "route -n add -net 10.10.20.0/24 -interface utun9" "$out"
has "never adds a default route" "SKIPPED=0.0.0.0/0" "$out"

echo
finish
