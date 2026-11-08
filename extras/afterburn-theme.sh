# shellcheck shell=bash
# shellcheck disable=SC2034
# afterburn-theme.sh: shared helpers for the Afterburn extras. Source it, do not run it.
# Used by the theme-set hook and the afterburn CLI.
#
# An "Afterburn theme" is the base theme (`afterburn`) or a colour edition (`afterburn-<edition>`).
# Colours always come from the ACTIVE theme's colors.toml, so every edition recolours the glow,
# the heat levels, the fail flash, the colour picker and the lock-screen embers.
#
# The three ember colours are the three stops of `hyprland_active_border` in colors.toml
# (accent, ember, flare). Rust is `brown`, ash is `dark_foreground`, the cool-level middle
# stop is `afterburn_cool` (an extra key the editions carry; ANSI `magenta` is a fixed violet
# in every edition, so it cannot be used). Every value falls back to the base theme's, so a
# missing file or key leaves the original orange look.

# Theme name as Omarchy stores it (lowercase, dashes). Empty if unknown.
ab_theme_name() {
  cat "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme.name" 2>/dev/null || true
}

# True for `afterburn` and `afterburn-<edition>`.
ab_is_afterburn() { [[ ${1:-} == afterburn || ${1:-} == afterburn-* ]]; }

# Share laptop policy between the CLI and watcher. USB-C docks and chargers are
# external power too; the kernel reports them with several USB supply types.
ab_on_external_power() {
  local d type
  for d in "${POWER_DIR:-/sys/class/power_supply}"/*; do
    type=$(cat "$d/type" 2>/dev/null)
    case $type in
      Mains|USB|USB_*|Wireless)
        [[ $(cat "$d/online" 2>/dev/null) == 1 ]] && return 0 ;;
    esac
  done
  return 1
}

ab_saver_want() {
  case ${1:-auto} in
    on|off) echo "$1" ;;
    *)
      if grep -qx Battery "${POWER_DIR:-/sys/class/power_supply}"/*/type 2>/dev/null &&
         ! ab_on_external_power; then echo on; else echo off; fi ;;
  esac
}

# Path of the colors.toml for a theme: the user's copy (like omarchy-theme-dir), else the
# staged current theme, else the base theme. Prints nothing if none exists.
ab_colors_file() {
  local name=${1:-} f
  for f in "$HOME/.config/omarchy/themes/$name/colors.toml" \
           "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme/colors.toml" \
           "$HOME/.config/omarchy/themes/afterburn/colors.toml"; do
    [[ -n $name && -f $f ]] && { echo "$f"; return 0; }
  done
  return 1
}

# mix HEX1 HEX2 PERCENT_OF_HEX2 -> hex (6 digits, no #)
ab_mix() {
  local a=$1 b=$2 p=$3 i out=""
  for i in 0 2 4; do
    out+=$(printf '%02x' $(( ( 0x${a:i:2} * (100 - p) + 0x${b:i:2} * p + 50 ) / 100 )))
  done
  echo "$out"
}

