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

echo; o "  ❯ afterburn // full stack"; echo

# 1. Ghostty
if ! command -v ghostty >/dev/null; then
  if ask "Install Ghostty and make it your default terminal? (the cursor effects need it)"; then
    omarchy install terminal ghostty
    ok "Ghostty installed and set as default"
  else
    skip "skipped Ghostty: no cursor effects without it"
  fi
elif ! grep -qi ghostty <(grep -v '^#' "$HOME/.config/xdg-terminals.list" 2>/dev/null | head -1); then
  if ask "Make Ghostty your default terminal (Super + Return)?"; then
    omarchy default terminal ghostty >/dev/null
    ok "Ghostty is now the default terminal"
  else
    skip "kept your current default terminal"
  fi
else
  ok "Ghostty ready"
fi

# 2. cursor-fx
if command -v cursor-fx >/dev/null; then
  ok "cursor-fx already installed"
elif ! command -v ghostty >/dev/null; then
  skip "skipped cursor-fx (needs Ghostty)"
elif ask "Install cursor-fx, animated Ghostty cursors by Avarce (MIT)?"; then
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
