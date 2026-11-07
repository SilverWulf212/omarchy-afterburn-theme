#!/bin/bash
# Remove Afterburn extras: the hook, your old cursor effect, your old default terminal,
# the subtle pack (links, watcher service, ~/.bashrc line, starship prompt, desktop entry,
# afterburn.conf), the lock-screen embers and the colour editions if the installer added them.
# The boot/login screen is put back with Omarchy's omarchy-plymouth-reset if the installer set it
# (it needs sudo, so you are asked; or the exact command is printed).
# Ghostty and cursor-fx stay installed; how to remove them is printed at the end.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
D="$HOME/.config/omarchy/hooks/theme-set.d"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/afterburn"
CONF_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$HOME/.local/bin"

if [[ -f $STATE_DIR/prev-cursor-fx ]] && command -v cursor-fx >/dev/null; then
  cursor-fx "$(cat "$STATE_DIR/prev-cursor-fx")" >/dev/null 2>&1 && echo "  ✓ cursor effect restored"
fi
if [[ -s $STATE_DIR/prev-terminal ]]; then
  prev=$(cat "$STATE_DIR/prev-terminal")
  name=$(basename "$prev" .desktop | sed -E 's/.*\.//; s/^(ghostty|alacritty|kitty|foot).*/\1/' | tr '[:upper:]' '[:lower:]')
  if [[ $name =~ ^(alacritty|foot|ghostty|kitty)$ ]]; then
    omarchy default terminal "$name" >/dev/null && echo "  ✓ default terminal restored to $name"
  else
    echo "  · previous terminal was $prev; set it again with: omarchy default terminal <name>"
  fi
fi
if [[ -s $STATE_DIR/prev-font ]]; then
  omarchy font set "$(cat "$STATE_DIR/prev-font")" >/dev/null && echo "  ✓ font restored to $(cat "$STATE_DIR/prev-font")"
fi

# Colour editions: remove only the afterburn-<name> folders the installer copied (listed in the state
# dir). A folder of the same name that the installer did not create is never in that list.
THEMES_HOME="$HOME/.config/omarchy/themes"
if [[ -s $STATE_DIR/editions ]]; then
  cur=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme.name" 2>/dev/null || true)
  while IFS= read -r e || [[ -n $e ]]; do
    [[ $e =~ ^[a-z]+$ ]] || continue          # the state file is data: only plain edition names
    dir="$THEMES_HOME/afterburn-$e"
    [[ -d $dir && ! -L $dir ]] || continue
    if [[ $cur == "afterburn-$e" ]]; then
      # Decision: switch to the base theme first, so the desktop is never left on a theme that is gone.
      omarchy theme set afterburn >/dev/null 2>&1 || true
      cur=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme.name" 2>/dev/null || true)
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
if [[ -f $CONF_HOME/systemd/user/afterburn-watch.service ]]; then
  systemctl --user disable --now afterburn-watch.service >/dev/null 2>&1 || true
  rm -f "$CONF_HOME/systemd/user/afterburn-watch.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  echo "  ✓ watcher service removed"
fi
# Starship: put back only the original error_symbol line, and only if the line is still the one we wrote.
STARSHIP="$CONF_HOME/starship.toml"
OURS_SYMBOL='error_symbol = "[❯](bold red)"'
if [[ -f $STATE_DIR/starship-error-symbol && -f $STARSHIP ]]; then
  if grep -qxF "$OURS_SYMBOL" "$STARSHIP"; then
    orig=$(cat "$STATE_DIR/starship-error-symbol")
    real=$(readlink -f "$STARSHIP")
    tmp=$(mktemp "$(dirname "$real")/.starship.XXXXXX")
    awk -v ours="$OURS_SYMBOL" -v orig="$orig" '
      $0 == ours && !done { done = 1; if (orig != "absent") print orig; next }
      { print }
    ' "$real" > "$tmp"
    chmod --reference="$real" "$tmp"
    mv "$tmp" "$real"
    echo "  ✓ starship error_symbol restored"
  else
    echo "  · starship error_symbol changed since install; left as is"
  fi
fi

# ~/.bashrc: delete only the line(s) carrying the marker. Written to a temp file, then moved into place.
if grep -q '# afterburn$' "$HOME/.bashrc" 2>/dev/null; then
  real=$(readlink -f "$HOME/.bashrc")
  tmp=$(mktemp "$(dirname "$real")/.bashrc.XXXXXX")
  if [[ -f $STATE_DIR/bashrc-newline && $(tail -n1 "$real") == *'# afterburn' ]]; then
    # The installer added a newline before its line because the file had none, and the marker line is last:
    # drop the marker line and that newline, so the file is byte-for-byte the original.
    head -n -1 "$real" | head -c -1 > "$tmp"
  else
    grep -v '# afterburn$' "$real" > "$tmp" || true
  fi
  chmod --reference="$real" "$tmp"
  mv "$tmp" "$real"
  echo "  ✓ ~/.bashrc line removed"
fi
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
rm -f "$APPS_DIR/afterburn-colors.desktop"
# Only the file the installer wrote; then the folder, if nothing else is in it.
rm -f "$CONF_HOME/afterburn/afterburn.conf"
rmdir "$CONF_HOME/afterburn" 2>/dev/null || true
# The cursor-fx checkout is the one thing the installer puts in ~/.local/share/afterburn.
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
rm -rf "$HOME/.local/share/afterburn/ghostty-cursor-fx"
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
if [[ -f $STATE_DIR/starship.toml.bak ]]; then
  find "$STATE_DIR" -mindepth 1 -maxdepth 1 ! -name starship.toml.bak -exec rm -rf {} +
  echo "  · kept a safety copy of your old starship.toml: $STATE_DIR/starship.toml.bak"
else
  rm -rf "$STATE_DIR"
fi
echo "  ✓ Afterburn hook removed"
cat <<'EOF'

  Still installed (remove only if you want):
    cursor-fx:  cursor-fx off; rm ~/.local/bin/cursor-fx; rm -r ~/.config/ghostty/{shaders,cursor-effects}
                and delete the `config-file = cursor-effects/...` line in ~/.config/ghostty/config
    Ghostty:    omarchy pkg drop ghostty   (set another default terminal first)
  The glow disappears the next time you apply any theme.
EOF
