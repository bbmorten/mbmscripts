#!/bin/bash
# Tests for mbm-sslkeylog-capture.   Run:  tests/run.sh sslkeylog-capture    or:  bash tests/commands/sslkeylog-capture.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-sslkeylog-capture"
echo "mbm-sslkeylog-capture"

# Nothing here starts a real browser or a real capture. From this line on both browser
# settings point into the sandbox, and tshark, pgrep, pkill, route and ip are fakes. Never
# run the command in a test with these two settings unset: it would find the real browser.
FAKES="$TMP/Fake Apps"
export MBM_SSLKEYLOG_CHROME="$FAKES/chrome bin"
export MBM_SSLKEYLOG_FIREFOX="$FAKES/firefox"
export SBX="$TMP"
mkdir -p "$FAKES" "$TMP/work"
cd "$TMP/work" || exit 1

# fake PATH BODY - like stub, for a program that is not on the PATH.
fake() {
  {
    echo '#!/bin/bash'
    echo "{ printf '%s' '${1##*/}'; for _a in \"\$@\"; do printf ' %s' \"\$_a\"; done; echo; } >> \"\$STUB_LOG\""
    printf '%s\n' "$2"
  } > "$1"
  chmod +x "$1"
}
# Every fake that waits gives up by itself after 20 seconds, so that a failing test leaves
# nothing running.
WAIT='i=0; while [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done'
# A capture that runs until it is told to stop, as tshark does.
TSHARK_RUNS='out=""; while [ $# -gt 0 ]; do [ "$1" = "-w" ] && out="$2"; shift; done
echo $$ > "$SBX/tshark.pid"
echo "Capturing on fake" >&2
printf PCAPNG > "$out"
trap "exit 0" TERM INT
'"$WAIT"
# A browser that writes one key line and runs until it is told to stop.
BROWSER_RUNS='echo "env SSLKEYLOGFILE=${SSLKEYLOGFILE:-unset}" >> "$STUB_LOG"
echo $$ > "$SBX/browser.pid"
echo "CLIENT_RANDOM 00 11" >> "$SSLKEYLOGFILE"
trap "echo browser-asked-to-end >> \"\$STUB_LOG\"; exit 0" TERM
'"$WAIT"
# A browser that its user closes after a moment.
BROWSER_IS_CLOSED='echo "CLIENT_RANDOM 00 11" >> "$SSLKEYLOGFILE"; sleep 0.7; exit 0'

fresh() {   # the fakes of an ordinary session, and an empty call log
  stub tshark "$TSHARK_RUNS"
  fake "$MBM_SSLKEYLOG_CHROME" "$BROWSER_RUNS"
  fake "$MBM_SSLKEYLOG_FIREFOX" "$BROWSER_RUNS"
  stub pgrep 'exit 1'
  stub pkill 'exit 1'
  stub route 'echo "   interface: en7"'
  stub ip 'exit 1'
  rm -f "$TMP/tshark.pid" "$TMP/browser.pid" "$TMP/tshark.dead"
  reset_calls
}
gone() { ! kill -0 "$(cat "$1" 2>/dev/null)" 2>/dev/null; }    # gone PIDFILE
mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
one() { ls "$1"/$2 2>/dev/null; }                               # one DIR GLOB
# matches PATTERN TEXT - what pgrep -f and pkill -f do with a command line
matches() { printf '%s\n' "$2" | grep -E -c -- "$1"; }

# The everyday browser of the user: the same kind of program, on another profile. It must
# still run at the end (it gives up by itself after two minutes).
printf '%s\n' '#!/bin/bash' 'trap "exit 0" TERM' 'i=0; while [ "$i" -lt 240 ]; do sleep 0.5; i=$((i + 1)); done' > "$FAKES/everyday browser"
chmod +x "$FAKES/everyday browser"
"$FAKES/everyday browser" --user-data-dir="$TMP/elsewhere/chrome" &
EVERYDAY=$!

# ---- help
run "$CMD" --help
for word in "-b BROWSER" "-i INTERFACE" "-r " "-f FILTER" "-d SECONDS" "-o DIR, --output DIR" "-h, --help" \
            "MBM_SSLKEYLOG_DIR" "MBM_SSLKEYLOG_CHROME" "MBM_SSLKEYLOG_FIREFOX" "(Pre)-Master-Secret log filename" "Needs: tshark"; do
  has "help names: $word" "$word" "$OUT"
