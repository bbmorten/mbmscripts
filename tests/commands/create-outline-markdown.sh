#!/bin/bash
# Tests for mbm-create-outline-markdown.   Run:  tests/run.sh create-outline-markdown    or:  bash tests/commands/create-outline-markdown.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-create-outline-markdown"
echo "mbm-create-outline-markdown"

W="$TMP/w"
mkdir -p "$W"
cd "$W" || exit 1

# snap - every name and every file's checksum below the working folder
snap() { find . | LC_ALL=C sort; find . -type f -exec cksum {} + | LC_ALL=C sort; }
# bytes FILE - the file, with its line ends and other unprintable bytes made visible
bytes() { od -c "$1" | sed 's/^[0-9]* *//' | tr -s ' \n' ' '; }

# ---- the main job, on a simple outline in a folder with a space
mkdir "my course"
printf '# Course\n\nSome text.\n\n- Introduction\n- Getting Started\n- Summary\n' > "my course/outline.md"
outline_before="$(cksum < "my course/outline.md")"
run "$CMD" "my course/outline.md" "my course/index.md"
check "OUTLINE OUTPUT: exit 0" "0" "$RC"
check "the items are links, the rest is as it was" \
  "$(printf '# Course\n\nSome text.\n\n- [Introduction](gen_introduction.md)\n- [Getting Started](gen_getting_started.md)\n- [Summary](gen_summary.md)')" \
  "$(cat "my course/index.md")"
check "a page per item, next to the output" "$(printf 'gen_getting_started.md\ngen_introduction.md\ngen_summary.md\nindex.md\noutline.md')" "$(ls "my course")"
check "a page holds the item as its heading" "# Getting Started" "$(cat "my course/gen_getting_started.md")"
check "the outline itself is not changed" "$outline_before" "$(cksum < "my course/outline.md")"
has "says what it created" "created my course/gen_summary.md" "$OUT"
has "the last line counts" "Pages created in my course: 3; there already: 0; the linked outline is in my course/index.md." "$OUT"
check "nothing is written into the working folder" "my course" "$(ls)"

# ---- the old three-argument form: DIR OUTLINE OUTPUT
mkdir old
printf '# Course\n\n- Introduction\n- Getting Started\n- Summary\n' > old/outline.md
WANT_OLD="$(printf '# Course\n\n- [Introduction](gen_introduction.md)\n- [Getting Started](gen_getting_started.md)\n- [Summary](gen_summary.md)')"
run "$CMD" old outline.md out.md
check "DIR OUTLINE OUTPUT from outside the folder: exit 0" "0" "$RC"
check "DIR OUTLINE OUTPUT from outside: the linked outline is in DIR" "$WANT_OLD" "$(cat old/out.md 2>&1)"
check "DIR OUTLINE OUTPUT from outside: the outline is not changed (the old version left it half linked)" \
  "$(printf '# Course\n\n- Introduction\n- Getting Started\n- Summary')" "$(cat old/outline.md)"
check "DIR OUTLINE OUTPUT: pages in DIR, and no .bak file" "$(printf 'gen_getting_started.md\ngen_introduction.md\ngen_summary.md\nout.md\noutline.md')" "$(ls old)"
mkdir old2
cp old/outline.md old2/outline.md
( cd old2 && "$CMD" . outline.md out.md >/dev/null 2>&1 )
check "DIR OUTLINE OUTPUT from inside the folder (.)" "$WANT_OLD" "$(cat old2/out.md 2>&1)"

# ---- which lines are items, and awkward item texts
mkdir plan
cat > plan/outline.md <<'EOF_OUTLINE'
---
tags:
  - yaml item
---
# Plan

- Intro
- Intro to Networking
- TCP/IP: Q&A
- C.I.A
  - Nested item
    * Deep *star* item
