#!/bin/bash
# Tests for mbm-interface-test.   Run:  tests/run.sh interface-test    or:  bash tests/commands/interface-test.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-interface-test"
echo "mbm-interface-test"

# Everything that touches an interface is a fake here: ip, ifconfig, sudo, id, sleep.
# FAKE_ROOT=1 makes "id -u" answer 0; the fake sudo sets it and runs the command.
# FAIL_DOWN=1 / FAIL_UP=1 make the fake ip and ifconfig refuse that change.
export TMP
stub uname 'echo Linux'
stub id 'if [ "${FAKE_ROOT:-}" = 1 ]; then echo 0; else echo 501; fi'
# The fake sudo does what the real one does for this command: it runs it, as "root", and
# names it in SUDO_COMMAND. It gives up after 20 calls, so that a mistake cannot loop.
fake_sudo() {
  stub sudo '[ "$(grep -c "^sudo " "$STUB_LOG")" -le 20 ] || { echo "fake sudo: called too often" >&2; exit 97; }
while [ $# -gt 0 ]; do
  case "$1" in -u) shift 2 ;; --) shift; break ;; *) break ;; esac
done
export SUDO_COMMAND="$*" '"$1"'
exec "$@"'
}
fake_sudo FAKE_ROOT=1
stub sleep 'exit 0'
stub ip 'case "$*" in
  "link show dev eth0"|"link show dev ens160") echo "2: $4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP mode DEFAULT" ;;
  "link show dev dummy0") echo "3: dummy0: <BROADCAST,NOARP> mtu 1500 qdisc noop state DOWN mode DEFAULT" ;;
  "link show dev "*) echo "Device \"$4\" does not exist." >&2; exit 1 ;;
  "link set dev "*" down") [ "${FAIL_DOWN:-}" = 1 ] && { echo "RTNETLINK answers: Operation not permitted" >&2; exit 2; }; exit 0 ;;
  "link set dev "*" up") [ "${FAIL_UP:-}" = 1 ] && { echo "RTNETLINK answers: Operation not permitted" >&2; exit 2; }; exit 0 ;;
  *) echo "ip: unexpected arguments: $*" >&2; exit 1 ;;
esac'
stub ifconfig 'case "$*" in
  en0|eth0) echo "$1: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500" ;;
  en5) echo "en5: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500" ;;
  "en0 down"|"en0 up"|"eth0 down"|"eth0 up") exit 0 ;;
  *) echo "ifconfig: interface $1 does not exist" >&2; exit 1 ;;
esac'

# What was changed, in order: the "set" calls and the sleep, on one line.
changes() { calls | grep -E '^(ip link set|ifconfig [a-z0-9]+ (down|up)|sleep)' | tr '\n' ';'; }

echo " wrong use"
run "$CMD"
check "no interface: exit 2" "2" "$RC"
has "... the message points to the help" "--help" "$ERR"
run "$CMD" eth0 ens160
check "two interfaces: exit 2" "2" "$RC"
run "$CMD" -t
check "-t without a value: exit 2" "2" "$RC"
run "$CMD" -t soon eth0
check "-t with a word: exit 2" "2" "$RC"
run "$CMD" -t 0 eth0
check "-t 0: exit 2" "2" "$RC"
run "$CMD" -t 1.5 eth0
check "-t 1.5: exit 2" "2" "$RC"
run "$CMD" --fast eth0
check "an unknown option: exit 2" "2" "$RC"
check "wrong use runs nothing" "" "$(calls)"
run "$CMD" --help
check "--help: exit 0" "0" "$RC"
check "--help runs nothing (the old version took ens160 down)" "" "$(calls)"

echo " an interface that cannot be tested"
run "$CMD" --yes nope0
check "an interface that does not exist: exit 1" "1" "$RC"
has "... the message names it and says how to list them" "no such interface: nope0 (to list them: ip -br link)" "$ERR"
run "$CMD" --yes dummy0
check "an interface that is down already: exit 1" "1" "$RC"
has "... the message" "dummy0 is down already" "$ERR"
run "$CMD" --yes -- -a
check "a name that looks like an option: exit 1" "1" "$RC"
run "$CMD" --yes 'eth0 down; reboot'
check "a name with other characters: exit 1" "1" "$RC"
has "... the message" "not an interface name" "$ERR"
check "nothing was changed and sudo was not asked" "" "$(changes)$(calls sudo)"

