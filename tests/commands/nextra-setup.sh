#!/bin/bash
# Tests for mbm-nextra-setup.   Run:  tests/run.sh nextra-setup    or:  bash tests/commands/nextra-setup.sh
#
# Offline by default. With TEST_NETWORK=1 the last section also installs the generated project
# with the real npm, builds it and asks the built site for its pages on 127.0.0.1 (about a minute):
#     TEST_NETWORK=1 bash tests/commands/nextra-setup.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-nextra-setup"
echo "mbm-nextra-setup"

W="$TMP/w"
mkdir -p "$W"
cd "$W" || exit 1

# files DIR - the files of a project, sorted, one per line
files() { (cd "$1" && find . -type f | LC_ALL=C sort); }
# state DIR - a line per file with its checksum: to see that nothing changed
state() { (cd "$1" && find . -type f -exec cksum {} + | LC_ALL=C sort); }
# json FILE PERL-EXPRESSION - a value of a JSON file ($j is the decoded file)
json() { perl -MJSON::PP -e 'local $/; open my $f, "<", $ARGV[0] or die; my $j = decode_json(<$f>); print eval $ARGV[1]' "$1" "$2" 2>&1; }

COMMON="./.dockerignore
./.gitignore
./Dockerfile
./README.md
./app/[[...mdxPath]]/page.jsx
./app/layout.jsx
./content/_meta.js
./content/api/index.mdx
./content/docs/_meta.js
./content/docs/advanced-usage.mdx
./content/docs/configuration.mdx
./content/docs/getting-started.mdx
./content/docs/index.mdx
./content/index.mdx"
DOCKER_SET="$COMMON
./docker-compose.yml
./mdx-components.js
./next.config.mjs
./package.json
./public/.gitkeep"
PODMAN_SET="$COMMON
./mdx-components.js
./next.config.mjs
./package.json
./podman-run.sh
./public/.gitkeep"

# ---- the main job
run "$CMD" my-docs
check "a project is created (exit 0)" "0" "$RC"
check "nothing on standard error" "" "$ERR"
check "exactly the documented files" "$DOCKER_SET" "$(files my-docs)"
has "it says what it wrote" "Wrote 19 files into my-docs" "$OUT"
has "it says what to do next" "cd my-docs && npm install && npm run dev" "$OUT"
check "no placeholder is left in any file" "" "$(grep -rl '@NAME@\|@PORT@\|@NODE@' my-docs)"
check "nothing is written outside the project folder" "my-docs" "$(ls -A "$W")"
check "nothing is written into HOME" "" "$(ls -A "$HOME")"

if command -v perl >/dev/null 2>&1 && perl -MJSON::PP -e 1 2>/dev/null; then
  check "package.json parses and is named after the folder" "my-docs" "$(json my-docs/package.json '$j->{name}')"
  check "the versions are the ones that were built" "16.4.6 4.6.1 4.6.1 19.3.1 19.3.1 1.6.0 4.1.12" \
    "$(json my-docs/package.json 'join " ", @{$j->{dependencies}}{qw(next nextra nextra-theme-docs react react-dom)}, $j->{devDependencies}{pagefind}, $j->{overrides}{zod}')"
  check "every version is exact (no ^, ~ or latest)" "" \
    "$(json my-docs/package.json 'join " ", grep { !/^\d+\.\d+\.\d+$/ } values %{$j->{dependencies}}, values %{$j->{devDependencies}}, values %{$j->{overrides}}')"
  check "the port is in the dev and start scripts" "next dev -p 3000|next start -p 3000" \
    "$(json my-docs/package.json '"$j->{scripts}{dev}|$j->{scripts}{start}"')"
  check "no 'next export' script (Next.js removed that command)" "" "$(json my-docs/package.json '$j->{scripts}{export}')"
else
  skip "perl with JSON::PP is not installed: package.json is not parsed"
fi
for v in "nextra 4.6.1" "next 16.4.6" "react 19.3.1" "pagefind 1.6.0" "zod 4.1.12"; do
  has "the help names the version: $v" "$v" "$("$CMD" --help)"
done