# Fills AB_* (6-digit lowercase hex, no #) for the named theme.
#   AB_ACCENT AB_EMBER AB_FLARE   the three gradient stops
#   AB_RUST AB_ASH                cooled ember, burnt-out ember
#   AB_COOL                       middle stop of the cool heat level
#   AB_INACTIVE                   unfocused border
#   AB_HOTWHITE AB_HOTGLOW        hot-level border highlight and shadow
ab_load_palette() {
  AB_ACCENT=f59145 AB_EMBER=ff5a1f AB_FLARE=ffc48a AB_RUST=7a3e16 AB_ASH=5e5b55
  AB_COOL=e8703a AB_INACTIVE=2b2a28
  local f line k v stops=() cool_set=
  f=$(ab_colors_file "${1:-}") || f=""
  if [[ -n $f ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
        k=${BASH_REMATCH[1]} v=${BASH_REMATCH[2]}
        v=${v,,}
        case $k in
          brown)           [[ $v =~ ^#([0-9a-f]{6})$ ]] && AB_RUST=${BASH_REMATCH[1]} ;;
          dark_foreground) [[ $v =~ ^#([0-9a-f]{6})$ ]] && AB_ASH=${BASH_REMATCH[1]} ;;
          afterburn_cool)  [[ $v =~ ^#([0-9a-f]{6})$ ]] && { AB_COOL=${BASH_REMATCH[1]}; cool_set=1; } ;;
          hyprland_active_border)
            stops=()
            while [[ $v =~ rgba\(([0-9a-f]{6})[0-9a-f]{2}\)(.*) ]]; do
              stops+=("${BASH_REMATCH[1]}"); v=${BASH_REMATCH[2]}
            done
            if (( ${#stops[@]} >= 3 )); then AB_ACCENT=${stops[0]} AB_EMBER=${stops[1]} AB_FLARE=${stops[2]}; fi ;;
          hyprland_inactive_border)
            [[ $v =~ rgba\(([0-9a-f]{6})[0-9a-f]{2}\) ]] && AB_INACTIVE=${BASH_REMATCH[1]} ;;
        esac
      fi
    done < "$f"
  fi
  # Hot level: the base theme's literals are kept exactly; editions derive theirs from the stops.
  # A non-base theme without an `afterburn_cool` key gets a cooled ember instead of the base orange.
  if [[ $AB_ACCENT$AB_EMBER$AB_FLARE == f59145ff5a1fffc48a ]]; then
    AB_HOTWHITE=fff1e0 AB_HOTGLOW=ffb37a
  else
    AB_HOTWHITE=$(ab_mix "$AB_FLARE" ffffff 75)
    AB_HOTGLOW=$(ab_mix "$AB_ACCENT" "$AB_FLARE" 60)
    [[ -n $cool_set ]] || AB_COOL=$(ab_mix "$AB_EMBER" "$AB_RUST" 35)
  fi
}

# State for things that cannot parse colors.toml cheaply (the fail flash in every shell).
ab_write_palette_env() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/afterburn"
  mkdir -p "$d" || return 1
  printf 'FLARE=%s\nEMBER=%s\nRUST=%s\nASH=%s\n' "$AB_FLARE" "$AB_EMBER" "$AB_RUST" "$AB_ASH" | ab_atomic_write "$d/palette.env"
}

# Print FILE (a glow template carrying the base theme's colours) in the loaded palette's colours.
# One pass through placeholders, so a new colour can never be rewritten twice. Base: unchanged.
ab_recolor_glow() {
  sed -e "s/f59145/@ACCENT@/g; s/ff5a1f/@EMBER@/g; s/ffc48a/@FLARE@/g; s/2b2a28/@INACTIVE@/g" "$1" |
    sed -e "s/@ACCENT@/$AB_ACCENT/g; s/@EMBER@/$AB_EMBER/g; s/@FLARE@/$AB_FLARE/g; s/@INACTIVE@/$AB_INACTIVE/g"
}

# ---- Edition knobs ------------------------------------------------------------------------------
# Five settings can come from three places. First hit wins:
#   1. a value you saved yourself in ~/.config/afterburn/afterburn.conf
#   2. the active edition's edition.conf (shipped with the edition, never written by you)
#   3. the built-in default (the base theme's)
# Every value is checked before it is used; one that fails is skipped, so a typo can never reach
# Hyprland, cursor-fx or the lock screen. edition.conf is parsed as data (KEY=VALUE lines), never
# sourced. The lines `ROTATE=slow ...` and `DIM=0.08 ...` exactly as the first-run conf wrote them
# are not choices, so an older conf follows the edition too.
#   CURSOR_FX    a cursor-fx effect name                       (base: embers)
#   ROTATE       off|slow|medium|fast                          (base: slow)
#   DIM          0 to 1                                        (base: 0.08)
#   GLOW_RANGE   4 to 30, the shadow range at the normal level (base: 14)
#   EMBER_STYLE  rise|fall|drift|spark|pulse|burst             (base: rise)
AB_EDITION_KEYS="CURSOR_FX ROTATE DIM GLOW_RANGE EMBER_STYLE"
AB_CURSOR_FX_NAMES="cyber lightning glitch neon phosphor embers shockwave katana teleport fireworks aurora mecha hologram"

ab_base_default() {
  case ${1:-} in
    CURSOR_FX) echo embers ;; ROTATE) echo slow ;; DIM) echo 0.08 ;;
    GLOW_RANGE) echo 14 ;; EMBER_STYLE) echo rise ;; *) return 1 ;;
  esac
}

# ab_valid KEY VALUE: success if VALUE is allowed for the edition key KEY.
ab_valid() {
  local k=${1:-} v=${2:-}
  case $k in
    CURSOR_FX)   [[ $v =~ ^(cyber|lightning|glitch|neon|phosphor|embers|shockwave|katana|teleport|fireworks|aurora|mecha|hologram)$ ]] ;;
    ROTATE)      [[ $v =~ ^(off|slow|medium|fast)$ ]] ;;
    DIM)         [[ $v =~ ^(0|1|0?\.[0-9]+|1\.0*)$ ]] ;;
    GLOW_RANGE)  [[ $v =~ ^[1-9][0-9]?$ ]] && (( v >= 4 && v <= 30 )) ;;
    EMBER_STYLE) [[ $v =~ ^(rise|fall|drift|spark|pulse|burst)$ ]] ;;
    *) return 1 ;;
  esac
}

