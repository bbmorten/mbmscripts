#!/bin/bash
# Tests for mbm-entra-ip.   Run:  tests/run.sh entra-ip    or:  bash tests/commands/entra-ip.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-entra-ip"
echo "mbm-entra-ip"

# curl and pwsh are fakes: nothing here asks a real service or signs in anywhere.
# The fake address services answer by host:  A=  B=  C=  (unset: 203.0.113.7; "down": fails)
stub curl 'url=""; for a in "$@"; do url="$a"; done
case "$url" in
  *ifconfig.me*) v="${A-203.0.113.7}" ;;
  *ipify*) v="${B-203.0.113.7}" ;;
  *icanhazip*) v="${C-203.0.113.7}" ;;
  *) v="${D-203.0.113.7}" ;;
esac
[ "$v" = down ] && { echo "curl: (28) timed out" >&2; exit 28; }
printf "%s\n" "$v"'
stub pwsh 'exit "${PWSH_RC:-0}"'
pwsh_call() { calls pwsh | sed "s|$BIN/../libexec/entra-ip.ps1|HELPER|"; }
PS="pwsh -NoProfile -NoLogo -File HELPER"
BK="-BackupDir $HOME/.local/state/mbm-entra-ip -Me mbm-entra-ip"

echo " ip: only the address"
reset_calls
run "$CMD" ip
check "exit 0" "0" "$RC"
check "prints the address" "203.0.113.7" "$OUT"
check "says which services agreed" "(ifconfig.me and api.ipify.org agree)" "$ERR"
check "asks two services, IPv4 only, with a time limit" \
  "curl -4 -fsS --max-time 5 https://ifconfig.me/ip;curl -4 -fsS --max-time 5 https://api.ipify.org;" \
  "$(calls curl | tr '\n' ';')"
check "no sign-in" "" "$(calls pwsh)"
reset_calls
A=down run "$CMD" ip
check "first service down: the next two answer" "0:203.0.113.7" "$RC:$OUT"
reset_calls
A="<html>rate limited</html>" run "$CMD" ip
check "an answer that is not an address is skipped" "0:203.0.113.7" "$RC:$OUT"
reset_calls
A=203.0.113.7 B=198.51.100.1 run "$CMD" ip
check "two services disagree: exit 1" "1" "$RC"
has "... and both answers are shown" "ifconfig.me says 203.0.113.7, api.ipify.org says 198.51.100.1" "$ERR"
reset_calls
A=down B=down C=down D=down run "$CMD" ip
check "no service answers: exit 1" "1" "$RC"
has "... says so" "no service answered with an IPv4 address" "$ERR"
reset_calls
A=down B=down C=down run "$CMD" ip
check "only one answers: used" "0:203.0.113.7" "$RC:$OUT"
has "... and said" "checkip.amazonaws.com only" "$ERR"
reset_calls
A=999.1.1.1 B=198.51.100.1 C=198.51.100.1 run "$CMD" ip
check "999.1.1.1 is not an address" "0:198.51.100.1" "$RC:$OUT"
reset_calls
MBM_ENTRA_IP_SERVICES="https://example.test/ip" D=192.0.2.4 run "$CMD" ip
check "MBM_ENTRA_IP_SERVICES replaces the list" "0:192.0.2.4" "$RC:$OUT"

echo " no arguments: add your address"
reset_calls
run "$CMD" -l Bulent -y
check "exit 0" "0" "$RC"
has "shows the address first" "Your public IPv4 address: 203.0.113.7 (ifconfig.me and api.ipify.org agree)" "$OUT"
check "hands it to the helper as an add" \
  "$PS -Action add -Location Bulent $BK -MyIp 203.0.113.7 -Cidrs 203.0.113.7 -Yes" "$(pwsh_call)"
