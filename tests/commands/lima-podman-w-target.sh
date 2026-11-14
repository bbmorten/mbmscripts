#!/bin/bash
# Tests for mbm-lima-podman-w-target.   Run:  tests/run.sh lima-podman-w-target    or:  bash tests/commands/lima-podman-w-target.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-lima-podman-w-target"
echo "mbm-lima-podman-w-target"

# Nothing here is real: hdiutil, limactl and podman are fakes, and the "volume" is a folder
# in the sandbox, given with -v as a full path. A file in $FIX switches a fake to a failure.
export FIX="$TMP/fix"
VOL="$TMP/vol"
MNT="$FIX/mnt/LimaData"
SOCK="$MNT/podman/sock/podman.sock"
mkdir -p "$FIX" "$VOL/LimaData.sparsebundle" "$TMP/my vol/Lima Data.sparsebundle"

stub uname 'if [ -f "$FIX/linux" ]; then echo Linux; else echo Darwin; fi'
# hdiutil attach prints one line per device, tab-separated, the mounted folder last - also
# when the image is attached already. The fake mounts NAME.sparsebundle on $FIX/mnt/NAME.
cat > "$FIX/hdiutil" <<'EOF_HDIUTIL'
image="${!#}"
case "$1" in
  create) [ -f "$FIX/create-fails" ] && { echo "hdiutil: create failed - No space left on device" >&2; exit 1; }
          mkdir -p "$image" ;;
  attach) [ -f "$FIX/attach-fails" ] && { echo "hdiutil: attach failed - Resource busy" >&2; exit 1; }
          [ -f "$FIX/attach-silent" ] && exit 0
          name="${image##*/}"
          mount="$FIX/mnt/${name%.sparsebundle}"
          [ -f "$FIX/mount-as" ] && mount="$FIX/mnt/$(cat "$FIX/mount-as")"
          mkdir -p "$mount"
          printf '/dev/disk4          \tGUID_partition_scheme          \t\n'
          printf '/dev/disk4s1        \tApple_APFS                     \t\n'
          printf '/dev/disk5          \tEF57347C-0000-11AA-AA11-0030654\t\n'
          printf '/dev/disk5s1        \t41504653-0000-11AA-AA11-0030654\t%s\n' "$mount" ;;
esac
exit 0
EOF_HDIUTIL
# limactl keeps the machine in $LIMA_HOME: "list" prints its state (nothing, and an error,
# when there is none); "start" makes the podman socket and the state Running.
cat > "$FIX/limactl" <<'EOF_LIMACTL'
echo "  LIMA_HOME=${LIMA_HOME:-unset}" >> "$STUB_LOG"
case "$1" in
  list) [ -f "$LIMA_HOME/state" ] || { echo 'WARN[0000] No instance matching podman found.' >&2; exit 1; }
        cat "$LIMA_HOME/state" ;;
  start) [ -f "$FIX/start-fails" ] && { echo 'FATA[0003] did not receive an event with the "running" status' >&2; exit 1; }
         [ -f "$FIX/no-socket" ] || { mkdir -p "$LIMA_HOME/podman/sock"; : > "$LIMA_HOME/podman/sock/podman.sock"; }
         echo Running > "$LIMA_HOME/state" ;;
esac
exit 0
EOF_LIMACTL
cat > "$FIX/podman" <<'EOF_PODMAN'
case "$1 $3" in
  "system add") [ -f "$FIX/add-fails" ] && { echo "Error: cannot write the connection" >&2; exit 125; } ;;
  "run "*) [ -f "$FIX/run-fails" ] && { echo "Error: initializing source docker://quay.io/podman/hello:latest" >&2; exit 125; } ;;
