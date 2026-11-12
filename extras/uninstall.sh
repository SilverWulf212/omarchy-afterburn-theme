#!/bin/bash
# Remove Afterburn extras: the hook, your old cursor effect, your old default terminal,
# the subtle pack (links, watcher service, ~/.bashrc line, starship prompt, desktop entry;
# afterburn.conf is kept as afterburn.conf.bak), the lock-screen embers and the colour editions if the installer added them.
# The boot/login screen is put back with Omarchy's omarchy-plymouth-reset if the installer set it
# (it needs sudo, so you are asked; or the exact command is printed).
# Ghostty and cursor-fx stay installed; how to remove them is printed at the end.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
D="$HOME/.config/omarchy/hooks/theme-set.d"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/afterburn"
CONF_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$HOME/.local/bin"
KEEP=(preview-backups)   # state files that stay: the manual undo in the README needs preview-backups; a failed restore adds its own
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
      # stdin is the editions list this loop is reading: keep the command away from it.
      omarchy theme set afterburn >/dev/null 2>&1 </dev/null || true
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
if [[ -f $STATE_DIR/prev-cursor-fx ]] && command -v cursor-fx >/dev/null; then
  cursor-fx "$(cat "$STATE_DIR/prev-cursor-fx")" >/dev/null 2>&1 && echo "  ✓ cursor effect restored"
fi

# Subtle: only if battery saver turned it on and nothing has turned it off again (a subtle you had on is left alone).
if [[ -f $STATE_DIR/subtle-by-afterburn ]] && command -v cursor-fx >/dev/null; then
  cursor-fx subtle off >/dev/null 2>&1 && echo "  ✓ cursor subtle mode restored"
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
STARSHIP="$CONF_HOME/starship.toml"
OURS_SYMBOL='error_symbol = "[❯](bold red)"'
if [[ -f $STATE_DIR/starship-error-symbol && -f $STARSHIP ]]; then
  if grep -qxF "$OURS_SYMBOL" "$STARSHIP"; then
    orig=$(cat "$STATE_DIR/starship-error-symbol")
    real=$(readlink -f "$STARSHIP")
    tmp=$(mktemp "$(dirname "$real")/.starship.XXXXXX")
    # ENVIRON, not -v: awk -v would turn a backslash in your original line (\u2717, \\) into something else.
    # Write, then chmod, then move: if any step fails (a full disk) your file is left as it was.
    if OURS="$OURS_SYMBOL" ORIG="$orig" awk '
      $0 == ENVIRON["OURS"] && !done { done = 1; if (ENVIRON["ORIG"] != "absent") print ENVIRON["ORIG"]; next }
      { print }
    ' "$real" > "$tmp" && chmod --reference="$real" "$tmp" && mv "$tmp" "$real"; then
      echo "  ✓ starship error_symbol restored"
    else
      rm -f "$tmp"; KEEP+=(starship-error-symbol); RC=1
      echo "  ✗ starship error_symbol not restored (your file is unchanged); original line is in $STATE_DIR/starship-error-symbol"
    fi
  else
    echo "  · starship error_symbol changed since install; left as is"
  fi
fi

# ~/.bashrc: delete only the line the installer added, matched whole. Written to a temp file, then moved into place.
if grep -qxF "$AB_BASHRC_LINE" "$HOME/.bashrc" 2>/dev/null; then
  real=$(readlink -f "$HOME/.bashrc")
  tmp=$(mktemp "$(dirname "$real")/.bashrc.XXXXXX")
  # Write, then chmod, then move (as for starship above). awk, not grep -v: grep exits 1 when nothing is left.
  if {
    if [[ -f $STATE_DIR/bashrc-newline && $(tail -n1 "$real") == "$AB_BASHRC_LINE" ]]; then
      # The installer added a newline before its line because the file had none, and the marker line is last:
      # drop the marker line and that newline, so the file is byte-for-byte the original.
      head -n -1 "$real" | head -c -1 > "$tmp"
    else
      LINE="$AB_BASHRC_LINE" awk '$0 != ENVIRON["LINE"]' "$real" > "$tmp"
    fi
  } && chmod --reference="$real" "$tmp" && mv "$tmp" "$real"; then
    echo "  ✓ ~/.bashrc line removed"
    # The installer made this file (there was none): take it away again if nothing else is in it.
    if [[ -f $STATE_DIR/bashrc-created && ! -s $real ]]; then rm -f "$real" && echo "  ✓ ~/.bashrc removed (the installer had created it, and it is empty)"; fi
  else
    rm -f "$tmp"; KEEP+=(bashrc-newline bashrc-created); RC=1
    echo "  ✗ ~/.bashrc line not restored (your file is unchanged); remove the line ending in '# afterburn' yourself"
  fi
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
KEEP+=(starship.toml.bak)
find_keep=(); for k in "${KEEP[@]}"; do find_keep+=(! -name "$k"); done
find "$STATE_DIR" -mindepth 1 -maxdepth 1 "${find_keep[@]}" -exec rm -rf {} + 2>/dev/null
rmdir "$STATE_DIR" 2>/dev/null || true
[[ -f $STATE_DIR/starship.toml.bak ]] && echo "  · kept a safety copy of your old starship.toml: $STATE_DIR/starship.toml.bak"
[[ -d $STATE_DIR/preview-backups ]] && echo "  · kept your preview backups: $STATE_DIR/preview-backups"
echo "  ✓ Afterburn hook removed"
cat <<'EOF'

  Still installed (remove only if you want):
    cursor-fx:  cursor-fx off; rm ~/.local/bin/cursor-fx; rm -r ~/.config/ghostty/{shaders,cursor-effects}
                and delete the `config-file = cursor-effects/...` line in ~/.config/ghostty/config
    Ghostty:    omarchy pkg drop ghostty   (set another default terminal first)
  The glow disappears the next time you apply any theme.
EOF
exit $RC
