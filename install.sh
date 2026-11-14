#!/bin/bash
# install.sh - put the mbmscripts commands on your PATH, for bash and zsh. No administrator
# rights needed.
#
# From a copy of the repository:   ./install.sh
# Without one (downloads it):      bash -c "$(curl -fsSL https://raw.githubusercontent.com/bbmorten/mbmscripts/main/install.sh)"
#
# It asks two questions. Press Return to keep the value in [brackets].
#   Name     what this installation is called. Everything it creates lives in ~/.<name>
#            (default: mbmscripts -> ~/.mbmscripts).
#   Prefix   what every command starts with (default: mbm- -> mbm-help, mbm-dns-flush, ...).
#            Choose xyz- and the same commands are called xyz-help, xyz-dns-flush, ...
#
# What it does:
#   1. creates ~/.<name>/bin with one entry per command, named <prefix><command>
#   2. writes ~/.<name>/env.sh, which adds that folder to the PATH
#   3. adds one small block to ~/.zshrc and ~/.bashrc that loads env.sh (the file it changes
#      is first copied to <file>.bak-<name>-<time>)
# Run it again at any time, for example to choose another prefix.
#
# Options:
#   --name NAME       answer the first question on the command line
#   --prefix PREFIX   answer the second question on the command line
#   --yes             ask nothing; use the defaults for whatever was not given
#   --copy            copy the scripts into ~/.<name>/src even when run from a checkout
#                     (from a checkout the commands normally point at the checkout itself,
#                     so that "git pull" updates them)
#   --no-shell        do not touch ~/.zshrc and ~/.bashrc
#
# Bash 3.2 compatible (the macOS /bin/bash).

set -u

REPO="bbmorten/mbmscripts"
BRANCH="main"
CANON="mbm-"          # the prefix the files carry inside the repository

die() { echo "install: $*" >&2; exit 1; }

# add_block FILE: append the loader block to FILE once, keeping a copy of the file first.
add_block() {
  local file="$1" begin="# >>> $NAME >>>" end="# <<< $NAME <<<"
  if [ -e "$file" ] && grep -qF -- "$begin" "$file"; then
    echo "  $file already loads $NAME"
    return 0
  fi
  if [ -e "$file" ]; then
    cp -p "$file" "$file.bak-$NAME-$STAMP" || die "could not copy $file before changing it"
  fi
  {
    printf '\n%s\n' "$begin"
    printf '%s\n' "[ -r \"\$HOME/.$NAME/env.sh\" ] && . \"\$HOME/.$NAME/env.sh\""
    printf '%s\n' "$end"
  } >> "$file" || die "could not write $file"
  echo "  added the $NAME block to $file"
}