esac
exit 0
EOF_PODMAN
stub hdiutil "$(cat "$FIX/hdiutil")"
stub limactl "$(cat "$FIX/limactl")"
stub podman "$(cat "$FIX/podman")"
fresh() { rm -rf "${FIX:?}/mnt"; rm -f "${FIX:?}"/*-fails "$FIX/no-socket" "$FIX/attach-silent" "$FIX/mount-as" "$FIX/linux"; reset_calls; }
PODMAN_CALLS="podman system connection add lima-podman unix://$SOCK
podman system connection default lima-podman
podman run --rm quay.io/podman/hello"

# ---- the first run: the machine does not exist yet
fresh
run "$CMD" -v "$VOL"
check "first run: exit 0" "0" "$RC"
check "first run: attach, look, create from the podman template, connect, test - in this order" \
"uname -s
hdiutil attach $VOL/LimaData.sparsebundle
limactl list --format {{.Status}} podman
  LIMA_HOME=$MNT
limactl start --name=podman --tty=false template://podman
  LIMA_HOME=$MNT
$PODMAN_CALLS" "$(calls)"
check "the last lines are the export line for the calling shell" \
"For limactl, run this line in your own shell:
  export LIMA_HOME=$MNT" "$(printf '%s\n' "$OUT" | tail -n 2)"
has "each command is shown as it runs" "+ limactl start --name=podman --tty=false template://podman" "$OUT"

# ---- the machine exists: running, or stopped
reset_calls
run "$CMD" -v "$VOL"
check "machine already running (image attached already): exit 0" "0" "$RC"
has "already running: says so" "The Lima machine podman is already running." "$OUT"
check "already running: it is not started again; podman is still connected" \
"limactl list --format {{.Status}} podman
  LIMA_HOME=$MNT
$PODMAN_CALLS" "$(calls | grep -v -e '^uname' -e '^hdiutil')"

echo Stopped > "$MNT/state"
reset_calls
run "$CMD" -v "$VOL" --no-test
has "machine stopped: a plain start, not a new machine" "limactl start podman" "$(calls limactl)"
hasnt "machine stopped: no template" "template" "$(calls limactl)"
hasnt "--no-test: no test container" "podman run" "$(calls)"
has "--no-test: the connection is still made the default" "podman system connection default lima-podman" "$(calls)"

# ---- where the image mounts (the old version assumed /Volumes/NAME)
fresh
echo "Lima Volume 1" > "$FIX/mount-as"
run "$CMD" -v "$VOL"
has "LIMA_HOME is the folder hdiutil reports, whatever its name" "  LIMA_HOME=$FIX/mnt/Lima Volume 1" "$(calls)"
has "the socket of the connection is under that folder" \
  "podman system connection add lima-podman unix://$FIX/mnt/Lima Volume 1/podman/sock/podman.sock" "$(calls)"
LIMA_HOME=""
eval "$(printf '%s\n' "$OUT" | tail -n 1)"
check "the export line can be pasted, also with a space in the path" "$FIX/mnt/Lima Volume 1" "$LIMA_HOME"
unset LIMA_HOME

fresh
touch "$FIX/attach-silent"
run "$CMD" -v "$VOL"
check "hdiutil reports no folder and /Volumes/NAME is not there: exit 1" "1" "$RC"
has "no mounted folder: says where it looked" "its volume is not at /Volumes/LimaData" "$ERR"
check "no mounted folder: nothing is started" "" "$(calls limactl; calls podman)"

# ---- a step fails: stop there, say what to do
fresh
touch "$FIX/attach-fails"
run "$CMD" -v "$VOL"
check "attach fails: exit 1" "1" "$RC"
has "attach fails: says what to check" "could not attach $VOL/LimaData.sparsebundle" "$ERR"
check "attach fails: nothing after it runs" "" "$(calls limactl; calls podman)"

fresh
touch "$FIX/start-fails"
run "$CMD" -v "$VOL"
check "limactl start fails: exit 1" "1" "$RC"
has "limactl start fails: names the step" "this step failed: limactl start" "$ERR"
has "limactl start fails: says how to let the image go" "hdiutil detach $MNT" "$ERR"
check "limactl start fails: podman is not touched" "" "$(calls podman)"

fresh
touch "$FIX/no-socket"
run "$CMD" -v "$VOL"
check "the machine has no podman socket: exit 1" "1" "$RC"
has "no podman socket: explains it" "there is no podman socket at $SOCK" "$ERR"
check "no podman socket: podman is not touched" "" "$(calls podman)"

fresh
touch "$FIX/add-fails"
run "$CMD" -v "$VOL"
check "podman connection fails: exit 1" "1" "$RC"
has "podman connection fails: names the step" "this step failed: podman system" "$ERR"
check "podman connection fails: it stops there" "1" "$(calls podman | wc -l | tr -d ' ')"

fresh
touch "$FIX/run-fails"
run "$CMD" -v "$VOL"
check "the test container fails: exit 1 (the old version said 'Warning' and exited 0)" "1" "$RC"
has "the test container fails: says what is done and what is not" "the test container did not run" "$ERR"

# ---- the image is not there
fresh
run "$CMD" -v "$VOL" -e Other
check "no such image: exit 1" "1" "$RC"
has "no such image: names the path and the way to create one" "there is no disk image $VOL/Other.sparsebundle. Check -v and -e, or add \"-c 50g\"" "$ERR"
check "no such image: nothing is run" "uname -s" "$(calls)"
run "$CMD" -v "$TMP/unplugged"
check "the volume is not there: exit 1" "1" "$RC"
has "the volume is not there: says so" "the volume is not mounted: there is no folder $TMP/unplugged" "$ERR"
run "$CMD" -n -v "no such volume $$"
has "-v NAME means /Volumes/NAME" "there is no folder /Volumes/no such volume $$" "$ERR"

fresh
run "$CMD" -v "$VOL" -e Fresh -c 20g --no-test
check "-c SIZE creates the missing image: exit 0" "0" "$RC"
check "-c SIZE: create, then attach" \
"hdiutil create -size 20g -type SPARSEBUNDLE -fs Case-sensitive APFS -volname Fresh $VOL/Fresh.sparsebundle
hdiutil attach $VOL/Fresh.sparsebundle" "$(calls hdiutil)"
reset_calls
run "$CMD" -v "$VOL" -e Fresh --create=20g --no-test
hasnt "-c SIZE with an image that exists: nothing is created" "hdiutil create" "$(calls)"
fresh
touch "$FIX/create-fails"
run "$CMD" -v "$VOL" -e Fresh2 -c 20g
check "create fails: exit 1" "1" "$RC"
check "create fails: nothing is attached" "1" "$(calls hdiutil | wc -l | tr -d ' ')"

# ---- -n
fresh
run "$CMD" -n -v "$VOL"
check "-n: exit 0" "0" "$RC"
check "-n runs nothing" "uname -s" "$(calls)"
check "-n prints the steps" \
"+ hdiutil attach $VOL/LimaData.sparsebundle
+ export LIMA_HOME=/Volumes/LimaData
+ limactl start podman
#   when the machine does not exist yet: limactl start --name=podman --tty=false template://podman
+ podman system connection add lima-podman unix:///Volumes/LimaData/podman/sock/podman.sock
+ podman system connection default lima-podman
+ podman run --rm quay.io/podman/hello
For limactl, run this line in your own shell:
  export LIMA_HOME=/Volumes/LimaData" "$OUT"
run "$CMD" -n -v "$VOL" -e Planned -c 5g
has "-n -c prints the create command" "+ hdiutil create -size 5g -type SPARSEBUNDLE -fs Case-sensitive\\ APFS -volname Planned $VOL/Planned.sparsebundle" "$OUT"
[ ! -e "$VOL/Planned.sparsebundle" ] && ok "-n -c creates nothing" || bad "-n -c creates nothing"
run "$CMD" -n
has "the built-in default is the volume External and the image LimaData" "/Volumes/External" "$OUT$ERR"
check "-n with the defaults runs nothing" "" "$(calls hdiutil; calls limactl; calls podman)"

# ---- options and settings
fresh
run "$CMD" -v "$TMP/my vol" -e "Lima Data" --no-test
check "names with spaces: exit 0" "0" "$RC"
has "names with spaces: the image" "hdiutil attach $TMP/my vol/Lima Data.sparsebundle" "$(calls)"
has "names with spaces: the socket" "unix://$FIX/mnt/Lima Data/podman/sock/podman.sock" "$(calls)"
fresh
run "$CMD" "-v$VOL" -eLimaData --no-test
has "the old attached forms -vVOLUME and -eNAME still work" "hdiutil attach $VOL/LimaData.sparsebundle" "$(calls)"
fresh
MBM_LIMA_VOLUME="$VOL" run "$CMD" --no-test
has "MBM_LIMA_VOLUME names the volume" "hdiutil attach $VOL/LimaData.sparsebundle" "$(calls)"
fresh
MBM_LIMA_VOLUME="$TMP/unplugged" run "$CMD" --volume "$TMP/my vol" --name="Lima Data" --no-test
has "the option wins over the setting" "hdiutil attach $TMP/my vol/Lima Data.sparsebundle" "$(calls)"
fresh
MBM_LIMA_TEMPLATE="template:podman-rootful" run "$CMD" -v "$VOL" --no-test
has "MBM_LIMA_TEMPLATE names the template of a new machine" "limactl start --name=podman --tty=false template:podman-rootful" "$(calls)"

# ---- wrong use, wrong system, missing programs
fresh
run "$CMD" -h
check "-h: exit 0 (the old version exited 1)" "0" "$RC"
run "$CMD" -v "$VOL" extra
check "an argument: exit 2 (the old version ignored it and went ahead)" "2" "$RC"
run "$CMD" -e
check "-e without a value: exit 2" "2" "$RC"
run "$CMD" -e "a/b"
check "a name with a slash: exit 2" "2" "$RC"
check "wrong use runs nothing" "" "$(calls)"

touch "$FIX/linux"
run "$CMD" -v "$VOL"
check "not macOS: exit 1" "1" "$RC"
has "not macOS: says so" "works on macOS only" "$ERR"
check "not macOS: nothing is run" "uname -s" "$(calls)"
rm -f "$FIX/linux"

rm -f "$STUBS/podman"
run "$CMD" -v "$VOL"
has "podman missing: says how to get it" "podman is not installed (brew install podman)" "$ERR"
rm -f "$STUBS/limactl"
run "$CMD" -v "$VOL"
check "limactl missing: exit 1" "1" "$RC"
has "limactl missing: says how to get it" "limactl is not installed (brew install lima)" "$ERR"
check "a missing program: nothing is attached" "" "$(calls hdiutil)"
run "$CMD" -n -v "$VOL"
check "-n needs neither limactl nor podman" "0" "$RC"

finish
