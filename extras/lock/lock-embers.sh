#!/bin/bash
# lock-embers.sh install|uninstall
#
# Adds the Afterburn ember layer to Omarchy's lock screen without editing Omarchy.
#
# install:   clone the built-in omarchy.lock with omarchy-plugin-clone (which makes
#            ~/.config/omarchy/plugins/$USER.lock and switches to it), copy
#            EmberLayer.qml next to the clone's LockView.qml, insert one
#            `EmberLayer { anchors.fill: parent }` just before the lock form (after
#            the wallpaper blur), then run omarchy-plugin-validate on the clone.
# uninstall: remove the clone with omarchy-plugin-remove (which restores omarchy.lock
#            when the clone was active), then make sure omarchy.lock is enabled.
#
# Both are idempotent. Re-running install on an existing clone refreshes
# EmberLayer.qml and does not insert a second layer.
#
# Test hooks (for dry runs only): LOCK_EMBERS_PLUGINS_DIR and LOCK_EMBERS_OMARCHY_PATH
# override the plugin folder and the Omarchy install root.

set -euo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EMBER_SRC="$SELF_DIR/EmberLayer.qml"
SOURCE_ID="omarchy.lock"
CLONE_ID="${USER:-$(id -un)}.lock"
PLUGINS_DIR="${LOCK_EMBERS_PLUGINS_DIR:-$HOME/.config/omarchy/plugins}"
OMARCHY_ROOT="${LOCK_EMBERS_OMARCHY_PATH:-/usr/share/omarchy}"
OFFICIAL_LOCK_DIR="$OMARCHY_ROOT/shell/plugins/lock"

say() { echo "lock-embers: $*"; }
die() { echo "lock-embers: $*" >&2; exit 1; }

