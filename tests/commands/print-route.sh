#!/bin/bash
# Tests for mbm-print-route.   Run:  tests/run.sh print-route    or:  bash tests/commands/print-route.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-print-route"
echo "mbm-print-route"

# ---------------------------------------------------------------- canned system output
# The fakes print what the real tools print; the addresses are documentation ranges.

cat > "$TMP/netstat4.txt" <<'EOF_NETSTAT4'
Routing tables

Internet:
Destination        Gateway            Flags               Netif Expire
default            192.0.2.1          UGScg                 en0
default            link#39            UCSIg               utun9
10                 198.51.100.85      UGSc                utun9
10.0.200/24        198.51.100.85      UGSc                utun9
127                127.0.0.1          UCS                   lo0
127.0.0.1          127.0.0.1          UH                    lo0
169.254            link#14            UCS                   en0      !
172.16/12          198.51.100.85      UGSc                utun9
192.0.2/24         link#14            UCS                   en0      !
192.0.2.1          3c:64:cf:0:0:1     UHLWIir               en0   1187
192.0.2.1/32       link#14            UCS                   en0      !
192.0.2.77         link#14            UHWIi                 en0
192.168.49         198.51.100.85      UGSc                utun9
203.0.113.9/32     192.0.2.1          UGSc                  en0
224.0.0/4          link#14            UmCS                  en0      !
EOF_NETSTAT4

cat > "$TMP/netstat6.txt" <<'EOF_NETSTAT6'
Routing tables

Internet6:
Destination                             Gateway                                 Flags               Netif Expire
default                                 fe80::%utun0                            UGcIg               utun0
::1                                     ::1                                     UHL                   lo0
fe80::%lo0/64                           fe80::1%lo0                             UcI                   lo0
fe80::%en0/64                           link#14                                 UCI                   en0
ff02::%en0/32                           link#14                                 UmCI                  en0
EOF_NETSTAT6

# netstat -rn -f inet|inet6
stub netstat 'case "$*" in
  "-rn -f inet") cat "$TMP/netstat4.txt" ;;
  "-rn -f inet6") cat "$TMP/netstat6.txt" ;;
  *) echo "netstat: unexpected arguments: $*" >&2; exit 1 ;;
esac'

# route -n get [-inet6] DEST
stub route 'dest="${!#}"
case "$dest" in
  8.8.8.8) printf "%s\n" "   route to: 8.8.8.8" "destination: default" "       mask: default" "    gateway: 192.0.2.1" "  interface: en0" "      flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>" ;;
  10.1.2.3) printf "%s\n" "   route to: 10.1.2.3" "destination: 10.0.0.0" "       mask: 255.0.0.0" "    gateway: 198.51.100.85" "  interface: utun9" "      flags: <UP,GATEWAY,DONE,STATIC,PRCLONING>" ;;
  172.20.1.1) printf "%s\n" "   route to: 172.20.1.1" "destination: 172.16.0.0" "       mask: 255.240.0.0" "    gateway: 198.51.100.85" "  interface: utun9" ;;
  192.0.2.50) printf "%s\n" "   route to: 192.0.2.50" "destination: 192.0.2.0" "       mask: 255.255.255.0" "  interface: en0" "      flags: <UP,DONE,CLONING,STATIC>" ;;
  example.com) printf "%s\n" "   route to: 203.0.113.9" "destination: 203.0.113.9" "    gateway: 192.0.2.1" "  interface: en0" "      flags: <UP,GATEWAY,HOST,DONE,STATIC>" ;;
  ::1) printf "%s\n" "   route to: ::1" "destination: ::1" "  interface: lo0" "      flags: <UP,HOST,DONE,LLINFO,LOCAL>" ;;
  2001:db8::1) echo "route: writing to routing socket: not in table" >&2; exit 1 ;;
  *) echo "route: bad address: $dest" >&2; exit 68 ;;
esac'
stub uname 'echo Darwin'
export TMP

# The table with single spaces between the columns, each line between "|" marks.
norm() { printf '%s\n' "$OUT" | awk '{ printf "|%s %s %s|\n", $1, $2, $3 }'; }

