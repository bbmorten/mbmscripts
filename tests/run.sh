#!/bin/bash
# tests/run.sh - offline checks. Nothing here connects a VPN, uses sudo, reads your real
# Messages database, touches the Keychain or writes outside a temporary folder.
#
#   tests/run.sh
#
# Covers: syntax of every script, the descriptions list, a scan for personal values, the
# installer and uninstaller in a throw-away HOME (default and custom name + prefix, bash and
# zsh), the SMS code reader against a generated Messages database, and the route hook as a
# dry run.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin"
LIBEXEC="$ROOT/libexec"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mbmscripts-tests.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ok    $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }
# check NAME EXPECTED ACTUAL
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
# has NAME NEEDLE HAYSTACK
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1 (no '$2' in: $(printf '%s' "$3" | head -n 3))" ;; esac; }

echo "Syntax"
n=0; broken=""
for f in "$BIN"/* "$LIBEXEC"/btvpn-sms-code "$LIBEXEC"/multivpn-proxy "$LIBEXEC"/multivpn-routes \
         "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/tests/run.sh"; do
  n=$((n + 1))
  case "$(head -n 1 "$f")" in
    *zsh*) if command -v zsh >/dev/null 2>&1; then zsh -n "$f" 2>/dev/null || broken="$broken ${f#"$ROOT"/}"; fi ;;
    *) bash -n "$f" 2>/dev/null || broken="$broken ${f#"$ROOT"/}" ;;
  esac
done
if [ -z "$broken" ]; then ok "$n scripts parse (bash -n / zsh -n, by their first line)"; else bad "do not parse:$broken"; fi
for f in "$BIN"/*; do [ -x "$f" ] || broken="$broken ${f##*/}"; done
if [ -z "$broken" ]; then ok "every command is executable"; else bad "not executable:$broken"; fi

echo "Descriptions"
check "every command has one description, and the reverse" "" \
  "$(diff <(cut -f1 "$LIBEXEC/descriptions.txt" | sort) <(ls "$BIN" | sed 's/^mbm-//' | sort))"

echo "Personal values"
found="$(grep -rn -E '/Users/[A-Za-z]|/home/[a-z]+/[a-z]' "$BIN" "$LIBEXEC" "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/README.md" \
          | grep -v -E '/home/vm/docker' )"
check "no home-folder path of a real person in the published files" "" "$found"

echo "Installer (throw-away HOME, defaults)"
FAKE="$TMP/home"
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
  echo "  skip  sqlite3 is not installed"
fi

echo "Route hook (multivpn, dry run)"
out="$(reason=connect TUNDEV=utun9 INTERNAL_IP4_ADDRESS=10.99.0.5 MULTIVPN_DRYRUN=1 \
       MULTIVPN_STATE="$TMP/routes.state" MULTIVPN_ROUTES="10.10.20.0/24 0.0.0.0/0 10.10.21.7/32" \
       "$LIBEXEC/multivpn-routes")"
has "adds a network route" "route -n add -net 10.10.20.0/24 -interface utun9" "$out"
has "never adds a default route" "SKIPPED=0.0.0.0/0" "$out"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
