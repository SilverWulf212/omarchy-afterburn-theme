#!/bin/bash
# Remove Afterburn extras: the hook, your old cursor effect, your old default terminal,
# the subtle pack (links, watcher service, ~/.bashrc line, starship prompt, desktop entry,
# afterburn.conf) and the lock-screen embers if the installer added them.
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
if [[ -f $STATE_DIR/starship.toml.bak ]]; then
  cat "$STATE_DIR/starship.toml.bak" > "$CONF_HOME/starship.toml" && echo "  ✓ starship prompt restored from backup"
fi
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
if grep -q '# afterburn$' "$HOME/.bashrc" 2>/dev/null; then
  sed -i '/# afterburn$/d' "$HOME/.bashrc"
  # The installer added a newline before its line when the file had none; take it back.
  if [[ -f $STATE_DIR/bashrc-newline ]]; then truncate -s -1 "$HOME/.bashrc"; fi
  echo "  ✓ ~/.bashrc line removed"
fi
rm -f "$APPS_DIR/afterburn-colors.desktop"
rm -rf "$CONF_HOME/afterburn"
# Remove the directories the installer created, but only if they are now empty.
rmdir "$BIN" "$CONF_HOME/systemd/user" "$CONF_HOME/systemd" "$APPS_DIR" "${XDG_DATA_HOME:-$HOME/.local/share}" 2>/dev/null || true

rm -f "$D/50-afterburn-extras"; rm -rf "$STATE_DIR" "$HOME/.local/share/afterburn"
echo "  ✓ Afterburn hook removed"
cat <<'EOF'

  Still installed (remove only if you want):
    cursor-fx:  cursor-fx off; rm ~/.local/bin/cursor-fx; rm -r ~/.config/ghostty/{shaders,cursor-effects}
                and delete the `config-file = cursor-effects/...` line in ~/.config/ghostty/config
    Ghostty:    omarchy pkg drop ghostty   (set another default terminal first)
  The glow disappears the next time you apply any theme.
EOF