# The old version put the API page in pages/api, where Next.js expects request handlers: /api answered 500.
check "the API page is an ordinary page, not under pages/api" "" "$(find my-docs -path '*pages/api*')"
has "the Dockerfile asks for the standalone build it copies" "BUILD_STANDALONE=1" "$(cat my-docs/Dockerfile)"
has "next.config.mjs makes the standalone build when asked" "process.env.BUILD_STANDALONE ? 'standalone'" "$(cat my-docs/next.config.mjs)"
has "the Dockerfile installs without a lock file too" "if [ -f package-lock.json ]; then npm ci; else npm install; fi" "$(cat my-docs/Dockerfile)"
has "the container files use a Node.js that Next.js 16 accepts" "FROM node:24-slim" "$(cat my-docs/Dockerfile)"
has "docker-compose.yml publishes the port" '- "3000:3000"' "$(cat my-docs/docker-compose.yml)"
if real node; then
  run node --check my-docs/next.config.mjs
  check "next.config.mjs is valid JavaScript" "0" "$RC"
  run node --check my-docs/content/docs/_meta.js
  check "a _meta.js is valid JavaScript" "0" "$RC"
  rm -f "$STUBS/node"
else
  skip "node is not installed: the generated .js files are not syntax-checked"
fi

# ---- the default folder, and the examples of the help
run "$CMD"
check "without an argument the folder is nextra-docs" "$DOCKER_SET" "$(files nextra-docs)"
run "$CMD" --podman --port 8080 "Team Handbook"
check "example: --podman --port 8080 \"Team Handbook\" (exit 0)" "0" "$RC"
check "--podman writes podman-run.sh and no docker-compose.yml" "$PODMAN_SET" "$(files "Team Handbook")"
[ -x "Team Handbook/podman-run.sh" ] && ok "podman-run.sh is executable" || bad "podman-run.sh is executable"
has "a name with a space and capitals becomes a slug" '"name": "team-handbook"' "$(cat "Team Handbook/package.json")"
has "the next step quotes a folder name with a space" 'cd Team\ Handbook && ./podman-run.sh' "$OUT"
check "--port reaches every file that carries the port" "Dockerfile README.md content/docs/getting-started.mdx content/docs/configuration.mdx package.json podman-run.sh" \
  "$(cd "Team Handbook" && grep -l 8080 Dockerfile README.md content/docs/getting-started.mdx content/docs/configuration.mdx package.json podman-run.sh | tr '\n' ' ' | sed 's/ $//')"
check "and the default port is nowhere" "" "$(grep -rl 3000 "Team Handbook")"

# ---- options
run "$CMD" -p 8081 short-p
has "-p PORT" "next dev -p 8081" "$(cat short-p/package.json)"
run "$CMD" --port=8082 equals-p
has "--port=PORT" "EXPOSE 8082" "$(cat equals-p/Dockerfile)"
run "$CMD" after-dir --podman -q
check "options may follow the folder" "$PODMAN_SET" "$(files after-dir)"
check "--quiet prints nothing" "" "$OUT$ERR"
run "$CMD" -- -docs
check "after --, a name with a leading dash is a folder" "$DOCKER_SET" "$(files ./-docs)"
has "and its project name has no dash in front" '"name": "docs"' "$(cat ./-docs/package.json)"
run "$CMD" "it's \"quoted\""
check "a name with quote characters (exit 0)" "0" "$RC"
has "a name with quote characters gives a clean project name" '"name": "it-s-quoted"' "$(cat "it's \"quoted\"/package.json")"
run env LC_ALL=tr_TR.UTF-8 "$CMD" "Döküman WIKI"
has "Turkish letters and a Turkish locale still give a plain a-z name" '"name": "d-k-man-wiki"' "$(cat "Döküman WIKI/package.json")"
mkdir "Empty One"
OUT="$(cd "Empty One" && "$CMD" . 2>&1 </dev/null)"; RC=$?
check "an existing empty folder needs no confirmation, also as '.'" "0" "$RC"
has "'.' is named after the folder it is" '"name": "empty-one"' "$(cat "Empty One/package.json")"

