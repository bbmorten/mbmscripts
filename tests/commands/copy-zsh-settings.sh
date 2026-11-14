#!/bin/bash
# Tests for mbm-copy-zsh-settings.   Run:  tests/run.sh copy-zsh-settings    or:  bash tests/commands/copy-zsh-settings.sh
. "$(dirname "$0")/../lib.sh"
CMD="$BIN/mbm-copy-zsh-settings"
echo "mbm-copy-zsh-settings"

# Nothing connects anywhere. The fake ssh is "the other machine": it runs what it is given
# with sh, with $TMP/remote as the home folder there. The fake rsync only logs its call.
export TEST_TMP="$TMP"
R="$TMP/remote"
RBIN="$TMP/rbin"                      # programs only the other machine has
mkdir -p "$RBIN"
FAKE_REMOTE='shift; cd "$TEST_TMP/remote" && HOME="$TEST_TMP/remote" SHELL=/bin/bash PATH="$TEST_TMP/rbin:$PATH" sh -c "$*"'
stub ssh "$FAKE_REMOTE"
stub rsync

# This machine: a configuration with a secret in .zshenv, and files that must never travel.
mkdir -p "$HOME/.config/zsh" "$HOME/.oh-my-zsh/custom/themes" "$HOME/.oh-my-zsh/lib"
echo 'export PATH=/x:$PATH' > "$HOME/.zshrc"
echo 'export API_KEY=secret-123' > "$HOME/.zshenv"
echo 'p10k' > "$HOME/.p10k.zsh"
echo 'alias x=y' > "$HOME/.config/zsh/a b.zsh"
echo 'theme' > "$HOME/.oh-my-zsh/custom/themes/mine.zsh-theme"
echo 'history' > "$HOME/.zsh_history"
echo 'dump' > "$HOME/.zcompdump"
# The other machine: an older .zshrc and its own oh-my-zsh; no .config at all.
new_remote() {
  rm -rf "$R"
  mkdir -p "$R/.oh-my-zsh/custom"
  echo 'old remote zshrc' > "$R/.zshrc"
  echo 'their plugin' > "$R/.oh-my-zsh/custom/theirs.zsh"
}
remote_tree() { (cd "$R" && find . | sort); }
new_remote
export MBM_REMOTE_HOST=mac.example MBM_REMOTE_USER=alice
FILES_CALL="$HOME/.zshrc $HOME/.zshenv $HOME/.p10k.zsh alice@mac.example:"

# ---- help
run "$CMD" --help
has "the help says that the files travel as they are" "exactly as they are" "$OUT"
has "the help names the file that often holds keys, and the way out" "leave it out with --skip" "$OUT"
has "the help says what is never copied" "Never copied: .zsh_history, .zcompdump*, oh-my-zsh itself" "$OUT"
has "the help says where the oh-my-zsh installer comes from" "github.com/ohmyzsh/ohmyzsh" "$OUT"
check "help creates nothing in the home folder (the old one made a log folder)" "" "$(find "$HOME" -name '.local')"

# ---- wrong use
run env -u MBM_REMOTE_HOST "$CMD"
check "no host: exit 2" "2" "$RC"
has "no host: names the option" "--host" "$ERR"
has "no host: names the setting" "MBM_REMOTE_HOST" "$ERR"
run "$CMD" --skip zshenv
check "--skip with a name that is never copied (a typing error): exit 2" "2" "$RC"
has "--skip with an unknown name: said" "not one of the names" "$ERR"
run "$CMD" --skip
check "--skip without a name: exit 2" "2" "$RC"
run "$CMD" -H
check "-H without a host: exit 2" "2" "$RC"
run "$CMD" extra
check "a surplus argument: exit 2" "2" "$RC"
run "$CMD" -H "-oProxyCommand=x@y"
check "a host that looks like an ssh option: exit 2" "2" "$RC"
check "wrong use runs nothing" "" "$(calls)"
mkdir -p "$TMP/emptyhome"
run env HOME="$TMP/emptyhome" "$CMD"
check "no zsh configuration here: exit 1" "1" "$RC"
has "no zsh configuration here: said" "nothing to copy" "$ERR"
check "no zsh configuration here: nothing ran" "" "$(calls)"

# ---- the dry run
before="$(remote_tree)"
run "$CMD" --dry-run
check "-n: exit 0" "0" "$RC"
check "-n: nothing is changed on the other machine (the old one made folders there)" "$before" "$(remote_tree)"
check "-n: one connection, to look" "ssh alice@mac.example sh" "$(calls ssh)"
check "-n: every rsync is a dry run; files in one call; a folder that is not there yet is not tried" \
  "rsync -avzL --dry-run $FILES_CALL
