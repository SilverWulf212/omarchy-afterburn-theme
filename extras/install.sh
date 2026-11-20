#!/bin/bash
# Afterburn: the full stack.
#   1. Ghostty terminal (installed and made default if needed)
#   2. cursor-fx animated cursors by Avarce (MIT), set to the theme's effect while Afterburn is active
#      (embers on the base theme, the edition's own on a colour edition)
#   3. The orange window glow (Omarchy drops .lua from installed themes; a theme-set hook restores it)
#   4. The subtle pack (optional): slow border turn, dimmed background windows, heat levels,
#      quiet fullscreen, battery saver, red prompt with a fail flash, the `afterburn` CLI
#   5. The animated lock screen (optional, asked separately)
#   6. Colour editions, one per folder in .editions/ (optional, asked separately)
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
# shellcheck disable=SC1091
. "$HERE/afterburn-theme.sh"   # AB_BASHRC_LINE
HOOK_NAME=50-afterburn-extras
HOOKS="$HOME/.config/omarchy/hooks/theme-set.d"
# Vendored copy of ghostty-cursor-fx by Avarce (MIT) at commit 252df6c6344fe68ab8715d3e4a57f73ad91ed7ed, the
# version tested with Afterburn (the upstream repo was taken down; the commit survives in its forks).
CFX_SRC="$HERE/ghostty-cursor-fx"
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
BASHRC="$HOME/.bashrc"

# Append one guarded line ($1) to ~/.bashrc unless it is there already. $2 names the marker that tells
# uninstall.sh a newline was added before it (the file did not end in one), so it can drop that again.
# $3 is the rc file (default ~/.bashrc; the zsh line passes ~/.zshrc, which it only touches when it exists).
add_bashrc_line() {
  local rc=${3:-$BASHRC}
  grep -qxF "$1" "$rc" 2>/dev/null && return 0
  mkdir -p "$STATE_DIR"
  [[ -e $rc ]] || : > "$STATE_DIR/bashrc-created"   # no .bashrc yet: uninstall.sh removes ours again if it ends up empty
  if [[ -s $rc && -n $(tail -c1 "$rc") ]]; then
    echo >> "$rc"
    : > "$STATE_DIR/$2"
  fi
  echo "$1" >> "$rc"
}
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

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
  • THIRD-PARTY CODE: copies ghostty-cursor-fx by Avarce (MIT, bundled with this theme at
    one tested commit) and runs its installer. It writes ~/.local/bin/cursor-fx,
    ~/.config/ghostty/shaders/ and cursor-effects/, edits ~/.config/ghostty/config,
    and, if ~/.pi/agent exists, adds a pi extension and turns on showHardwareCursor.
    Anything it replaces is copied to ~/.local/state/afterburn/ghostty-savepoints/ first.
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
  • COLOUR EDITIONS (optional, asked separately): copies the colour edition themes (the
    question names them) from this theme's .editions/ folder to
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

# What the default terminal was before: the first entry of your own list, or "none" when you have no list
# or it has no entries (a fresh Omarchy user: the system default applies, and uninstall.sh removes the list this step creates).
record_prev_terminal() {
  local first
  first=$(grep -vE '^[[:space:]]*(#|$)' "$HOME/.config/xdg-terminals.list" 2>/dev/null | head -1) || true
  echo "${first:-none}" > "$STATE_DIR/prev-terminal"
}

# 1. Ghostty
if ! command -v ghostty >/dev/null; then
  if ask "Install Ghostty and make it your default terminal? (the cursor effects need it)"; then
    record_prev_terminal
    CHANGED+=("Ghostty installed and made default terminal")
    omarchy install terminal ghostty
    ok "Ghostty installed and set as default"
  else
    skip "skipped Ghostty: no cursor effects without it"
  fi
elif ! grep -qi ghostty <(grep -v '^#' "$HOME/.config/xdg-terminals.list" 2>/dev/null | head -1); then
  if ask "Make Ghostty your default terminal (Super + Return), replacing your current one?"; then
    record_prev_terminal
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
  CHANGED+=("cursor-fx installed (its own installer edits Ghostty config; old config in $AB_SAVEPOINTS/)")
  [[ -f $HOME/.config/ghostty/config ]] || omarchy refresh config ghostty/config >/dev/null
  rm -rf "$CFX_DIR"
  mkdir -p "$(dirname "$CFX_DIR")"
  cp -a "$CFX_SRC" "$CFX_DIR"
  (cd "$CFX_DIR" && ./install.sh >/dev/null)
  ok "cursor-fx installed (old Ghostty config backed up in $AB_SAVEPOINTS/)"
else
  skip "skipped cursor-fx. Re-run this script any time to add it"
fi
# Enter and done moments in bash: cursor-fx's own installer wires pi only (zsh and Claude Code are manual).
if command -v cursor-fx >/dev/null; then
  if grep -qxF "$AB_CFX_BASHRC_LINE" "$BASHRC" 2>/dev/null; then
    ok "cursor effects play on Enter in bash"
  elif ask "Play the cursor effect on Enter in bash? (one line in ~/.bashrc; cursor-fx ships only a zsh hook)"; then
    CHANGED+=("~/.bashrc: cursor-fx Enter line appended")
    add_bashrc_line "$AB_CFX_BASHRC_LINE" cfx-bashrc-newline
    ok "cursor effects play on Enter in bash (new terminals)"
  else
    skip "skipped the bash Enter hook: the effect plays while typing, not on Enter"
  fi