+ Plus item
- [Linked](x.md)
- see [this](y.md) too
- [ref][label]
- [ ] Task open
- [x] Task done
- İstanbul ğüş
- ???
- Intro
- 100% "quoted" \back & [brackets]
1. Numbered
- - -
* * *
---

```sh
- in code
```
- What's new? (2024)
-not an item
- last line
EOF_OUTLINE
echo "my own text" > plan/gen_intro.md
before_outline="$(cksum < plan/outline.md)"
run "$CMD" plan/outline.md plan/index.md
check "a mixed outline: exit 0" "0" "$RC"
line() { sed -n "$1p" plan/index.md; }
check "front matter is left alone" "  - yaml item" "$(line 3)"
check "an item that is the start of another one" "- [Intro](gen_intro.md)" "$(line 7)"
check "the longer item is linked once, as a whole (the old version linked 'Intro' inside it)" "- [Intro to Networking](gen_intro_to_networking.md)" "$(line 8)"
check "/ : & in an item (the old version failed on /)" "- [TCP/IP: Q&A](gen_tcp_ip_q_a.md)" "$(line 9)"
check "dots stay in the page name" "- [C.I.A](gen_c.i.a.md)" "$(line 10)"
check "a nested item" "  - [Nested item](gen_nested_item.md)" "$(line 11)"
check "a * item, deeper" "    * [Deep *star* item](gen_deep_star_item.md)" "$(line 12)"
check "a + item" "+ [Plus item](gen_plus_item.md)" "$(line 13)"
check "an item that is a link already" "- [Linked](x.md)" "$(line 14)"
check "an item that holds a link" "- see [this](y.md) too" "$(line 15)"
check "an item that is a reference link" "- [ref][label]" "$(line 16)"
check "an open task keeps its box" "- [ ] [Task open](gen_task_open.md)" "$(line 17)"
check "a done task keeps its box" "- [x] [Task done](gen_task_done.md)" "$(line 18)"
check "letters outside ASCII stay as they are" "- [İstanbul ğüş](gen_İstanbul_ğüş.md)" "$(line 19)"
check "an item that gives no page name is left as it is" "- ???" "$(line 20)"
has "and that is reported with its line number" "line 20: no page name can be made from '???'" "$ERR"
check "the same item again links to the same page" "- [Intro](gen_intro.md)" "$(line 21)"
check "% \" \\ & [ ] in an item" '- [100% "quoted" \back & [brackets]](gen_100_quoted_back_brackets.md)' "$(line 22)"
check "a numbered item is left alone" "1. Numbered" "$(line 23)"
check "- - - is a rule, not an item" "- - -" "$(line 24)"
check "* * * is a rule, not an item" "* * *" "$(line 25)"
check "a list inside a code block is left alone" "- in code" "$(line 29)"
check "' ? ( ) in an item" "- [What's new? (2024)](gen_what_s_new_2024.md)" "$(line 31)"
check "a dash without a space is not an item" "-not an item" "$(line 32)"
check "the last line" "- [last line](gen_last_line.md)" "$(line 33)"
check "no line is added or lost" "$(wc -l < plan/outline.md | tr -d ' ')" "$(wc -l < plan/index.md | tr -d ' ')"
check "a page that existed is not overwritten" "my own text" "$(cat plan/gen_intro.md)"
check "the heading of a page is the item text" '# 100% "quoted" \back & [brackets]' "$(cat plan/gen_100_quoted_back_brackets.md)"
check "a task's page has no box in its heading" "# Task open" "$(cat plan/gen_task_open.md)"
has "the count: one page was there, 'Intro' twice counts once" "Pages created in plan: 12; there already: 1;" "$OUT"
check "the outline is not changed" "$before_outline" "$(cksum < plan/outline.md)"
check "the examples of the page-name rule in the help hold" "gen_getting_started.md gen_tcp_ip_q_a.md" "$(ls "my course/gen_getting_started.md" plan/gen_tcp_ip_q_a.md | sed 's|.*/||' | tr '\n' ' ' | sed 's/ $//')"