echo " dry run"
reset_calls
run "$CMD" -n eth0
check "-n: exit 0" "0" "$RC"
check "-n: the three commands" "sudo ip link set dev eth0 down|sleep 60|sudo ip link set dev eth0 up|" "$(printf '%s\n' "$OUT" | awk 'NR > 1 { sub(/^ +/, ""); printf "%s|", $0 }')"
check "-n: nothing was changed and sudo was not asked" "" "$(changes)$(calls sudo)"
run "$CMD" --dry-run -t 5 ens160
has "--dry-run -t 5: the time and the interface" "sleep 5" "$OUT"
has "--dry-run names the interface" "ip link set dev ens160 down" "$OUT"
FAKE_ROOT=1 run "$CMD" -n eth0
hasnt "-n as root: no sudo in the commands" "sudo" "$OUT"
run "$CMD" -n nope0
check "-n with an interface that does not exist: exit 1" "1" "$RC"

echo " asking first"
reset_calls
run "$CMD" eth0
check "not a terminal, no --yes: exit 1" "1" "$RC"
has "... it says why and how to go ahead" "Add --yes" "$ERR"
check "... nothing was changed and sudo was not asked" "" "$(changes)$(calls sudo)"
# On a terminal. (Not tty_run of lib.sh: it waits 5 seconds for each answer and does not
# pass on the exit status of the command.)   answer TEXT CMD [ARG...]  sets OUT and RC.
EXPECT="$(export PATH="$REAL_PATH"; command -v expect 2>/dev/null)"
cat > "$TMP/answer.exp" <<'EOF_ANSWER'
set timeout 20
set text [lindex $argv 0]
spawn -noecho {*}[lrange $argv 1 end]
expect {
    -ex {[y/N] } { send -- "$text\r" }
    timeout { exit 98 }
    eof { exit 99 }
}
expect eof
catch wait result
exit [lindex $result 3]
EOF_ANSWER
answer() {
  "$EXPECT" -f "$TMP/answer.exp" -- "$@" > "$TMP/answer.out" 2>&1
  RC=$?
  OUT="$(tr -d '\r' < "$TMP/answer.out")"
}
if [ -n "$EXPECT" ]; then
  answer "n" "$CMD" eth0
  check "answer n: exit 1" "1" "$RC"
  has "answer n: the question names the interface and the time" "Take eth0 down for 60 seconds?" "$OUT"
  has "answer n: it says nothing was done" "nothing done" "$OUT"
  check "answer n: nothing was changed and sudo was not asked" "" "$(changes)$(calls sudo)"
  answer "" "$CMD" eth0
  check "just Enter: exit 1, nothing was changed" "1:" "$RC:$(changes)"
  reset_calls
  answer "y" "$CMD" -t 3 eth0
  check "answer y: exit 0" "0" "$RC"
  check "answer y: down, wait, up" "ip link set dev eth0 down;sleep 3;ip link set dev eth0 up;" "$(changes)"
  has "answer y: it says the interface is back" "eth0 is up again." "$OUT"
else
  skip "expect is not installed: the question on a terminal is not tested"
fi

