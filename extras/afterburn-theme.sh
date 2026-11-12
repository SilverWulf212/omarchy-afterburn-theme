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
#
# A light edition (`mode = "light"` in its colors.toml, e.g. afterburn-lite) is ink on paper: adding
# white cannot make it hotter, so its hot level deepens instead, and the unfocused shadow is a soft
# warm one rather than the dark themes' black.

# The one line install.sh adds to ~/.bashrc and uninstall.sh takes out again (matched whole, so a line of yours
# that merely ends in "# afterburn" is never touched). $HOME stays literal in the file.
AB_FAIL_SH='$HOME/.config/omarchy/themes/afterburn/extras/afterburn-fail.bash'
AB_BASHRC_LINE="[[ -f \"$AB_FAIL_SH\" ]] && source \"$AB_FAIL_SH\"  # afterburn"

# Theme name as Omarchy stores it (lowercase, dashes). Empty if unknown.
ab_theme_name() {
  cat "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme.name" 2>/dev/null || true
}

# True for `afterburn` and `afterburn-<edition>`.
ab_is_afterburn() { [[ ${1:-} == afterburn || ${1:-} == afterburn-* ]]; }

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
  local a=$1 b=$2 p=$3 i h out=""
  for i in 0 2 4; do
    printf -v h '%02x' $(( ( 0x${a:i:2} * (100 - p) + 0x${b:i:2} * p + 50 ) / 100 ))
    out+=$h
  done
  echo "$out"
}

# Fills AB_* (6-digit lowercase hex, no #) for the named theme.
#   AB_ACCENT AB_EMBER AB_FLARE   the three gradient stops
#   AB_RUST AB_ASH                cooled ember, burnt-out ember
#   AB_COOL                       middle stop of the cool heat level
#   AB_INACTIVE                   unfocused border
#   AB_HOTWHITE AB_HOTGLOW        hot-level border highlight and shadow
#   AB_MODE                       dark|light, from the theme's `mode`
#   AB_SHADOW_INACTIVE            8-digit rgba hex of the unfocused window shadow
ab_load_palette() {
  AB_ACCENT=f59145 AB_EMBER=ff5a1f AB_FLARE=ffc48a AB_RUST=7a3e16 AB_ASH=5e5b55
  AB_COOL=e8703a AB_INACTIVE=2b2a28 AB_MODE=dark AB_SHADOW_INACTIVE=00000066
  local f line k v stops=() cool_set=
  f=$(ab_colors_file "${1:-}") || f=""
  if [[ -n $f ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
        k=${BASH_REMATCH[1]} v=${BASH_REMATCH[2]}
        v=${v,,}
        case $k in
          mode)            [[ $v == light ]] && AB_MODE=light ;;
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
  # Light edition: a near-white stop vanishes on paper, so the hot highlight is the ember deepened
  # with ink, and the hot shadow leans to the ember. The unfocused shadow becomes a faint warm one.
  if [[ $AB_MODE == light ]]; then
    AB_HOTWHITE=$(ab_mix "$AB_EMBER" 000000 22)
    AB_HOTGLOW=$(ab_mix "$AB_ACCENT" "$AB_EMBER" 60)
    AB_SHADOW_INACTIVE=${AB_RUST}26
  fi
}

# State for things that cannot parse colors.toml cheaply (the fail flash in every shell).
ab_write_palette_env() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/afterburn"
  mkdir -p "$d" || return 0
  printf 'FLARE=%s\nEMBER=%s\nRUST=%s\nASH=%s\n' "$AB_FLARE" "$AB_EMBER" "$AB_RUST" "$AB_ASH" > "$d/palette.env.tmp" &&
    mv -f "$d/palette.env.tmp" "$d/palette.env"
}

# Print FILE (a glow template carrying the base theme's colours) in the loaded palette's colours.
# One pass through placeholders, so a new colour can never be rewritten twice. Base: unchanged.
ab_recolor_glow() {
  sed -e "s/f59145/@ACCENT@/g; s/ff5a1f/@EMBER@/g; s/ffc48a/@FLARE@/g; s/2b2a28/@INACTIVE@/g" \
      -e "s/rgba(00000066)/rgba(@SHADOW_INACTIVE@)/g" "$1" |
    sed -e "s/@ACCENT@/$AB_ACCENT/g; s/@EMBER@/$AB_EMBER/g; s/@FLARE@/$AB_FLARE/g; s/@INACTIVE@/$AB_INACTIVE/g" \
        -e "s/@SHADOW_INACTIVE@/${AB_SHADOW_INACTIVE:-00000066}/g"
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
AB_EMBER_STYLES="rise fall drift spark pulse burst"

# Sets AB_VAL to the base theme's value for an edition key.
ab_base_default() {
  case ${1:-} in
    CURSOR_FX) AB_VAL=embers ;; ROTATE) AB_VAL=slow ;; DIM) AB_VAL=0.08 ;;
    GLOW_RANGE) AB_VAL=14 ;; EMBER_STYLE) AB_VAL=rise ;; *) AB_VAL=; return 1 ;;
  esac
}

