#!/bin/bash
# lock-embers.sh install|uninstall|recolor [FLARE EMBER RUST [STYLE]]
#
# Adds the Afterburn ember layer to Omarchy's lock screen without editing Omarchy.
#
# install:   clone the built-in omarchy.lock with omarchy-plugin-clone (which makes
#            ~/.config/omarchy/plugins/afterburn.lock and switches to it), copy
#            EmberLoader.qml in as EmberLayer.qml and EmberLayer.qml (the embers) as
#            embers.<n>/Embers.qml next to the clone's LockView.qml, insert one
#            `EmberLayer { anchors.fill: parent }` just before the lock form (after
#            the wallpaper blur), then run omarchy-plugin-validate on the clone.
#            If any step after the switch fails, the clone is removed and omarchy.lock is
#            enabled again, so you are never left without a lock screen.
# uninstall: remove the clone with omarchy-plugin-remove (which restores omarchy.lock
#            when the clone was active), then make sure omarchy.lock is enabled.
#
# The clone id. omarchy-plugin-clone names the clone "$USER.lock" and takes no id argument, so a
# user called "omarchy" would get "omarchy.lock": the built-in's own id, which the shell rejects.
# We run it with USER=afterburn instead, which gives "afterburn.lock" for everyone. The id is
# recorded in the state marker (afterburn/lock-embers, one line: clone_id=afterburn.lock) and read
# back from there by recolor and uninstall. A marker without an id (installs made before this
# change) means the old id, "$USER.lock", if that clone exists and is ours.
#
# The clone's EmberLayer.qml is only a loader. The shell keeps the lock loaded all session, and Quickshell keeps
# the text of every QML file it has read, by path, so each set of embers goes into a new folder,
# embers.<n>/Embers.qml (the older one is deleted), and the loader shows the newest each time the lock shows.
#
# recolor [FLARE EMBER RUST [STYLE]]: write the installed clone's embers from the shipped
#            one with the given 6-digit hex colours (the active theme's; no arguments = the base
#            orange) and the given motion. STYLE is rise (EmberLayer.qml itself, the default), or
#            fall, drift, spark, pulse or burst (styles/<STYLE>.qml). An unknown STYLE gives rise.
#            Run by the theme-set hook so the embers follow the theme or edition.
#            Does nothing unless the clone exists and is ours.
#
# Install and uninstall are idempotent. Re-running install on an existing clone refreshes
# EmberLayer.qml and the embers and does not insert a second layer.
#
# Test hooks (for dry runs only): LOCK_EMBERS_PLUGINS_DIR and LOCK_EMBERS_OMARCHY_PATH
# override the plugin folder and the Omarchy install root. LOCK_EMBERS_CLONE_USER overrides the
# "afterburn" prefix of the clone id (to try the reserved-id refusal).

set -euo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EMBER_SRC="$SELF_DIR/EmberLayer.qml"
LOADER="$SELF_DIR/EmberLoader.qml"
SOURCE_ID="omarchy.lock"
# What omarchy-plugin-clone builds the id from. Never the login name: "omarchy" would collide with the built-in.
CLONE_USER="${LOCK_EMBERS_CLONE_USER:-afterburn}"
NEW_ID="$CLONE_USER.${SOURCE_ID#omarchy.}"
LEGACY_ID="${USER:-$(id -un)}.lock"   # what installs made before the id change used
CLONE_ID=""                            # settled by resolve_clone_id
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/afterburn"
MARKER="$STATE_DIR/lock-embers"       # exists while the embers are installed; holds clone_id=<id>
PLUGINS_DIR="${LOCK_EMBERS_PLUGINS_DIR:-$HOME/.config/omarchy/plugins}"
OMARCHY_ROOT="${LOCK_EMBERS_OMARCHY_PATH:-/usr/share/omarchy}"
OFFICIAL_LOCK_DIR="$OMARCHY_ROOT/shell/plugins/lock"

