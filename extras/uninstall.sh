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
FAILED=0
# Only remove a regular file whose contents still match our installation snapshot.
remove_owned() {
  local path=$1 key=$2
  [[ -f $STATE_DIR/owned/$key ]] || return 0
  if [[ ! -e $path && ! -L $path ]]; then
    rm -f "$STATE_DIR/owned/$key" || FAILED=1
  elif [[ ! -L $path && -f $path ]] && cmp -s "$path" "$STATE_DIR/owned/$key"; then
    if rm -f "$path"; then rm -f "$STATE_DIR/owned/$key" || FAILED=1; else FAILED=1; fi
  else
    echo "  · $path changed since install; kept your copy"
    rm -f "$STATE_DIR/owned/$key" || FAILED=1
  fi
}

if [[ -s $STATE_DIR/prev-terminal ]]; then
  prev=$(cat "$STATE_DIR/prev-terminal")
  name=$(basename "$prev" .desktop | sed -E 's/.*\.//; s/^(ghostty|alacritty|kitty|foot).*/\1/' | tr '[:upper:]' '[:lower:]')
  if [[ $name =~ ^(alacritty|foot|ghostty|kitty)$ ]]; then
    if omarchy default terminal "$name" >/dev/null; then
      rm -f "$STATE_DIR/prev-terminal"
      echo "  ✓ default terminal restored to $name"
    else FAILED=1; fi
  else
    echo "  · previous terminal was $prev; set it again with: omarchy default terminal <name>"
    FAILED=1
  fi
fi
if [[ -s $STATE_DIR/prev-font ]]; then
  if omarchy font set "$(cat "$STATE_DIR/prev-font")" >/dev/null; then
    echo "  ✓ font restored to $(cat "$STATE_DIR/prev-font")"
    rm -f "$STATE_DIR/prev-font"
  else FAILED=1; fi
fi

# Colour editions: remove only the afterburn-<name> folders the installer copied (listed in the state
# dir). A folder of the same name that the installer did not create is never in that list.
edition_inventory() {
  (cd "$1" && find . -mindepth 1 -print0 | sort -z |
    while IFS= read -r -d '' f; do
      if [[ -L $f ]]; then printf 'link %s %s\n' "$f" "$(readlink "$f")";
      elif [[ -f $f ]]; then sha256sum "$f";
      else printf 'dir %s\n' "$f"; fi
    done)
}
# During retry, files already deleted are expected; every survivor must still match.
edition_survivors_unchanged() {
  local inventory
  inventory=$(edition_inventory "$1") || return 1
  [[ -z $inventory ]] && return 0
  printf '%s\n' "$inventory" | awk '
    NR == FNR { known[$0] = 1; next }
    !($0 in known) { bad = 1 }
    END { exit bad }
  ' "$2" -
}
THEMES_HOME="$HOME/.config/omarchy/themes"
if [[ -s $STATE_DIR/editions ]]; then
  cur=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme.name" 2>/dev/null || true)
  pending=$(mktemp "$STATE_DIR/.editions.XXXXXX")
  while IFS= read -r e || [[ -n $e ]]; do
    [[ $e =~ ^[a-z]+$ ]] || continue          # the state file is data: only plain edition names
    dir="$THEMES_HOME/afterburn-$e"
    [[ -d $dir && ! -L $dir ]] || continue
    if [[ ! -f $STATE_DIR/owned-editions/$e ]] ||
       { ! cmp -s <(edition_inventory "$dir") "$STATE_DIR/owned-editions/$e" &&
         { [[ ! -f $STATE_DIR/removing-editions/$e ]] ||
           ! edition_survivors_unchanged "$dir" "$STATE_DIR/owned-editions/$e"; }; }; then
      echo "  · kept afterburn-$e: changed since install, or from an older install without an ownership snapshot"
      continue
    fi
    if [[ $cur == "afterburn-$e" ]]; then
      # Decision: switch to the base theme first, so the desktop is never left on a theme that is gone.
      # stdin is the editions list this loop is reading: keep the command away from it.
      omarchy theme set afterburn >/dev/null 2>&1 </dev/null || true
      cur=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme.name" 2>/dev/null || true)
      if [[ $cur == afterburn ]]; then
        echo "  ✓ switched from afterburn-$e to afterburn"
      else
        echo "  · afterburn-$e is your active theme and could not be switched, so it was kept."
        echo "    Switch theme (omarchy theme set <name>), then remove it: rm -rf $dir"
        echo "$e" >> "$pending"
        FAILED=1
        continue
      fi
    fi
    mkdir -p "$STATE_DIR/removing-editions"
    : > "$STATE_DIR/removing-editions/$e"
    if rm -rf "$dir"; then echo "  ✓ edition removed: afterburn-$e";
    else echo "$e" >> "$pending"; FAILED=1; fi
  done < "$STATE_DIR/editions"
  mv "$pending" "$STATE_DIR/editions"