reset_calls
run "$CMD" -l Bulent
check "no terminal and no --yes: exit 1" "1" "$RC"
has "... says how to go ahead" "Add --yes" "$ERR"
check "... no sign-in" "" "$(calls pwsh)"
reset_calls
run "$CMD" -l Bulent -n
check "-n needs no terminal" "0" "$RC"
has "-n is passed on" "-DryRun" "$(pwsh_call)"
reset_calls
A=203.0.113.7 B=198.51.100.1 run "$CMD" -l Bulent -y
check "services disagree: nothing is added" "1:" "$RC:$(calls pwsh)"
reset_calls
MBM_ENTRA_LOCATION=Bulent MBM_ENTRA_TENANT=contoso.example run "$CMD" -y
check "the settings give location and tenant" \
  "$PS -Action add -Location Bulent $BK -Tenant contoso.example -MyIp 203.0.113.7 -Cidrs 203.0.113.7 -Yes" "$(pwsh_call)"
reset_calls
MBM_ENTRA_LOCATION=Other run "$CMD" --location="Home office" -t 00000000-0000-0000-0000-000000000000 -y -f --device-code
check "options win over settings; a name with a space stays one argument" \
  "$PS -Action add -Location Home office $BK -Tenant 00000000-0000-0000-0000-000000000000 -MyIp 203.0.113.7 -Cidrs 203.0.113.7 -Yes -Force -DeviceCode" "$(pwsh_call)"
reset_calls
MBM_ENTRA_IP_BACKUP_DIR=/x/backups run "$CMD" -l Bulent -y
has "MBM_ENTRA_IP_BACKUP_DIR is passed on" "-BackupDir /x/backups " "$(pwsh_call)"

echo " list, add, remove, edit, restore"
reset_calls
run "$CMD" -l Bulent list
check "list: exit 0, no --yes needed" "0" "$RC"
check "list passes your address to mark it" "$PS -Action list -Location Bulent $BK -MyIp 203.0.113.7" "$(pwsh_call)"
reset_calls
A=down B=down C=down D=down run "$CMD" -l Bulent list
check "list works without an address" "0:$PS -Action list -Location Bulent $BK" "$RC:$(pwsh_call)"
reset_calls
run "$CMD" -l Bulent add 198.51.100.0/24 192.0.2.9 -y
check "add: the ranges, joined" \
  "$PS -Action add -Location Bulent $BK -MyIp 203.0.113.7 -Cidrs 198.51.100.0/24,192.0.2.9 -Yes" "$(pwsh_call)"
for verb in remove delete rm; do
  reset_calls
  run "$CMD" -l Bulent "$verb" 192.0.2.9 -n
  check "$verb is remove" "$PS -Action remove -Location Bulent $BK -MyIp 203.0.113.7 -Cidrs 192.0.2.9 -DryRun" "$(pwsh_call)"
done
reset_calls
run "$CMD" -l Bulent edit
check "edit without a terminal: exit 1, no sign-in" "1:" "$RC:$(calls pwsh)"
has "... says why" "edit needs a terminal" "$ERR"
echo '{}' > "$TMP/b.json"
reset_calls
run "$CMD" -l Bulent restore "$TMP/b.json" -y
check "restore passes the file" "$PS -Action restore -Location Bulent $BK -MyIp 203.0.113.7 -RestoreFile $TMP/b.json -Yes" "$(pwsh_call)"
reset_calls
PWSH_RC=2 run "$CMD" -l Bulent add 1.2.3.4 -y
check "the helper's exit status is the command's" "2" "$RC"

echo " called wrongly"
reset_calls
run "$CMD" -y
check "no location: exit 2" "2" "$RC"
has "... says how to give one" "Give -l NAME, or set MBM_ENTRA_LOCATION" "$ERR"
run "$CMD" -l Bulent add
check "add without a range: exit 2" "2" "$RC"
run "$CMD" -l Bulent add 1.2.3.4,5.6.7.8
check "ranges with commas: exit 2" "2" "$RC"
run "$CMD" -l Bulent list extra
check "list with an argument: exit 2" "2" "$RC"
run "$CMD" -l Bulent restore "$TMP/nope.json"
check "restore of a missing file: exit 2" "2" "$RC"
run "$CMD" -l Bulent frobnicate
check "unknown action: exit 2" "2" "$RC"
run "$CMD" -l
check "-l without a name: exit 2" "2" "$RC"
check "none of these signed in" "" "$(calls pwsh)"
rm -f "$STUBS/pwsh"
reset_calls
run "$CMD" -l Bulent list
check "no pwsh: exit 1" "1" "$RC"
has "... says how to install it" "brew install powershell" "$ERR"

finish