say() { echo "lock-embers: $*"; }
die() { echo "lock-embers: $*" >&2; exit 1; }

# A plugin id we may create or remove: well-formed and outside the first-party omarchy.* namespace.
usable_id() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $1 != *..* && $1 != omarchy.* ]]; }

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

insert_layer() {
  local file="$1"
  if grep -q 'EmberLayer {' "$file"; then
    say "EmberLayer already present in $file, not inserting again"
    return 0
  fi

  local line
  line=$(find_anchor "$file") || return 1

  # Written next to the file and moved over it only once complete: a failed write leaves LockView.qml as it was.
  local tmp
  tmp=$(mktemp "$(dirname "$file")/.LockView.XXXXXX")
  awk -v at="$line" '
    NR == at {
      print "    // Ember layer (lock-embers.sh): ambient, input-transparent, above the blur."
      print "    EmberLayer {"
      print "      anchors.fill: parent"
      print "    }"
      print ""
    }
    { print }
  ' "$file" >"$tmp" && chmod --reference="$file" "$tmp" && mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  say "inserted EmberLayer before line $line of $(basename "$file")"
}

# Copy $1 over $2 through a temp file next to it: a failed write leaves $2 as it was.
put() {
  local tmp
  tmp=$(mktemp "$(dirname "$2")/.put.XXXXXX") || return
  install -m 0644 "$1" "$tmp" && mv "$tmp" "$2" || { rm -f "$tmp"; return 1; }
}

# Make $2 the clone $1's embers: a new embers.<n>/Embers.qml, then the older folders go. Only older ones: two recolours
# at once (quick theme switches) must not delete each other's, so the newest always stays. Nothing changes when the
# newest folder already holds the same embers, or when a write fails.
put_embers() {
  local cur new tmp d
  cur=$(find "$1" -mindepth 1 -maxdepth 1 -type d -name 'embers.*' | sort | tail -n 1)
  [[ -n $cur ]] && cmp -s "$2" "$cur/Embers.qml" && return 0
  tmp=$(mktemp -d "$1/.embers.XXXXXX") || return
  new="$1/embers.$(date +%s%N)"
  install -m 0644 "$2" "$tmp/Embers.qml" && chmod 0755 "$tmp" && mv -T "$tmp" "$new" || { rm -rf "$tmp"; return 1; }
  for d in "$1"/embers.*; do
    [[ $d < "$new" && -d $d ]] || continue
    rm -rf -- "$d"
  done
}

is_our_clone() {
  local dir="$1"
  [[ -f $dir/manifest.json ]] &&
    [[ $(jq -r '.omarchy.clonedFrom // empty' "$dir/manifest.json") == "$SOURCE_ID" ]]
}

# Settle CLONE_ID: the id recorded in the marker, else the old "$USER.lock" if that clone exists and is
# ours (installs from before the marker held an id), else the new id.
resolve_clone_id() {
  local m
  m=$(sed -n 's/^clone_id=//p' "$MARKER" 2>/dev/null | head -n1) || m=""
  if [[ -n $m ]]; then
    if usable_id "$m"; then CLONE_ID=$m; return 0; fi
    say "ignoring clone_id '$m' in $MARKER (not a usable plugin id)"
  fi
  if usable_id "$LEGACY_ID" && [[ -d $PLUGINS_DIR/$LEGACY_ID ]] && is_our_clone "$PLUGINS_DIR/$LEGACY_ID"; then
    CLONE_ID=$LEGACY_ID
    return 0
  fi
  CLONE_ID=$NEW_ID
}

# Refuse an id that could collide with a first-party plugin, before anything is changed.
require_usable_id() {
  usable_id "$CLONE_ID" || die "clone id '$CLONE_ID' is reserved for first-party Omarchy plugins (or malformed); nothing changed"
}