fi

# Cursor effect: after the edition switch above, not before. Switching to the base theme runs the theme-set
# hook, which sets that theme's effect; restoring first would let it overwrite your own effect again.
if [[ -f $STATE_DIR/prev-cursor-fx ]]; then
  if command -v cursor-fx >/dev/null && cursor-fx "$(cat "$STATE_DIR/prev-cursor-fx")" >/dev/null 2>&1; then
    rm -f "$STATE_DIR/prev-cursor-fx"
    echo "  ✓ cursor effect restored"
  else FAILED=1; fi
fi

# Subtle: only if battery saver turned it on and nothing has turned it off again (a subtle you had on is left alone).
if [[ -f $STATE_DIR/subtle-by-afterburn ]]; then
  if command -v cursor-fx >/dev/null && cursor-fx subtle off >/dev/null 2>&1; then
    rm -f "$STATE_DIR/subtle-by-afterburn"
    echo "  ✓ cursor subtle mode restored"
  else FAILED=1; fi
fi

# Lock screen: only if the installer added the embers (marker written on a successful install).
if [[ -f $STATE_DIR/lock-embers ]]; then
  if [[ -f $HERE/lock/lock-embers.sh ]] && bash "$HERE/lock/lock-embers.sh" uninstall; then
    rm -f "$STATE_DIR/lock-embers"
    echo "  ✓ lock screen cleanup finished"
  else
    echo "  · lock screen not restored; run: bash $HERE/lock/lock-embers.sh uninstall"
    FAILED=1
  fi
fi

# Subtle pack: each piece is removed only if the installer put it there.
UNIT="$CONF_HOME/systemd/user/afterburn-watch.service"
if [[ ! -L $UNIT && -f $STATE_DIR/owned/unit ]] && cmp -s "$UNIT" "$STATE_DIR/owned/unit"; then
  if systemctl --user disable --now afterburn-watch.service >/dev/null 2>&1; then
    remove_owned "$UNIT" unit
    systemctl --user daemon-reload >/dev/null 2>&1 || true
  else
    echo "  · watcher could not be stopped; kept its unit for retry"
    FAILED=1
  fi
else
  remove_owned "$UNIT" unit
fi
if [[ ! -f $STATE_DIR/owned/unit ]]; then
  for f in afterburn afterburn-watch; do
    if [[ -f $STATE_DIR/owned-links/$f && -L $BIN/$f &&
          $(readlink "$BIN/$f") == "$(cat "$STATE_DIR/owned-links/$f")" ]]; then
      if rm -f "$BIN/$f"; then echo "  ✓ unlinked $BIN/$f"; else FAILED=1; fi
    fi
  done
fi
# Starship: put back only the original error_symbol line, and only if the line is still the one we wrote.
STARSHIP="$CONF_HOME/starship.toml"
OURS_SYMBOL='error_symbol = "[❯](bold red)"'
if [[ -f $STATE_DIR/starship-error-symbol && -f $STARSHIP ]]; then
  if grep -qxF "$OURS_SYMBOL" "$STARSHIP"; then
    orig=$(cat "$STATE_DIR/starship-error-symbol")
    real=$(readlink -f "$STARSHIP")
    tmp=$(mktemp "$(dirname "$real")/.starship.XXXXXX")
    # ENVIRON, not -v: awk -v would turn a backslash in your original line (\u2717, \\) into something else.
    if OURS="$OURS_SYMBOL" ORIG="$orig" awk '
      $0 == ENVIRON["OURS"] && !done { done = 1; if (ENVIRON["ORIG"] != "absent") print ENVIRON["ORIG"]; next }
      { print }
    ' "$real" > "$tmp" && chmod --reference="$real" "$tmp" && mv "$tmp" "$real"; then
      rm -f "$STATE_DIR/starship-error-symbol"
      echo "  ✓ starship error_symbol restored"
    else
      rm -f "$tmp"
      FAILED=1
      echo "  · starship restoration failed; kept state for retry"
    fi
  else
    echo "  · starship error_symbol changed since install; left as is"
  fi
