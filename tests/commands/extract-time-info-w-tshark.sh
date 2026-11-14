#!/bin/bash
# Tests for mbm-extract-time-info-w-tshark.   Run:  tests/run.sh extract-time-info-w-tshark    or:  bash tests/commands/extract-time-info-w-tshark.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-extract-time-info-w-tshark"
echo "mbm-extract-time-info-w-tshark"

mkdir -p "$TMP/work"
cd "$TMP/work" || exit 1
# A zone without summer time that needs no zone files: three hours east of UTC.
export TZ="XXX-3"

# The fake tshark answers for the file after -r with the lines of FILE.times (the output of
# "-T fields -e frame.time_epoch") and ends with the status in FILE.rc, if there is one.
fake_tshark() {
  stub tshark 'f=""; while [ $# -gt 0 ]; do [ "$1" = "-r" ] && f="$2"; shift; done
cat "$f.times" 2>/dev/null
[ -r "$f.rc" ] && exit "$(cat "$f.rc")"
exit 0'
}
# capture FILE EPOCH...  - a (fake) capture file with these packet times
capture() { local f="$1"; shift; : > "./$f"; : > "./$f.times"; [ $# -eq 0 ] || printf '%s\n' "$@" > "./$f.times"; }

# ---- help
run "$CMD" --help
for word in "FILE..." "-h, --help" "Needs: tshark" "Exit status:"; do
  has "help names: $word" "$word" "$OUT"
done

# ---- the main job, with a fake tshark
fake_tshark
# 2026-11-01 07:00:00.25 UTC to 2026-11-02 08:30:05.75 UTC: one day, 1 h 30 min 5.5 s
capture "my capture.pcap" 1793516400.250000000 1793516401.000000000 1793516402.000000000 1793516403.000000000 1793608205.750000000
run "$CMD" "my capture.pcap"
check "first, last, elapsed and packets of one file" "File:         my capture.pcap
First packet: 2026-11-01 10:00:00.250000000 +0300  (2026-11-01 07:00:00.250000000 UTC)
Last packet:  2026-11-02 11:30:05.750000000 +0300  (2026-11-02 08:30:05.750000000 UTC)
Elapsed:      1d 01:30:05.500000000  (91805.500000000 seconds)
Packets:      5" "$OUT"
check "exit 0" "0" "$RC"
check "nothing on standard error" "" "$ERR"
check "the file is read once, by its epoch times" \
  "tshark -n -r my capture.pcap -T fields -e frame.time_epoch" "$(calls tshark)"
TZ=UTC run "$CMD" "my capture.pcap"
has "local time follows the time zone" "First packet: 2026-11-01 07:00:00.250000000 +0000  (2026-11-01 07:00:00.250000000 UTC)" "$OUT"
LC_ALL=tr_TR.UTF-8 run "$CMD" "my capture.pcap"
has "the same under a Turkish locale" "Elapsed:      1d 01:30:05.500000000  (91805.500000000 seconds)" "$OUT"

capture short.pcap 1793516400.000000000 1793521801.500000000
run "$CMD" short.pcap
has "under a day: no day count" "Elapsed:      01:30:01.500000000  (5401.500000000 seconds)" "$OUT"

capture nano.pcap 1793516400.000000001 1793516400.000000003
run "$CMD" nano.pcap
has "nanoseconds are exact" "Elapsed:      00:00:00.000000002  (0.000000002 seconds)" "$OUT"
capture borrow.pcap 1793516400.900000000 1793516401.000000080
run "$CMD" borrow.pcap
has "a fraction that borrows from the seconds, and one that starts with zeros (080 is not octal)" "Elapsed:      00:00:00.100000080  (0.100000080 seconds)" "$OUT"
capture micro.pcap 1793516400.5 1793516402
run "$CMD" micro.pcap
has "short fractions are filled up" "First packet: 2026-11-01 10:00:00.500000000 +0300" "$OUT"
has "a time without a fraction" "Elapsed:      00:00:01.500000000  (1.500000000 seconds)" "$OUT"

capture mixed.pcap 1793516402.000000000 1793516400.250000000 1793516403.750000000 1793516401.000000000
run "$CMD" mixed.pcap
has "packets out of order: the earliest time" "First packet: 2026-11-01 10:00:00.250000000" "$OUT"
has "packets out of order: the latest time" "Last packet:  2026-11-01 10:00:03.750000000" "$OUT"
has "packets out of order: elapsed is never negative" "Elapsed:      00:00:03.500000000" "$OUT"

capture one.pcap 1793516400.250000000
run "$CMD" one.pcap
has "one packet: elapsed is zero" "Elapsed:      00:00:00.000000000  (0.000000000 seconds)" "$OUT"
has "one packet: counted" "Packets:      1" "$OUT"
capture none.pcap
run "$CMD" none.pcap
check "no packets: the file and a count of 0, no times" "File:         none.pcap
Packets:      0" "$OUT"
check "no packets: exit 0" "0" "$RC"

# ---- several files
reset_calls
run "$CMD" one.pcap nothere.pcap short.pcap
check "several files: each reported, a blank line between" "File:         one.pcap
First packet: 2026-11-01 10:00:00.250000000 +0300  (2026-11-01 07:00:00.250000000 UTC)
Last packet:  2026-11-01 10:00:00.250000000 +0300  (2026-11-01 07:00:00.250000000 UTC)
Elapsed:      00:00:00.000000000  (0.000000000 seconds)
Packets:      1

File:         short.pcap
First packet: 2026-11-01 10:00:00.000000000 +0300  (2026-11-01 07:00:00.000000000 UTC)
Last packet:  2026-11-01 11:30:01.500000000 +0300  (2026-11-01 08:30:01.500000000 UTC)
Elapsed:      01:30:01.500000000  (5401.500000000 seconds)
Packets:      2" "$OUT"
check "several files, one missing: exit 1" "1" "$RC"
has "several files, one missing: the message names it" "no such file: nothere.pcap" "$ERR"
check "several files: one tshark call per file that exists" "2" "$(calls tshark | wc -l | tr -d ' ')"

mkdir -p glob
( cd glob && capture a.pcapng 1793516400.0 && capture "b c.pcapng" 1793516401.0 )
OUT="$(cd glob && /bin/bash -c '"$0" *.pcapng' "$CMD" 2>&1)"
has "the example with *.pcapng: first file" "File:         a.pcapng" "$OUT"
has "the example with *.pcapng: a name with a space" "File:         b c.pcapng" "$OUT"

for name in "-dash.pcap" "it's a \"quote\".pcap"; do
  capture "$name" 1793516400.0
  reset_calls
  run "$CMD" -- "$name"
  has "file name [$name]: reported" "File:         $name" "$OUT"
  check "file name [$name]: handed to tshark unchanged" "tshark -n -r $name -T fields -e frame.time_epoch" "$(calls tshark)"
done

# ---- tshark fails
capture junk.pcap; echo 2 > junk.pcap.rc
run "$CMD" junk.pcap
check "tshark fails without output: exit 1" "1" "$RC"
has "tshark fails without output: the message names the file" "tshark could not read: junk.pcap" "$ERR"
check "tshark fails without output: nothing reported" "" "$OUT"
capture cut.pcap 1793516400.000000000 1793516410.000000000; echo 14 > cut.pcap.rc
run "$CMD" cut.pcap
check "file cut short: exit 1" "1" "$RC"
has "file cut short: the part that was read is reported" "Elapsed:      00:00:10.000000000" "$OUT"
has "file cut short: said on standard error" "stopped before the end of cut.pcap" "$ERR"
run "$CMD" junk.pcap one.pcap
has "a file that fails does not stop the next one" "File:         one.pcap" "$OUT"

# ---- wrong use
reset_calls
run "$CMD"
check "no file: exit 2" "2" "$RC"
has "no file: points to --help" "--help" "$ERR"
run "$CMD" --utc one.pcap
check "unknown option: exit 2" "2" "$RC"
check "wrong use never runs tshark" "" "$(calls tshark)"
run "$CMD" nothere.pcap
check "missing file: exit 1" "1" "$RC"
has "missing file: the message names it" "no such file: nothere.pcap" "$ERR"
check "missing file: nothing on standard output" "" "$OUT"

ln -sf "$CMD" "$TMP/zz-extract-time-info-w-tshark"
run "$TMP/zz-extract-time-info-w-tshark" nothere.pcap
has "under another prefix the messages use that name" "zz-extract-time-info-w-tshark: no such file" "$ERR"

# ---- tshark is not installed
rm -f "$STUBS/tshark"
run "$CMD" one.pcap
check "without tshark: exit 1" "1" "$RC"
has "without tshark: says how to get it" "tshark is not installed (macOS: brew install wireshark" "$ERR"

# ---- the real tshark, on capture files made here
if real tshark && real text2pcap; then
  ARP="ff ff ff ff ff ff 00 11 22 33 44 55 08 06 00 01 08 00 06 04 00 01 00 11 22 33 44 55 0a 00 00 01 00 00 00 00 00 00 0a 00 00 02"
  {
    printf '2026-11-01 10:00:00.250000\n0000 %s\n\n' "$ARP"
    printf '2026-11-01 10:00:01.000000\n0000 %s\n\n' "$ARP"
    printf '2026-11-02 11:30:05.750000\n0000 %s\n\n' "$ARP"
  } > frames.txt
  text2pcap -q -t '%Y-%m-%d %H:%M:%S.%f' frames.txt "real capture.pcapng" >/dev/null 2>&1
  run "$CMD" "real capture.pcapng"
  check "real tshark: the report (the time format of tshark does not matter)" "File:         real capture.pcapng
First packet: 2026-11-01 10:00:00.250000000 +0300  (2026-11-01 07:00:00.250000000 UTC)
Last packet:  2026-11-02 11:30:05.750000000 +0300  (2026-11-02 08:30:05.750000000 UTC)
Elapsed:      1d 01:30:05.500000000  (91805.500000000 seconds)
Packets:      3" "$OUT"
  check "real tshark: exit 0" "0" "$RC"

  printf 'this is not a capture\n' > real-junk.pcap
  run "$CMD" real-junk.pcap
  check "real tshark, not a capture file: exit 1" "1" "$RC"
  has "real tshark, not a capture file: our message" "tshark could not read: real-junk.pcap" "$ERR"

  head -c $(( $(wc -c < "real capture.pcapng") - 10 )) "real capture.pcapng" > real-cut.pcapng   # the last packet is incomplete
  run "$CMD" real-cut.pcapng
  check "real tshark, file cut short: exit 1" "1" "$RC"
  has "real tshark, file cut short: the packets before the cut are reported" "Packets:      2" "$OUT"
else
  skip "tshark and text2pcap are not installed: the checks on real capture files"
fi

finish
