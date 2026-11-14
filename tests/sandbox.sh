#!/bin/bash
# tests/sandbox.sh - try a command by hand inside the test sandbox (see tests/lib.sh): a
# temporary HOME, no MBM_* settings, only system programs, and guards on everything that
# reaches outside (ssh, rsync, sudo, docker, ...). Use it instead of running a script under
# development directly.
#
# Usage:
#   tests/sandbox.sh [-s NAME]... [-r NAME]... [-k] [--] COMMAND [ARG...]
#
# Options:
#   -s NAME   a fake program NAME that succeeds silently (its calls are listed afterwards)
#   -r NAME   allow the real program NAME (for example tshark, to read a capture file)
#   -k        keep the sandbox folder afterwards and print its path
#
# The command runs in an empty folder, $TMP/work. ROOT, BIN, LIBEXEC, TMP and STUB_LOG are in
# its environment. Afterwards the exit status and the calls of fake programs are printed.
#
# Examples:
#   tests/sandbox.sh bin/mbm-du --help
#   tests/sandbox.sh -s docker bin/mbm-docker-cmdline web
#   tests/sandbox.sh bash -c 'mkdir "a b"; touch "a b/x.pdf"; "$BIN/mbm-list-folders-with-pdf" .'

case "${1:-}" in
  ''|-h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
esac

. "$(dirname "$0")/lib.sh"

keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    -s) stub "$2"; shift 2 ;;
    -r) real "$2" || { echo "sandbox: $2 is not installed" >&2; exit 1; }; shift 2 ;;
    -k) keep=1; shift ;;
    --) shift; break ;;
    -*) echo "sandbox: unknown option $1 (see: tests/sandbox.sh --help)" >&2; exit 2 ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { echo "sandbox: no command given" >&2; exit 2; }

# A command given relative to the repository still works from the empty working folder.
case "$1" in
  /*) ;;
  */*) [ -e "$PWD/$1" ] && set -- "$PWD/$1" "${@:2}" ;;
esac

mkdir -p "$TMP/work"
export ROOT BIN LIBEXEC TMP
( cd "$TMP/work" && "$@" )
rc=$?
echo "--- exit status: $rc"
if [ -s "$STUB_LOG" ]; then
  echo "--- calls of fake programs:"
  sed 's/^/    /' "$STUB_LOG"
fi
if [ "$keep" = 1 ]; then
  trap - EXIT
  echo "--- sandbox kept: $TMP"
fi
exit "$rc"