fi

# ~/.bashrc: delete only the line(s) carrying the marker. Written to a temp file, then moved into place.
if [[ -s $STATE_DIR/bashrc-line ]] && grep -qxF -f "$STATE_DIR/bashrc-line" "$HOME/.bashrc" 2>/dev/null; then
  real=$(readlink -f "$HOME/.bashrc")
  tmp=$(mktemp "$(dirname "$real")/.bashrc.XXXXXX")
  EDIT_OK=1
  if [[ -f $STATE_DIR/bashrc-newline && $(tail -n1 "$real") == "$(cat "$STATE_DIR/bashrc-line")" ]]; then
    # The installer added a newline before its line because the file had none, and the marker line is last:
    # drop the marker line and that newline, so the file is byte-for-byte the original.
    head -n -1 "$real" | head -c -1 > "$tmp" || EDIT_OK=0
  else
    grep -vxF -f "$STATE_DIR/bashrc-line" "$real" > "$tmp" || { [[ $? == 1 ]] || EDIT_OK=0; }
  fi
  if (( EDIT_OK )) && chmod --reference="$real" "$tmp" && mv "$tmp" "$real"; then
    rm -f "$STATE_DIR/bashrc-line"
    echo "  ✓ ~/.bashrc line removed"
  # The installer made this file (there was none): take it away again if nothing else is in it.
    if [[ -f $STATE_DIR/bashrc-created && ! -s $real ]]; then
      rm -f "$real" || FAILED=1
    fi
  else
    rm -f "$tmp"
    FAILED=1
    echo "  · ~/.bashrc restoration failed; kept state for retry"
  fi
fi
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
remove_owned "$APPS_DIR/afterburn-colors.desktop" desktop
# Only the file the installer wrote; then the folder, if nothing else is in it.
remove_owned "$CONF_HOME/afterburn/afterburn.conf" conf
rmdir "$CONF_HOME/afterburn" 2>/dev/null || true
# The cursor-fx checkout is the one thing the installer puts in ~/.local/share/afterburn.
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
# Keep the third-party checkout: legacy installs have no ownership record for it.
# Removing cursor-fx remains an explicit manual action, as documented below.
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
      rm -f "$STATE_DIR/plymouth"
      echo "  ✓ boot/login screen restored"
    else
      PLYMOUTH_NOTE="the boot/login screen reset did not finish. Run: omarchy-plymouth-reset"
    fi
  else
    PLYMOUTH_NOTE="the boot/login screen is still set to Afterburn. Restore it with: omarchy-plymouth-reset   (needs sudo)"
  fi
  if [[ -n $PLYMOUTH_NOTE ]]; then echo "  · $PLYMOUTH_NOTE"; FAILED=1; fi
fi

remove_owned "$D/50-afterburn-extras" hook
# The whole-file starship backup stays in the state dir as a safety copy. Nothing restores from it.
if (( FAILED )); then
  echo "  · some undo steps did not finish; kept state in $STATE_DIR. Re-run uninstall.sh to retry."
elif [[ -f $STATE_DIR/starship.toml.bak ]]; then
  find "$STATE_DIR" -mindepth 1 -maxdepth 1 ! -name starship.toml.bak -exec rm -rf {} +
  echo "  · kept a safety copy of your old starship.toml: $STATE_DIR/starship.toml.bak"
else
  rm -rf "$STATE_DIR"
fi
echo "  · owned, unchanged Afterburn files cleaned up"
cat <<'EOF'

  Still installed (remove only if you want):
    cursor-fx:  cursor-fx off; rm ~/.local/bin/cursor-fx; rm -r ~/.config/ghostty/{shaders,cursor-effects}
                and delete the `config-file = cursor-effects/...` line in ~/.config/ghostty/config
    Ghostty:    omarchy pkg drop ghostty   (set another default terminal first)
  The glow disappears the next time you apply any theme.
EOF

exit "$FAILED"