echo " macOS: the table"
run "$CMD"
T="$(norm)"
check "the table: exit 0" "0" "$RC"
check "nothing on standard error" "" "$ERR"
check "a header, then the default routes first" "DESTINATION default default" "$(printf '%s\n' "$OUT" | awk 'NR <= 3 { printf "%s%s", sep, $1; sep = " " }')"
has "the default route with its gateway and interface" "|default 192.0.2.1 en0|" "$T"
has "a default route without a gateway" "|default direct utun9|" "$T"
has "'10' is written as 10.0.0.0/8" "|10.0.0.0/8 198.51.100.85 utun9|" "$T"
has "'10.0.200/24' is written as 10.0.200.0/24" "|10.0.200.0/24 198.51.100.85 utun9|" "$T"
has "'127' is written as 127.0.0.0/8" "|127.0.0.0/8 127.0.0.1 lo0|" "$T"
has "'172.16/12' is written as 172.16.0.0/12" "|172.16.0.0/12 198.51.100.85 utun9|" "$T"
has "'169.254' is written as 169.254.0.0/16, and link#14 as direct" "|169.254.0.0/16 direct en0|" "$T"
has "'192.168.49' is written as 192.168.49.0/24" "|192.168.49.0/24 198.51.100.85 utun9|" "$T"
has "'224.0.0/4' keeps its length" "|224.0.0.0/4 direct en0|" "$T"
has "a host route stays a plain address" "|127.0.0.1 127.0.0.1 lo0|" "$T"
has "an address with its own /32 stays as it is" "|203.0.113.9/32 192.0.2.1 en0|" "$T"
hasnt "neighbour entries (flag L) are left out" "3c:64:cf" "$OUT"
hasnt "cloned host entries (flag W) are left out" "192.0.2.77" "$OUT"
check "the columns are aligned" "1" "$(printf '%s\n' "$OUT" | awk '{ match($0, /^[^ ]+ +[^ ]+ +/); print RLENGTH }' | sort -u | wc -l | tr -d ' ')"
check "13 routes and the header" "14" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
check "it asked netstat for IPv4 only" "netstat -rn -f inet" "$(calls netstat)"

run "$CMD" -a
has "-a shows the neighbour entry" "|192.0.2.1 3c:64:cf:0:0:1 en0|" "$(norm)"
has "-a shows the cloned entry" "|192.0.2.77 direct en0|" "$(norm)"
run "$CMD" --all
check "--all is the same as -a" "16" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"

run "$CMD" -i en0
check "-i en0: exit 0" "0" "$RC"
check "-i en0: only the routes through en0" "en0" "$(printf '%s\n' "$OUT" | awk 'NR > 1 { print $3 }' | sort -u)"
check "-i en0: 6 routes" "7" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
run "$CMD" --interface utun9
check "--interface utun9: only utun9" "utun9" "$(printf '%s\n' "$OUT" | awk 'NR > 1 { print $3 }' | sort -u)"
run "$CMD" -i en7
check "-i with an interface that has no route: exit 1" "1" "$RC"
has "... and it says so" "no IPv4 route goes through en7" "$ERR"
check "... and prints nothing" "" "$OUT"
# The old version appended its argument to a pattern, unquoted: 'en0' printed nothing at all.
run "$CMD" -i 'en.*'
check "-i is a name, not a pattern" "1" "$RC"

reset_calls
run "$CMD" -6
check "-6 asks netstat for IPv6" "netstat -rn -f inet6" "$(calls netstat)"
has "-6: the default route" "|default fe80::%utun0 utun0|" "$(norm)"
has "-6: an IPv6 network is left as it is" "|fe80::%en0/64 direct en0|" "$(norm)"
hasnt "-6: the neighbour entry is left out" "|::1 " "$(norm)"
run "$CMD" --ipv6 -i lo0
check "--ipv6 -i lo0: one route" "fe80::%lo0/64 fe80::1%lo0 lo0" "$(printf '%s\n' "$OUT" | awk 'NR > 1 { print $1, $2, $3 }')"

echo " macOS: one destination"
reset_calls
run "$CMD" 8.8.8.8
check "DEST: exit 0" "0" "$RC"
check "DEST through the default route" "to 8.8.8.8|route default|gateway 192.0.2.1|interface en0|" "$(printf '%s\n' "$OUT" | awk '{ printf "%s %s|", $1, $2 }')"
check "it asked route, without resolving names in the answer" "route -n get 8.8.8.8" "$(calls route)"
run "$CMD" 10.1.2.3
has "the matching entry with its mask as a length" "route      10.0.0.0/8" "$OUT"
has "... its gateway" "gateway    198.51.100.85" "$OUT"
run "$CMD" 172.20.1.1
has "mask 255.240.0.0 is /12" "route      172.16.0.0/12" "$OUT"
run "$CMD" 192.0.2.50
has "a directly connected destination" "gateway    direct" "$OUT"
has "... its network" "route      192.0.2.0/24" "$OUT"
run "$CMD" example.com
check "a host name: exit 0" "0" "$RC"
has "a host name shows the address it resolved to" "to         203.0.113.9" "$OUT"
reset_calls
run "$CMD" ::1
check "an address with a colon is looked up as IPv6" "route -n get -inet6 ::1" "$(calls route)"
has "... and answered" "interface  lo0" "$OUT"
reset_calls
run "$CMD" -6 example.org
check "-6 with a name asks for IPv6" "route -n get -inet6 example.org" "$(calls route)"
run "$CMD" -- 8.8.8.8
check "-- ends the options" "0" "$RC"

