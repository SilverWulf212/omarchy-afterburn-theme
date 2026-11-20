#!/bin/bash
# Remove Afterburn extras: the hook, your old cursor effect, your old default terminal,
# the subtle pack (links, watcher service, ~/.bashrc line, starship prompt, desktop entry;
# afterburn.conf is kept as afterburn.conf.bak), the lock-screen embers and the colour editions if the installer added them.
# The boot/login screen is put back with Omarchy's omarchy-plymouth-reset if the installer set it
# (it needs sudo, so you are asked; or the exact command is printed).
# cursor-fx goes too if the installer put it there (you are asked; files are moved to a backup folder, not
# deleted). Ghostty stays installed; how to remove it is printed at the end.
#   --remove-cursor-fx  remove cursor-fx without asking      --keep-cursor-fx  keep it without asking
set -u
CFX_MODE=ask
for arg in "$@"; do
  case $arg in
    --remove-cursor-fx) CFX_MODE=remove ;;
    --keep-cursor-fx) CFX_MODE=keep ;;
    *) echo "usage: $0 [--remove-cursor-fx | --keep-cursor-fx]" >&2; exit 2 ;;
  esac
done
HERE="$(cd "$(dirname "$0")" && pwd)"
D="$HOME/.config/omarchy/hooks/theme-set.d"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/afterburn"
CONF_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$HOME/.local/bin"
KEEP=(preview-backups ghostty-savepoints 'cursor-fx-removed-*')   # state files that stay: the manual undo in the README needs preview-backups; a failed restore adds its own
RC=0
# shellcheck disable=SC1091
. "$HERE/afterburn-theme.sh"   # AB_BASHRC_LINE

# Terminal and font: put the old one back only while the installer's is still current (Ghostty, and the
# font install.sh sets). A later choice of yours is left alone, like the starship line below.
if [[ -s $STATE_DIR/prev-terminal ]]; then
  prev=$(cat "$STATE_DIR/prev-terminal")
  name=$(basename "$prev" .desktop | sed -E 's/.*\.//; s/^(ghostty|alacritty|kitty|foot).*/\1/' | tr '[:upper:]' '[:lower:]')
  if ! grep -qi ghostty <(grep -vE '^[[:space:]]*(#|$)' "$HOME/.config/xdg-terminals.list" 2>/dev/null | head -1); then
    echo "  · default terminal changed since install; left as is"
  elif [[ $prev == none ]]; then
    # No list of your own before the install (a fresh Omarchy user): remove the one it created, so the
    # system default applies again. Only if Ghostty is its one and only entry; lines you added are yours.
    list="$HOME/.config/xdg-terminals.list"
    if [[ $(grep -cvE '^[[:space:]]*(#|$)' "$list") == 1 ]]; then
      rm -f "$list" && echo "  ✓ default terminal back to Omarchy's own (the list the installer created was removed)"
    else
      echo "  · terminal list has your own lines; left as is"
    fi
  elif [[ $name =~ ^(alacritty|foot|ghostty|kitty)$ ]]; then
    omarchy default terminal "$name" >/dev/null && echo "  ✓ default terminal restored to $name"
  else
    echo "  · previous terminal was $prev; set it again with: omarchy default terminal <name>"
  fi
fi
if [[ -s $STATE_DIR/prev-font ]]; then
  if [[ $(omarchy font current 2>/dev/null) == "JetBrainsMono Nerd Font" ]]; then   # the FONT install.sh sets
    omarchy font set "$(cat "$STATE_DIR/prev-font")" >/dev/null && echo "  ✓ font restored to $(cat "$STATE_DIR/prev-font")"
  else
    echo "  · font changed since install; left as is"
  fi
fi

