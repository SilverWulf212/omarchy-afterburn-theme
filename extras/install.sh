#!/bin/bash
# Afterburn: the full stack.
#   1. Ghostty terminal (installed and made default if needed)
#   2. cursor-fx animated cursors by Avarce (MIT), set to the theme's effect while Afterburn is active
#      (embers on the base theme, the edition's own on a colour edition)
#   3. The orange window glow (Omarchy drops .lua from installed themes; a theme-set hook restores it)
#   4. The subtle pack (optional): slow border turn, dimmed background windows, heat levels,
#      quiet fullscreen, battery saver, red prompt with a fail flash, the `afterburn` CLI
#   5. The animated lock screen (optional, asked separately)
#   6. Colour editions: Voltage, Cyber, Overdrive, Redline, Phantom (optional, asked separately)
#   7. The boot/login screen set to the current theme (optional, needs sudo, default No)
# Run:  ~/.config/omarchy/themes/afterburn/extras/install.sh        (asks before each step)
#       ~/.config/omarchy/themes/afterburn/extras/install.sh --yes  (no questions)
# Undo: ~/.config/omarchy/themes/afterburn/extras/uninstall.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# The hook, the CLI and the .bashrc line all look for the extras at this path, so a copy of the theme
# anywhere else would install links to files nothing reads. Stop before changing anything.
EXPECTED="$HOME/.config/omarchy/themes/afterburn/extras"
if [[ $(realpath -- "$HERE") != "$(realpath -m -- "$EXPECTED")" ]]; then
  echo "afterburn: run this from the installed theme: $EXPECTED/install.sh" >&2
  echo "  (this copy is at $HERE; install the theme first: omarchy theme install https://github.com/silverwulf212/omarchy-afterburn-theme)" >&2
  exit 1
fi
HOOK_NAME=50-afterburn-extras
HOOKS="$HOME/.config/omarchy/hooks/theme-set.d"
CFX_REPO=https://github.com/Avarce/ghostty-cursor-fx.git
CFX_PIN=252df6c6344fe68ab8715d3e4a57f73ad91ed7ed   # version tested with Afterburn
CFX_DIR="$HOME/.local/share/afterburn/ghostty-cursor-fx"
YES=false; [[ ${1:-} == --yes || ${1:-} == -y ]] && YES=true

o() { printf '\033[38;2;245;145;69m%s\033[0m\n' "$*"; }
ok() { printf '  \033[38;2;245;145;69m✓\033[0m %s\n' "$*"; }
skip() { printf '  \033[2m· %s\033[0m\n' "$*"; }
# EOF (no terminal / closed stdin) counts as No, so nothing changes unasked.
ask() { $YES && return 0; local a; read -rp "  $1 [Y/n] " a || { echo; return 1; }; [[ -z $a || $a =~ ^[Yy] ]]; }
# Default No, and --yes does not answer it: for steps that need sudo or change the system outside the theme.
ask_no() { local a; read -rp "  $1 [y/N] " a || { echo; return 1; }; [[ $a =~ ^[Yy] ]]; }

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/afterburn"

