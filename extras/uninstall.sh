#!/bin/bash
# Remove Afterburn extras. Restores your previous cursor-fx effect if one was saved.
set -u
D="$HOME/.config/omarchy/hooks/theme-set.d"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/afterburn/prev-cursor-fx"
[[ -f $STATE ]] && command -v cursor-fx >/dev/null && cursor-fx "$(cat "$STATE")" >/dev/null 2>&1
rm -rf "$D/50-afterburn-extras" "$(dirname "$STATE")"
echo "Afterburn extras removed. Re-apply a theme to drop the glow: omarchy theme set afterburn"
