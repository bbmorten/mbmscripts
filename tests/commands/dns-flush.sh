#!/bin/bash
# Tests for mbm-dns-flush.   Run:  tests/run.sh dns-flush    or:  bash tests/commands/dns-flush.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-dns-flush"
echo "mbm-dns-flush"

# sudo, pgrep, sleep and uname are fakes: nothing here flushes a cache or stops a service.
# The fake DNS service: pid 111 until "sudo killall mDNSResponder" ran, then pid 222.
#   OLD_PID=    the service was not running before        SLOW=N     it is back at the Nth look
#   STUCK=1     killall does not stop it (pid stays 111)  GONE=1     it never comes back
#   FAIL_FLUSH=1 / FAIL_KILL=1   that sudo step fails
export TMP
stub uname 'echo Darwin'
stub sleep 'exit 0'
stub sudo 'case "$*" in
  "dscacheutil -flushcache") if [ "${FAIL_FLUSH:-}" = 1 ]; then echo "sudo: 3 incorrect password attempts" >&2; exit 1; fi ;;
  "killall mDNSResponder") if [ "${FAIL_KILL:-}" = 1 ]; then echo "No matching processes were found" >&2; exit 1; fi
     : > "$TMP/killed" ;;
  *) echo "fake sudo: unexpected command: $*" >&2; exit 64 ;;
esac
exit 0'
stub pgrep '[ "$*" = "-x mDNSResponder" ] || { echo "fake pgrep: unexpected arguments: $*" >&2; exit 2; }
if [ ! -e "$TMP/killed" ]; then
  [ -n "${OLD_PID-111}" ] && echo "${OLD_PID-111}"
  exit 0
fi
[ "${STUCK:-}" = 1 ] && { echo 111; exit 0; }
[ "${GONE:-}" = 1 ] && exit 1
echo x >> "$TMP/looks"
[ "$(wc -l < "$TMP/looks")" -ge "${SLOW:-1}" ] && echo 222
exit 0'
fresh() { rm -f "$TMP/killed" "$TMP/looks"; reset_calls; }

echo " the job"
fresh
run "$CMD"
check "exit 0" "0" "$RC"
check "it says what happened, with the old and the new process number" \
  "DNS cache flushed and the DNS service restarted (mDNSResponder pid 111 -> 222)." "$OUT"
check "nothing on standard error" "" "$ERR"
check "exactly the two commands, in that order" "sudo dscacheutil -flushcache;sudo killall mDNSResponder;" "$(calls sudo | tr '\n' ';')"
check "the old process number is read before the flush" "pgrep -x mDNSResponder" "$(calls | sed -n 2p)"
check "back at the first look: no waiting" "" "$(calls sleep)"
fresh
run "$CMD" --
check "-- ends the options: exit 0" "0" "$RC"
fresh
SLOW=3 run "$CMD"
check "the service is back at the third look: exit 0" "0" "$RC"
check "... after waiting twice half a second" "sleep 0.5;sleep 0.5;" "$(calls sleep | tr '\n' ';')"
fresh
OLD_PID="" run "$CMD"
check "the service was not running before: exit 0" "0" "$RC"
has "... the message says none" "pid none -> 222" "$OUT"

echo " when it does not work"
fresh
STUCK=1 run "$CMD"
check "the service keeps its process number: exit 1" "1" "$RC"
has "... the message" "the DNS service was not restarted within 10 seconds (mDNSResponder pid is still 111)" "$ERR"
check "... nothing on standard output" "" "$OUT"
check "... it looked 20 times, half a second apart" "20" "$(calls sleep | grep -c '^sleep 0.5$')"
fresh
GONE=1 run "$CMD"
check "the service never comes back: exit 1" "1" "$RC"
has "... the message" "pid is still none" "$ERR"
fresh
FAIL_FLUSH=1 run "$CMD"
check "the flush fails: exit 1" "1" "$RC"
has "... the message names the step" "this failed: sudo dscacheutil -flushcache" "$ERR"
hasnt "... and only that step" "killall mDNSResponder" "$(printf '%s\n' "$ERR" | grep 'this failed')"
check "... the second command still ran, as in the one-line form" "sudo killall mDNSResponder" "$(calls sudo | sed -n 2p)"
check "... it does not wait for a restart" "" "$(calls sleep)"
hasnt "... and does not claim success" "flushed and" "$OUT"
fresh
FAIL_KILL=1 run "$CMD"
check "killall fails: exit 1" "1" "$RC"
has "... the message names the step" "this failed: sudo killall mDNSResponder" "$ERR"
check "... it does not wait for a restart" "" "$(calls sleep)"
fresh
FAIL_FLUSH=1 FAIL_KILL=1 run "$CMD"
has "both fail: the message names both" "this failed: sudo dscacheutil -flushcache and sudo killall mDNSResponder" "$ERR"

echo " wrong use"
fresh
run "$CMD" --now
check "an unknown option: exit 2 (the old version flushed anyway)" "2" "$RC"
has "... the message points to the help" "--help" "$ERR"
run "$CMD" now
check "an argument: exit 2" "2" "$RC"
run "$CMD" -- now
check "an argument after --: exit 2" "2" "$RC"
check "wrong use runs nothing" "" "$(calls)"
run "$CMD" --help
check "--help: exit 0" "0" "$RC"
has "--help shows the command line it runs" "sudo dscacheutil -flushcache; sudo killall mDNSResponder" "$OUT"
check "--help runs nothing" "" "$(calls)"

echo " another system"
fresh
stub uname 'echo Linux'
run "$CMD"
check "on Linux: exit 1" "1" "$RC"
has "... it says it is for macOS" "this command is for macOS" "$ERR"
check "... and runs nothing else" "uname -s" "$(calls | tr '\n' ' ' | sed 's/ $//')"

finish