# Each step records here just before it changes something, so a failure can say what was touched.
CHANGED=()
FAILED_LINE=""
trap 'FAILED_LINE=$LINENO' ERR
on_exit() {
  local rc=$?
  (( rc == 0 )) && return 0
  echo
  o "  ✗ install stopped (exit $rc, near line ${FAILED_LINE:-?}). The steps after it did not run."
  if (( ${#CHANGED[@]} )); then
    echo "  Already changed:"
    printf '    - %s\n' "${CHANGED[@]}"
  else
    echo "  Nothing was changed yet."
  fi
  echo "  Undo: $HERE/uninstall.sh"
}
trap on_exit EXIT

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
    on every theme change: it adds the glow on Afterburn, swaps your cursor effect and
    applies the subtle pack's settings.
  • GPU / BATTERY: cursor shaders make Ghostty redraw constantly. `cursor-fx off` stops it.
  • MOTION: cursor effects animate and flash. If motion bothers you, skip cursor-fx
    or run `cursor-fx subtle on`.
  • SUBTLE PACK (optional): links afterburn and afterburn-watch into ~/.local/bin, writes
    ~/.config/afterburn/afterburn.conf, installs and starts a user systemd service
    (afterburn-watch), adds one guarded line to ~/.bashrc, changes error_symbol in
    ~/.config/starship.toml (backup in ~/.local/state/afterburn/), and copies a desktop
    entry to ~/.local/share/applications/. Its heat source "weather" is the only option
    that calls the network: api.weather.gov, and api.zippopotam.us once to find your ZIP.
  • LOCK SCREEN (optional, asked separately): clones Omarchy's lock screen plugin and adds
    an ember layer. The clone stops getting Omarchy's lock-screen updates until you uninstall.
  • COLOUR EDITIONS (optional, asked separately): copies the Voltage, Cyber, Overdrive,
    Redline and Phantom themes from this theme's .editions/ folder to
    ~/.config/omarchy/themes/afterburn-<name>. A folder that already exists is never touched.
    uninstall.sh removes only the ones it created.
  • BOOT/LOGIN SCREEN (optional, default No, needs sudo): runs Omarchy's
    omarchy-plymouth-set-by-theme for the current theme. It changes the boot splash and the
    login screen. Undo with Omarchy's own: omarchy-plymouth-reset (also needs sudo).

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
    CHANGED+=("Ghostty installed and made default terminal")
    omarchy install terminal ghostty
    ok "Ghostty installed and set as default"
  else
    skip "skipped Ghostty: no cursor effects without it"
  fi
elif ! grep -qi ghostty <(grep -v '^#' "$HOME/.config/xdg-terminals.list" 2>/dev/null | head -1); then
  if ask "Make Ghostty your default terminal (Super + Return), replacing your current one?"; then
    grep -v '^#' "$HOME/.config/xdg-terminals.list" 2>/dev/null | head -1 > "$STATE_DIR/prev-terminal" || true
    CHANGED+=("default terminal set to Ghostty")
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
elif ! fc-list | grep -F "$FONT" >/dev/null; then
  skip "font $FONT not installed; keeping your current font"
elif ask "Switch your system font to $FONT, the font Afterburn is designed around?"; then
  omarchy font current > "$STATE_DIR/prev-font" 2>/dev/null || true
  CHANGED+=("system font set to $FONT")
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
  CHANGED+=("cursor-fx installed (its own installer edits Ghostty config; old config in ~/ghostty-savepoints/)")
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
CHANGED+=("theme-set hook added")
omarchy hook install theme-set "$HERE/afterburn-theme-set-hook" >/dev/null
mv -f "$HOOKS/afterburn-theme-set-hook" "$HOOKS/$HOOK_NAME"
ok "glow hook installed"

# 4. Subtle pack (optional). Config keys and commands: see the README's "Subtle pack" section.
CONF_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CONF="$CONF_HOME/afterburn/afterburn.conf"
BIN="$HOME/.local/bin"
UNIT_DIR="$CONF_HOME/systemd/user"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
STARSHIP="$CONF_HOME/starship.toml"
BASHRC="$HOME/.bashrc"
FAIL_SH='$HOME/.config/omarchy/themes/afterburn/extras/afterburn-fail.bash'
conf_set() { sed -i -E "s/^$1=[^ #]*/$1=$2/" "$CONF"; }

echo
# Never overwrite a file of the user's own: if a name is taken by something that is not our link,
# the whole subtle pack is skipped (the watcher unit would otherwise run their file).
SUBTLE_BLOCKED=""
for f in afterburn afterburn-watch; do
  t="$BIN/$f"
  if [[ ( -e $t || -L $t ) && $(readlink "$t" 2>/dev/null) != "$HERE/bin/$f" ]]; then SUBTLE_BLOCKED=$t; fi
done
if [[ -n $SUBTLE_BLOCKED ]]; then
  skip "warning: $SUBTLE_BLOCKED already exists and is not Afterburn's link, so the subtle pack was skipped. Move it aside and re-run."
elif ask "Add the subtle pack? (slow-turning border, dimmed background windows, heat levels, quiet fullscreen, battery saver, red prompt with a fail flash, afterburn colors)"; then
  mkdir -p "$BIN" "$UNIT_DIR" "$APPS_DIR"
  CHANGED+=("subtle pack: links in ~/.local/bin, ~/.config/afterburn/afterburn.conf, desktop entry")
  for f in afterburn afterburn-watch; do ln -sfn "$HERE/bin/$f" "$BIN/$f"; done
  ok "afterburn and afterburn-watch linked into ~/.local/bin"

  # Writes the default conf if there is none. An existing conf keeps its settings.
  "$BIN/afterburn" get >/dev/null

  # Heat source: "time" on a first install, and whatever you set before on a re-run. Only an answer
  # here changes it: Enter, EOF and --yes keep it, so a re-run never undoes your choice (and --yes never
  # turns on the weather source, the one that calls the network).
  HEAT=$("$BIN/afterburn" get HEAT_SOURCE)
  a=""
  if ! $YES; then
    read -rp "  Heat source: [t]ime, [p]ressure (CPU load), [w]eather (US ZIP; calls NWS), [o]ff. Enter keeps $HEAT: " a || a=""
    case $a in
      t*|T*) HEAT=time ;;
      p*|P*) HEAT=pressure ;;
      w*|W*) HEAT=weather ;;
      o*|O*) HEAT=off ;;
    esac
  fi
  if [[ $a =~ ^[Ww] ]]; then
    read -rp "  US ZIP code (sent once to api.zippopotam.us to find your coordinates): " zip || zip=""
    if [[ $zip =~ ^[0-9]{5}$ ]] && "$BIN/afterburn" locate "$zip" >/dev/null 2>&1; then
      ok "location saved for the weather heat source"
    else
      skip "no ZIP lookup, so the heat source is time instead"
      HEAT=time
    fi
  fi
  conf_set HEAT_SOURCE "$HEAT"
  ok "heat source: $HEAT"

  # Red error symbol in starship.toml. The original is backed up once, before the first edit.
  if [[ -f $STARSHIP ]]; then
    [[ -f $STATE_DIR/starship.toml.bak ]] || cp -p "$STARSHIP" "$STATE_DIR/starship.toml.bak"
    # Remember only the original error_symbol line ("absent" if there was none). uninstall.sh puts it back.
    [[ -f $STATE_DIR/starship-error-symbol ]] || awk '
      /^\[/ { sec = $0; sub(/^\[/, "", sec); sub(/\].*$/, "", sec) }
      sec == "character" && /^error_symbol[ \t]*=/ { print; found = 1; exit }
      END { if (!found) print "absent" }
    ' "$STARSHIP" > "$STATE_DIR/starship-error-symbol"
    CHANGED+=("starship.toml error_symbol (safety copy of the whole file in $STATE_DIR/starship.toml.bak)")
    awk -v line='error_symbol = "[❯](bold red)"' '
      function close_character() { if (sec == "character" && !done) { print line; done = 1 } }
      /^\[/ { close_character(); sec = $0; sub(/^\[/, "", sec); sub(/\].*$/, "", sec); print; next }
      sec == "character" && /^error_symbol[ \t]*=/ { print line; done = 1; next }
      { print }
      END { if (!done) { if (sec == "character") print line; else { print ""; print "[character]"; print line } } }
    ' "$STARSHIP" > "$STATE_DIR/starship.tmp" \
      && cat "$STATE_DIR/starship.tmp" > "$STARSHIP" && rm -f "$STATE_DIR/starship.tmp" \
      && ok "prompt: failed command shows a red ❯ (backup in $STATE_DIR/starship.toml.bak)" \
      || skip "couldn't edit $STARSHIP; prompt unchanged"
  else
    skip "no $STARSHIP, so the prompt symbol is unchanged"
  fi

  # One guarded line in ~/.bashrc, sourced only when the file exists.
  if ! grep -q '# afterburn$' "$BASHRC" 2>/dev/null; then
    CHANGED+=("~/.bashrc: fail-effect line appended")
    [[ -e $BASHRC ]] || : > "$STATE_DIR/bashrc-created"   # no .bashrc yet: uninstall.sh removes ours again if it ends up empty
    if [[ -s $BASHRC && -n $(tail -c1 "$BASHRC") ]]; then
      echo >> "$BASHRC"
      : > "$STATE_DIR/bashrc-newline"   # uninstall.sh drops this newline again
    fi
    echo "[[ -f \"$FAIL_SH\" ]] && source \"$FAIL_SH\"  # afterburn" >> "$BASHRC"
  fi
  ok "~/.bashrc: one guarded line sources the fail effect"

  # User service: the watcher handles fullscreen quiet, battery saver and the heat level.
  CHANGED+=("afterburn-watch user service enabled")
  cp "$HERE/afterburn-watch.service" "$UNIT_DIR/afterburn-watch.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  if systemctl --user enable --now afterburn-watch.service >/dev/null 2>&1; then
    ok "watcher service enabled (user unit: afterburn-watch)"
  else
    skip "couldn't start the watcher; run: systemctl --user enable --now afterburn-watch.service"
  fi

  cp "$HERE/afterburn-colors.desktop" "$APPS_DIR/afterburn-colors.desktop"
  ok "subtle pack installed. Try: afterburn status"
else
  skip "skipped the subtle pack. Re-run this script any time to add it"
fi

# 5. Animated lock screen (optional, asked separately). The script clones Omarchy's lock plugin.
LOCK="$HERE/lock/lock-embers.sh"
echo
if [[ ! -f $LOCK ]]; then
  skip "lock screen: $LOCK not found, skipped"
elif ask "Animate the lock screen with embers? (clones Omarchy's lock plugin; it stops getting Omarchy's lock-screen updates until you uninstall)"; then
  CLONE_DIR="$HOME/.config/omarchy/plugins/${USER:-$(id -un)}.lock"
  CHANGED+=("lock screen clone $CLONE_DIR (if it exists, uninstall.sh removes it)")
  rc=0
  bash "$LOCK" install || rc=$?
  # Mark whenever the clone exists, even after a failure, so uninstall.sh always undoes it.
  if [[ -e $CLONE_DIR || -L $CLONE_DIR ]]; then : > "$STATE_DIR/lock-embers"; fi
  if (( rc == 0 )); then
    ok "lock screen animated with embers"
  elif (( rc == 3 )); then
    skip "lock screen: another lock screen is active, so nothing changed"
  else
    skip "lock screen: the install did not finish (see the messages above)"
  fi
else
  skip "kept the stock lock screen"
fi

# 6. Colour editions (optional, asked separately). Each .editions/<name>/ is a complete Omarchy theme
# (the folder is hidden so Omarchy's theme staging, which globs `*`, does not copy it on every switch);
# the installer copies it to ~/.config/omarchy/themes/afterburn-<name>. A folder that is already there
# is never touched or recorded, so uninstall.sh can only ever remove what this script made.
THEME_ROOT="$(dirname "$HERE")"
THEMES_HOME="$HOME/.config/omarchy/themes"
# add_missing SRC DEST: copy every file under SRC that DEST does not have yet. Prints how many.
add_missing() {
  local f n=0
  while IFS= read -r -d '' f; do
    [[ -e $2/$f || -L $2/$f ]] && continue
    mkdir -p "$(dirname "$2/$f")" && cp -a "$1/$f" "$2/$f" && n=$((n + 1))
  done < <(cd "$1" && find . -type f -print0)
  echo "$n"
}
EDITIONS=(voltage cyber overdrive redline phantom)
echo
AVAILABLE=()
for e in "${EDITIONS[@]}"; do [[ -f $THEME_ROOT/.editions/$e/colors.toml ]] && AVAILABLE+=("$e"); done
if (( ${#AVAILABLE[@]} == 0 )); then
  skip "colour editions: no .editions/ folder in $THEME_ROOT (this copy of the theme has none), skipped"
elif ask "Install colour editions (Voltage, Cyber, Overdrive, Redline, Phantom)? (copies each to ~/.config/omarchy/themes/afterburn-<name>; the extras follow the edition you pick)"; then
  for e in "${AVAILABLE[@]}"; do
    dest="$THEMES_HOME/afterburn-$e"
    if [[ -e $dest || -L $dest ]]; then
      if grep -qxF "$e" "$STATE_DIR/editions" 2>/dev/null; then
        # Ours: add what this release has and the copy lacks (a new wallpaper set, say). Never overwrites.
        added=$(add_missing "$THEME_ROOT/.editions/$e" "$dest")
        if (( added )); then ok "afterburn-$e already installed; added $added new files"; else ok "afterburn-$e already installed"; fi
      else
        skip "afterburn-$e: $dest already exists and is not ours, left alone"
      fi
      continue
    fi
    mkdir -p "$THEMES_HOME"
    # Record first, so uninstall.sh also cleans up a copy that stops halfway.
    echo "$e" >> "$STATE_DIR/editions"
    CHANGED+=("edition theme $dest")
    cp -a "$THEME_ROOT/.editions/$e" "$dest"
    ok "edition installed: afterburn-$e"
  done
else
  skip "skipped the colour editions. Re-run this script any time to add them"
fi

# Which theme the installer leaves active: the current Afterburn edition if one is active, else the base.
FINAL_THEME=afterburn
CUR_NAME=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme.name" 2>/dev/null || true)
[[ $CUR_NAME == afterburn-* && -d $THEMES_HOME/$CUR_NAME ]] && FINAL_THEME=$CUR_NAME

# 7. Boot/login screen (optional). Default No: needs sudo and changes the system outside your home folder.
echo
if ! command -v omarchy-plymouth-set-by-theme >/dev/null; then
  skip "boot/login screen: omarchy-plymouth-set-by-theme not found, skipped"
elif [[ ! -f $THEMES_HOME/$FINAL_THEME/unlock.png ]]; then
  skip "boot/login screen: $FINAL_THEME has no unlock.png, skipped"
elif $YES; then
  skip "boot/login screen: --yes does not answer this one (it needs sudo). Run: omarchy-plymouth-set-by-theme $FINAL_THEME"
elif ask_no "Set the boot and login screen to $FINAL_THEME? (needs sudo and changes Omarchy's boot splash and login screen; undo: omarchy-plymouth-reset)"; then
  echo "$FINAL_THEME" > "$STATE_DIR/plymouth"   # recorded before the change, so uninstall.sh offers the undo
  CHANGED+=("boot/login screen set to $FINAL_THEME (undo: omarchy-plymouth-reset)")
  if omarchy-plymouth-set-by-theme "$FINAL_THEME"; then
    ok "boot/login screen set to $FINAL_THEME. Undo any time: omarchy-plymouth-reset"
  else
    skip "boot/login screen: the change did not finish. To be safe, undo with: omarchy-plymouth-reset"
  fi
else
  skip "kept the boot and login screen"
fi

CHANGED+=("theme set to $FINAL_THEME")
omarchy theme set "$FINAL_THEME" >/dev/null
if command -v cursor-fx >/dev/null; then
  echo; o "  ❯ $FINAL_THEME is live. Open a new Ghostty window (Super + Return) and type."; echo
else
  echo; o "  ❯ $FINAL_THEME is live."; echo
fi
