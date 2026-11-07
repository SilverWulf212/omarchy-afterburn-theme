#!/bin/bash
# Afterburn: the full stack.
#   1. Ghostty terminal (installed and made default if needed)
#   2. cursor-fx animated cursors by Avarce (MIT), set to "embers" while Afterburn is active
#   3. The orange window glow (Omarchy drops .lua from installed themes; a theme-set hook restores it)
# Run:  ~/.config/omarchy/themes/afterburn/extras/install.sh        (asks before each step)
#       ~/.config/omarchy/themes/afterburn/extras/install.sh --yes  (no questions)
# Undo: ~/.config/omarchy/themes/afterburn/extras/uninstall.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK_NAME=50-afterburn-extras
HOOKS="$HOME/.config/omarchy/hooks/theme-set.d"
CFX_REPO=https://github.com/Avarce/ghostty-cursor-fx.git
CFX_PIN=252df6c6344fe68ab8715d3e4a57f73ad91ed7ed   # version tested with Afterburn
CFX_DIR="$HOME/.local/share/afterburn/ghostty-cursor-fx"
YES=false; [[ ${1:-} == --yes || ${1:-} == -y ]] && YES=true

o() { printf '\033[38;2;245;145;69m%s\033[0m\n' "$*"; }
ok() { printf '  \033[38;2;245;145;69m✓\033[0m %s\n' "$*"; }
skip() { printf '  \033[2m· %s\033[0m\n' "$*"; }
ask() { $YES && return 0; read -rp "  $1 [Y/n] " a; [[ -z $a || $a =~ ^[Yy] ]]; }

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/afterburn"

echo; o "  ❯ afterburn // full stack"; echo
cat <<'EOF'
  Before you go on, this script can change the following (it asks before each part):

  • DEFAULT TERMINAL: installs Ghostty (pacman, needs sudo) and/or makes it your
    default terminal, replacing your current one for Super + Return and every
    "open in terminal" action. uninstall.sh puts your old default back.
  • FONT: switches your system font to JetBrainsMono Nerd Font (terminals, bar, menus).
    uninstall.sh puts your old font back.
  • THIRD-PARTY CODE: downloads ghostty-cursor-fx by Avarce (MIT) from GitHub, pinned
    to one tested commit, and runs its installer. It writes ~/.local/bin/cursor-fx,
    ~/.config/ghostty/shaders/ and cursor-effects/, edits ~/.config/ghostty/config,
    and, if ~/.pi/agent exists, adds a pi extension and turns on showHardwareCursor.
    Anything it replaces is copied to ~/ghostty-savepoints/ first.
  • SYSTEM HOOK: adds ~/.config/omarchy/hooks/theme-set.d/50-afterburn-extras, which runs
    on every theme change: it adds the glow on Afterburn and swaps your cursor effect.
  • GPU / BATTERY: cursor shaders make Ghostty redraw constantly. `cursor-fx off` stops it.
  • MOTION: cursor effects animate and flash. If motion bothers you, skip cursor-fx
    or run `cursor-fx subtle on`.

  Full details: https://github.com/silverwulf212/omarchy-afterburn-theme#what-the-full-stack-changes
EOF
echo
ask "Continue?" || { echo "  Nothing changed."; exit 0; }
mkdir -p "$STATE_DIR"
echo

# 1. Ghostty
if ! command -v ghostty >/dev/null; then
  if ask "Install Ghostty and make it your default terminal? (the cursor effects need it)"; then
    grep -v '^#' "$HOME/.config/xdg-terminals.list" 2>/dev/null | head -1 > "$STATE_DIR/prev-terminal" || true
    omarchy install terminal ghostty
    ok "Ghostty installed and set as default"
  else
    skip "skipped Ghostty: no cursor effects without it"
  fi
elif ! grep -qi ghostty <(grep -v '^#' "$HOME/.config/xdg-terminals.list" 2>/dev/null | head -1); then
  if ask "Make Ghostty your default terminal (Super + Return), replacing your current one?"; then
    grep -v '^#' "$HOME/.config/xdg-terminals.list" 2>/dev/null | head -1 > "$STATE_DIR/prev-terminal" || true
    omarchy default terminal ghostty >/dev/null
    ok "Ghostty is now the default terminal"
  else
    skip "kept your current default terminal"
  fi
else
  ok "Ghostty ready"
fi

# 1b. Font
FONT="JetBrainsMono Nerd Font"
if [[ $(omarchy font current 2>/dev/null) == "$FONT" ]]; then
  ok "font: $FONT"
elif ! fc-list | grep -q "$FONT"; then
  skip "font $FONT not installed; keeping your current font"
elif ask "Switch your system font to $FONT, the font Afterburn is designed around?"; then
  omarchy font current > "$STATE_DIR/prev-font" 2>/dev/null || true
  omarchy font set "$FONT" >/dev/null
  ok "font set to $FONT"
else
  skip "kept your current font"
fi

# 2. cursor-fx
if command -v cursor-fx >/dev/null; then
  ok "cursor-fx already installed"
elif ! command -v ghostty >/dev/null; then
  skip "skipped cursor-fx (needs Ghostty)"
elif ask "Install cursor-fx, animated Ghostty cursors by Avarce (MIT)?"; then
  [[ -f $HOME/.config/ghostty/config ]] || omarchy refresh config ghostty/config >/dev/null
  rm -rf "$CFX_DIR"
  git clone -q "$CFX_REPO" "$CFX_DIR"
  git -C "$CFX_DIR" -c advice.detachedHead=false checkout -q "$CFX_PIN"
  (cd "$CFX_DIR" && ./install.sh >/dev/null)
  ok "cursor-fx installed (old Ghostty config backed up in ~/ghostty-savepoints/)"
else
  skip "skipped cursor-fx. Re-run this script any time to add it"
fi

# 3. Glow + cursor hook
omarchy hook install theme-set "$HERE/afterburn-theme-set-hook" >/dev/null
mv -f "$HOOKS/afterburn-theme-set-hook" "$HOOKS/$HOOK_NAME"
ok "glow hook installed"

omarchy theme set afterburn >/dev/null
echo; o "  ❯ afterburn is live. Open a new Ghostty window (Super + Return) and type."; echo
