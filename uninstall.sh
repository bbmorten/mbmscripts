#!/bin/bash
# uninstall.sh - remove an installation made by install.sh.
#
#   ./uninstall.sh                  remove the installation called mbmscripts
#   ./uninstall.sh --name NAME      remove the installation called NAME
#   ./uninstall.sh --purge          also remove your own settings file (~/.<name>/local.env)
#
# It removes the commands (~/.<name>/bin), env.sh, the copied scripts (~/.<name>/src) and the
# block install.sh added to ~/.zshrc, ~/.bashrc and the bash login file. Each startup file it
# changes is first copied to <file>.bak-<name>-<time>. The repository checkout, the settings
# of the VPN commands (~/.config/btvpn, ~/.config/multivpn) and saved passwords are not touched.

set -u

name="mbmscripts"
purge=0
while [ $# -gt 0 ]; do
  case "$1" in
    --name) [ $# -ge 2 ] || { echo "uninstall: --name needs a value" >&2; exit 1; }; name="$2"; shift ;;
    --purge) purge=1 ;;
    *) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
  esac
  shift
done
case "$name" in
  ''|.*|*[!A-Za-z0-9._-]*) echo "uninstall: not a valid name: $name" >&2; exit 1 ;;
esac

root="$HOME/.$name"
stamp="$(date +%Y%m%d-%H%M%S)"
begin="# >>> $name >>>"
end="# <<< $name <<<"

for f in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
  [ -e "$f" ] || continue
  grep -qF -- "$begin" "$f" || continue
  cp -p "$f" "$f.bak-$name-$stamp" || { echo "uninstall: could not copy $f before changing it" >&2; exit 1; }
  # Drop the block and the empty line install.sh put in front of it.
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1; if (held) held = 0; next }
    skip && $0 == e { skip = 0; next }
    skip { next }
    held { print "" ; held = 0 }
    $0 == "" { held = 1; next }
    { print }
    END { if (held) print "" }
  ' "$f.bak-$name-$stamp" > "$f" && echo "removed the $name block from $f"
done

if [ -d "$root" ]; then
  [ -d "$root/bin" ] && find "$root/bin" -maxdepth 1 -type l -exec rm -f {} +
  rmdir "$root/bin" 2>/dev/null
  rm -rf "$root/src"
  rm -f "$root/env.sh" "$root/install.conf"
  if [ "$purge" = 1 ]; then rm -f "$root/local.env"; fi
  if rmdir "$root" 2>/dev/null; then
    echo "removed $root"
  else
    echo "kept $root (it still holds: $(ls -A "$root" | tr '\n' ' '))"
  fi
else
  echo "no installation called $name ($root does not exist)"
fi