mkdir tr
printf -- '- TITLE IN CAPITALS\n' > tr/outline.md
LC_ALL=tr_TR.UTF-8 run "$CMD" tr/outline.md tr/index.md
check "in a Turkish locale I still becomes i, not a dotless i" "- [TITLE IN CAPITALS](gen_title_in_capitals.md)" "$(cat tr/index.md)"

mkdir trail
printf -- '- Two spaces after  \n-\tTab after the dash\n' > trail/outline.md
run "$CMD" trail/outline.md
check "spaces at the end of an item stay outside the link; a tab after the dash" "$(printf -- '- [Two spaces after](gen_two_spaces_after.md)  \n-\t[Tab after the dash](gen_tab_after_the_dash.md)')" "$OUT"

mkdir crlf
printf '# T\r\n- One Item\r\n' > crlf/outline.md
run "$CMD" crlf/outline.md crlf/index.md
check "CRLF line ends stay, and are not part of the link" "# T \r \n - [ O n e I t e m ] ( g e n _ o n e _ i t e m . m d ) \r \n " "$(bytes crlf/index.md)"
check "CRLF: the page name has no carriage return" "$(printf 'gen_one_item.md\nindex.md\noutline.md')" "$(ls crlf)"

# ---- standard output, -d, -p
mkdir -p std docs
printf -- '- First Topic\n- Second Topic\n' > std/outline.md
run "$CMD" std/outline.md
check "without OUTPUT the linked outline goes to standard output" "$(printf -- '- [First Topic](gen_first_topic.md)\n- [Second Topic](gen_second_topic.md)')" "$OUT"
has "then the notes go to standard error" "created std/gen_first_topic.md" "$ERR"
check "without OUTPUT the pages are next to the outline" "$(printf 'gen_first_topic.md\ngen_second_topic.md\noutline.md')" "$(ls std)"
run "$CMD" -p topic- -d docs std/outline.md
check "-p PREFIX names the pages and the links" "$(printf -- '- [First Topic](topic-first_topic.md)\n- [Second Topic](topic-second_topic.md)')" "$OUT"
check "-d PAGES_DIR is where the pages go" "$(printf 'topic-first_topic.md\ntopic-second_topic.md')" "$(ls docs)"
run "$CMD" --prefix "" --pages-dir docs std/outline.md docs/index.md
check "--prefix '' and --pages-dir" "$(printf 'first_topic.md\nindex.md\nsecond_topic.md\ntopic-first_topic.md\ntopic-second_topic.md')" "$(ls docs)"

# ---- -n
before="$(snap)"
run "$CMD" -n -p new- std/outline.md std/new-index.md
check "-n: exit 0" "0" "$RC"
check "-n writes nothing" "$before" "$(snap)"
check "-n prints the linked outline" "$(printf -- '- [First Topic](new-first_topic.md)\n- [Second Topic](new-second_topic.md)')" "$OUT"
has "-n lists the pages it would create" "would create std/new-second_topic.md" "$ERR"
has "-n counts" "Pages that would be created in std: 2; there already: 0." "$ERR"
run "$CMD" std/outline.md docs/index.md --dry-run
check "--dry-run, given last, with an OUTPUT that exists: writes nothing" "$before" "$(snap)"
has "--dry-run says that OUTPUT would be overwritten" "would overwrite docs/index.md" "$ERR"

