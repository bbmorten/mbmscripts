#!/bin/bash
# Tests for mbm-eth-conv.   Run:  tests/run.sh eth-conv    or:  bash tests/commands/eth-conv.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-eth-conv"
echo "mbm-eth-conv"

A=00:11:22:33:44:55; B=00:aa:bb:cc:dd:ee; C=02:00:00:00:00:0c; BC=ff:ff:ff:ff:ff:ff
mkdir -p "$TMP/work"
cd "$TMP/work" || exit 1

# The fake tshark prints the canned field output of $CANNED and ends with status $CANNED_RC.
fake_tshark() { stub tshark 'cat "$CANNED"; exit "${CANNED_RC:-0}"'; }
export CANNED="$TMP/fields.txt" CANNED_RC=0
# canned SRC DST ...  - one frame per pair of arguments; "" "" is a frame without Ethernet
canned() { : > "$CANNED"; while [ $# -gt 0 ]; do printf '%s\t%s\n' "$1" "$2" >> "$CANNED"; shift 2; done; }
guard gawk    # the old version needed gawk; a call fails the test

TABLE="ADDRESS A          ADDRESS B          FRAMES
$A  $B       3
$A  $C       1
$A  $BC       1"

# ---- help
run "$CMD" --help
for word in "-j, --json" "-t N, --top N" "-h, --help" "Needs: tshark" "Exit status:"; do
  has "help names: $word" "$word" "$OUT"
done

# ---- the main job, with a fake tshark
fake_tshark
canned "$A" "$BC"  "$B" "$A"  "$A" "$B"  "$A" "$B"  "$C" "$A"
: > "my capture.pcap"
run "$CMD" "my capture.pcap"
check "table: one line per pair, both directions together, most frames first" "$TABLE" "$OUT"
check "table: exit 0" "0" "$RC"
check "table: nothing on standard error" "" "$ERR"
check "tshark is called once, with the file name as one argument" \
  "tshark -n -r my capture.pcap -T fields -E occurrence=f -e eth.src -e eth.dst" "$(calls tshark)"

run "$CMD" -j "my capture.pcap"
check "-j: one JSON array" "[
  { \"src\": \"$A\", \"dst\": \"$B\", \"count\": 3 },
  { \"src\": \"$A\", \"dst\": \"$C\", \"count\": 1 },
  { \"src\": \"$A\", \"dst\": \"$BC\", \"count\": 1 }
]" "$OUT"
run "$CMD" --json "my capture.pcap"
has "--json is the same option" "\"count\": 3 }," "$OUT"
if command -v plutil >/dev/null 2>&1; then
  "$CMD" -j "my capture.pcap" > pairs.json
  plutil -convert xml1 -o /dev/null pairs.json 2>/dev/null && ok "-j: a JSON parser accepts it" || bad "-j: a JSON parser accepts it"
else
  skip "no plutil to parse the JSON with"
fi

run "$CMD" -t 1 "my capture.pcap"
check "-t 1 keeps the busiest pair" "$(printf '%s\n' "$TABLE" | head -n 2)" "$OUT"
run "$CMD" --top 2 "my capture.pcap"
check "--top 2" "$(printf '%s\n' "$TABLE" | head -n 3)" "$OUT"
run "$CMD" --top=2 "my capture.pcap"
check "--top=2" "$(printf '%s\n' "$TABLE" | head -n 3)" "$OUT"
run "$CMD" -t 9 "my capture.pcap"
check "-t above the number of pairs prints them all" "$TABLE" "$OUT"
run "$CMD" -t 1 -j "my capture.pcap"
check "-t with -j" "[
  { \"src\": \"$A\", \"dst\": \"$B\", \"count\": 3 }
]" "$OUT"

canned "$C" "$B"  "$B" "$A"  "$B" "$C"  "$A" "$B"  "$BC" "$A"  "$A" "$BC"  "$A" "$BC"
run "$CMD" "my capture.pcap"
check "order: by frames, then by address" "ADDRESS A          ADDRESS B          FRAMES
$A  $BC       3
$A  $B       2
$B  $C       2" "$OUT"

# ---- frames without an Ethernet header
canned "$A" "$B"  "" ""  "" ""  "$B" "$A"
run "$CMD" "my capture.pcap"
check "frames without Ethernet are not a pair" "ADDRESS A          ADDRESS B          FRAMES
$A  $B       2" "$OUT"
has "their number is said on standard error" "2 frame(s) without an Ethernet header" "$ERR"
canned "" ""
run "$CMD" "my capture.pcap"
check "no Ethernet at all: nothing on standard output" "" "$OUT"
has "no Ethernet at all: said on standard error" "no Ethernet frames in: my capture.pcap" "$ERR"
check "no Ethernet at all: exit 0" "0" "$RC"
run "$CMD" -j "my capture.pcap"
check "no Ethernet at all, -j: an empty array" "[
]" "$OUT"

# ---- file names
canned "$A" "$B"
for name in "-dash.pcap" "it's a \"quote\".pcap" "sp  ace.pcapng"; do
  : > "./$name"
  reset_calls
  run "$CMD" -- "$name"
  check "file name [$name]: exit 0" "0" "$RC"
  check "file name [$name]: handed to tshark unchanged" \
    "tshark -n -r $name -T fields -E occurrence=f -e eth.src -e eth.dst" "$(calls tshark)"
done

# ---- tshark fails
canned
CANNED_RC=2 run "$CMD" "my capture.pcap"
check "tshark fails without output: exit 1" "1" "$RC"
has "tshark fails without output: the message names the file" "tshark could not read: my capture.pcap" "$ERR"
check "tshark fails without output: no table" "" "$OUT"
canned "$A" "$B"  "$B" "$A"
CANNED_RC=14 run "$CMD" "my capture.pcap"
check "file cut short: the part that was read is printed" "ADDRESS A          ADDRESS B          FRAMES
$A  $B       2" "$OUT"
check "file cut short: exit 1" "1" "$RC"
has "file cut short: said on standard error" "stopped before the end of my capture.pcap" "$ERR"

# ---- wrong use
reset_calls
run "$CMD"
check "no file: exit 2" "2" "$RC"
has "no file: points to --help" "--help" "$ERR"
run "$CMD" a.pcap b.pcap
check "two files: exit 2" "2" "$RC"
for bad_n in 0 abc -3 1.5; do
  run "$CMD" -t "$bad_n" "my capture.pcap"
  check "-t $bad_n: exit 2" "2" "$RC"
done
run "$CMD" -t
check "-t without a number: exit 2" "2" "$RC"
run "$CMD" --frames "my capture.pcap"
check "unknown option: exit 2" "2" "$RC"
check "wrong use never runs tshark" "" "$(calls tshark)"
run "$CMD" nothere.pcap
check "missing file: exit 1" "1" "$RC"
has "missing file: the message names it" "no such file: nothere.pcap" "$ERR"
mkdir -p adir
run "$CMD" adir
check "a folder: exit 1" "1" "$RC"
has "a folder: the message says so" "not a file: adir" "$ERR"
check "a missing file or a folder never reaches tshark" "" "$(calls tshark)"

ln -sf "$CMD" "$TMP/zz-eth-conv"
run "$TMP/zz-eth-conv"
has "under another prefix the messages use that name" "zz-eth-conv: no capture file given (see: zz-eth-conv --help)" "$ERR"

# ---- tshark is not installed
rm -f "$STUBS/tshark"
run "$CMD" "my capture.pcap"
check "without tshark: exit 1" "1" "$RC"
has "without tshark: says how to get it" "tshark is not installed (macOS: brew install wireshark" "$ERR"

# ---- the real tshark, on capture files made here
if real tshark && real text2pcap; then
  ARP="08 06 00 01 08 00 06 04 00 01 00 11 22 33 44 55 0a 00 00 01 00 00 00 00 00 00 0a 00 00 02"
  hex() { printf '%s' "$1" | tr ':' ' '; }
  frame() { printf '0000 %s %s %s\n\n' "$(hex "$1")" "$(hex "$2")" "$ARP"; }   # frame DST SRC
  { frame "$BC" "$A"; frame "$A" "$B"; frame "$B" "$A"; frame "$B" "$A"; frame "$A" "$C"; } > frames.txt
  text2pcap -q frames.txt "real capture.pcapng" >/dev/null 2>&1
  run "$CMD" "real capture.pcapng"
  check "real tshark: the table" "$TABLE" "$OUT"
  check "real tshark: exit 0" "0" "$RC"

  # Ethernet inside GRE: outer C -> B, inner A -> broadcast. Only the outer pair counts.
  printf '0000 %s %s 08 00 45 00 00 42 00 00 00 00 40 2f 00 00 0a 00 00 01 0a 00 00 02 00 00 65 58 %s %s %s\n\n' \
    "$(hex "$B")" "$(hex "$C")" "$(hex "$BC")" "$(hex "$A")" "$ARP" > tunnel.txt
  text2pcap -q tunnel.txt tunnel.pcapng >/dev/null 2>&1
  run "$CMD" tunnel.pcapng
  check "real tshark: of a tunnelled frame the outer addresses count" "ADDRESS A          ADDRESS B          FRAMES
$B  $C       1" "$OUT"

  printf '0000 45 00 00 14 00 00 00 00 40 3b 00 00 0a 00 00 01 0a 00 00 02\n\n' > raw.txt
  text2pcap -q -l 101 raw.txt raw.pcapng >/dev/null 2>&1
  run "$CMD" raw.pcapng
  check "real tshark, raw IP capture: nothing on standard output" "" "$OUT"
  has "real tshark, raw IP capture: 1 frame without Ethernet" "1 frame(s) without an Ethernet header" "$ERR"

  printf 'this is not a capture\n' > junk.pcap
  run "$CMD" junk.pcap
  check "real tshark, not a capture file: exit 1" "1" "$RC"
  has "real tshark, not a capture file: our message" "tshark could not read: junk.pcap" "$ERR"

  head -c $(( $(wc -c < "real capture.pcapng") - 10 )) "real capture.pcapng" > cut.pcapng   # the last frame is incomplete
  run "$CMD" cut.pcapng
  check "real tshark, file cut short: exit 1" "1" "$RC"
  has "real tshark, file cut short: the frames before the cut are counted" "$A  $B       3" "$OUT"
else
  skip "tshark and text2pcap are not installed: the checks on real capture files"
fi

finish