echo " the job"
reset_calls
run "$CMD" --yes eth0
check "--yes: exit 0" "0" "$RC"
check "down, 60 seconds, up - in that order" "ip link set dev eth0 down;sleep 60;ip link set dev eth0 up;" "$(changes)"
check "not root: one sudo, running the command itself for the whole job" "sudo -u root -- $CMD --yes --time 60 -- eth0" "$(calls sudo)"
has "it says the interface is back" "eth0 is up again." "$OUT"
reset_calls
run "$CMD" -y -t 5 ens160
check "-y -t 5 ens160" "ip link set dev ens160 down;sleep 5;ip link set dev ens160 up;" "$(changes)"
reset_calls
run "$CMD" --time 7 --yes eth0
check "--time 7" "ip link set dev eth0 down;sleep 7;ip link set dev eth0 up;" "$(changes)"
reset_calls
FAKE_ROOT=1 run "$CMD" -y -t 2 eth0
check "as root: the same job" "ip link set dev eth0 down;sleep 2;ip link set dev eth0 up;" "$(changes)"
check "as root: no sudo" "" "$(calls sudo)"
reset_calls
mkdir -p "$TMP/zz"
ln -s "$CMD" "$TMP/zz/zz-interface-test"
run "$TMP/zz/zz-interface-test" -y -t 2 eth0
check "under another prefix sudo runs the command by the name it was called" "sudo -u root -- $TMP/zz/zz-interface-test --yes --time 2 -- eth0" "$(calls sudo)"
reset_calls
OUT="$(cd "$BIN" && /bin/bash mbm-interface-test -y -t 2 eth0 2>&1)"
check "started without a folder in its name, sudo still gets a path" "sudo -u root -- ./mbm-interface-test --yes --time 2 -- eth0" "$(calls sudo)"

echo " when a step fails"
reset_calls
FAIL_DOWN=1 run "$CMD" -y eth0
check "down refused: exit 1" "1" "$RC"
has "down refused: the message" "could not take eth0 down" "$ERR"
check "down refused: no wait and no up" "ip link set dev eth0 down;" "$(changes)"
reset_calls
FAIL_UP=1 run "$CMD" -y eth0
check "up refused: exit 1" "1" "$RC"
has "up refused: the message gives the command to run by hand" "could not bring eth0 up again. Run: ip link set dev eth0 up" "$ERR"
hasnt "up refused: it does not claim the interface is back" "is up again" "$OUT"
# A sudo that does not make the command root must not be asked again and again.
reset_calls
fake_sudo FAKE_ROOT=0
run "$CMD" -y eth0
check "sudo does not give root: exit 1" "1" "$RC"
has "... the message" "sudo did not make this root" "$ERR"
check "... sudo was asked once, and nothing was changed" "1:" "$(calls sudo | wc -l | tr -d ' '):$(changes)"
fake_sudo FAKE_ROOT=1
# No sudo at all: a PATH that holds only fakes (and bash for the first line). The guard on
# sudo is never removed: without it the real /usr/bin/sudo would be found.
mkdir -p "$TMP/bare"
ln -s /bin/bash "$TMP/bare/bash"
cp "$STUBS/uname" "$STUBS/ip" "$STUBS/id" "$TMP/bare/"
reset_calls
run env PATH="$TMP/bare" "$CMD" -y eth0
check "not root and no sudo: exit 1" "1" "$RC"
has "... the message" "sudo is not installed: run it as root" "$ERR"
check "... nothing was changed" "" "$(changes)"

echo " interrupted while the interface is down (the old version left it down)"
# The fake sleep really waits here, and writes its process number down.
stub sleep 'echo $$ > "$TMP/sleep.pid"; exec /bin/sleep 30'
# wait_for PATTERN - until the fake programs have logged a line like PATTERN (5 seconds at most)
wait_for() {
  local i=0
  while [ "$i" -lt 50 ]; do
    grep -q -- "$1" "$STUB_LOG" 2>/dev/null && [ -s "$TMP/sleep.pid" ] && return 0
    /bin/sleep 0.1
    i=$((i + 1))
  done
  return 1
}
for sig in TERM HUP; do
  reset_calls
  rm -f "$TMP/sleep.pid"
  FAKE_ROOT=1 "$CMD" -y -t 30 eth0 > "$TMP/sig.out" 2>&1 </dev/null &
  pid=$!
  if wait_for '^sleep 30'; then
    kill "-$sig" "$pid"
    wait "$pid"
    rc=$?
    case "$sig" in TERM) want=143 ;; HUP) want=129 ;; esac
    check "$sig: exit $want" "$want" "$rc"
    check "$sig: the interface is brought up at once" "ip link set dev eth0 down;sleep 30;ip link set dev eth0 up;" "$(changes)"
    has "$sig: it says so" "eth0 is up again." "$(cat "$TMP/sig.out")"
    if kill -0 "$(cat "$TMP/sleep.pid")" 2>/dev/null; then
      bad "$sig: the waiting sleep is gone"
      kill "$(cat "$TMP/sleep.pid")" 2>/dev/null
    else
      ok "$sig: the waiting sleep is gone"
    fi
  else
    bad "$sig: the command did not reach the wait"
    kill "$pid" 2>/dev/null
  fi