# ab_file_value FILE KEY: print KEY's value from a KEY=VALUE file (last line wins; a trailing comment,
# surrounding spaces and one pair of quotes are dropped). Fails if the key is absent.
ab_file_value() {
  local line value= found=0 raw
  local assignment='^[[:space:]]*([A-Z_]+)[[:space:]]*=[[:space:]]*(.*)$'
  local double='^"([^"]*)"[[:space:]]*(#.*)?$' single="^'([^']*)'[[:space:]]*(#.*)?$"
  [[ -r $1 ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ $assignment && ${BASH_REMATCH[1]} == "$2" ]] || continue
    raw=${BASH_REMATCH[2]}; found=1
    if [[ $raw =~ $double || $raw =~ $single ]]; then value=${BASH_REMATCH[1]}
    elif [[ $raw == \"* || $raw == \'* ]]; then value= # malformed final assignment invalidates earlier ones
    else
      value=${raw%%#*}
      value=${value#"${value%%[![:space:]]*}"}
      value=${value%"${value##*[![:space:]]}"}
    fi
  done < "$1"
  (( found )) || return 1
  printf '%s' "$value"
}

# The user's own conf, and where it keeps its explicit values.
ab_conf_path() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/afterburn/afterburn.conf"; }

# ab_conf_value KEY: the value you saved yourself, unless the line is an untouched first-run default.
ab_conf_value() {
  local f line
  f=$(ab_conf_path)
  [[ -f $f ]] || return 1
  line=$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$f" | tail -n1) || return 1
  case $line in
    'ROTATE=slow          # off|slow|medium|fast  (border gradient turn: 60s|20s|8s per turn)' | \
    'DIM=0.08             # dim_inactive strength, 0 = off') return 1 ;;
  esac
  ab_file_value "$f" "$1"
}

# The edition.conf of a theme: your installed copy, the staged current theme, then the base theme's own
# .editions/ copy (so an edition installed by an older release still gets its defaults).
# Only afterburn-<edition> names qualify, and the base theme has none.
ab_edition_file() {
  local name=${1:-} f
  [[ $name =~ ^afterburn-[a-z0-9]+$ ]] || return 1
  for f in "$HOME/.config/omarchy/themes/$name/edition.conf" \
           "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme/edition.conf" \
           "$HOME/.config/omarchy/themes/afterburn/.editions/${name#afterburn-}/edition.conf"; do
    [[ -f $f ]] && { echo "$f"; return 0; }
  done
  return 1
}

# ab_effective KEY [THEME]: sets AB_VAL to the value to use and AB_SRC to where it came from
# (conf, edition or default).
ab_effective() {
  local k=$1 theme=${2:-} v f
  AB_VAL=$(ab_base_default "$k") AB_SRC=default
  if v=$(ab_conf_value "$k"); then
    if ab_valid "$k" "$v"; then AB_VAL=$v AB_SRC=conf; return 0; fi
    echo "afterburn: ignoring $k='$v' in $(ab_conf_path) (not an allowed value)" >&2
  fi
  if f=$(ab_edition_file "$theme") && v=$(ab_file_value "$f" "$k") && ab_valid "$k" "$v"; then
    AB_VAL=$v AB_SRC=edition
  fi
  return 0
}

# Runtime policy is data, never shell code. Reset every key on every read.
AB_CONFIG_KEYS="$AB_EDITION_KEYS GLOW CURSOR_EFFECTS MOTION HEAT_SOURCE EVENING_HOURS ZIP LAT LON HOT_F COOL_F HEAT_WALLPAPERS FULLSCREEN_QUIET LAPTOP_MODE FAIL_FX"
ab_default() {
  case $1 in
    MOTION) echo on ;; HEAT_SOURCE) echo time ;; EVENING_HOURS) echo 19-07 ;;
    ZIP|LAT|LON) echo '' ;; HOT_F) echo 90 ;; COOL_F) echo 50 ;;
    GLOW|CURSOR_EFFECTS|HEAT_WALLPAPERS|FULLSCREEN_QUIET) echo yes ;; LAPTOP_MODE) echo auto ;;
    FAIL_FX) echo random ;; *) ab_base_default "$1" ;;
  esac
}
ab_config_valid() {
  local k=$1 v=$2 a b
  case $k in
    MOTION) [[ $v == on || $v == off ]] ;;
    HEAT_SOURCE) [[ $v =~ ^(off|time|pressure|weather)$ ]] ;;
    EVENING_HOURS)
      [[ $v =~ ^([0-9]{1,2})-([0-9]{1,2})$ ]] || return 1
      a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]}; (( 10#$a <= 23 && 10#$b <= 23 )) ;;
    ZIP) [[ $v =~ ^([0-9]{5})?$ ]] ;;
    LAT|LON)
      [[ -z $v ]] && return 0
      [[ $v =~ ^-?[0-9]{1,3}(\.[0-9]+)?$ ]] || return 1
      a=90; [[ $k == LON ]] && a=180
      awk -v v="$v" -v n="$a" 'BEGIN {exit !(v >= -n && v <= n)}' ;;
    HOT_F|COOL_F) [[ $v =~ ^[0-9]{1,3}$ ]] ;;
    GLOW|CURSOR_EFFECTS|HEAT_WALLPAPERS|FULLSCREEN_QUIET) [[ $v == yes || $v == no ]] ;;
    LAPTOP_MODE) [[ $v =~ ^(auto|on|off)$ ]] ;;
    FAIL_FX) [[ $v =~ ^(random|burn|cascade|dissolve|off)$ ]] ;;
    *) ab_valid "$k" "$v" ;;
  esac
}
ab_load_conf() {
  local k v
  for k in $AB_CONFIG_KEYS; do
    if [[ " $AB_EDITION_KEYS " == *" $k "* ]]; then
      ab_effective "$k" "${1:-$(ab_theme_name)}"
    else
      AB_VAL=$(ab_default "$k") AB_SRC=default
      if v=$(ab_file_value "$(ab_conf_path)" "$k"); then
        if ab_config_valid "$k" "$v"; then AB_VAL=$v AB_SRC=conf
        else echo "afterburn: ignoring invalid $k in $(ab_conf_path)" >&2; fi
      fi
    fi
    printf -v "$k" %s "$AB_VAL"
    if declare -p SRC &>/dev/null; then SRC[$k]=$AB_SRC; fi
  done
}
ab_motion_enabled() { [[ ${MOTION:-on} == on && -z ${NO_MOTION+x} ]]; }

