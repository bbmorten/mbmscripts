#!/bin/bash
# Tests for mbm-delete-old-models.   Run:  tests/run.sh delete-old-models    or:  bash tests/commands/delete-old-models.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-delete-old-models"
echo "mbm-delete-old-models"

# The fake ollama: "list" prints $FIX/list, in the layout of the real one (columns padded
# with spaces; some lines here end in spaces); "rm" fails for the model broken:latest.
export FIX="$TMP/fix"
mkdir -p "$FIX"
cat > "$FIX/ollama" <<'EOF_OLLAMA'
case "$1" in
  list) [ -f "$FIX/down" ] && { echo "Error: could not connect to ollama app, is it running?" >&2; exit 1; }
        cat "$FIX/list" ;;
  rm) [ "$2" = "broken:latest" ] && { echo "Error: unable to stop existing running model" >&2; exit 1; }
      echo "deleted '$2'" ;;
esac
exit 0
EOF_OLLAMA
stub ollama "$(cat "$FIX/ollama")"
{
  echo 'NAME                                ID              SIZE      MODIFIED            '
  echo 'Nemotron-3-nano:latest              b725f1117407    24 GB     3 months ago        '
  echo 'FenkoHQ/Foundation-Sec-8B:latest    791f9f9227ad    16 GB     4 months ago'
  echo 'gemma4:latest                       c6eb396dbd59    9.6 GB    6 months ago'
  echo 'three-days:latest                   aaaaaaaaaaa1    1.0 GB    3 days ago'
  echo 'six-days:latest                     aaaaaaaaaaa2    1.1 GB    6 days ago'
  echo 'seven-days:latest                   aaaaaaaaaaa3    1.2 GB    7 days ago'
  echo 'two-weeks:latest                    aaaaaaaaaaa4    2.0 GB    2 weeks ago'
  echo 'five-weeks:latest                   aaaaaaaaaaa5    274 MB    5 weeks ago'
  echo 'a-minute:latest                     aaaaaaaaaaa6    3.0 GB    About a minute ago'
  echo 'an-hour:latest                      aaaaaaaaaaa7    4.0 GB    About an hour ago'
  echo 'hours-23:latest                     aaaaaaaaaaa8    5.0 GB    23 hours ago'
  echo 'hours-47:latest                     aaaaaaaaaaa9    5.5 GB    47 hours ago'
  echo 'just-now:latest                     aaaaaaaaaab1    6.0 GB    Less than a second ago'
  echo 'seven-min:latest                    aaaaaaaaaab2    7.0 GB    7 minutes ago'
  echo 'one-year:latest                     aaaaaaaaaab3    8.0 GB    1 year ago'
  echo 'in-the-cloud:cloud                  aaaaaaaaaab4    -         3 months ago'
  echo 'odd-wording:latest                  aaaaaaaaaab5    1.0 GB    Yesterday'
} > "$FIX/list"
# What a week (the default) must delete, in the order of the list.
WEEK="ollama rm Nemotron-3-nano:latest
ollama rm FenkoHQ/Foundation-Sec-8B:latest
ollama rm gemma4:latest
ollama rm seven-days:latest
ollama rm two-weeks:latest
ollama rm five-weeks:latest
ollama rm one-year:latest
ollama rm in-the-cloud:cloud"
removed() { calls ollama | grep '^ollama rm '; }

# ---- asked for help, it must not delete anything (the old version did)
run "$CMD" --help
check "--help runs nothing" "" "$(calls)"
has "the help says the column is not the last use" "NOT when the model was last used" "$OUT"

# ---- nothing is deleted without a yes
run "$CMD"
check "no terminal and no --yes: exit 1" "1" "$RC"
has "no terminal and no --yes: says how to go ahead" "Add --yes" "$ERR"
check "no terminal and no --yes: only the list was read" "ollama list" "$(calls)"
has "the models are shown with size and age before the question" \
  "  Nemotron-3-nano:latest                       24 GB     3 months ago" "$OUT"
has "a size without a unit (a cloud model) is read too" \
  "  in-the-cloud:cloud                           -         3 months ago" "$OUT"

reset_calls
run "$CMD" -n
check "-n: exit 0" "0" "$RC"
check "-n lists the 8 models a week covers" "8" "$(printf '%s\n' "$OUT" | grep -c '^  ')"
has "-n says nothing was deleted" "Dry run: nothing was deleted." "$OUT"
check "-n deletes nothing" "ollama list" "$(calls)"
reset_calls
run "$CMD" -n -y
check "-n wins over -y" "ollama list" "$(calls)"