rsync -avzL --dry-run $HOME/.oh-my-zsh/custom/ alice@mac.example:.oh-my-zsh/custom/" "$(calls rsync)"
has "-n: the list shows what is replaced" ".zshrc              is there already: kept in ~/.zsh-backup-" "$OUT"
has "-n: the list shows what is new" ".zshenv             new there" "$OUT"
has "-n: the list shows the folders" ".config/zsh/        new there" "$OUT"
has "-n: says it is a dry run" "nothing is changed on alice@mac.example" "$OUT"
hasnt "the history is never sent" "zsh_history" "$(calls)$OUT"
hasnt "the completion dump is never sent" "zcompdump" "$(calls)$OUT"
hasnt "oh-my-zsh itself is never sent" ".oh-my-zsh/lib" "$(calls)$OUT"
reset_calls
run "$CMD" -H mac-mini.local -n
check "-H over the setting (an example in the help)" "ssh alice@mac-mini.local sh" "$(calls ssh)"
if [ -x /bin/bash ]; then
  run /bin/bash "$CMD" -n
  check "it runs under /bin/bash $(/bin/bash -c 'echo $BASH_VERSION') (the old one died at its first ssh under 3.2)" "0" "$RC"
fi

# ---- without a terminal
reset_calls
run "$CMD"
check "no terminal and no --yes: exit 1" "1" "$RC"
has "no terminal and no --yes: says how to go ahead" "--yes" "$ERR"
check "no terminal and no --yes: it only looked; nothing was sent" "ssh alice@mac.example sh" "$(calls)"
check "no terminal and no --yes: nothing is changed on the other machine" "$before" "$(remote_tree)"
run_in "y
" "$CMD"
check "a y on a pipe is not a yes" "1" "$RC"
check "a y on a pipe: nothing is changed on the other machine" "$before" "$(remote_tree)"

# ---- the copy
reset_calls
run "$CMD" --yes
check "--yes: exit 0" "0" "$RC"
check "--yes: two connections (look, prepare) and then the copies" \
  "ssh alice@mac.example sh
ssh alice@mac.example sh
rsync -avzL $FILES_CALL
rsync -avzL $HOME/.config/zsh/ alice@mac.example:.config/zsh/
rsync -avzL $HOME/.oh-my-zsh/custom/ alice@mac.example:.oh-my-zsh/custom/" "$(calls)"
bdir="$(cd "$R" && ls -d .zsh-backup-* 2>/dev/null)"
check "what was there is in the backup: .zshrc" "old remote zshrc" "$(cat "$R/$bdir/.zshrc" 2>/dev/null)"
check "what was there is in the backup: the oh-my-zsh custom folder, under its own path" "their plugin" "$(cat "$R/$bdir/.oh-my-zsh/custom/theirs.zsh" 2>/dev/null)"
[ -d "$R/.config/zsh" ] && ok "a folder that was not there is made before rsync needs it" || bad "a folder that was not there is made before rsync needs it"
has "says how to go back" "To go back, there:  cp -a ~/$bdir/. ~/" "$OUT"
has "says that zsh is not the login shell there" "The login shell there is /bin/bash, not zsh" "$OUT"
hasnt "no colour codes when the output is not a terminal" "$(printf '\033')" "$OUT"
check "no log file is written here any more" "" "$(find "$HOME" -name '*.log')"
check "the copy needed no oh-my-zsh installer" "" "$(calls curl)"

# ---- leaving files out, another account
new_remote
reset_calls
run "$CMD" -y --skip "$HOME/.zshenv" -s .config/zsh/ -u bob
check "--skip (twice, one written as a path): exit 0" "0" "$RC"
check "--skip: the names are in no command line; -u over the setting" \
  "rsync -avzL $HOME/.zshrc $HOME/.p10k.zsh bob@mac.example:
rsync -avzL $HOME/.oh-my-zsh/custom/ bob@mac.example:.oh-my-zsh/custom/" "$(calls rsync)"
has "--skip: said" "Left out: .zshenv .config/zsh" "$OUT"
[ -e "$R/.config" ] && bad "--skip: a folder left out is not made there" || ok "--skip: a folder left out is not made there"
reset_calls
run "$CMD" -n -H carol@192.0.2.10
check "-H USER@HOST" "ssh carol@192.0.2.10 sh" "$(calls ssh)"