# All mutators share one advisory lock. Children inherit descriptor 9; checking its
# inode permits nested CLI/hook calls without accepting a forgeable environment flag.
ab_lock() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/afterburn" lock
  mkdir -p "$d" || return 1
  lock="$d/runtime.lock"
  command -v flock >/dev/null || { echo 'afterburn: flock is required' >&2; return 1; }
  if [[ ! /proc/$$/fd/9 -ef $lock ]]; then exec 9>"$lock" || return 1; fi
  flock -x 9
}
# Atomic replacement uses a unique temporary sibling; failed writers never publish.
ab_atomic_write() {
  local file=$1 tmp
  # Configs are commonly dotfile-manager links; replace their target atomically,
  # keeping the user-owned symlink itself intact (including relative links).
  if [[ -L $file ]]; then file=$(readlink -f "$file") || return 1; fi
  mkdir -p "$(dirname "$file")" || return 1
  tmp=$(mktemp "$(dirname "$file")/.afterburn-write.XXXXXX") || return 1
  if cat > "$tmp" && { [[ ! -f $file ]] || chmod --reference="$file" "$tmp"; } && mv -f "$tmp" "$file"; then return 0; fi
  rm -f "$tmp"; return 1
}
ab_run() {
  local rc d="${XDG_STATE_HOME:-$HOME/.local/state}/afterburn"
  if "$@"; then return 0; else rc=$?; fi
  # The status of a failed AND-list is preserved before publishing the diagnostic.
  printf '%s: %s failed (%s)\n' "$(date -u +%FT%TZ)" "$1" "$rc" | ab_atomic_write "$d/last-error"
  echo "afterburn: $1 failed ($rc)" >&2
  return "$rc"
}

# A restarted compositor has a new instance signature. Resolve only the instance
# serving this process's Wayland display, so subprocesses stop targeting the old one.
ab_refresh_instance() {
  local selected
  [[ -n ${WAYLAND_DISPLAY:-} ]] || return 0
  selected=$(hyprctl instances -j 2>/dev/null | jq -r --arg display "$WAYLAND_DISPLAY" '[.[] | select(.wl_socket == $display)] | if length == 1 then .[0].instance else empty end') || return 0
  if [[ $selected =~ ^[A-Za-z0-9_.-]+$ ]]; then export HYPRLAND_INSTANCE_SIGNATURE=$selected; fi
}
