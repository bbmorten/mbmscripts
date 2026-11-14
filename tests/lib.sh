# tests/lib.sh - shared helpers for tests/run.sh and the test files in tests/commands/.
#
# Source it; never run it. A test file starts with
#     . "$(dirname "$0")/../lib.sh"
# and ends with
#     finish
#
# Sourcing it puts the test inside a sandbox, so that a test can never touch the real machine:
#   HOME     an empty temporary folder, $TMP/home
#   PATH     $STUBS (fake programs), then $SYS: links to the programs of the system folders,
#            WITHOUT the ones that reach outside the sandbox. Those exist only as guards.
#   TMPDIR   a folder inside the sandbox
#   MBM_*    every such variable is removed from the environment
#   guards   programs that reach outside the sandbox (ssh, rsync, sudo, docker, ...) are
#            replaced by fakes that fail, and `finish` fails the test when one was called.
#            A test that needs such a program defines its own fake with `stub`.
#            Removing a fake ("rm -f $STUBS/sudo") makes the program NOT INSTALLED: the real
#            one is not on the sandbox PATH. A script that names a program by its full path
#            (/usr/bin/sudo) escapes all of this; tests/run.sh refuses such scripts.
#
# Variables for tests:  ROOT  BIN  LIBEXEC  TMP  STUBS  STUB_LOG   and, after `run`:  OUT ERR RC
# Functions:            ok bad skip check has hasnt run run_in tty_run stub guard real calls
#                       reset_calls finish
#
# Bash 3.2 compatible (the macOS /bin/bash).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/bin"
LIBEXEC="$ROOT/libexec"

_t="${TMPDIR:-/tmp}"
TMP="$(mktemp -d "${_t%/}/mbm-test.XXXXXX")" || exit 1
# The physical path, so that a test can compare it with what `pwd -P` or a program prints.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
STUBS="$TMP/stubs"
STUB_LOG="$TMP/stub.log"
mkdir -p "$STUBS" "$TMP/home"
: > "$STUB_LOG"
export STUB_LOG

# The PATH of the person running the tests, kept for `real`. A test file started by
# tests/run.sh inherits the sandbox PATH, so the original travels in a variable.
REAL_PATH="${TESTS_REAL_PATH:-$PATH}"
export TESTS_REAL_PATH="$REAL_PATH"

for _v in $(env | sed -n 's/^\(MBM_[A-Za-z0-9_]*\)=.*/\1/p; s/^\(BTVPN_[A-Za-z0-9_]*\)=.*/\1/p; s/^\(MULTIVPN_[A-Za-z0-9_]*\)=.*/\1/p'); do
  unset "$_v"
done
unset CDPATH BASH_ENV ENV NO_COLOR
export HOME="$TMP/home"

# Programs that reach outside the sandbox or change the machine. They are never on the
# sandbox PATH for real: the first list gets a guard (below), the second is simply absent.
GUARDED="ssh scp sftp rsync sudo su curl wget hdiutil diskutil open osascript killall pkill \
launchctl security dscacheutil ifconfig networksetup script docker podman ollama limactl npm npx \
tshark dumpcap fswatch inotifywait mkdocs brew"
ABSENT="shutdown reboot halt crontab at batch passwd chsh chfn login defaults pmset systemsetup \
scutil pfctl mount umount nvram softwareupdate tmutil mail sendmail ssh-add ssh-keygen \
ssh-copy-id screen tmux telnet ftp nc ncat apt apt-get dnf yum pip pip3 systemctl service \
ip nmcli iptables nft"

