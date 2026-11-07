#!/bin/bash
# Remove Afterburn extras: the hook, your old cursor effect, your old default terminal.
# Ghostty and cursor-fx stay installed; how to remove them is printed at the end.
set -u
D="$HOME/.config/omarchy/hooks/theme-set.d"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/afterburn"

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
rm -f "$D/50-afterburn-extras"; rm -rf "$STATE_DIR" "$HOME/.local/share/afterburn"
echo "  ✓ Afterburn hook removed"
cat <<'EOF'

  Still installed (remove only if you want):
    cursor-fx:  cursor-fx off; rm ~/.local/bin/cursor-fx; rm -r ~/.config/ghostty/{shaders,cursor-effects}
                and delete the `config-file = cursor-effects/...` line in ~/.config/ghostty/config
    Ghostty:    omarchy pkg drop ghostty   (set another default terminal first)
  The glow disappears the next time you apply any theme.
EOF