done

# The reader of its output goes away (a pipe into a program that ended).
stub sleep 'exit 0'
reset_calls
FAKE_ROOT=1 "$CMD" -y -t 2 eth0 2>/dev/null | :
check "its output is a closed pipe: it stops there, and the interface still comes up" "ip link set dev eth0 down;ip link set dev eth0 up;" "$(changes)"
stub sleep 'echo $$ > "$TMP/sleep.pid"; exec /bin/sleep 30'

# Ctrl-C needs a terminal: a command started in the background ignores the INT signal.
if [ -n "$EXPECT" ]; then
  reset_calls
  rm -f "$TMP/sleep.pid"
  cat > "$TMP/ctrl-c.exp" <<'EOF_CTRL_C'
set timeout 20
spawn -noecho {*}$argv
expect {
    "is down for" { after 300; send "\003" }
    timeout { exit 98 }
    eof { exit 99 }
}
expect eof
catch wait result
exit [lindex $result 3]
EOF_CTRL_C
  FAKE_ROOT=1 "$EXPECT" -f "$TMP/ctrl-c.exp" -- "$CMD" -y -t 30 eth0 > "$TMP/ctrl-c.out" 2>&1
  RC=$?
  OUT="$(tr -d '\r' < "$TMP/ctrl-c.out")"
  check "Ctrl-C: exit 130" "130" "$RC"
  check "Ctrl-C: the interface is brought up at once" "ip link set dev eth0 down;sleep 30;ip link set dev eth0 up;" "$(changes)"
  has "Ctrl-C: it says so" "eth0 is up again." "$OUT"
  if kill -0 "$(cat "$TMP/sleep.pid" 2>/dev/null)" 2>/dev/null; then
    bad "Ctrl-C: the waiting sleep is gone"
    kill "$(cat "$TMP/sleep.pid")" 2>/dev/null
  else
    ok "Ctrl-C: the waiting sleep is gone"
  fi
else
  skip "expect is not installed: Ctrl-C is not tested"
fi
stub sleep 'exit 0'

echo " macOS, and Linux without ip"
stub uname 'echo Darwin'
reset_calls
run "$CMD" -y -t 4 en0
check "macOS: exit 0" "0" "$RC"
check "macOS: ifconfig down, wait, up" "ifconfig en0 down;sleep 4;ifconfig en0 up;" "$(changes)"
check "macOS: ip is not used" "" "$(calls ip)"
run "$CMD" -n en0
has "macOS -n: the commands" "sudo ifconfig en0 down" "$OUT"
run "$CMD" -y en5
check "macOS: an interface that is down already: exit 1" "1" "$RC"
run "$CMD" -y en9
check "macOS: an interface that does not exist: exit 1" "1" "$RC"
has "... and how to list them" "ifconfig -l" "$ERR"

stub uname 'echo Linux'
rm -f "$STUBS/ip"
if command -v ip >/dev/null 2>&1; then
  skip "this machine has a real ip: the ifconfig fallback is not tested"
else
  reset_calls
  run "$CMD" -y -t 4 eth0
  check "Linux without ip: ifconfig down, wait, up" "ifconfig eth0 down;sleep 4;ifconfig eth0 up;" "$(changes)"
  # Neither ip nor ifconfig: the PATH with only fakes again, this time without ip.
  rm -f "$TMP/bare/ip"
  run env PATH="$TMP/bare" "$CMD" -y eth0
  check "Linux with neither ip nor ifconfig: exit 1" "1" "$RC"
  has "... and how to get one" "install the iproute2 package" "$ERR"
fi
stub uname 'echo FreeBSD'
run "$CMD" -y eth0
check "another system: exit 1" "1" "$RC"
has "... the message" "works on Linux and macOS" "$ERR"

finish
