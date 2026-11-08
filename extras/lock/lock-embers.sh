#!/bin/bash
# lock-embers.sh install|uninstall|recolor [FLARE EMBER RUST [STYLE]]
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
# recolor [FLARE EMBER RUST [STYLE]]: rewrite the installed clone's EmberLayer.qml from the shipped
#            one with the given 6-digit hex colours (the active theme's; no arguments = the base
#            orange) and the given motion. STYLE is rise (EmberLayer.qml itself, the default), or
#            fall, drift, spark, pulse or burst (styles/<STYLE>.qml). An unknown STYLE gives rise.
#            Run by the theme-set hook so the embers follow the theme or edition.
#            Does nothing unless the clone exists and is ours.
#
# Install and uninstall are idempotent. Re-running install on an existing clone refreshes
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
REMOVAL_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/afterburn/lock-removal"


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

# Include names and file contents, including user additions, but not our own records.
clone_inventory() {
  (cd "$1" && find . -mindepth 1 ! -name '.afterburn-*' -print0 | sort -z |
    while IFS= read -r -d '' f; do
      if [[ -L $f ]]; then printf 'link %s %s\n' "$f" "$(readlink "$f")";
      elif [[ -f $f ]]; then sha256sum "$f";
      else printf 'dir %s\n' "$f"; fi
    done)
}

is_our_clone() {
  local dir="$1"
  [[ ! -L $dir && -f $dir/.afterburn-lock-embers && -f $dir/manifest.json ]] &&
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
    is_our_clone "$clone_dir" || die "$clone_dir exists and is not an Afterburn-owned clone of $SOURCE_ID; not touching it"
    if [[ ! -f $clone_dir/.afterburn-inventory ]] ||
       ! cmp -s <(clone_inventory "$clone_dir") "$clone_dir/.afterburn-inventory"; then
      die "$clone_dir has changed since install; not touching your customization"
    fi
    say "clone $CLONE_ID already exists, reusing it"
  else
    say "running omarchy-plugin-clone $SOURCE_ID"
    omarchy-plugin-clone "$SOURCE_ID"
    [[ -d $clone_dir ]] || die "clone did not appear at $clone_dir"
    created=1
    : > "$clone_dir/.afterburn-lock-embers"
    clone_inventory "$clone_dir" > "$clone_dir/.afterburn-inventory"
  fi

  install -m 0644 "$EMBER_SRC" "$clone_dir/EmberLayer.qml"
  clone_inventory "$clone_dir" > "$clone_dir/.afterburn-inventory"
  say "copied EmberLayer.qml into $clone_dir"

  if ! insert_layer "$clone_dir/LockView.qml"; then
    if (( created )); then
      say "anchor missing in the clone's LockView.qml, removing the clone we just made"
      uninstall_layer || say "rollback did not finish; ownership state kept for uninstall retry"
      die "aborted; omarchy.lock should be active again"
    fi
    die "could not insert EmberLayer into $clone_dir/LockView.qml; clone left as is"
  fi

  clone_inventory "$clone_dir" > "$clone_dir/.afterburn-inventory"
  if ! omarchy-plugin-validate "$clone_dir"; then
    if (( created )); then
      say "validation failed on the clone we just made, removing it"
      uninstall_layer || say "rollback did not finish; ownership state kept for uninstall retry"
      die "aborted; omarchy.lock should be active again"
    fi
    die "omarchy-plugin-validate failed on $clone_dir"
  fi
  clone_inventory "$clone_dir" > "$clone_dir/.afterburn-inventory"
  say "validated $CLONE_ID"

  omarchy-shell shell rescanPlugins >/dev/null || true
  say "installed. $CLONE_ID is the active lock screen (clone of $SOURCE_ID)"
  say "undo with: $0 uninstall"
}