# Prints the line number of the insertion point, or exits 1 if the anchor is not
# exactly once where we expect it. The anchor is the blur layer's `MultiEffect {`
# followed by the wake `MouseArea {` and then the password `BorderSurface {`. The
# ember layer goes right before the MouseArea, so it lands above the blur and below
# the form. Indentation is part of the match, so nested blocks are ignored.
find_anchor() {
  awk '
    /^    MultiEffect \{$/  { multi++; mline = NR }
    /^    MouseArea \{$/    { mouse++; mouseline = NR }
    /^    BorderSurface \{$/ { border++; bline = NR }
    END {
      if (multi != 1 || mouse != 1 || border != 1) exit 1
      if (!(mline < mouseline && mouseline < bline)) exit 1
      print mouseline
    }
  ' "$1"
}

# Net brace depth of a file. Insertion must leave it unchanged, since the block is
# balanced.
brace_depth() {
  awk '{ n += gsub(/\{/, "{"); m += gsub(/\}/, "}") } END { print n - m + 0 }' "$1"
}

insert_layer() {
  local file="$1"
  if grep -q 'EmberLayer {' "$file"; then
    say "EmberLayer already present in $file, not inserting again"
    return 0
  fi

  local line
  line=$(find_anchor "$file") || return 1

  local block depth_before depth_after tmp
  block=$(mktemp)
  tmp=$(mktemp "$(dirname "$file")/.LockView.XXXXXX")
  depth_before=$(brace_depth "$file")
  cat >"$block" <<'BLOCK'
    // Ember layer (lock-embers.sh): ambient, input-transparent, above the blur.
    EmberLayer {
      anchors.fill: parent
    }

BLOCK
  awk -v at="$line" -v blockfile="$block" '
    NR == at {
      while ((getline l < blockfile) > 0) print l
      close(blockfile)
    }
    { print }
  ' "$file" >"$tmp"
  rm -f "$block"

  depth_after=$(brace_depth "$tmp")
  if [[ $depth_before != "$depth_after" ]]; then
    rm -f "$tmp"
    return 2
  fi
  chmod --reference="$file" "$tmp"
  mv "$tmp" "$file"
  say "inserted EmberLayer before line $line of $(basename "$file")"
}

is_our_clone() {
  local dir="$1"
  [[ -f $dir/manifest.json ]] &&
    [[ $(jq -r '.omarchy.clonedFrom // empty' "$dir/manifest.json") == "$SOURCE_ID" ]]
}

install_layer() {
  [[ -f $EMBER_SRC ]] || die "missing $EMBER_SRC"
  [[ -f $OFFICIAL_LOCK_DIR/LockView.qml ]] || die "official lock not found at $OFFICIAL_LOCK_DIR"
  command -v omarchy-plugin-clone >/dev/null || die "omarchy-plugin-clone not on PATH"

  # Check the anchor on the official source before cloning, so a changed Omarchy
  # release never leaves a half-made clone behind.
  if ! find_anchor "$OFFICIAL_LOCK_DIR/LockView.qml" >/dev/null; then
    die "anchor not found in official LockView.qml (Omarchy changed the lock layout); nothing changed"
  fi

  # Only touch the lock screen when Omarchy's built-in lock is the active one. Someone
  # using another lock plugin (e.g. hello-lock) keeps theirs untouched.
  if command -v omarchy-plugin-list >/dev/null && [[ -z ${LOCK_EMBERS_PLUGINS_DIR:-} ]]; then
    local state other
    state=$(omarchy-plugin-list 2>/dev/null | awk -v id="$SOURCE_ID" '$1 == id { print $2 }')
    if [[ $state != enabled && ! -d $PLUGINS_DIR/$CLONE_ID ]]; then
      other=$(omarchy-plugin-list 2>/dev/null | awk 'tolower($0) ~ /lock/ && $2 == "enabled" { print $1 }' | head -1)
      say "your active lock screen is ${other:-a third-party lock}; embers only support Omarchy's built-in lock, so nothing changed"
      exit 3
    fi
  fi

  local clone_dir="$PLUGINS_DIR/$CLONE_ID" created=0
  if [[ -e $clone_dir || -L $clone_dir ]]; then
    is_our_clone "$clone_dir" || die "$clone_dir exists and is not a clone of $SOURCE_ID; not touching it"
    say "clone $CLONE_ID already exists, reusing it"
  else
    say "running omarchy-plugin-clone $SOURCE_ID"
    omarchy-plugin-clone "$SOURCE_ID"
    [[ -d $clone_dir ]] || die "clone did not appear at $clone_dir"
    created=1
  fi

  install -m 0644 "$EMBER_SRC" "$clone_dir/EmberLayer.qml"
  say "copied EmberLayer.qml into $clone_dir"

  if ! insert_layer "$clone_dir/LockView.qml"; then
    if (( created )); then
      say "anchor missing in the clone's LockView.qml, removing the clone we just made"
      omarchy-plugin-remove "$CLONE_ID" --yes || true
      die "aborted; omarchy.lock should be active again"
    fi
    die "could not insert EmberLayer into $clone_dir/LockView.qml; clone left as is"
  fi

  if ! omarchy-plugin-validate "$clone_dir"; then
    if (( created )); then
      say "validation failed on the clone we just made, removing it"
      omarchy-plugin-remove "$CLONE_ID" --yes || true
      die "aborted; omarchy.lock should be active again"
    fi
    die "omarchy-plugin-validate failed on $clone_dir"
  fi
  say "validated $CLONE_ID"

  omarchy-shell shell rescanPlugins >/dev/null || true
  say "installed. $CLONE_ID is the active lock screen (clone of $SOURCE_ID)"
  say "undo with: $0 uninstall"
}

uninstall_layer() {
  local clone_dir="$PLUGINS_DIR/$CLONE_ID"
  if [[ -e $clone_dir || -L $clone_dir ]]; then
    if is_our_clone "$clone_dir"; then
      say "removing clone $CLONE_ID"
      omarchy-plugin-remove "$CLONE_ID" --yes
    else
      die "$clone_dir exists and is not a clone of $SOURCE_ID; not touching it"
    fi
  else
    # No clone means lock-embers never installed: leave whatever lock is active alone.
    say "no clone $CLONE_ID, nothing to remove"
    return 0
  fi

  # omarchy-plugin-remove switches back to omarchy.lock when the clone was active;
  # make sure of it, since the clone could only be installed over omarchy.lock.
  say "making $SOURCE_ID the active lock screen"
  omarchy-plugin-enable "$SOURCE_ID"
  say "uninstalled"
}

main() {
  case "${1:-}" in
    install) install_layer ;;
    uninstall) uninstall_layer ;;
    *) die "usage: $(basename "$0") install|uninstall" ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