write_marker() {
  mkdir -p "$STATE_DIR"
  printf 'clone_id=%s\n' "$CLONE_ID" > "$MARKER"
}

# omarchy-plugin-remove keeps a plugin folder that is not a git checkout as .<id>.bak.<UTC time>[-n] and says so
# ("Backup at: <path>"). The clone is ours to delete, so delete the backup this call just made, and only that one.
remove_clone() {
  local out bak
  out=$(omarchy-plugin-remove "$1" --yes) || return
  bak=$(sed -n 's/.*Backup at: //p' <<<"$out")
  [[ $bak =~ ^"$PLUGINS_DIR/.$1.bak."[0-9]{14}(-[0-9]+)?$ && -d $bak && ! -L $bak ]] && rm -rf -- "$bak"
  sed 's/ Backup at: .*//' <<<"$out"
}

# From the moment the built-in lock may be switched off until the install is done, a failure must leave
# omarchy.lock enabled. GUARD is on during that window; the EXIT trap rolls back what this run made.
GUARD=0 PRE_NEW=0 PRE_LEGACY=0 PRE_MARKER=0
rollback() {
  local id d
  say "install did not finish; undoing what this run changed"
  for id in "$NEW_ID" "$LEGACY_ID"; do
    usable_id "$id" || continue
    d="$PLUGINS_DIR/$id"
    if [[ $id == "$NEW_ID" ]]; then (( PRE_NEW )) && continue; else (( PRE_LEGACY )) && continue; fi
    if [[ -d $d ]] && is_our_clone "$d"; then
      say "removing the clone $id this run made"
      remove_clone "$id" >/dev/null 2>&1 || say "could not remove $d; delete it by hand"
    fi
  done
  (( PRE_MARKER )) || rm -f "$MARKER"
  if omarchy-plugin-enable "$SOURCE_ID" >/dev/null 2>&1; then
    say "$SOURCE_ID is enabled again, so your lock screen is the stock one"
  else
    echo "lock-embers: COULD NOT re-enable $SOURCE_ID. Run this now: omarchy plugin enable $SOURCE_ID" >&2
  fi
}
on_exit() {
  local rc=$?
  trap - EXIT
  if (( GUARD && rc != 0 )); then rollback; fi
  exit "$rc"
}