done
ln -sf "$CMD" "$TMP/zz-sslkeylog-capture"
run "$TMP/zz-sslkeylog-capture" --help
# shellcheck disable=SC2088  # the help text itself says ~/..., nothing is expanded here
has "under another prefix the default folder keeps its name" "~/.local/share/sslkeylog-capture)" "$OUT"

# ---- session 1: chrome, a named interface, a filter, stops by itself after 1 second
fresh
run "$CMD" -b chrome -i lo0 -f 'tcp port 443' -d 1
D="$HOME/.local/share/sslkeylog-capture"
KEYS="$(one "$D/logs/sslkeys" 'session-*.log')"
PCAP="$(one "$D/ldumps" 'session-*.pcapng')"
PROFILE="$D/logs/browser-profiles/chrome"
check "session: exit 0" "0" "$RC"
check "session: the keys and the capture carry the same time" "${KEYS##*/session-}" "$(basename "${PCAP##*/session-}" .pcapng).log"
check "session: tshark gets the interface, the file and the filter" "tshark -i lo0 -w $PCAP -s 0 -q -f tcp port 443" "$(calls tshark)"
check "session: chrome starts on a profile folder of its own" \
  "chrome bin --user-data-dir=$PROFILE --no-first-run --no-default-browser-check --new-window about:blank" "$(calls 'chrome bin')"
has "session: the browser gets SSLKEYLOGFILE" "env SSLKEYLOGFILE=$KEYS" "$(calls)"
check "session: the keys are in the key log" "CLIENT_RANDOM 00 11" "$(cat "$KEYS")"
check "session: the capture file is there" "PCAPNG" "$(cat "$PCAP")"
check "session: the key log is private" "600" "$(mode "$KEYS")"
check "session: the capture is private" "600" "$(mode "$PCAP")"
has "session: the browser was asked to end" "browser-asked-to-end" "$(calls)"
gone "$TMP/browser.pid" && ok "session: the browser is gone" || bad "session: the browser is gone"
gone "$TMP/tshark.pid" && ok "session: the capture is gone" || bad "session: the capture is gone"
check "session: -i given, the default route is not asked" "" "$(calls route)"
has "session: the summary names the key log" "TLS keys: $KEYS (1 line(s))" "$OUT"
has "session: the summary says how to decrypt" "(Pre)-Master-Secret log filename" "$OUT"
check "session: an earlier browser is looked for first" "pgrep" "$(calls | head -n 1 | cut -d' ' -f1)"
PATTERN="$(calls pkill | sed 's/^pkill -f -- //')"
check "session: pgrep and pkill get the same pattern" "pgrep -f -- $PATTERN" "$(calls pgrep)"
check "session: pkill runs once" "1" "$(calls pkill | wc -l | tr -d ' ')"
check "the pattern finds the browser started here" "1" "$(matches "$PATTERN" "$(calls 'chrome bin')")"
check "the pattern does not find a browser on another profile" "0" \
  "$(matches "$PATTERN" "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --user-data-dir=$TMP/elsewhere/chrome")"
check "the pattern does not find a browser without a profile option" "0" \
  "$(matches "$PATTERN" "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")"

# ---- session 2: firefox, all interfaces, a folder name full of pattern characters, TERM
fresh
OUT2="$TMP/out.dir+(1)|x"
"$CMD" -b firefox -r --output "$OUT2" -d 59 > "$TMP/s2.out" 2> "$TMP/s2.err" < /dev/null &
pid=$!
i=0; while [ ! -s "$TMP/browser.pid" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
t0="$(date +%s)"
kill -TERM "$pid"
wait "$pid"; RC=$?
took=$(( $(date +%s) - t0 ))
OUT="$(cat "$TMP/s2.out")"
PCAP="$(one "$OUT2/ldumps" 'session-*.pcapng')"
check "TERM: exit 0" "0" "$RC"
[ "$took" -le 10 ] && ok "TERM: the session stops at once, not after -d" || bad "TERM: the session stops at once, not after -d (took ${took}s)"
has "TERM: the session is closed properly" "Session finished" "$OUT"
check "-r: tshark captures on all interfaces" "tshark -i any -w $PCAP -s 0 -q" "$(calls tshark)"
check "firefox starts on a profile folder of its own" \
  "firefox -no-remote -profile $OUT2/logs/browser-profiles/firefox -new-instance" "$(calls firefox)"
gone "$TMP/browser.pid" && ok "TERM: the browser is gone" || bad "TERM: the browser is gone"
gone "$TMP/tshark.pid" && ok "TERM: the capture is gone" || bad "TERM: the capture is gone"
check "TERM: the waiting sleep is gone too" "0" "$(ps -A -o command | grep -c '[s]leep 59$')"
check "--output: nothing new in the default folder" "1" "$(one "$D/ldumps" 'session-*.pcapng' | wc -l | tr -d ' ')"
PATTERN="$(calls pkill | sed 's/^pkill -f -- //')"
check "odd folder name: the pattern finds the browser started here" "1" "$(matches "$PATTERN" "$(calls firefox)")"
check "odd folder name: the pattern finds nothing else (| . + ( are not pattern characters)" "0" \
  "$(matches "$PATTERN" "editor /somewhere/x/logs/browser-profiles/firefox")"

# ---- session 3: on a terminal - the browser question, MBM_SSLKEYLOG_DIR, Ctrl-C
fresh
export MBM_SSLKEYLOG_DIR="$TMP/env dir"
if tty_run "2
$(printf '\003')" "$CMD"; then
  PCAP="$(one "$MBM_SSLKEYLOG_DIR/ldumps" 'session-*.pcapng')"
  check "terminal: exit 0 after Ctrl-C" "0" "$RC"
  has "terminal: asks which browser" "Which browser?" "$OUT"
  has "terminal: answer 2 starts firefox" "firefox -no-remote -profile $MBM_SSLKEYLOG_DIR/logs/browser-profiles/firefox" "$(calls firefox)"
  check "no -i: the interface of the default route (macOS)" "tshark -i en7 -w $PCAP -s 0 -q" "$(calls tshark)"
  has "terminal: Ctrl-C closes the session properly" "Session finished" "$OUT"
  hasnt "terminal: Ctrl-C is not reported as a capture that died" "stopped by itself" "$OUT"
  gone "$TMP/browser.pid" && ok "terminal: the browser is gone" || bad "terminal: the browser is gone"
  gone "$TMP/tshark.pid" && ok "terminal: the capture is gone" || bad "terminal: the capture is gone"
else
  skip "no expect: the terminal session (browser question, Ctrl-C)"
fi
unset MBM_SSLKEYLOG_DIR

# ---- session 4: no terminal, no -b, -d 0, the user closes the browser; Linux default route
fresh
fake "$MBM_SSLKEYLOG_CHROME" "$BROWSER_IS_CLOSED"
stub route 'exit 1'
stub ip 'echo "default via 10.0.0.1 dev eth9 proto dhcp src 10.0.0.5 metric 100"'
run "$CMD" -d 0 -o "$TMP/o4"
check "browser closed by its user: exit 0" "0" "$RC"
has "no terminal, no -b: chrome" "chrome bin --user-data-dir=$TMP/o4/logs/browser-profiles/chrome" "$(calls 'chrome bin')"
has "-d 0 waits instead of stopping at once" "standard input is closed: waiting for the browser" "$OUT"
check "no -i: the interface of the default route (Linux)" "ip -o route show default" "$(calls ip)"
has "no -i: tshark gets that interface" "tshark -i eth9 -w " "$(calls tshark)"
has "browser closed by its user: the session is closed properly" "Session finished" "$OUT"
gone "$TMP/tshark.pid" && ok "browser closed by its user: the capture is gone" || bad "browser closed by its user: the capture is gone"

# ---- session 5: the capture dies in the middle; Enter ends the session; no default route
fresh
# This capture ends with an error as soon as the browser runs; Enter is typed after that.
stub tshark 'i=0; while [ ! -s "$SBX/browser.pid" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
echo "tshark: the interface went away" >&2
: > "$SBX/tshark.dead"
exit 2'
stub route 'exit 1'
OUT="$( ( i=0; while [ ! -e "$TMP/tshark.dead" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; sleep 0.3; echo ) |
        "$CMD" -b chrome -o "$TMP/o5" 2> "$TMP/stderr")"; RC=$?
ERR="$(cat "$TMP/stderr")"
check "capture died: exit 1" "1" "$RC"
has "capture died: said on standard error" "the capture had already stopped by itself" "$ERR"
has "capture died: the message of tshark is shown" "[tshark] tshark: the interface went away" "$ERR"
has "capture died: the browser is stopped all the same" "browser-asked-to-end" "$(calls)"
gone "$TMP/browser.pid" && ok "capture died: the browser is gone" || bad "capture died: the browser is gone"
has "no default route: tshark chooses the interface" "tshark -w $TMP/o5/ldumps/session-" "$(calls tshark)"
has "no default route: said so" "Interface: the first one tshark finds" "$OUT"

# ---- the capture cannot start (no permission)
fresh
stub tshark 'echo "tshark: You do not have permission to capture on device \"en0\"." >&2; exit 1'
stub my-chromium "$BROWSER_RUNS"
MBM_SSLKEYLOG_CHROME=my-chromium run "$CMD" -b chrome -i en0 -o "$TMP/o6"
check "capture cannot start: exit 1" "1" "$RC"
has "capture cannot start: our message" "tshark could not start the capture" "$ERR"
has "capture cannot start: the message of tshark is shown" "You do not have permission to capture" "$ERR"
has "capture cannot start: says what gives the permission" "ChmodBPF" "$ERR"
hasnt "capture cannot start: no session summary" "Session finished" "$OUT"
check "capture cannot start: the browser is never started" "" "$(calls my-chromium)"
check "capture cannot start: pkill is never run" "" "$(calls pkill)"
check "capture cannot start: no empty capture file is left" "" "$(one "$TMP/o6/ldumps" '*')"
has "the browser setting may be a program on the PATH" "Browser:   chrome ($STUBS/my-chromium)" "$OUT"

# ---- refusals before anything is started
fresh
stub pgrep 'exit 0'
run "$CMD" -rb firefox --output="$TMP/o7"
check "an earlier browser on the profile: exit 1" "1" "$RC"
has "an earlier browser on the profile: the message names it" "a firefox of an earlier session still runs on $TMP/o7/logs/browser-profiles/firefox" "$ERR"
check "an earlier browser on the profile: no capture" "" "$(calls tshark)"
check "an earlier browser on the profile: no browser" "" "$(calls firefox)"
[ ! -e "$TMP/o7" ] && ok "an earlier browser on the profile: nothing created" || bad "an earlier browser on the profile: nothing created"

fresh
MBM_SSLKEYLOG_FIREFOX="$TMP/nothing here/firefox" run "$CMD" -b firefox -o "$TMP/o8"
check "browser program missing: exit 1" "1" "$RC"
has "browser program missing: the message names the setting" "MBM_SSLKEYLOG_FIREFOX names a program that is not there: $TMP/nothing here/firefox" "$ERR"
check "browser program missing: no capture" "" "$(calls tshark)"
[ ! -e "$TMP/o8" ] && ok "browser program missing: nothing created" || bad "browser program missing: nothing created"

for args in "-b safari" "-d abc" "-d -5" "-x" "--nope" "extra" "-b" "-o" "--output"; do
  # shellcheck disable=SC2086  # the words of $args are separate arguments on purpose
  run "$CMD" $args
  check "wrong use [$args]: exit 2" "2" "$RC"
  has "wrong use [$args]: points to --help" "--help" "$ERR"
done
check "wrong use starts nothing" "" "$(calls)"

rm -f "$STUBS/tshark"
run "$CMD" -b chrome
check "without tshark: exit 1" "1" "$RC"
has "without tshark: says how to get it" "tshark is not installed (macOS: brew install wireshark" "$ERR"
check "without tshark: no browser" "" "$(calls 'chrome bin')"

# ---- nothing else was stopped
kill -0 "$EVERYDAY" 2>/dev/null && ok "the everyday browser still runs after all sessions" || bad "the everyday browser still runs after all sessions"
kill "$EVERYDAY" 2>/dev/null
wait "$EVERYDAY" 2>/dev/null

# ---- the real tshark knows the option that the help gives for reading a session
if real tshark && real text2pcap; then
  printf '0000 ff ff ff ff ff ff 00 11 22 33 44 55 08 06 00 01 08 00 06 04 00 01 00 11 22 33 44 55 0a 00 00 01 00 00 00 00 00 00 0a 00 00 02\n' > f.txt
  text2pcap -q f.txt session.pcapng >/dev/null 2>&1
  : > session.log
  run tshark -r session.pcapng -o tls.keylog_file:session.log -Y http
  check "real tshark accepts: -o tls.keylog_file:FILE -Y http" "0" "$RC"
else
  skip "tshark and text2pcap are not installed: the reading example of the help"
fi

finish