run "$CMD" 2001:db8::1
check "no route: exit 1" "1" "$RC"
has "no route: the message" "no route to 2001:db8::1: the routing table has no entry for it" "$ERR"
check "no route: nothing on standard output" "" "$OUT"
run "$CMD" nosuch.invalid
check "unknown host: exit 1" "1" "$RC"
has "unknown host: the message" "not an address or a known host name" "$ERR"
# The old way of calling it, with an interface name as the only argument.
run "$CMD" en0
check "an interface name as DEST: exit 1" "1" "$RC"
has "... and the message shows the way" "mbm-print-route -i en0" "$ERR"

echo " wrong use"
reset_calls
run "$CMD" 1.1.1.1 2.2.2.2
check "two destinations: exit 2" "2" "$RC"
run "$CMD" -i
check "-i without a name: exit 2" "2" "$RC"
run "$CMD" -i en0 8.8.8.8
check "-i with a destination: exit 2" "2" "$RC"
has "... the message points to the help" "--help" "$ERR"
run "$CMD" -a 8.8.8.8
check "-a with a destination: exit 2" "2" "$RC"
run "$CMD" ""
check "an empty destination: exit 2" "2" "$RC"
run "$CMD" -x
check "an unknown option: exit 2" "2" "$RC"
run "$CMD" -- -inet6
check "a destination that looks like an option of route is refused" "1" "$RC"
run "$CMD" 'a b;c'
check "a destination with other characters is refused" "1" "$RC"
has "... with a message" "not an address or a host name: a b;c" "$ERR"
check "wrong use runs nothing" "" "$(calls)"
run "$CMD" --help
check "--help: exit 0" "0" "$RC"
check "--help runs nothing" "" "$(calls)"

echo " Linux"
stub uname 'echo Linux'
rm -f "$STUBS/netstat" "$STUBS/route"
run "$CMD"
check "Linux without ip: exit 1" "1" "$RC"
has "... and how to get it" "ip is not installed (install the iproute2 package)" "$ERR"

# ip -o -4|-6 route show        ip -o -4|-6 route get [fibmatch] ADDR
stub ip 'case "$*" in
  "-o -4 route show") printf "%s\n" \
     "default via 192.0.2.1 dev eth0 proto dhcp src 192.0.2.10 metric 100 " \
     "10.8.0.0/24 dev wg0 proto kernel scope link src 10.8.0.2 " \
     "172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1 linkdown " \
     "192.0.2.0/24 dev eth0 proto kernel scope link src 192.0.2.10 metric 100 " \
     "198.51.100.0/24 via 10.8.0.1 dev wg0 " \
     "blackhole 203.0.113.0/24 " ;;
  "-o -6 route show") printf "%s\n" \
     "::1 dev lo proto kernel metric 256 pref medium" \
     "fe80::/64 dev eth0 proto kernel metric 1024 pref medium" \
     "default via fe80::1 dev eth0 proto ra metric 100 pref medium" ;;
  "-o -4 route get fibmatch 8.8.8.8") echo "default via 192.0.2.1 dev eth0 proto dhcp src 192.0.2.10 metric 100 " ;;
  "-o -4 route get 8.8.8.8") echo "8.8.8.8 via 192.0.2.1 dev eth0 src 192.0.2.10 uid 1000 \    cache " ;;
  "-o -4 route get fibmatch 192.0.2.99") echo "192.0.2.0/24 dev eth0 proto kernel scope link src 192.0.2.10 metric 100 " ;;
  "-o -4 route get 192.0.2.99") echo "192.0.2.99 dev eth0 src 192.0.2.10 uid 1000 \    cache " ;;
  "-o -4 route get fibmatch 203.0.113.9") echo "Error: unknown fibmatch option" >&2; exit 255 ;;
  "-o -4 route get 203.0.113.9") echo "203.0.113.9 via 192.0.2.1 dev eth0 src 192.0.2.10 uid 1000 \    cache " ;;
  "-o -4 route get 127.0.0.1") echo "local 127.0.0.1 dev lo src 127.0.0.1 uid 1000 \    cache <local> " ;;
  "-o -4 route get fibmatch 127.0.0.1") echo "local 127.0.0.1 dev lo table local proto kernel scope host src 127.0.0.1 " ;;
  "-o -6 route get fibmatch 2001:db8::1") echo "default via fe80::1 dev eth0 proto ra metric 100 pref medium" ;;
  "-o -6 route get 2001:db8::1") echo "2001:db8::1 from :: via fe80::1 dev eth0 proto ra src 2001:db8::5 metric 100 pref medium" ;;
  "-o -4 route get 192.0.0.8") echo "RTNETLINK answers: Network is unreachable" >&2; exit 2 ;;
  *) echo "ip: unexpected arguments: $*" >&2; exit 1 ;;