reset_calls
if tty_run "n" "$CMD"; then
  has "on a terminal, answer n: the question" "Delete every model listed above? [y/N]" "$OUT"
  has "answer n: says nothing was deleted" "cancelled; nothing was deleted" "$OUT"
  check "answer n: nothing was deleted" "" "$(removed)"
  reset_calls
  tty_run "y" "$CMD"
  check "answer y: the models are deleted" "$WEEK" "$(removed)"
else
  skip "no expect: the terminal answers are not tested"
fi

# ---- with a yes: which models go (the old version kept "2 weeks" to "8 weeks")
reset_calls
run "$CMD" -y
check "--yes: exit 0" "0" "$RC"
check "a week: 7 days, weeks, months and years go; younger ones stay" "$WEEK" "$(removed)"
has "'2 weeks ago' is older than a week" "ollama rm two-weeks:latest" "$(calls)"
check "'About a minute', 'About an hour', 'Less than a second', 47 hours: kept without a warning" \
  "mbm-delete-old-models: kept odd-wording:latest: cannot read its age from \"Yesterday\"" "$ERR"

reset_calls
run "$CMD" -d 30 -y
check "-d 30: a month and older (5 weeks is 35 days)" "ollama rm Nemotron-3-nano:latest
ollama rm FenkoHQ/Foundation-Sec-8B:latest
ollama rm gemma4:latest
ollama rm five-weeks:latest
ollama rm one-year:latest
ollama rm in-the-cloud:cloud" "$(removed)"
reset_calls
run "$CMD" --days=14 -n
has "-d 14: '2 weeks ago' counts as 14 days" "two-weeks:latest" "$OUT"
hasnt "-d 14: '7 days ago' stays" "seven-days:latest" "$OUT"
run "$CMD" --days 15 -n
hasnt "-d 15: '2 weeks ago' stays (the low end counts)" "two-weeks:latest" "$OUT"
run "$CMD" -d 1 -n
has "-d 1: '47 hours ago' is one day" "hours-47:latest" "$OUT"
hasnt "-d 1: '23 hours ago' stays" "hours-23:latest" "$OUT"
run "$CMD" -d 400 -n
check "nothing old enough: exit 0 and says so" "0:No model was pulled or changed 400 days ago or earlier. Nothing to delete." "$RC:$OUT"

reset_calls
LC_ALL=tr_TR.UTF-8 run "$CMD" -y
check "the same under a Turkish locale" "$WEEK" "$(removed)"

# ---- failures
printf '%s\n' 'NAME               ID              SIZE      MODIFIED' \
              'broken:latest      bbbbbbbbbbb1    1.0 GB    3 months ago' \
              'fine:latest        bbbbbbbbbbb2    1.0 GB    3 months ago' > "$FIX/list"
reset_calls
run "$CMD" -y
check "a model that cannot be deleted: exit 1" "1" "$RC"
has "a model that cannot be deleted: named at the end" "could not delete: broken:latest" "$ERR"
has "a model that cannot be deleted: the others still go" "ollama rm fine:latest" "$(calls)"

echo 'NAME    ID    SIZE    MODIFIED' > "$FIX/list"
run "$CMD"
check "no model at all: exit 0, without a question" "0" "$RC"
has "no model at all: says so" "Nothing to delete." "$OUT"

touch "$FIX/down"
reset_calls
run "$CMD" -y
check "ollama does not answer: exit 1" "1" "$RC"
has "ollama does not answer: says what to do" "is the ollama server running? start it with: ollama serve" "$ERR"
rm -f "$FIX/down"

# ---- wrong use, missing program
reset_calls
for bad_days in 0 abc 1.5 -3 07 ""; do
  run "$CMD" -d "$bad_days" -y
  check "-d '$bad_days': exit 2" "2" "$RC"
done
run "$CMD" -d
check "-d without a value: exit 2" "2" "$RC"
run "$CMD" -y gemma4:latest
check "an argument: exit 2" "2" "$RC"
check "wrong use runs nothing" "" "$(calls)"
rm -f "$STUBS/ollama"
run "$CMD" -y
check "ollama missing: exit 1" "1" "$RC"
has "ollama missing: says where to get it" "ollama is not installed (https://ollama.com/download)" "$ERR"

finish