# Path of the manifest of a user plugin (the catalog reads ~/.config/omarchy/plugins/<folder>/manifest.json
# and takes the id from inside it), by folder name first, then by the id the manifest declares.
user_manifest() {
  local id=$1 f
  [[ -f $PLUGINS_DIR/$id/manifest.json ]] && { echo "$PLUGINS_DIR/$id/manifest.json"; return 0; }
  for f in "$PLUGINS_DIR"/*/manifest.json; do
    [[ -f $f && $(jq -r '.id // empty' "$f" 2>/dev/null) == "$id" ]] && { echo "$f"; return 0; }
  done
  return 1
}

# Is anyone else's lock screen enabled? Prints the plugin id and returns 0 if so, 1 if we can positively
# see that none is, 2 if we cannot tell (then the caller must change nothing).
# Omarchy lists a lock as a "service" like any other, so the kind says nothing. A lock is a plugin whose
# manifest has the "authentication" capability or is cloned from omarchy.lock (hello-lock has both). First-party
# plugins are skipped: omarchy.polkit also has the capability, and omarchy.lock itself is the built-in. An
# enabled plugin whose manifest cannot be read counts as a lock when its id ends in "lock", else we cannot tell.
other_lock_enabled() {
  local list rows id m doubt=0
  list=$(omarchy-plugin-list 2>/dev/null) || return 2
  rows=$(awk 'NR > 1 && $2 == "enabled" { print $1 }' <<<"$list")
  # An empty list is not "no lock": the list command may have failed.
  awk 'NR > 1 { n++ } END { exit n ? 0 : 1 }' <<<"$list" || return 2
  while IFS= read -r id; do
    [[ -n $id && $id != omarchy.* ]] || continue
    if m=$(user_manifest "$id") && jq -e . "$m" >/dev/null 2>&1; then
      if jq -e '((.omarchy.capabilities // []) | index("authentication")) != null or .omarchy.clonedFrom == "omarchy.lock"' "$m" >/dev/null 2>&1; then
        echo "$id"
        return 0
      fi
    elif [[ $id =~ (^|[._-])lock$ ]]; then
      echo "$id"
      return 0
    else
      doubt=1
    fi
  done <<<"$rows"
  (( doubt )) && return 2
  return 1
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

  resolve_clone_id
  # No clone of ours yet: a new one gets the new id (the one omarchy-plugin-clone is asked for below).
  [[ -d $PLUGINS_DIR/$CLONE_ID ]] || CLONE_ID=$NEW_ID
  require_usable_id

  # Only touch the lock screen when Omarchy's built-in lock is the active one. Someone
  # using another lock plugin (e.g. hello-lock) keeps theirs untouched.
  if command -v omarchy-plugin-list >/dev/null && [[ -z ${LOCK_EMBERS_PLUGINS_DIR:-} ]]; then
    local state other
    state=$(omarchy-plugin-list 2>/dev/null | awk -v id="$SOURCE_ID" '$1 == id { print $2 }') || state=""
    if [[ $state != enabled && ! -d $PLUGINS_DIR/$CLONE_ID ]]; then
      local rc=0
      other=$(other_lock_enabled) || rc=$?
      if (( rc != 1 )); then
        # 0: a lock plugin of someone else is enabled. 2: cannot tell. Either way, touch nothing.
        say "your active lock screen is ${other:-a third-party lock}; embers only support Omarchy's built-in lock, so nothing changed"
        exit 3
      fi
      # Positively no lock screen is enabled (an earlier failed install can leave it so): fix that first.
      say "no lock screen is enabled ($SOURCE_ID is disabled); enabling it so you are never left without one"
      omarchy-plugin-enable "$SOURCE_ID" >/dev/null || die "could not enable $SOURCE_ID. Run: omarchy plugin enable $SOURCE_ID"
    fi
  fi

  local clone_dir="$PLUGINS_DIR/$CLONE_ID"
  trap on_exit EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  [[ -e $MARKER ]] && PRE_MARKER=1
  if [[ -e $clone_dir || -L $clone_dir ]]; then
    is_our_clone "$clone_dir" || die "$clone_dir exists and is not a clone of $SOURCE_ID; not touching it"
    say "clone $CLONE_ID already exists, reusing it"
    write_marker
  else
    [[ -e $PLUGINS_DIR/$NEW_ID || -L $PLUGINS_DIR/$NEW_ID ]] && PRE_NEW=1
    [[ -e $PLUGINS_DIR/$LEGACY_ID || -L $PLUGINS_DIR/$LEGACY_ID ]] && PRE_LEGACY=1
    GUARD=1   # omarchy-plugin-clone switches away from the built-in lock: from here on, undo on failure
    say "running omarchy-plugin-clone $SOURCE_ID (as $CLONE_USER, giving $CLONE_ID)"
    USER="$CLONE_USER" omarchy-plugin-clone "$SOURCE_ID"
    [[ -d $clone_dir ]] || die "clone did not appear at $clone_dir"
    [[ $(jq -r '.id // empty' "$clone_dir/manifest.json") == "$CLONE_ID" ]] ||
      die "the clone's manifest id is not $CLONE_ID (did omarchy-plugin-clone change how it names clones?)"
    write_marker
  fi

  put "$LOADER" "$clone_dir/EmberLayer.qml" && put_embers "$clone_dir" "$EMBER_SRC" ||
    die "could not write the ember layer into $clone_dir"
  say "copied the ember layer into $clone_dir"

  insert_layer "$clone_dir/LockView.qml" ||
    die "could not insert EmberLayer into $clone_dir/LockView.qml (Omarchy changed the lock layout?)"
  omarchy-plugin-validate "$clone_dir" || die "omarchy-plugin-validate failed on $clone_dir"
  say "validated $CLONE_ID"
  GUARD=0

  omarchy-shell shell rescanPlugins >/dev/null || true
  say "installed. $CLONE_ID is the active lock screen (clone of $SOURCE_ID)"
  say "undo with: $0 uninstall"
}

# Write the clone's embers with the given colours and motion (defaults: the shipped orange,
# rising). Placeholders keep one replacement from being rewritten by the next.
recolor_layer() {
  local flare=${1:-ffc48a} ember=${2:-ff5a1f} rust=${3:-7a3e16} style=${4:-rise} clone_dir tmp
  local c src="$EMBER_SRC"
  resolve_clone_id
  require_usable_id
  clone_dir="$PLUGINS_DIR/$CLONE_ID"
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
  # An install from before the loader: its EmberLayer.qml holds the embers. It loads the new ones from the next login on.
  cmp -s "$LOADER" "$clone_dir/EmberLayer.qml" || put "$LOADER" "$clone_dir/EmberLayer.qml"
  rm -f "$clone_dir/Embers.qml"   # the embers' place in a pre-release layout
  tmp=$(mktemp "$clone_dir/.EmberLayer.XXXXXX")
  sed -e 's/ffc48a/@FLARE@/g; s/ff5a1f/@EMBER@/g; s/7a3e16/@RUST@/g' "$src" |
    sed -e "s/@FLARE@/${flare,,}/g; s/@EMBER@/${ember,,}/g; s/@RUST@/${rust,,}/g" > "$tmp" &&
    put_embers "$clone_dir" "$tmp" || { rm -f "$tmp"; die "could not write the embers into $clone_dir"; }
  rm -f "$tmp"
  say "embers #$flare #$ember #$rust, $style; the lock shows them the next time it opens"
}

uninstall_layer() {
  resolve_clone_id
  require_usable_id
  local clone_dir="$PLUGINS_DIR/$CLONE_ID"
  if [[ -e $clone_dir || -L $clone_dir ]]; then
    if is_our_clone "$clone_dir"; then
      say "removing clone $CLONE_ID"
      remove_clone "$CLONE_ID"
    else
      die "$clone_dir exists and is not a clone of $SOURCE_ID; not touching it"
    fi
  else
    # No clone means lock-embers is not installed (or the clone was removed by hand): leave whatever lock is active alone.
    say "no clone $CLONE_ID, nothing to remove"
    rm -f "$MARKER"
    return 0
  fi

  # omarchy-plugin-remove switches back to omarchy.lock when the clone was active: if it is enabled already,
  # nothing is left to do. Otherwise enable the built-in ourselves only when positively no lock is enabled:
  # a lock you chose after our clone must stay yours (enabling omarchy.lock would switch it off).
  # A failed enable must not skip the marker removal below (this script runs under set -e).
  local state other rc=0 failed=0
  state=$(omarchy-plugin-list 2>/dev/null | awk -v id="$SOURCE_ID" '$1 == id { print $2 }') || state=""
  if [[ $state == enabled ]]; then
    say "$SOURCE_ID is the active lock screen"
  else
    other=$(other_lock_enabled) || rc=$?
    if (( rc == 1 )); then
      say "no lock screen is enabled; making $SOURCE_ID the active lock screen"
      omarchy-plugin-enable "$SOURCE_ID" || { failed=1; say "could not enable $SOURCE_ID. Run: omarchy plugin enable $SOURCE_ID"; }
    else
      say "your lock screen is ${other:-one we cannot identify}; leaving it as it is"
    fi
  fi
  rm -f "$MARKER"
  # Non-zero tells uninstall.sh the lock screen was not restored.
  (( failed == 0 )) || return 1
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