# Colour editions: remove only the afterburn-<name> folders the installer copied (listed in the state
# dir). A folder of the same name that the installer did not create is never in that list.
THEMES_HOME="$HOME/.config/omarchy/themes"
if [[ -s $STATE_DIR/editions ]]; then
  cur=$(ab_theme_name)
  while IFS= read -r e || [[ -n $e ]]; do
    [[ $e =~ ^[a-z0-9]+$ ]] || continue       # the state file is data: only plain edition names (same rule as install.sh)
    dir="$THEMES_HOME/afterburn-$e"
    [[ -d $dir && ! -L $dir ]] || continue
    if [[ $cur == "afterburn-$e" ]]; then
      # Decision: switch to the base theme first, so the desktop is never left on a theme that is gone.
      # stdin is the editions list this loop is reading: keep the command away from it. With no tty omarchy would
      # run the theme hook detached, after the watcher stops below; OMARCHY_THEME_WAIT=1 makes it finish first.
      OMARCHY_THEME_WAIT=1 omarchy theme set afterburn >/dev/null 2>&1 </dev/null || true
      cur=$(ab_theme_name)
      if [[ $cur == afterburn ]]; then
        echo "  ✓ switched from afterburn-$e to afterburn"
      else
        echo "  · afterburn-$e is your active theme and could not be switched, so it was kept."
        echo "    Switch theme (omarchy theme set <name>), then remove it: rm -rf $dir"
        continue
      fi
    fi
    rm -rf "$dir" && echo "  ✓ edition removed: afterburn-$e"
  done < "$STATE_DIR/editions"
fi

# Watcher: stopped before the cursor effect is restored (a running watcher could re-apply its own), and after
# the edition switch above, which runs the theme-set hook. Stopped whether or not the unit file is still there.
systemctl --user disable --now afterburn-watch.service >/dev/null 2>&1 || true
if [[ -f $CONF_HOME/systemd/user/afterburn-watch.service ]]; then
  rm -f "$CONF_HOME/systemd/user/afterburn-watch.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  echo "  ✓ watcher service removed"
fi

# Cursor effect: after the edition switch above, not before. Switching to the base theme runs the theme-set
# hook, which sets that theme's effect; restoring first would let it overwrite your own effect again.
# Only over Afterburn's own effect (as when you leave Afterburn): one you picked yourself stays.
if [[ -f $STATE_DIR/prev-cursor-fx ]] && command -v cursor-fx >/dev/null; then
  cur=$(ab_cursor_now)
  [[ -f $STATE_DIR/cursor-pre-quiet ]] && cur=$(cat "$STATE_DIR/cursor-pre-quiet")
  ours=$(cat "$STATE_DIR/cursor-fx-set" 2>/dev/null || true)
  if [[ -n $ours && $cur != "$ours" ]]; then
    echo "  · cursor effect: kept $cur, which you picked yourself"
  elif cursor-fx "$(cat "$STATE_DIR/prev-cursor-fx")" >/dev/null 2>&1; then
    echo "  ✓ cursor effect restored"
  fi
fi

# Subtle: only if battery saver turned it on and nothing has turned it off again (a subtle you had on is left alone).
if [[ -f $STATE_DIR/subtle-by-afterburn ]] && command -v cursor-fx >/dev/null; then
  cursor-fx subtle off >/dev/null 2>&1 && echo "  ✓ cursor subtle mode restored"
fi
# Battery saver's no-animation line in the Ghostty config.
if grep -qF -e "$AB_STILL_MARK" -e "$AB_STILL_LINE  # afterburn battery saver" "$(ab_ghostty_config)" 2>/dev/null; then
  ab_ghostty_still off && echo "  ✓ Ghostty shader animation restored"
fi