# Everything runs inside main, so the whole file is read before the first command runs
# (needed when the script arrives through a pipe).
main() {
  local name="" prefix="" yes=0 copy=0 shell=1 self src="" tmp="" mode root f base n login answer

  while [ $# -gt 0 ]; do
    case "$1" in
      --name) [ $# -ge 2 ] || die "--name needs a value"; name="$2"; shift ;;
      --prefix) [ $# -ge 2 ] || die "--prefix needs a value"; prefix="$2"; shift ;;
      --yes|-y) yes=1 ;;
      --copy) copy=1 ;;
      --no-shell) shell=0 ;;
      -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
  done

  # Questions are read from the terminal even when the script itself came through a pipe.
  if [ ! -t 0 ] && ( : < /dev/tty ) 2>/dev/null; then exec < /dev/tty; fi

  if [ "$yes" = 0 ] && [ -t 0 ]; then
    if [ -z "$name" ]; then
      echo "Name of this installation. Everything it creates goes into ~/.<name>."
      printf "Name [mbmscripts]: "
      read -r answer || answer=""
      name="$answer"
    fi
    if [ -z "$prefix" ]; then
      echo "Prefix of the commands. With mbm- they are called mbm-help, mbm-dns-flush, ..."
      printf "Prefix [%s]: " "$CANON"
      read -r answer || answer=""
      prefix="$answer"
    fi
  fi
  NAME="${name:-mbmscripts}"
  PREFIX="${prefix:-$CANON}"
  STAMP="$(date +%Y%m%d-%H%M%S)"

  case "$NAME" in
    ''|.*|*[!A-Za-z0-9._-]*) die "the name may hold letters, digits, dot, dash and underscore only, and not start with a dot: $NAME" ;;
  esac
  case "$PREFIX" in
    ''|-*|*[!A-Za-z0-9._-]*) die "the prefix may hold letters, digits, dot, dash and underscore only, and not start with a dash: $PREFIX" ;;
  esac
  root="$HOME/.$NAME"

  # The scripts: next to this file, or downloaded.
  self="${BASH_SOURCE[0]:-}"
  if [ -n "$self" ] && [ -r "$(dirname "$self")/bin/${CANON}help" ]; then
    src="$(cd "$(dirname "$self")" && pwd)"
    if [ "$copy" = 1 ]; then mode=copy; else mode=link; fi
  else
    echo "Downloading $REPO from github.com ..."
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/mbmscripts-install.XXXXXX")" || die "could not create a temporary folder"
    curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$tmp" \
      || die "the download failed. Check your internet connection and try again."
    src="$tmp/${REPO##*/}-$BRANCH"
    [ -r "$src/bin/${CANON}help" ] || die "the download did not contain the scripts ($src)"
    mode=copy
  fi

  echo "Installing \"$NAME\" into $root (commands start with $PREFIX)"
  mkdir -p "$root/bin" || die "could not create $root/bin"

  if [ "$mode" = copy ]; then
    rm -rf "$root/src"
    mkdir -p "$root/src" || die "could not create $root/src"
    cp -R "$src/bin" "$src/libexec" "$root/src/" || die "could not copy the scripts"
    [ -d "$src/local" ] && cp -R "$src/local" "$root/src/"
    src="$root/src"
  fi
  [ -n "$tmp" ] && rm -rf "$tmp"

  # One entry per command. The folder holds nothing but these links, so a re-install
  # (another prefix, a removed script) starts from an empty folder.
  find "$root/bin" -maxdepth 1 -type l -exec rm -f {} +
  n=0
  for f in "$src"/bin/"$CANON"* "$src"/local/bin/"$CANON"*; do
    [ -f "$f" ] || continue
    base="${f##*/}"
    base="${base#"$CANON"}"
    if command -v "$PREFIX$base" >/dev/null 2>&1 && [ "$(command -v "$PREFIX$base")" != "$root/bin/$PREFIX$base" ]; then
      echo "  note: $PREFIX$base already exists as $(command -v "$PREFIX$base"); that one stays first on the PATH"
    fi
    ln -s "$f" "$root/bin/$PREFIX$base" || die "could not create $root/bin/$PREFIX$base"
    n=$((n + 1))
  done
  echo "  $n commands in $root/bin"

  # env.sh: one file, read by bash and by zsh. The folder goes to the END of the PATH, so a
  # command here can never hide a system command of the same name.
  {
    echo "# $NAME: puts the $PREFIX* commands on the PATH. Read by bash and by zsh."
    echo "# Written by install.sh; your own settings belong in local.env next to this file."
    echo "case \":\$PATH:\" in"
    echo "  *\":\$HOME/.$NAME/bin:\"*) ;;"
    echo "  *) PATH=\"\$PATH:\$HOME/.$NAME/bin\"; export PATH ;;"
    echo "esac"
    echo "[ -r \"\$HOME/.$NAME/local.env\" ] && . \"\$HOME/.$NAME/local.env\""
  } > "$root/env.sh" || die "could not write $root/env.sh"
  {
    echo "# Written by install.sh. Read by uninstall.sh."
    printf 'NAME=%q\nPREFIX=%q\nMODE=%q\nSOURCE=%q\nINSTALLED=%q\n' "$NAME" "$PREFIX" "$mode" "$src" "$STAMP"
  } > "$root/install.conf"

  if [ "$shell" = 1 ]; then
    echo "Shell startup files:"
    add_block "$HOME/.zshrc"
    add_block "$HOME/.bashrc"
    # A login bash reads only the first of these three, and not ~/.bashrc.
    login=""
    for f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
      if [ -e "$f" ]; then login="$f"; break; fi
    done
    if [ -z "$login" ]; then
      add_block "$HOME/.bash_profile"
    elif grep -q 'bashrc' "$login"; then
      echo "  $login already reads ~/.bashrc"
    else
      add_block "$login"
    fi
  fi

  echo
  echo "Done. Open a NEW terminal window, then type:   ${PREFIX}help"
  echo "To choose another name or prefix, run this installer again."
}

main "$@"