SYS="$TMP/sys"
mkdir -p "$SYS" "$TMP/tmp"
for _d in /sbin /usr/sbin /bin /usr/bin; do
  [ -d "$_d" ] && ln -sf "$_d"/* "$SYS"/ 2>/dev/null
done
for _n in $GUARDED $ABSENT; do rm -f "$SYS/$_n"; done
export PATH="$STUBS:$SYS"
export TMPDIR="$TMP/tmp"

pass=0
fail=0
OUT=""
ERR=""
RC=0

ok()   { pass=$((pass + 1)); echo "  ok    $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL  $1"; }
skip() { echo "  skip  $1"; }

# check NAME EXPECTED ACTUAL
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
# has NAME NEEDLE HAYSTACK      hasnt NAME NEEDLE HAYSTACK
has()   { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1 (no '$2' in: $(printf '%s' "$3" | head -n 3))" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1 (found '$2')" ;; *) ok "$1" ;; esac; }

# run CMD [ARG...] - run it with nothing on standard input.
# Sets OUT (standard output), ERR (standard error) and RC (exit status).
run() {
  OUT="$("$@" 2>"$TMP/stderr" </dev/null)"
  RC=$?
  ERR="$(cat "$TMP/stderr")"
}

# run_in TEXT CMD [ARG...] - the same, with TEXT on standard input (a pipe, not a terminal).
run_in() {
  local text="$1"
  shift
  OUT="$(printf '%s' "$text" | "$@" 2>"$TMP/stderr")"
  RC=$?
  ERR="$(cat "$TMP/stderr")"
}

# tty_run ANSWERS CMD [ARG...] - run it on a pseudo-terminal, as a person would, typing
# ANSWERS (one answer per line; "" types nothing). Each answer is typed when the output ends
# in something that looks like a prompt (? : ] or >), or after 5 seconds. Sets OUT (everything
# the terminal showed, typed answers included) and RC (the exit status of CMD). Returns 1
# without running anything when `expect` is not installed, so write:
#     if tty_run "y" "$CMD" ...; then check ...; else skip "expect is not installed"; fi
tty_run() {
  local answers="$1" exp
  shift
  exp="$(export PATH="$REAL_PATH"; command -v expect 2>/dev/null)" || return 1
  cat > "$TMP/tty.exp" <<'EOF_TTY_EXP'
set timeout 30
set answers [split [lindex $argv 0] "\n"]
spawn -noecho {*}[lrange $argv 1 end]
foreach a $answers {
    if {$a eq ""} { continue }
    expect {
        -timeout 5 -re {[]?:>] ?$} {}
        timeout {}
        eof { break }
    }
    send -- "$a\r"
}
expect {
    eof {}
    timeout { catch {exec kill [exp_pid]}; catch {close}; catch wait; exit 124 }
}
catch wait result
exit [lindex $result 3]
EOF_TTY_EXP
  "$exp" -f "$TMP/tty.exp" -- "$answers" "$@" > "$TMP/tty.out" 2>&1
  RC=$?
  OUT="$(tr -d '\r' < "$TMP/tty.out")"
  ERR=""
  return 0
}

# stub NAME [BODY] - a fake program NAME, first on the PATH. Each call is written to
# $STUB_LOG as one line: NAME followed by its arguments, separated by single spaces.
# BODY is shell code run after that, with the arguments in "$@" (default: succeed silently).
stub() {
  local name="$1" body="${2:-exit 0}"
  rm -f "$STUBS/$name"
  {
    echo '#!/bin/bash'
    echo "{ printf '%s' '$name'; for _a in \"\$@\"; do printf ' %s' \"\$_a\"; done; echo; } >> \"\$STUB_LOG\""
    printf '%s\n' "$body"
  } > "$STUBS/$name"
  chmod +x "$STUBS/$name"
}

# guard NAME... - NAME must not run for real. A call is logged as "GUARD NAME ..." and fails.
guard() {
  local n
  for n in "$@"; do
    rm -f "$STUBS/$n"
    {
      echo '#!/bin/bash'
      echo "echo \"GUARD $n \$*\" >> \"\$STUB_LOG\""
      echo "echo \"test sandbox: $n must not run for real; define a stub\" >&2"
      echo 'exit 97'
    } > "$STUBS/$n"
    chmod +x "$STUBS/$n"
  done
}

# real NAME - let the real program NAME be used inside the sandbox (looked up on the PATH of
# the person running the tests). False when it is not installed:
#     real tshark || { skip "tshark is not installed"; finish; exit; }
real() {
  local p
  p="$(export PATH="$REAL_PATH"; command -v "$1" 2>/dev/null)" || return 1
  case "$p" in /*) ;; *) return 1 ;; esac
  rm -f "$STUBS/$1"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$p" > "$STUBS/$1"
  chmod +x "$STUBS/$1"
}

# calls [NAME] - the calls logged so far: all of them, or those of one program.
calls() {
  if [ $# -eq 0 ]; then cat "$STUB_LOG"; else grep -E "^(GUARD )?$1( |\$)" "$STUB_LOG"; fi
}
# reset_calls - forget the calls logged so far (a guard that fired is still reported).
reset_calls() {
  grep '^GUARD ' "$STUB_LOG" >> "$TMP/guard.log" 2>/dev/null
  : > "$STUB_LOG"
}

# finish - the last line of a test file: the totals, and the exit status of the file.
finish() {
  local fired
  fired="$(cat "$TMP/guard.log" 2>/dev/null; grep '^GUARD ' "$STUB_LOG" 2>/dev/null)"
  if [ -n "$fired" ]; then
    bad "a program that must not run for real was called: $(printf '%s' "$fired" | head -n 3 | tr '\n' ';')"
  fi
  echo "$pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

# Everything that reaches outside the sandbox gets a guard. `stub NAME` replaces a guard,
# `real NAME` allows the real program, `rm -f "$STUBS/NAME"` makes it "not installed".
# shellcheck disable=SC2086  # a list of names, split on purpose
guard $GUARDED