# ab_valid KEY VALUE: success if VALUE is allowed for the edition key KEY.
ab_valid() {
  local k=${1:-} v=${2:-}
  case $k in
    CURSOR_FX)   [[ $v =~ ^(${AB_CURSOR_FX_NAMES// /|})$ ]] ;;
    ROTATE)      [[ $v =~ ^(off|slow|medium|fast)$ ]] ;;
    DIM)         [[ $v =~ ^(0|1|0?\.[0-9]+|1\.0*)$ ]] ;;
    GLOW_RANGE)  [[ $v =~ ^[1-9][0-9]?$ ]] && (( v >= 4 && v <= 30 )) ;;
    EMBER_STYLE) [[ $v =~ ^(${AB_EMBER_STYLES// /|})$ ]] ;;
    *) return 1 ;;
  esac
}

# Every afterburn call resolves five keys, so this part reads files with builtins only: no grep, no subshells.
# ab_scan FILE KEY: AB_LINE = the last line that assigns KEY (leading spaces allowed), AB_LINE0 = the last one
# that starts with KEY= itself. Both empty if there is none or the file cannot be read.
ab_scan() {
  local line
  AB_LINE= AB_LINE0=
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == *"$2="* && $line =~ ^[[:space:]]*"$2"= ]] || continue   # the glob first: it is cheap
    AB_LINE=$line
    [[ $line == "$2="* ]] && AB_LINE0=$line
  done 2>/dev/null < "$1"
  return 0
}

# Sets AB_V to the value in AB_LINE (a trailing comment, surrounding spaces and one pair of quotes are dropped).
# Fails if it is empty.
ab_line_value() {
  local v=${AB_LINE#*=}
  if [[ $v =~ ^[[:space:]]*\"([^\"]*)\" || $v =~ ^[[:space:]]*\'([^\']*)\' ]]; then
    v=${BASH_REMATCH[1]}
  else
    v=${v%%#*}
    v=${v#"${v%%[![:space:]]*}"}
    v=${v%"${v##*[![:space:]]}"}
  fi
  AB_V=$v
  [[ -n $v ]]
}

# ab_file_value FILE KEY: print KEY's value from a KEY=VALUE file (last line wins, see ab_line_value).
# Fails if the key is absent or empty.
ab_file_value() { ab_scan "$1" "$2"; ab_line_value && printf '%s' "$AB_V"; }

# The user's own conf, and where it keeps its explicit values. Sets AB_CONF.
ab_conf_path() { AB_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/afterburn/afterburn.conf"; }

# ab_conf_value KEY: sets AB_V to the value you saved yourself, unless the line is an untouched first-run default.
ab_conf_value() {
  ab_conf_path
  [[ -f $AB_CONF ]] || return 1
  ab_scan "$AB_CONF" "$1"
  case $AB_LINE0 in
    'ROTATE=slow          # off|slow|medium|fast  (border gradient turn: 60s|20s|8s per turn)' | \
    'DIM=0.08             # dim_inactive strength, 0 = off') return 1 ;;
  esac
  ab_line_value
}

# Sets AB_EDITION_FILE to the edition.conf of a theme: your installed copy, the staged current theme, then the
# base theme's own .editions/ copy (so an edition installed by an older release still gets its defaults).
# Only afterburn-<edition> names qualify, and the base theme has none.
ab_edition_file() {
  local name=${1:-} f
  [[ $name =~ ^afterburn-[a-z0-9]+$ ]] || return 1
  for f in "$HOME/.config/omarchy/themes/$name/edition.conf" \
           "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme/edition.conf" \
           "$HOME/.config/omarchy/themes/afterburn/.editions/${name#afterburn-}/edition.conf"; do
    [[ -f $f ]] && { AB_EDITION_FILE=$f; return 0; }
  done
  return 1
}

# ab_effective KEY [THEME]: sets AB_VAL to the value to use and AB_SRC to where it came from
# (conf, edition or default).
ab_effective() {
  local k=$1 theme=${2:-}
  ab_base_default "$k"; AB_SRC=default
  if ab_conf_value "$k"; then
    if ab_valid "$k" "$AB_V"; then AB_VAL=$AB_V AB_SRC=conf; return 0; fi
    echo "afterburn: ignoring $k='$AB_V' in $AB_CONF (not an allowed value)" >&2
  fi
  if ab_edition_file "$theme" && ab_scan "$AB_EDITION_FILE" "$k" && ab_line_value && ab_valid "$k" "$AB_V"; then
    AB_VAL=$AB_V AB_SRC=edition
  fi
  return 0
}