# ---- oh-my-zsh is missing on the other machine
# The fake curl there hands out an "installer" that records how it was run.
fresh_remote() { rm -rf "$R"; mkdir -p "$R"; : > "$TMP/installer.log"; }
stub curl 'printf "%s\n" "#!/bin/sh" "echo \"RUNZSH=\$RUNZSH CHSH=\$CHSH KEEP_ZSHRC=\$KEEP_ZSHRC\" >> \"$TEST_TMP/installer.log\"" "mkdir -p \"\$HOME/.oh-my-zsh/custom\""'
fresh_remote
reset_calls
run "$CMD" -n
has "missing there, -n: the user is told what will be fetched and run" \
  "its installer will be downloaded from https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh and run there" "$OUT"
check "missing there, -n: nothing is fetched" "" "$(calls curl)"
check "missing there, -n: nothing is changed there" "." "$(remote_tree)"
reset_calls
run "$CMD" --yes
check "missing there, --yes: exit 0" "0" "$RC"
check "the installer is fetched there, from the oh-my-zsh repository" \
  "curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" "$(calls curl)"
check "the installer runs (the old command line never ran it), and may not start a shell, change the login shell or replace .zshrc" \
  "RUNZSH=no CHSH=no KEEP_ZSHRC=yes" "$(cat "$TMP/installer.log")"
check "the order: look, prepare (the installer runs in that connection), then copy" "ssh curl rsync" "$(calls | cut -d' ' -f1 | uniq | tr '\n' ' ' | sed 's/ $//')"
fresh_remote
reset_calls
run "$CMD" -H 192.0.2.10 -u admin --no-omz --yes
check "--no-omz (an example in the help): exit 0" "0" "$RC"
check "--no-omz: nothing is fetched" "" "$(calls curl)"
check "--no-omz: the custom folder is not sent to a machine without oh-my-zsh" \
  "rsync -avzL $HOME/.zshrc $HOME/.zshenv $HOME/.p10k.zsh admin@192.0.2.10:
rsync -avzL $HOME/.config/zsh/ admin@192.0.2.10:.config/zsh/" "$(calls rsync)"
[ -e "$R/.oh-my-zsh" ] && bad "--no-omz: no half an oh-my-zsh folder is made there" || ok "--no-omz: no half an oh-my-zsh folder is made there"
fresh_remote
reset_calls
stub curl 'exit 22'
run "$CMD" --yes
check "the installer cannot be fetched: exit 1" "1" "$RC"
has "the installer cannot be fetched: says what to do" "--no-omz" "$ERR"
check "the installer cannot be fetched: nothing is copied" "" "$(calls rsync)"
mv "$HOME/.oh-my-zsh" "$TMP/omz-aside"
fresh_remote
reset_calls
run "$CMD" --yes
check "no oh-my-zsh here: none is installed there (the old one always tried)" "" "$(calls curl)"
mv "$TMP/omz-aside" "$HOME/.oh-my-zsh"

# ---- on a terminal
new_remote
reset_calls
before="$(remote_tree)"
if tty_run "n" "$CMD" -H mac-mini.local --skip .zshenv; then
  has "on a terminal (an example in the help): asks" "Copy these to alice@mac-mini.local? [y/N]" "$OUT"
  has "on a terminal: the list comes before the question" "Left out: .zshenv" "${OUT%%Copy these to*}"
  check "on a terminal, answer n: nothing is sent" "" "$(calls rsync)"
  check "on a terminal, answer n: nothing is changed on the other machine" "$before" "$(remote_tree)"
else
  skip "no expect: the question is not tested"
fi

# ---- things that go wrong
reset_calls
stub uname 'echo Plan9'
mv "$STUBS/uname" "$RBIN/uname"       # only the other machine answers like this
run "$CMD" --yes
has "another system there: said" "That machine runs Plan9" "$OUT"
rm -f "$RBIN/uname"
stub ssh 'exit 255'
reset_calls
run "$CMD" --yes
check "the other machine cannot be reached: exit 1" "1" "$RC"
has "the other machine cannot be reached: says what to try" "try: ssh alice@mac.example" "$ERR"
check "the other machine cannot be reached: nothing is sent" "" "$(calls rsync)"
stub ssh "$FAKE_REMOTE"
stub rsync 'exit 12'
new_remote
run "$CMD" --yes
check "rsync fails: exit 1" "1" "$RC"
has "rsync fails: says where the old files are" "what was there before is in ~/.zsh-backup-" "$ERR"
BARE="$TMP/bare"
mkdir -p "$BARE"
for t in bash awk sed date id tr cat; do
  p="$(command -v "$t")" && ln -s "$p" "$BARE/$t"
done
ln -s "$STUBS/ssh" "$BARE/ssh"
reset_calls
run env PATH="$BARE" "$CMD" --yes
check "no rsync: exit 1" "1" "$RC"
has "no rsync: said" "rsync is not installed" "$ERR"
check "no rsync: nothing ran" "" "$(calls)"

finish