# ---- an OUTPUT that exists
echo "precious" > std/index.md
before="$(snap)"
run "$CMD" -p ask- std/outline.md std/index.md
check "OUTPUT exists, no terminal, no --yes: exit 1" "1" "$RC"
has "OUTPUT exists, no terminal: the message names --yes" "Add --yes to go ahead" "$ERR"
check "OUTPUT exists, no terminal: nothing is written, no page either" "$before" "$(snap)"
if tty_run "n" "$CMD" -p ask- std/outline.md std/index.md; then
  # (tty_run cannot tell the exit status: it reports the one of its own "tr".)
  has "on a terminal it asks" "Overwrite std/index.md? [y/N]" "$OUT"
  check "answer n: nothing is written, no page either" "$before" "$(snap)"
  has "answer n: it says that nothing was done" "was not overwritten and no page was created" "$OUT"
  tty_run "y" "$CMD" -p ask- std/outline.md std/index.md
  check "answer y: OUTPUT is overwritten" "- [First Topic](ask-first_topic.md)" "$(head -n 1 std/index.md)"
else
  skip "expect is not installed: the question on a terminal is not tested"
fi
echo "precious" > std/index.md
run "$CMD" -y std/outline.md std/index.md
check "-y overwrites without asking" "- [First Topic](gen_first_topic.md)" "$(head -n 1 std/index.md)"
echo "precious" > std/index.md
run "$CMD" --yes std/outline.md std/index.md
check "--yes is the same" "- [First Topic](gen_first_topic.md)" "$(head -n 1 std/index.md)"

# ---- wrong use
before="$(snap)"
run "$CMD"
check "no argument: exit 2" "2" "$RC"
has "no argument: points to --help" "--help" "$ERR"
run "$CMD" a b c d
check "four arguments: exit 2" "2" "$RC"
run "$CMD" nope.md
check "an outline that does not exist: exit 1" "1" "$RC"
has "an outline that does not exist: the message names it" "no such file: nope.md" "$ERR"
run "$CMD" -y std/outline.md std/outline.md
check "OUTPUT is the outline itself: exit 1" "1" "$RC"
has "OUTPUT is the outline itself: the message says why" "never changed" "$ERR"
run "$CMD" -y std/outline.md ./std/../std/outline.md
check "OUTPUT is the outline by another path: exit 1" "1" "$RC"
run "$CMD" -d nodir std/outline.md
check "a pages folder that does not exist: exit 1" "1" "$RC"
has "a pages folder that does not exist: the message names it" "no such folder for the pages: nodir" "$ERR"
run "$CMD" std/outline.md nodir/index.md
check "an OUTPUT in a folder that does not exist: exit 1" "1" "$RC"
run "$CMD" -p a/b std/outline.md
check "a prefix with a slash: exit 2" "2" "$RC"
run "$CMD" -d docs std outline.md index2.md
check "-d with the three-argument form: exit 2" "2" "$RC"
run "$CMD" std/outline.md -d
check "-d without a value: exit 2" "2" "$RC"
run "$CMD" -x std/outline.md
check "an unknown option: exit 2" "2" "$RC"
check "wrong use changes nothing" "$before" "$(snap)"

# ---- the examples in the help
E="$TMP/examples"
mkdir -p "$E/course" "$E/docs"
printf -- '- Week One\n- Week Two\n' > "$E/course/outline.md"
cp "$E/course/outline.md" "$E/outline.md"
cd "$E" || exit 1
run "$CMD" course/outline.md course/index.md
check "example: OUTLINE OUTPUT" "- [Week One](gen_week_one.md)" "$(head -n 1 course/index.md 2>&1)"
before="$(snap)"
run "$CMD" -n outline.md
[ "$RC" = 0 ] && [ "$before" = "$(snap)" ] && ok "example: -n OUTLINE" || bad "example: -n OUTLINE"
"$CMD" -p topic- -d docs outline.md > docs/index.md 2>/dev/null </dev/null
check "example: -p -d OUTLINE > FILE" "$(printf 'index.md\ntopic-week_one.md\ntopic-week_two.md')|- [Week Two](topic-week_two.md)" "$(ls docs)|$(tail -n 1 docs/index.md)"
rm course/index.md
run "$CMD" course outline.md index.md
check "example: DIR OUTLINE OUTPUT" "- [Week Two](gen_week_two.md)" "$(tail -n 1 course/index.md 2>&1)"

finish
