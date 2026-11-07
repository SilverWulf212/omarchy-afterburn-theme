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
  mkdir -p "$d" || return 0
  printf 'FLARE=%s\nEMBER=%s\nRUST=%s\nASH=%s\n' "$AB_FLARE" "$AB_EMBER" "$AB_RUST" "$AB_ASH" > "$d/palette.env.tmp" &&
    mv -f "$d/palette.env.tmp" "$d/palette.env"
}

# Print FILE (a glow template carrying the base theme's colours) in the loaded palette's colours.
# One pass through placeholders, so a new colour can never be rewritten twice. Base: unchanged.
ab_recolor_glow() {
  sed -e "s/f59145/@ACCENT@/g; s/ff5a1f/@EMBER@/g; s/ffc48a/@FLARE@/g; s/2b2a28/@INACTIVE@/g" "$1" |
    sed -e "s/@ACCENT@/$AB_ACCENT/g; s/@EMBER@/$AB_EMBER/g; s/@FLARE@/$AB_FLARE/g; s/@INACTIVE@/$AB_INACTIVE/g"
}