# cursor-fx: only if the installer put it there (its checkout in ~/.local/share/afterburn is the proof: install.sh
# only clones it when it installs cursor-fx). Everything is moved into one backup folder, so it can be put back.
CFX_DIR="$HOME/.local/share/afterburn/ghostty-cursor-fx"   # install.sh's path, whatever XDG_DATA_HOME says
CFX_NOTE=mine
remove_cursor_fx() {
  local cfg gdir bak sub f name real tmp left
  cfg=${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config; [[ -e $cfg ]] || cfg+=.ghostty
  # cursor-fx's installer puts its folders beside the real config file (a dotfiles link is followed).
  gdir=$(dirname "$(readlink -f "$cfg")")
  bak="$STATE_DIR/cursor-fx-removed-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$bak" || return 1
  command -v cursor-fx >/dev/null && { cursor-fx off >/dev/null 2>&1 || true; }
  # `cursor-fx off` leaves its marker comment and its -last / -panes notes in the config: take those out too.
  if [[ -f $cfg ]]; then
    real=$(readlink -f "$cfg")
    cp -p "$real" "$bak/ghostty-config" || return 1
    tmp=$(mktemp "$(dirname "$real")/.ghostty.XXXXXX") || return 1
    awk '
      /^[ \t]*config-file[ \t]*=[ \t]*"?\??cursor-effects\// { next }
      /^# Cursor effect preset from cursor-effects\// { next }
      /^[ \t]*#[ \t]*cursor-fx-(last|panes)[ \t]*=/ { next }
      { print }
    ' "$real" > "$tmp" || { rm -f "$tmp"; return 1; }
    ab_replace_if_changed "$tmp" "$cfg" || return 1
  fi
  # Only the files cursor-fx ships (named in its checkout). A file of yours in those folders stays.
  for sub in shaders cursor-effects; do
    for f in "$CFX_DIR/$sub"/*; do
      name=$(basename "$f")
      [[ -f $f && ( -e $gdir/$sub/$name || -L $gdir/$sub/$name ) ]] || continue
      mkdir -p "$bak/$sub" && mv "$gdir/$sub/$name" "$bak/$sub/" || return 1
    done
    if [[ -d $gdir/$sub ]] && ! rmdir "$gdir/$sub" 2>/dev/null; then
      left=$(find "$gdir/$sub" -mindepth 1 -maxdepth 1 | wc -l)
      echo "  · kept $left file(s) of your own in $gdir/$sub"
    fi
  done
  if [[ -e $BIN/cursor-fx || -L $BIN/cursor-fx ]]; then mv "$BIN/cursor-fx" "$bak/" || return 1; fi
  f="$HOME/.pi/agent/extensions/cursor-fx.ts"
  if [[ -f $f ]]; then
    mv "$f" "$bak/pi-extension-cursor-fx.ts" || return 1
    echo "  · pi: removed the cursor-fx extension; showHardwareCursor in ~/.pi/agent/settings.json is left as it is"
  fi
  echo "  ✓ cursor-fx removed (everything it had is in $bak)"
}
if [[ -d $CFX_DIR ]]; then
  if [[ $CFX_MODE == ask ]]; then
    # No terminal (or no answer) keeps it: removing is never done unasked.
    if read -rp "  Remove cursor-fx too? (it came with Afterburn; its files are moved to a backup folder) [Y/n] " a; then
      [[ -z $a || $a =~ ^[Yy] ]] && CFX_MODE=remove || CFX_MODE=keep
    else
      echo; CFX_MODE=keep
    fi
  fi
  if [[ $CFX_MODE == remove ]]; then
    if remove_cursor_fx; then CFX_NOTE=removed; else
      RC=1; CFX_NOTE=failed
      echo "  ✗ cursor-fx not fully removed; what was moved is in $STATE_DIR/cursor-fx-removed-*"
      echo "    fix the error above, then run: $0 --remove-cursor-fx"
    fi
  else
    CFX_NOTE=kept
  fi
fi

# Lock screen: only if the installer added the embers (marker written on a successful install).
if [[ -f $STATE_DIR/lock-embers ]]; then
  if [[ -f $HERE/lock/lock-embers.sh ]] && bash "$HERE/lock/lock-embers.sh" uninstall; then
    echo "  ✓ lock screen restored"
  else
    echo "  · lock screen not restored; run: bash $HERE/lock/lock-embers.sh uninstall"
  fi
fi

# Subtle pack: each piece is removed only if the installer put it there.
for f in afterburn afterburn-watch; do
  if [[ -L $BIN/$f && $(readlink "$BIN/$f") == "$HERE/bin/$f" ]]; then
    rm -f "$BIN/$f"; echo "  ✓ unlinked $BIN/$f"
  fi
done
# Starship: put back only the original error_symbol line, and only if the line is still the one we wrote.
srv=0; ab_starship_restore || srv=$?
case $srv in
  0) echo "  ✓ starship error_symbol restored" ;;
  1) KEEP+=(starship-error-symbol); RC=1
     echo "  ✗ starship error_symbol not restored (your file is unchanged); original line is in $STATE_DIR/starship-error-symbol" ;;
  2) echo "  · starship error_symbol is not Afterburn's red ❯; nothing to restore" ;;
esac
# ~/.bashrc: delete only the lines the installer added, matched whole. Written to a temp file, then moved into place.
# $1 the line, $2 its marker (a newline was added before it), $3 what to call it. Reverse install order (the
# cursor-fx step runs before the subtle pack), so a line whose newline the installer added is the last one left.
BASHRC_REAL=$(readlink -f "$HOME/.bashrc")
# $4: the rc file (default ~/.bashrc). Symlinks are followed, so a dotfiles-managed rc keeps its link.
remove_bashrc_line() {
  local BASHRC_REAL=${4:-$BASHRC_REAL} name=${5:-.bashrc}
  grep -qxF "$1" "$BASHRC_REAL" 2>/dev/null || return 0
  local tmp
  tmp=$(mktemp "$(dirname "$BASHRC_REAL")/$name.XXXXXX")
  # Write, then chmod, then move (as for starship above). awk, not grep -v: grep exits 1 when nothing is left.
  if {
    if [[ -f $STATE_DIR/$2 && $(tail -n1 "$BASHRC_REAL") == "$1" ]]; then
      # The installer added a newline before its line because the file had none, and the line is last:
      # drop the line and that newline, so the file is byte-for-byte the original.
      head -n -1 "$BASHRC_REAL" | head -c -1 > "$tmp"
    else
      LINE="$1" awk '$0 != ENVIRON["LINE"]' "$BASHRC_REAL" > "$tmp"
    fi
  } && chmod --reference="$BASHRC_REAL" "$tmp" && mv "$tmp" "$BASHRC_REAL"; then
    echo "  ✓ ~/$name $3 line removed"
  else
    rm -f "$tmp"; KEEP+=("$2" bashrc-created); RC=1
    echo "  ✗ ~/$name $3 line not restored (your file is unchanged); remove the line ending in '# afterburn' yourself"
  fi
}
remove_bashrc_line "$AB_BASHRC_LINE" bashrc-newline "fail-effect"
remove_bashrc_line "$AB_CFX_BASHRC_LINE" cfx-bashrc-newline "cursor-fx Enter"
ZSHRC_REAL=$(readlink -f "${ZDOTDIR:-$HOME}/.zshrc")
[[ -f $ZSHRC_REAL ]] && remove_bashrc_line "$AB_ZSHRC_LINE" zshrc-newline "fail-effect" "$ZSHRC_REAL" .zshrc
# The installer made this file (there was none): take it away again if nothing else is in it.
if [[ -f $STATE_DIR/bashrc-created && -f $BASHRC_REAL && ! -s $BASHRC_REAL ]]; then
  rm -f "$BASHRC_REAL" && echo "  ✓ ~/.bashrc removed (the installer had created it, and it is empty)"
fi
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
rm -f "$APPS_DIR/afterburn-colors.desktop"
# Your settings are kept as afterburn.conf.bak (the installer promises an existing conf keeps them).
if [[ -f $CONF_HOME/afterburn/afterburn.conf ]]; then
  # Never overwrite an earlier backup: use the first free name (.bak, .bak.1, .bak.2, ...).
  bak="$CONF_HOME/afterburn/afterburn.conf.bak"
  n=0
  while [[ -e $bak || -L $bak ]]; do n=$((n + 1)); bak="$CONF_HOME/afterburn/afterburn.conf.bak.$n"; done
  mv "$CONF_HOME/afterburn/afterburn.conf" "$bak"
  echo "  · kept your settings: $bak (delete it if you do not want them)"
fi
rmdir "$CONF_HOME/afterburn" 2>/dev/null || true
# The cursor-fx checkout is the one thing the installer puts in ~/.local/share/afterburn. Kept while cursor-fx is:
# it names the files to remove, so `uninstall.sh --remove-cursor-fx` later still knows what is Afterburn's.
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
# Only after a full removal: a failed one keeps it, so a retry knows what is left.
[[ $CFX_NOTE == removed ]] && rm -rf "$CFX_DIR"
rmdir "$HOME/.local/share/afterburn" 2>/dev/null || true
# Remove the directories the installer created, but only if they are now empty.
rmdir "$BIN" "$CONF_HOME/systemd/user" "$CONF_HOME/systemd" "$APPS_DIR" "$DATA_HOME" 2>/dev/null || true

# Boot/login screen: only if the installer set it. omarchy-plymouth-reset needs sudo, so ask (default Yes,
# it is the undo of something you chose); with no answer (no terminal), print the exact command.
PLYMOUTH_NOTE=""
if [[ -s $STATE_DIR/plymouth ]]; then
  if command -v omarchy-plymouth-reset >/dev/null &&
     { read -rp "  Restore Omarchy's default boot and login screen now? (runs omarchy-plymouth-reset, needs sudo) [Y/n] " a || { echo; false; }; } &&
     [[ -z $a || $a =~ ^[Yy] ]]; then
    if omarchy-plymouth-reset; then
      echo "  ✓ boot/login screen restored"
    else
      PLYMOUTH_NOTE="the boot/login screen reset did not finish. Run: omarchy-plymouth-reset"
    fi
  else
    PLYMOUTH_NOTE="the boot/login screen is still set to Afterburn. Restore it with: omarchy-plymouth-reset   (needs sudo)"
  fi
  [[ -n $PLYMOUTH_NOTE ]] && echo "  · $PLYMOUTH_NOTE"
fi

rm -f "$D/50-afterburn-extras"
# The whole-file starship backup stays in the state dir as a safety copy. Nothing restores from it.
KEEP+=(starship.toml.bak)
find_keep=(); for k in "${KEEP[@]}"; do find_keep+=(! -name "$k"); done
find "$STATE_DIR" -mindepth 1 -maxdepth 1 "${find_keep[@]}" -exec rm -rf {} + 2>/dev/null
rmdir "$STATE_DIR" 2>/dev/null || true
[[ -f $STATE_DIR/starship.toml.bak ]] && echo "  · kept a safety copy of your old starship.toml: $STATE_DIR/starship.toml.bak"
[[ -d $STATE_DIR/ghostty-savepoints ]] && echo "  · kept your Ghostty config backups: $STATE_DIR/ghostty-savepoints"
[[ -d $STATE_DIR/preview-backups ]] && echo "  · kept your preview backups: $STATE_DIR/preview-backups"
echo "  ✓ Afterburn hook removed"
[[ $CFX_NOTE == removed ]] && echo "  · cursor-fx backup kept in $STATE_DIR (delete it when you are sure)"
echo
echo "  Still installed (remove only if you want):"
if [[ $CFX_NOTE == kept || $CFX_NOTE == mine ]] && command -v cursor-fx >/dev/null; then
  [[ $CFX_NOTE == kept ]] && echo "    cursor-fx:  $0 --remove-cursor-fx   (moves it all to a backup folder)" ||
    echo "    cursor-fx:  not installed by Afterburn (no ~/.local/share/afterburn checkout), so it was left alone"
fi
cat <<'EOF'
    Ghostty:    omarchy pkg drop ghostty   (set another default terminal first)
  The glow disappears the next time you apply any theme.
EOF
exit $RC