esac'
stub getent 'case "$*" in
  "ahostsv4 example.com") printf "%s\n" "203.0.113.9     STREAM example.com" "203.0.113.9     DGRAM  " ;;
  *) exit 2 ;;
esac'

run "$CMD"
check "Linux table: exit 0" "0" "$RC"
check "Linux table: destination, gateway and interface of every route" \
  "default 192.0.2.1 eth0|10.8.0.0/24 direct wg0|172.17.0.0/16 direct docker0|192.0.2.0/24 direct eth0|198.51.100.0/24 10.8.0.1 wg0|203.0.113.0/24 blackhole -|" \
  "$(printf '%s\n' "$OUT" | awk 'NR > 1 { printf "%s %s %s|", $1, $2, $3 }')"
run "$CMD" -i wg0
check "Linux -i wg0" "10.8.0.0/24 198.51.100.0/24" "$(printf '%s\n' "$OUT" | awk 'NR > 1 { printf "%s%s", sep, $1; sep = " " }')"
run "$CMD" -6
check "Linux -6: the default route is moved to the top" "default fe80::1 eth0" "$(printf '%s\n' "$OUT" | awk 'NR == 2 { print $1, $2, $3 }')"
run "$CMD" 8.8.8.8
check "Linux DEST: gateway, interface and the entry that matched" "to 8.8.8.8|route default|gateway 192.0.2.1|interface eth0|" "$(printf '%s\n' "$OUT" | awk '{ printf "%s %s|", $1, $2 }')"
run "$CMD" 192.0.2.99
check "Linux DEST on the local network" "to 192.0.2.99|route 192.0.2.0/24|gateway direct|interface eth0|" "$(printf '%s\n' "$OUT" | awk '{ printf "%s %s|", $1, $2 }')"
run "$CMD" 127.0.0.1
check "Linux DEST that is this machine" "to 127.0.0.1|route 127.0.0.1|gateway direct|interface lo|" "$(printf '%s\n' "$OUT" | awk '{ printf "%s %s|", $1, $2 }')"
reset_calls
run "$CMD" example.com
check "Linux: a host name is resolved first (ip does not do it)" "getent ahostsv4 example.com" "$(calls getent)"
check "Linux: an old ip without fibmatch still answers, without the route line" "to 203.0.113.9|gateway 192.0.2.1|interface eth0|" "$(printf '%s\n' "$OUT" | awk '{ printf "%s %s|", $1, $2 }')"
run "$CMD" 2001:db8::1
check "Linux IPv6 DEST" "to 2001:db8::1|route default|gateway fe80::1|interface eth0|" "$(printf '%s\n' "$OUT" | awk '{ printf "%s %s|", $1, $2 }')"
run "$CMD" 192.0.0.8
check "Linux no route: exit 1" "1" "$RC"
has "Linux no route: the message" "the routing table has no entry for it" "$ERR"
run "$CMD" nosuch.invalid
check "Linux unknown host: exit 1" "1" "$RC"
has "Linux unknown host: the message" "not an address or a known host name" "$ERR"

stub uname 'echo SunOS'
run "$CMD"
check "another system: exit 1" "1" "$RC"
has "... and it says which systems it knows" "works on macOS and Linux" "$ERR"

echo " the real tools (reading the routing table only)"
rm -f "$STUBS/uname" "$STUBS/ip" "$STUBS/getent" "$STUBS/netstat" "$STUBS/route"
case "$(uname -s)" in
  Darwin)
    run "$CMD"
    check "real table: exit 0" "0" "$RC"
    has "real table: the loopback network" "127.0.0.0/8" "$OUT"
    run "$CMD" -i lo0
    check "real -i lo0: only lo0" "lo0" "$(printf '%s\n' "$OUT" | awk 'NR > 1 { print $3 }' | sort -u)"
    run "$CMD" 127.0.0.1
    check "real DEST 127.0.0.1" "to 127.0.0.1|route 127.0.0.1|gateway direct|interface lo0|" "$(printf '%s\n' "$OUT" | awk '{ printf "%s %s|", $1, $2 }')"
    run "$CMD" localhost
    has "real DEST localhost resolves" "to         127.0.0.1" "$OUT"
    ;;
  Linux)
    if command -v ip >/dev/null 2>&1; then
      run "$CMD" 127.0.0.1
      check "real DEST 127.0.0.1: exit 0" "0" "$RC"
      has "real DEST 127.0.0.1: the loopback interface" "interface  lo" "$OUT"
    else
      skip "ip is not installed"
    fi
    ;;
  *) skip "no real check on this system" ;;
esac

finish