# Write EmberLayer.qml into the clone with the given colours and motion (defaults: the shipped orange,
# rising). Placeholders keep one replacement from being rewritten by the next.
recolor_layer() {
  local flare=${1:-ffc48a} ember=${2:-ff5a1f} rust=${3:-7a3e16} style=${4:-rise} clone_dir="$PLUGINS_DIR/$CLONE_ID" tmp
  local c src="$EMBER_SRC"
  for c in "$flare" "$ember" "$rust"; do
    [[ $c =~ ^[0-9a-fA-F]{6}$ ]] || die "recolor: '$c' is not a 6-digit hex colour"
  done
  [[ -f $EMBER_SRC ]] || die "missing $EMBER_SRC"
  # The style picks the source file. Anything but a known name (or a missing file) is the rising embers.
  if [[ $style =~ ^(fall|drift|spark|pulse|burst)$ && -f $SELF_DIR/styles/$style.qml ]]; then
    src="$SELF_DIR/styles/$style.qml"
  elif [[ $style != rise ]]; then
    say "unknown or missing ember style '$style', using rise"
    style=rise
  fi
  if [[ ! -d $clone_dir ]] || ! is_our_clone "$clone_dir"; then
    say "no clone $CLONE_ID of ours, nothing to recolor"
    return 0
  fi
  # Do not replace a layer the user edited since our last install/recolor.
  if [[ ! -f $clone_dir/.afterburn-inventory ]] ||
     ! cmp -s <(clone_inventory "$clone_dir") "$clone_dir/.afterburn-inventory"; then
    say "clone changed since install; keeping your lock customization"
    return 0
  fi
  tmp=$(mktemp "$clone_dir/.EmberLayer.XXXXXX")
  sed -e 's/ffc48a/@FLARE@/g; s/ff5a1f/@EMBER@/g; s/7a3e16/@RUST@/g' "$src" |
    sed -e "s/@FLARE@/${flare,,}/g; s/@EMBER@/${ember,,}/g; s/@RUST@/${rust,,}/g" > "$tmp"
  if cmp -s "$tmp" "$clone_dir/EmberLayer.qml"; then
    rm -f "$tmp"
    say "embers already #$ember, $style"
    return 0
  fi
  chmod 0644 "$tmp"
  mv "$tmp" "$clone_dir/EmberLayer.qml"
  clone_inventory "$clone_dir" > "$clone_dir/.afterburn-inventory"
  say "embers recolored (#$flare #$ember #$rust), $style"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
}

# Removal can stop after deleting some files. Missing originals are expected on retry;
# changed or newly added survivors belong to the user and must be kept.
clone_survivors_unchanged() {
  local inventory
  inventory=$(clone_inventory "$1") || return 1
  [[ -z $inventory ]] && return 0
  printf '%s\n' "$inventory" | awk '
    NR == FNR { known[$0] = 1; next }
    !($0 in known) { bad = 1 }
    END { exit bad }
  ' "$2" -
}

uninstall_layer() {
  local clone_dir="$PLUGINS_DIR/$CLONE_ID" pending=false
  if [[ -f $REMOVAL_STATE/id && -f $REMOVAL_STATE/inventory &&
        $(cat "$REMOVAL_STATE/id") == "$clone_dir" ]]; then pending=true; fi
  if [[ -e $clone_dir || -L $clone_dir ]]; then
    if [[ -L $clone_dir ]]; then die "$clone_dir is a symlink; not touching it"; fi
    if $pending; then
      if ! clone_survivors_unchanged "$clone_dir" "$REMOVAL_STATE/inventory"; then
        say "clone changed during removal; kept $clone_dir (remove manually if desired)"
        return 0
      fi
    elif is_our_clone "$clone_dir"; then
      if [[ ! -f $clone_dir/.afterburn-inventory ]] ||
         ! cmp -s <(clone_inventory "$clone_dir") "$clone_dir/.afterburn-inventory"; then
        say "clone changed since install; kept $clone_dir (remove manually if desired)"
        return 0
      fi
      # Keep provenance outside the clone so partial deletion of its manifest or
      # ownership marker cannot turn the next retry into adoption of an unknown clone.
      mkdir -p "$REMOVAL_STATE" &&
        cp "$clone_dir/.afterburn-inventory" "$REMOVAL_STATE/inventory" &&
        printf '%s\n' "$clone_dir" > "$REMOVAL_STATE/id" || return 1
    else
      die "$clone_dir exists and is not an Afterburn-owned clone of $SOURCE_ID; not touching it"
    fi
    say "removing clone $CLONE_ID"
    omarchy-plugin-remove "$CLONE_ID" --yes || return $?
  else
    say "no clone $CLONE_ID, nothing to remove"
  fi
  rm -rf "$REMOVAL_STATE" || return $?
  # Omarchy restores the stock plugin only when the removed clone was active.
  # Do not override a different lock the user has selected in the meantime.
  say "uninstalled"
}

main() {
  case "${1:-}" in
    install) install_layer ;;
    uninstall) uninstall_layer ;;
    recolor) shift; recolor_layer "$@" ;;
    *) die "usage: $(basename "$0") install|uninstall|recolor [FLARE EMBER RUST [STYLE]]" ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