fi
# cursor-fx's installer always backs up to ~/ghostty-savepoints; older Afterburn left its savepoints there too.
if [[ -d $HOME/ghostty-savepoints ]]; then
  ab_move_savepoints
  [[ -d $HOME/ghostty-savepoints ]] || ok "Ghostty savepoints moved out of your home folder to $CURSOR_FX_SAVEPOINTS/"
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
# Rewrite KEY=VALUE in place, or append it when the conf has no such line (as set_key in bin/afterburn does).
conf_set() {
  if grep -q "^$1=" "$CONF"; then
    sed -i --follow-symlinks -E "s/^$1=[^ #]*/$1=$2/" "$CONF"
  else
    [[ ! -s $CONF || -z $(tail -c1 "$CONF") ]] || printf '\n' >> "$CONF"
    printf '%s=%s\n' "$1" "$2" >> "$CONF"
  fi
}

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

  # Red error symbol in starship.toml. The original is backed up once, before the first edit. The theme-set hook
  # takes the symbol out on other themes and puts it back on Afterburn (ab_starship_* in afterburn-theme.sh).
  if [[ -f $STARSHIP ]]; then
    [[ -f $STATE_DIR/starship.toml.bak ]] || cp -p "$STARSHIP" "$STATE_DIR/starship.toml.bak"
    CHANGED+=("starship.toml error_symbol (safety copy of the whole file in $STATE_DIR/starship.toml.bak)")
    if ab_starship_record && ab_starship_apply; then
      ok "prompt: failed command shows a red ❯ on Afterburn themes (backup in $STATE_DIR/starship.toml.bak)"
    else
      skip "couldn't edit $STARSHIP; prompt unchanged"
    fi
  else
    skip "no $STARSHIP, so the prompt symbol is unchanged"
  fi

  # One guarded line in ~/.bashrc, sourced only when the file exists.
  grep -qxF "$AB_BASHRC_LINE" "$BASHRC" 2>/dev/null || CHANGED+=("~/.bashrc: fail-effect line appended")
  add_bashrc_line "$AB_BASHRC_LINE" bashrc-newline
  ok "~/.bashrc: one guarded line sources the fail effect"
  # zsh users get the zsh twin. Only into a ~/.zshrc that exists: a missing one would make zsh skip its
  # first-run setup, and an absent file means zsh is not what you use.
  if [[ -f $ZSHRC ]]; then
    grep -qxF "$AB_ZSHRC_LINE" "$ZSHRC" 2>/dev/null || CHANGED+=("~/.zshrc: fail-effect line appended")
    add_bashrc_line "$AB_ZSHRC_LINE" zshrc-newline "$ZSHRC"
    ok "~/.zshrc: one guarded line sources the fail effect"
  fi

  # User service: the watcher handles fullscreen quiet, battery saver and the heat level.
  CHANGED+=("afterburn-watch user service enabled")
  cp "$HERE/afterburn-watch.service" "$UNIT_DIR/afterburn-watch.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  # enable --now leaves a running unit as it is, so a re-install restarts it to pick up new watcher code.
  watcher_was=$(systemctl --user is-active afterburn-watch.service 2>/dev/null || true)
  if systemctl --user enable --now afterburn-watch.service >/dev/null 2>&1 &&
     { [[ $watcher_was != active ]] || systemctl --user restart afterburn-watch.service >/dev/null 2>&1; }; then
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
elif [[ $(bash "$LOCK" target 2>/dev/null) == explorer ]]; then
  LOCK_Q="Add an Afterburn lock design with embers to Lock Screen Explorer? (a design file in ~/.config/omarchy/lock-designs; the explorer itself is not changed)"
  LOCK_CHANGE="Afterburn design in ~/.config/omarchy/lock-designs (uninstall.sh removes it)"
else
  LOCK_Q="Animate the lock screen with embers? (clones Omarchy's lock plugin; it stops getting Omarchy's lock-screen updates until you uninstall)"
  LOCK_CHANGE="lock screen clone in ~/.config/omarchy/plugins (afterburn.lock; uninstall.sh removes it)"
fi
if [[ -n ${LOCK_Q:-} ]] && ask "$LOCK_Q"; then
  # lock-embers.sh picks the clone id (afterburn.lock; an older install keeps its <user>.lock) and writes
  # the marker $STATE_DIR/lock-embers with it as soon as the clone exists. If a step fails after the
  # built-in lock was switched off, it puts the built-in lock back before it exits.
  CHANGED+=("$LOCK_CHANGE")
  rc=0
  bash "$LOCK" install || rc=$?
  if (( rc == 0 )); then
    ok "lock screen animated with embers"
  elif (( rc == 3 )); then
    skip "lock screen: another lock screen is active, so nothing changed"
  else
    skip "lock screen: the install did not finish (see the messages above)"
  fi
elif [[ -n ${LOCK_Q:-} ]]; then
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
# The folders under .editions/ are the list; nothing here names an edition.
echo
AVAILABLE=() NAMES=()
for d in "$THEME_ROOT"/.editions/*/; do
  e=${d%/}; e=${e##*/}
  [[ $e =~ ^[a-z0-9]+$ && -f $d/colors.toml ]] && { AVAILABLE+=("$e"); NAMES+=("${e^}"); }
done
printf -v NAMES_LIST '%s, ' "${NAMES[@]}"; NAMES_LIST=${NAMES_LIST%, }
if (( ${#AVAILABLE[@]} == 0 )); then
  skip "colour editions: no .editions/ folder in $THEME_ROOT (this copy of the theme has none), skipped"
elif ask "Install colour editions ($NAMES_LIST)? (copies each to ~/.config/omarchy/themes/afterburn-<name>; the extras follow the edition you pick)"; then
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
CUR_NAME=$(ab_theme_name)
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