# ---- --dry-run
before="$(ls -A "$W")"
run "$CMD" -n dry
check "--dry-run exits 0" "0" "$RC"
check "--dry-run creates nothing" "$before" "$(ls -A "$W")"
check "--dry-run lists the 19 files as new" "19" "$(printf '%s\n' "$OUT" | grep -c '^  create   ')"
has "--dry-run names a file" "  create   app/[[...mdxPath]]/page.jsx" "$OUT"
stub npm 'exit 0'
run "$CMD" --dry-run --install --podman dry
has "--dry-run with --podman lists the runner" "  create   podman-run.sh" "$OUT"
has "--dry-run with --install says what it would run" "Would then run: npm install" "$OUT"
check "--dry-run does not run npm" "" "$(calls npm)"
check "--dry-run with --install still creates nothing" "$before" "$(ls -A "$W")"

# ---- a folder that already has files: never deleted, never silently overwritten
mkdir keep
echo "years of notes" > keep/PRECIOUS
echo "my own readme" > keep/README.md
before="$(state keep)"
run "$CMD" keep
check "not a terminal, no --yes: refused (exit 1)" "1" "$RC"
has "the refusal names --yes" "Add --yes" "$ERR"
check "refused: nothing in the folder changed" "$before" "$(state keep)"
run_in "y
" "$CMD" keep                 # the old version deleted the whole folder on a piped "y"
check "an answer on a pipe is not a confirmation (exit 1)" "1" "$RC"
check "an answer on a pipe: nothing changed" "$before" "$(state keep)"
run "$CMD" -n keep
has "--dry-run marks the file it would replace" "  replace  README.md" "$OUT"
has "--dry-run counts the replacements" "(1 of them replace" "$OUT"
check "--dry-run on a folder with files changes nothing" "$before" "$(state keep)"
# (tty_run's RC is not the command's exit status, so a shell prints it on the terminal.)
on_tty='"$0" "$@"; echo "exit status $?"'
if tty_run "n" /bin/sh -c "$on_tty" "$CMD" keep; then
  has "on a terminal it asks" "keep is not empty. Write 19 files into it, replacing 1 of its files? [y/N]" "$OUT"
  has "answer n: exit 1" "exit status 1" "$OUT"
  has "answer n: it says that nothing was written" "nothing written" "$OUT"
  check "answer n: nothing changed" "$before" "$(state keep)"
  tty_run "y" /bin/sh -c "$on_tty" "$CMD" keep
  has "answer y: exit 0" "exit status 0" "$OUT"
  check "answer y: the project is written, the other file stays" \
    "$(printf '%s\n' "./PRECIOUS" "$DOCKER_SET" | LC_ALL=C sort)" "$(files keep)"
  check "answer y: the other file is untouched" "years of notes" "$(cat keep/PRECIOUS)"
else
  skip "expect is not installed: the question on a terminal is not tested"
fi
mkdir keep2
echo "years of notes" > keep2/PRECIOUS
echo "my own readme" > keep2/README.md
run "$CMD" --yes keep2
check "--yes writes into the folder (exit 0)" "0" "$RC"
check "--yes: the other file is untouched" "years of notes" "$(cat keep2/PRECIOUS)"
has "--yes: a file of the same name is replaced" "# keep2" "$(head -n 1 keep2/README.md)"

# ---- --install
reset_calls
stub npm 'pwd > "$STUB_LOG.cwd"; echo "fake npm ran"'
run "$CMD" --install "with install"
check "--install exits 0" "0" "$RC"
check "--install runs npm install, once" "npm install" "$(calls npm)"
check "--install runs it inside the project" "$W/with install" "$(cat "$STUB_LOG.cwd")"
has "after --install the next step is npm run dev" "cd with\ install && npm run dev" "$OUT"
stub npm 'exit 1'
run "$CMD" --install npm-fails
check "npm install fails: exit 1" "1" "$RC"
has "npm install fails: the message says where to run it again" "npm install failed in npm-fails" "$ERR"
rm -f "$STUBS/npm"
if command -v npm >/dev/null 2>&1; then
  skip "npm is in a system folder here: the missing-npm message is not tested"
else
  run "$CMD" --install no-npm
  check "--install without npm: exit 1" "1" "$RC"
  has "--install without npm: says how to get it" "npm is not installed (get Node.js from https://nodejs.org" "$ERR"
  [ ! -e no-npm ] && ok "--install without npm: nothing is written first" || bad "--install without npm: nothing is written first"
fi
run "$CMD" no-npm
check "without --install, npm is not needed" "0" "$RC"
guard npm
reset_calls

# ---- wrong use
before="$(ls -A "$W")"
run "$CMD" one two
check "two folders: exit 2" "2" "$RC"
has "two folders: the message points to --help" "(see: mbm-nextra-setup --help)" "$ERR"
run "$CMD" ""
check "an empty folder name: exit 2" "2" "$RC"
for p in abc 0 70000 99999999999999999999; do
  run "$CMD" --port "$p" badport
  check "--port $p: exit 2" "2" "$RC"
done
run "$CMD" badport -p
check "-p without a number: exit 2" "2" "$RC"
run "$CMD" --help-me x
check "an unknown option: exit 2" "2" "$RC"
check "wrong use creates nothing" "$before" "$(ls -A "$W")"
echo "a file" > in-the-way
run "$CMD" in-the-way
check "a file of that name: exit 1" "1" "$RC"
has "a file of that name: the message says so" "in-the-way exists and is not a folder" "$ERR"
run "$CMD" in-the-way/sub
check "a folder that cannot be created: exit 1" "1" "$RC"

# ---- the real thing: install, build, serve (needs the network; not run by default)
if [ "${TEST_NETWORK:-}" != 1 ]; then
  skip "install and build of the generated project (set TEST_NETWORK=1)"
elif ! real node || ! real_npm="$(export PATH="$REAL_PATH"; command -v npm)"; then
  skip "node and npm are not installed: the generated project is not built"
else
  # Not `real npm`: an npm that is a shell wrapper looks for node next to the path it was called by.
  stub npm "exec '$real_npm' \"\$@\""
  export NEXT_TELEMETRY_DISABLED=1 npm_config_update_notifier=false npm_config_audit=false npm_config_fund=false
  run "$CMD" --install --quiet net
  check "network: --install with the real npm (exit 0)" "0" "$RC"
  cd net || exit 1
  check "network: the installed versions are the pinned ones" "16.4.6 4.6.1 4.6.1 19.3.1 19.3.1 1.6.0 4.1.12" \
    "$(for p in next nextra nextra-theme-docs react react-dom pagefind zod; do node -p "require('./node_modules/$p/package.json').version"; done | tr '\n' ' ' | sed 's/ $//')"
  BUILD_STANDALONE=1 npm run build > build.log 2>&1
  check "network: npm run build (exit 0)" "0" "$?"
  tail -n 12 build.log | sed 's/^/        /'
  has "network: the search index covers the six pages" "Indexed 6 pages" "$(cat build.log)"
  [ -f .next/standalone/server.js ] && ok "network: the standalone server the Dockerfile copies exists" || bad "network: the standalone server the Dockerfile copies exists"
  # What the Dockerfile does: the standalone server with public/ and .next/static next to it.
  cp -R public .next/standalone/public && cp -R .next/static .next/standalone/.next/static
  PORT=39431 HOSTNAME=127.0.0.1 node .next/standalone/server.js > server.log 2>&1 &
  server=$!
  pages="$(node -e '
    const sleep = ms => new Promise(r => setTimeout(r, ms));
    (async () => {
      for (let i = 0; i < 60; i++) { try { await fetch("http://127.0.0.1:39431/"); break } catch { await sleep(250) } }
      for (const p of ["/", "/docs", "/docs/getting-started", "/docs/advanced-usage", "/docs/configuration", "/api", "/_pagefind/pagefind.js", "/no-such-page"]) {
        try { const r = await fetch("http://127.0.0.1:39431" + p, { signal: AbortSignal.timeout(10000) }); const t = await r.text();
              console.log([p, r.status, (t.match(/<title>[^<]*<\/title>/) || [""])[0]].filter(Boolean).join(" ")) }
        catch (e) { console.log(p, "ERROR", e.name) }
      }
    })()' 2>&1)"
  kill "$server" 2>/dev/null
  wait "$server" 2>/dev/null
  check "network: the built site serves its pages" "/ 200 <title>Welcome to My Documentation - My Documentation</title>
/docs 200 <title>Documentation - My Documentation</title>
/docs/getting-started 200 <title>Getting Started - My Documentation</title>
/docs/advanced-usage 200 <title>Advanced Usage - My Documentation</title>
/docs/configuration 200 <title>Configuration - My Documentation</title>
/api 200 <title>API Reference - My Documentation</title>
/_pagefind/pagefind.js 200
/no-such-page 404 <title>My Documentation</title>" "$pages"
  cd "$W" || exit 1
fi

finish
