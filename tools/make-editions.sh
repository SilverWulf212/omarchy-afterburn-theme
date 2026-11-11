#!/usr/bin/env bash
# Rebuild every Afterburn colour edition from the base theme files.
#
# Writes .editions/<name>/ (one complete Omarchy theme dir per edition, with its
# own cool/hot heat wallpapers in heat-wallpapers/) and .editions/README.md, plus
# the base unlock.png and preview-unlock.png at the repo root. Everything under
# .editions/ is derived: the script builds a fresh tree and swaps it in, so never
# hand-edit those files. Change this script. The output is byte-for-byte
# repeatable, so rerunning it only changes git where its inputs or rules changed.
#
# The folder is hidden on purpose: Omarchy stages an installed theme with a `*` glob,
# which skips dot entries, so the ~125 MB of editions are not copied into current/theme
# every time you switch to the base theme. The installer copies them from here.
#
# Method: hue-rotate the alternative stills and palette. Curated default stills,
# matching heat variants and live loops are copied from edition-extras files/. Neutrals (backgrounds,
# greys, muted) stay put because they have almost no saturation.
#   - images: ImageMagick -modulate works in HSL. Its hue argument is
#     100 + degrees/1.8 (so 100 = no change, 200 = +180 deg, not 360).
#   - videos: base orange loops remain exclusive to orange. Edition videos
#     are rendered by tools/wallpapers/render.py and copied without transcoding.
#   - heat wallpapers: the base theme's extras/heat-wallpapers/{cool,hot}/ get
#     the same grade as the stills, so `afterburn level` swaps within an edition.
#   - the optional warm-band field squeezes the base's whole warm range (red to
#     yellow, 0-70 deg) into a narrow band. Redline needs it: its saturated
#     yellow highlights (the prompt text, the cursor) would otherwise rotate
#     only as far as orange, and orange is 30 deg from red.
#
# Per-edition extras (tools/edition-extras/<name>/): files/ is copied into .editions/<name>/ as it is
# (extra live wallpapers named live-*, btop.theme, neovim.lua) and edition.conf next to it. The conf
# holds the runtime knobs (CURSOR_FX ROTATE DIM GLOW_RANGE EMBER_STYLE, checked here with the same rules
# the runtime uses) and the build-time texts TAGLINE, PERSONALITY and FEELING, which end up in
# .editions/README.md and in the colors.toml header. A bad value stops the build.
#
# Requires: magick, ffmpeg, ffprobe, python3, fc-match, JetBrains Mono.
# Usage: tools/make-editions.sh
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# The runtime's own checks (ab_valid, ab_file_value), so the build and the runtime can never disagree.
# shellcheck disable=SC1091
. "$ROOT/extras/afterburn-theme.sh"

for tool in magick ffmpeg ffprobe python3 fc-match; do
  command -v "$tool" >/dev/null || { echo "make-editions: missing $tool" >&2; exit 1; }
done
for f in colors.toml hyprland.lua icons.theme backgrounds extras/heat-wallpapers/cool extras/heat-wallpapers/hot; do
  [[ -e $f ]] || { echo "make-editions: base file missing: $f" >&2; exit 1; }
done
FONT=$(fc-match -f '%{file}' 'JetBrainsMono Nerd Font:style=Bold')
[[ $FONT == *JetBrains* && -f $FONT ]] || { echo "make-editions: JetBrains Mono not installed" >&2; exit 1; }
FONT_REGULAR=$(fc-match -f '%{file}' 'JetBrainsMono Nerd Font:style=Regular')
[[ $FONT_REGULAR == *JetBrains* && -f $FONT_REGULAR ]] || { echo "make-editions: JetBrains Mono Regular not installed" >&2; exit 1; }

BASE_ACCENT=$(sed -n 's/^accent = "#\([0-9a-fA-F]\{6\}\)".*/\1/p' colors.toml)
BG=$(sed -n 's/^background = "\(#[0-9a-fA-F]\{6\}\)".*/\1/p' colors.toml)
[[ -n $BASE_ACCENT && -n $BG ]] || { echo "make-editions: could not read accent/background" >&2; exit 1; }

# name | target accent hue (deg) | Yaru icon variant | lightness x | saturation x | warm band | glow word
# (the tagline, personality and feeling live in tools/edition-extras/<name>/edition.conf)
# Lightness/saturation multipliers are optional tuning; 1.0 keeps the base feel.
# Warm band (optional, LO:HI deg): the base's 0-70 deg lands on LO..HI in the stills and the preview.
EDITIONS=(
  "voltage|185|Yaru-prussiangreen-dark|1.00|1.00||cyan"
  "cyber|115|Yaru-olive-dark|1.00|1.00||green"
  "overdrive|315|Yaru-magenta-dark|1.00|1.00||magenta"
  "redline|355|Yaru-red-dark|0.78|1.00|350:4|red"
  "phantom|270|Yaru-purple-dark|1.00|1.00||violet"
)

# Light editions are not hue rotations: ink on paper instead of light on black. Each brings a
# hand-made tools/edition-extras/<name>/colors.toml (`mode = "light"`), and the build prints the base
# stills onto its paper colour (see print_grade). name | icon theme | shadow word
LIGHT_EDITIONS=(
  "lite|Yaru|warm ink"
)

# The base theme's own row in the README (it has no edition.conf: its knobs are the built-in defaults).
BASE_TAGLINE="Orange on black. The original burn."
BASE_PERSONALITY="The original: warm, confident, jet at full burn."
BASE_FEELING="heat, momentum"

die() { echo "make-editions: $*" >&2; exit 1; }

# edition_conf NAME: read and check tools/edition-extras/NAME/edition.conf. Sets CONF_<KEY> for the five
# runtime keys and CONF_TAGLINE, CONF_PERSONALITY, CONF_FEELING. Every key is required.
edition_conf() {
  local conf="tools/edition-extras/$1/edition.conf" k v
  [[ -f $conf ]] || die "$conf is missing"
  for k in $AB_EDITION_KEYS; do
    v=$(ab_file_value "$conf" "$k") || die "$conf: $k is missing"
    ab_valid "$k" "$v" || die "$conf: $k='$v' is not an allowed value"
    printf -v "CONF_$k" %s "$v"
  done
  for k in TAGLINE PERSONALITY FEELING; do
    v=$(ab_file_value "$conf" "$k") || die "$conf: $k is missing"
    # Plain text only: these land in a Markdown table and a Python argument.
    [[ $v =~ ^[A-Za-z0-9\ .,:\;\!?\'-]{3,90}$ ]] || die "$conf: $k has characters or a length that is not allowed"
    printf -v "CONF_$k" %s "$v"
  done
}

# turn_words ROTATE: the border turn in words.
turn_words() {
  case $1 in off) echo "still" ;; slow) echo "slow, 10 s" ;; medium) echo "medium, 5 s" ;; fast) echo "fast, 2.5 s" ;; esac
}

# copy_extras NAME DIR: files/ of the edition's extras go into DIR as they are, and so does edition.conf.
# A file that would replace one the build already made is an error, not a silent overwrite.
copy_extras() {
  local src="tools/edition-extras/$1" f rel
  if [[ -d $src/files ]]; then
    while IFS= read -r -d '' f; do
      rel=${f#"$src/files/"}
      [[ ! -e $2/$rel ]] || die "$src/files/$rel would replace a file the build made ($2/$rel)"
      mkdir -p "$(dirname "$2/$rel")"
      cp "$f" "$2/$rel"
    done < <(find "$src/files" -type f -print0 | LC_ALL=C sort -z)
  fi
  cp "$src/edition.conf" "$2/edition.conf"
}

# Check every edition.conf before the slow image and video work, so a typo fails in a second.
for spec in "${EDITIONS[@]}" "${LIGHT_EDITIONS[@]}"; do edition_conf "${spec%%|*}"; done

HEAT_QUALITY=80   # the base heat set is q84; 80 keeps five more copies of it small

# Colour maths, stdlib only. Subcommands: info, toml, hypr.
PY=$(cat <<'PYEOF'
import colorsys, math, re, sys

# Semantic ANSI slots keep their meaning in every edition: errors stay red,
# warnings stay yellow, success stays green.
FIXED = {
    "red": "ff6467", "bright_red": "ff8a8c",
    "yellow": "f3ca3e", "bright_yellow": "ffdc70",
    "green": "8ee07a", "bright_green": "b8f08a",
    # Hue-rotated warm colours would collapse magenta into cyan/blue in cool
    # editions, so the ANSI magenta slot is a fixed violet-pink in every edition.
    "magenta": "c678dd", "bright_magenta": "dd9aee",
}
SAT_MIN = 0.3  # below this HLS saturation a colour is a neutral and stays put

def rgb(hx):
    return tuple(int(hx[i:i + 2], 16) / 255 for i in (0, 2, 4))

def hex_of(c):
    return "".join(f"{round(v * 255):02x}" for v in c)

def hue(hx):
    return colorsys.rgb_to_hls(*rgb(hx))[0] * 360

def normalise(deg):
    deg = deg % 360
    return deg - 360 if deg > 180 else deg

def rotate(hx, shift, lmul=1.0, smul=1.0):
    h, l, s = colorsys.rgb_to_hls(*rgb(hx))
    if s < SAT_MIN:
        return hx
    l, s = min(1.0, l * lmul), min(1.0, s * smul)
    return hex_of(colorsys.hls_to_rgb((h + shift / 360) % 1.0, l, s))

def recolour(text, shift, lmul, smul):
    def sub(m):
        return f"rgba({rotate(m.group(1).lower(), shift, lmul, smul)}{m.group(2) or ''})"
    return re.sub(r"rgba\(([0-9a-fA-F]{6})([0-9a-fA-F]{2})?\)", sub, text)

def toml_line(line, shift, lmul, smul):
    m = re.match(r'^([a-z_]+)(\s*=\s*)"(.*)"\s*$', line)
    if not m:
        return line
    key, eq, val = m.groups()
    if key in FIXED:
        return f'{key}{eq}"#{FIXED[key]}"'
    if re.fullmatch(r"#[0-9a-fA-F]{6}", val):
        return f'{key}{eq}"#{rotate(val[1:].lower(), shift, lmul, smul)}"'
    return f'{key}{eq}"{recolour(val, shift, lmul, smul)}"'

cmd = sys.argv[1]
if cmd == "info":  # info TARGET_HUE BASE_ACCENT LMUL SMUL -> "<shift> #<accent> <video gamma>"
    target, base = float(sys.argv[2]), sys.argv[3]
    lmul, smul = float(sys.argv[4]), float(sys.argv[5])
    shift = normalise(target - hue(base))
    accent = rotate(base, shift, lmul, smul)
    err = normalise(hue(accent) - target)
    if abs(err) > 2:
        sys.exit(f"make-editions: accent hue off target by {err:.1f} deg")
    # ffmpeg eq gamma g maps mid-grey 0.5 to 0.5**(1/g); pick g so that matches lmul.
    vgamma = math.log(0.5) / math.log(0.5 * lmul)
    print(f"{shift:.3f} #{accent} {vgamma:.3f}")
elif cmd == "toml":  # toml SRC DST NAME TAGLINE SHIFT LMUL SMUL
    src, dst, name, tagline = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
    shift, lmul, smul = float(sys.argv[6]), float(sys.argv[7]), float(sys.argv[8])
    lines = open(src, encoding="utf-8").read().splitlines()
    body = [toml_line(l, shift, lmul, smul) for l in lines if not l.startswith("#")]
    while body and body[0] == "":
        body.pop(0)
    # The cool heat level's middle stop is the base theme's `magenta`, rotated like the rest. The
    # edition's own `magenta` stays a fixed ANSI violet, so the runtime reads this key instead.
    cool = next((m.group(1).lower() for m in (re.match(r'^magenta\s*=\s*"#([0-9a-fA-F]{6})"', l) for l in lines) if m), None)
    if cool is None:
        sys.exit("make-editions: base colors.toml has no magenta")
    body += ["", "# Read by the Afterburn extras: middle stop of the cool heat level.",
             f'afterburn_cool = "#{rotate(cool, shift, lmul, smul)}"']
    header = [
        f"# Afterburn {name.title()}: {tagline}",
        "# Colour edition of Afterburn (base orange). Generated by tools/make-editions.sh; do not hand-edit.",
        "# github.com/silverwulf212/omarchy-afterburn-theme",
        "",
    ]
    open(dst, "w", encoding="utf-8").write("\n".join(header + body) + "\n")
elif cmd == "hypr":  # hypr SRC DST NAME SHIFT LMUL SMUL GLOW
    src, dst, name = sys.argv[2], sys.argv[3], sys.argv[4]
    shift, lmul, smul = float(sys.argv[5]), float(sys.argv[6]), float(sys.argv[7])
    glow = sys.argv[8]
    lines = open(src, encoding="utf-8").read().split("\n")
    # The base's own header names orange, which is wrong for an edition: replace it.
    if lines and lines[0].startswith("-- Afterburn:"):
        lines = lines[1:]
    head = (f"-- Afterburn {name.title()}: three-stop gradient on the focused window, plus a soft {glow} glow.\n"
            "-- Edition generated by tools/make-editions.sh; do not hand-edit.\n")
    open(dst, "w", encoding="utf-8").write(head + recolour("\n".join(lines), shift, lmul, smul))
elif cmd == "light":  # light COLORS_SRC COLORS_DST HYPR_SRC HYPR_DST NAME TAGLINE WORD RANGE
    csrc, cdst, hsrc, hdst, name, tagline, word, grange = sys.argv[2:10]
    text = open(csrc, encoding="utf-8").read()
    keys = dict(re.findall(r'^([a-z_]+)\s*=\s*"([^"]*)"', text, re.M))
    if keys.get("mode") != "light":
        sys.exit(f"make-editions: {csrc} must say mode = \"light\"")
    need = ["accent", "background", "foreground", "brown", "dark_foreground", "afterburn_cool",
            "hyprland_active_border", "hyprland_inactive_border"]
    missing = [k for k in need if k not in keys]
    if missing:
        sys.exit(f"make-editions: {csrc} lacks {', '.join(missing)}")
    stops = re.findall(r"rgba\(([0-9a-fA-F]{6})[0-9a-fA-F]{2}\)", keys["hyprland_active_border"])
    inactive = re.findall(r"rgba\(([0-9a-fA-F]{6})[0-9a-fA-F]{2}\)", keys["hyprland_inactive_border"])
    if len(stops) != 3 or len(inactive) != 1:
        sys.exit(f"make-editions: {csrc} needs three active border stops and one inactive colour")

    def lum(hx):
        c = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb(hx)]
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

    def contrast(a, b):
        hi, lo = sorted((lum(a), lum(b)), reverse=True)
        return (hi + 0.05) / (lo + 0.05)

    # Text colours have to stay readable on the paper. 4.5:1 is the WCAG AA line for body text.
    paper = keys["background"].lstrip("#")
    for k in ["accent", "foreground", "light_foreground", "red", "yellow", "green", "cyan", "blue", "magenta",
              "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta"]:
        if k in keys and contrast(keys[k].lstrip("#"), paper) < 4.5:
            sys.exit(f"make-editions: {csrc}: {k} {keys[k]} is under 4.5:1 on {keys['background']}")
    body = [l for l in text.splitlines() if not (l.startswith("#") and "afterburn_cool" not in l and "Read by" not in l)]
    while body and body[0] == "":
        body.pop(0)
    header = [
        f"# Afterburn {name.title()}: {tagline}",
        "# Light edition of Afterburn (base orange). Generated by tools/make-editions.sh from",
        f"# tools/edition-extras/{name}/colors.toml; do not hand-edit this copy.",
        "# github.com/silverwulf212/omarchy-afterburn-theme",
        "",
    ]
    open(cdst, "w", encoding="utf-8").write("\n".join(header + body) + "\n")
    lines = open(hsrc, encoding="utf-8").read().split("\n")
    if lines and lines[0].startswith("-- Afterburn:"):
        lines = lines[1:]
    lua = "\n".join(lines)
    for old, new in [("f59145", stops[0]), ("ff5a1f", stops[1]), ("ffc48a", stops[2]), ("2b2a28", inactive[0])]:
        lua = lua.replace(old, "@" + old + "@")
    for old, new in [("f59145", stops[0]), ("ff5a1f", stops[1]), ("ffc48a", stops[2]), ("2b2a28", inactive[0])]:
        lua = lua.replace("@" + old + "@", new.lower())
    # Paper wants a short warm shadow, not the dark themes' black one, and a tighter range.
    lua = lua.replace('rgba(00000066)', f'rgba({keys["brown"].lstrip("#").lower()}26)')
    lua = re.sub(r"range = \d+", f"range = {int(grange)}", lua)
    head = (f"-- Afterburn {name.title()}: three-stop gradient on the focused window, plus a soft {word} shadow.\n"
            "-- Edition generated by tools/make-editions.sh; do not hand-edit.\n")
    open(hdst, "w", encoding="utf-8").write(head + lua)
    print(f"#{stops[0].lower()} {keys['background']} #{keys['foreground'].lstrip('#')}")
elif cmd == "tint":  # tint HEX AMOUNT -> same hue and saturation, lightness pulled AMOUNT of the way to white
    hx, amt = sys.argv[2], float(sys.argv[3])
    h, l, s = colorsys.rgb_to_hls(*rgb(hx))
    print("#" + hex_of(colorsys.hls_to_rgb(h, l + (1 - l) * amt, s)))
else:
    sys.exit(f"unknown command {cmd}")
PYEOF
)

# ImageMagick stamps the time into every PNG it writes, which would make each run change every PNG
# in git. These keep the output repeatable.
NODATE=(+set date:create +set date:modify +set date:timestamp -define png:exclude-chunk=tIME)

# make_unlock OUT ACCENT_HEX LABEL [LABEL_INK]: 800x188 transparent wordmark with a soft glow.
# The caption (edition name) takes LABEL_INK, a lighter tint of the accent, at 60 pt: on the
# near-black background the raw accent of Redline and Phantom reads too dim at 640 px wide.
make_unlock() {
  local out=$1 accent=$2 label=$3 ink=${4:-$2}
  local tmp
  tmp=$(mktemp -d)
  magick -size 800x188 xc:none -font "$FONT" -pointsize 120 -kerning 8 \
    -gravity center -fill "$accent" -annotate +0-14 'AFTERBURN' "$tmp/word.png"
  if [[ -n $label ]]; then
    magick "$tmp/word.png" -font "$FONT" -pointsize 60 -kerning 14 \
      -gravity center -fill "$ink" -annotate +0+62 "$label" "$tmp/label.png"
    mv "$tmp/label.png" "$tmp/word.png"
  fi
  magick "$tmp/word.png" \( +clone -background "$accent" -shadow 55x8+0+0 \) \
    +swap -background none -layers merge +repage \
    -gravity center -extent 800x188 +repage "${NODATE[@]}" PNG32:"$out"
  rm -rf "$tmp"
}

# make_preview UNLOCK OUT: 1920x1080 frame in the theme background colour.
make_preview() {
  magick -size 1920x1080 "xc:$BG" "$1" -gravity center -composite "${NODATE[@]}" PNG24:"$2"
}

# band_fx LO HI: an ImageMagick -fx expression for the hue channel (0-1, HSL) that squeezes the base's
# warm band 0-70 deg onto LO..HI and stretches the rest of the wheel around the other way, so the
# remap is continuous and neutrals (no saturation) are untouched.
band_fx() {
  awk -v lo="$1" -v hi="$2" 'BEGIN {
    w = (hi - lo + 360) % 360; r = (lo - hi + 360) % 360
    printf "mod((u*360<=70) ? %s+u*360*%s/70 : %s+(u*360-70)*%s/290, 360)/360", lo, w, hi, r
  }'
}

# grade SRC DST [JPEG_QUALITY]: the current edition's colour grade for one image
# (uses im_light, im_sat, im_hue and band_expr, which the edition loop sets).
grade() {
  local q=()
  [[ -z ${3:-} ]] || q=(-quality "$3")
  if [[ -n $band_expr ]]; then
    magick "$1" -colorspace HSL -channel R -fx "$band_expr" +channel -colorspace sRGB \
      -modulate "$im_light,$im_sat,100" "${q[@]}" "${NODATE[@]}" "$2"
  else
    magick "$1" -modulate "$im_light,$im_sat,$im_hue" "${q[@]}" "${NODATE[@]}" "$2"
  fi
}

# relabel IMG HEX [JPEG_QUALITY]: 2-prompt.jpg carries the base accent as a caption
# ("cyber // 0xF59145 // jetbrains mono"). Paint the hex over with the edition's own, in place.
# The positions were measured on the 1200 px wide preview and scale with the image width. The old
# digits are covered with a clean patch of the same caption row (the average of the empty stretches left
# and right of the caption, which follows the glow's gradient), and the new ones get the ink of the
# neighbouring caption text and the same softness.
relabel() {
  local img=$1 hex=${2^^} q=() k ink
  [[ -z ${3:-} ]] || q=(-quality "$3")
  k=$(awk -v w="$(magick identify -format %w "$img")" 'BEGIN { printf "%.4f", w / 1200 }')
  px() { awk -v k="$k" -v v="$1" 'BEGIN { printf "%d", v * k + 0.5 }'; }
  ink=$(magick "$img" -crop "$(px 90)x$(px 12)+$(px 328)+$(px 297)" +repage txt:- |
    awk -F'[()]' 'NR > 1 { split($2, c, ","); s = c[1] + c[2] + c[3]
      if (s > m) { m = s; best = int(c[1] * .9) "," int(c[2] * .9) "," int(c[3] * .9) } }
      END { print "rgb(" best ")" }')
  magick "$img" \
    \( -clone 0 -crop "$(px 56)x$(px 20)+$(px 98)+$(px 292)" +repage \) \
    \( -clone 0 -crop "$(px 56)x$(px 20)+$(px 430)+$(px 292)" +repage \) \
    \( -clone 1,2 -evaluate-sequence Mean \) -delete 1,2 \
    -geometry "+$(px 237)+$(px 292)" -composite \
    \( -size "$(px 60)x$(px 20)" xc:none -font "$FONT_REGULAR" -pointsize "$(awk -v k="$k" 'BEGIN { printf "%.2f", 10.4 * k }')" \
       -fill "$ink" -gravity NorthWest -annotate "+$(px 1)+$(px 4)" "0x$hex" \
       -blur "0x$(awk -v k="$k" 'BEGIN { printf "%.2f", 0.45 * k }')" \) \
    -geometry "+$(px 238)+$(px 293)" -composite "${q[@]}" "${NODATE[@]}" "$img"
}

# print_grade SRC DST PAPER [JPEG_QUALITY]: a dark still as a print on PAPER. Lightness is inverted in
# Lab (black becomes blank paper, the brightest glow the heaviest ink) with hue and chroma kept, then
# the sheet is multiplied by the paper colour. A hotter (brighter) source prints with more ink.
print_grade() {
  local q=()
  [[ -z ${4:-} ]] || q=(-quality "$4")
  magick "$1" -colorspace Lab -channel R -negate +channel -colorspace sRGB \
    \( +clone -fill "$3" -colorize 100 \) -compose Multiply -composite \
    -sampling-factor 4:2:0 "${q[@]}" "${NODATE[@]}" "$2"
}

# make_unlock_light OUT ACCENT LABEL INK: the 800x188 wordmark for a light edition. No glow: a light
# background cannot show one, so the word is plain ink with a faint offset shadow in the accent.
make_unlock_light() {
  local out=$1 accent=$2 label=$3 ink=$4 tmp
  tmp=$(mktemp -d)
  magick -size 800x188 xc:none -font "$FONT" -pointsize 120 -kerning 8 \
    -gravity center -fill "$accent" -annotate +0-14 'AFTERBURN' \
    -font "$FONT" -pointsize 60 -kerning 14 -fill "$ink" -annotate +0+62 "$label" "$tmp/word.png"
  magick "$tmp/word.png" \( +clone -background "$accent" -shadow 22x3+0+3 \) \
    +swap -background none -layers merge +repage \
    -gravity center -extent 800x188 +repage "${NODATE[@]}" PNG32:"$out"
  rm -rf "$tmp"
}

# Base theme: top-level unlock art (orange, no edition label).
make_unlock unlock.png "#$BASE_ACCENT" ""
make_preview unlock.png preview-unlock.png
python3 tools/wallpapers/selector-previews.py render backgrounds/1-horizon.jpg preview.png

# Build in a scratch dir next to .editions/ and swap it in at the end, so a failed run (a missing
# codec, Ctrl-C) never leaves a half-wiped .editions/ behind.
STAGE=$(mktemp -d "$ROOT/.editions-build.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

# README rows, one table each: who they are, how they move, and what only they have.
feel_rows=("| afterburn (base) | #$BASE_ACCENT | $BASE_PERSONALITY | $BASE_FEELING | $BASE_TAGLINE |")
motion_rows=("| afterburn (base) | embers | $(turn_words slow) | 14 | 0.08 | rise |")
extras_rows=("| afterburn (base) | The nine wallpapers (six stills, three live loops) |")

for spec in "${EDITIONS[@]}"; do
  IFS='|' read -r name target icon lmul smul band glow <<<"$spec"
  edition_conf "$name"
  tagline=$CONF_TAGLINE
  dir="$STAGE/$name"
  mkdir -p "$dir/backgrounds" "$dir/heat-wallpapers/cool" "$dir/heat-wallpapers/hot"

  info=$(python3 -I -c "$PY" info "$target" "$BASE_ACCENT" "$lmul" "$smul")
  read -r shift accent vgamma <<<"$info"
  im_hue=$(awk -v s="$shift" 'BEGIN { printf "%.3f", 100 + s / 1.8 }')
  label="· ${name^^} ·"
  ink=$(python3 -I -c "$PY" tint "${accent#\#}" 0.45)

  python3 -I -c "$PY" toml colors.toml "$dir/colors.toml" "$name" "$tagline" "$shift" "$lmul" "$smul"
  python3 -I -c "$PY" hypr hyprland.lua "$dir/hyprland.lua" "$name" "$shift" "$lmul" "$smul" "$glow"
  printf '%s\n' "$icon" > "$dir/icons.theme"

  im_light=$(awk -v l="$lmul" 'BEGIN { printf "%.1f", 100 * l }')
  im_sat=$(awk -v s="$smul" 'BEGIN { printf "%.1f", 100 * s }')
  band_expr=""
  [[ -z $band ]] || band_expr=$(band_fx "${band%%:*}" "${band##*:}")

  for level in cool hot; do
    for src in "extras/heat-wallpapers/$level"/*.jpg; do
      # A curated edition default has matching heat variants supplied by files/.
      if [[ ${src##*/} == 1-horizon.jpg && -f tools/edition-extras/$name/files/heat-wallpapers/$level/1-horizon.jpg ]]; then continue; fi
      grade "$src" "$dir/heat-wallpapers/$level/$(basename "$src")" "$HEAT_QUALITY"
      [[ $src != */2-prompt.jpg ]] || relabel "$dir/heat-wallpapers/$level/2-prompt.jpg" "${accent#\#}" "$HEAT_QUALITY"
    done
  done

  # Grade only the original numbered base set, never the shared edition copies.
  for src in backgrounds/[1-9]-*; do
    file=$(basename "$src")
    case "$file" in
      *.jpg)
        if [[ $file == 1-horizon.jpg && -f tools/edition-extras/$name/files/backgrounds/$file ]]; then continue; fi
        grade "$src" "$dir/backgrounds/$file" 94
        [[ $file != 2-prompt.jpg ]] || relabel "$dir/backgrounds/$file" "${accent#\#}" 94 ;;
      *.mp4)
        # Orange's film artwork stays exclusive to base Afterburn. Each edition
        # ships its own curated live loop through copy_extras below.
        : ;;
      *)
        echo "make-editions: skipping unknown background $file" >&2 ;;
    esac
  done

  make_unlock "$dir/unlock.png" "$accent" "$label" "$ink"
  make_preview "$dir/unlock.png" "$dir/preview-unlock.png"

  copy_extras "$name" "$dir"
  python3 tools/wallpapers/selector-previews.py render "$dir/backgrounds/1-horizon.jpg" "$dir/preview.png"
  extra_list=()
  while IFS= read -r f; do extra_list+=("\`${f#"$dir/"}\`"); done < <(
    { find "$dir/backgrounds" -type f -name 'live-*' ; find "$dir" -maxdepth 1 -type f \( -name btop.theme -o -name neovim.lua \); } | LC_ALL=C sort)
  extras_joined=$(IFS=,; echo "${extra_list[*]}")
  extras_joined=${extras_joined//,/, }
  feel_rows+=("| $name | $accent | $CONF_PERSONALITY | $CONF_FEELING | $tagline |")
  motion_rows+=("| $name | $CONF_CURSOR_FX | $(turn_words "$CONF_ROTATE") | $CONF_GLOW_RANGE | $CONF_DIM | $CONF_EMBER_STYLE |")
  extras_rows+=("| $name | ${extras_joined:-none} |")
  echo "built $name: shift ${shift} deg, accent $accent"
done

# Light editions. The six base stills become prints (2 to 6 keep their names; the base's own
# 1-horizon becomes 7-sunprint, because files/ supplies the edition's bespoke 1-horizon), and so do
# their cool and hot heat variants: the brighter hot source prints darker, which is what "hot" means in ink.
for spec in "${LIGHT_EDITIONS[@]}"; do
  IFS='|' read -r name icon word <<<"$spec"
  edition_conf "$name"
  tagline=$CONF_TAGLINE
  src="tools/edition-extras/$name"
  [[ -f $src/colors.toml ]] || die "$src/colors.toml is missing (a light edition brings its own palette)"
  [[ -f $src/files/backgrounds/1-horizon.jpg ]] || die "$src/files/backgrounds/1-horizon.jpg is missing"
  dir="$STAGE/$name"
  mkdir -p "$dir/backgrounds" "$dir/heat-wallpapers/cool" "$dir/heat-wallpapers/hot"

  info=$(python3 -I -c "$PY" light "$src/colors.toml" "$dir/colors.toml" hyprland.lua "$dir/hyprland.lua" \
    "$name" "$tagline" "$word" "$CONF_GLOW_RANGE")
  read -r accent paper ink <<<"$info"
  printf '%s\n' "$icon" > "$dir/icons.theme"

  scratch=$(mktemp -d "$STAGE/.print.XXXXXX")
  print_one() { # print_one SRC DST QUALITY
    local file out
    file=$(basename "$1")
    out=$2/$file
    [[ $file != 1-horizon.jpg ]] || out=$2/7-sunprint.jpg
    if [[ $file == 2-prompt.jpg ]]; then
      # The caption carries the accent as hex: relabel the dark copy first, so the print inverts it too.
      magick "$1" -quality 98 "$scratch/prompt.jpg"
      relabel "$scratch/prompt.jpg" "${accent#\#}" 98
      print_grade "$scratch/prompt.jpg" "$out" "$paper" "$3"
    else
      print_grade "$1" "$out" "$paper" "$3"
    fi
  }
  for f in backgrounds/[1-9]-*.jpg; do print_one "$f" "$dir/backgrounds" 92; done
  for level in cool hot; do
    for f in "extras/heat-wallpapers/$level"/*.jpg; do print_one "$f" "$dir/heat-wallpapers/$level" "$HEAT_QUALITY"; done
  done
  rm -rf "$scratch"

  make_unlock_light "$dir/unlock.png" "$accent" "· ${name^^} ·" "$ink"
  magick -size 1920x1080 "xc:$paper" "$dir/unlock.png" -gravity center -composite "${NODATE[@]}" PNG24:"$dir/preview-unlock.png"

  copy_extras "$name" "$dir"
  python3 tools/wallpapers/selector-previews.py render "$dir/backgrounds/1-horizon.jpg" "$dir/preview.png"
  extra_list=()
  while IFS= read -r f; do extra_list+=("\`${f#"$dir/"}\`"); done < <(
    { find "$dir/backgrounds" -type f \( -name 'live-*' -o -name '1-horizon.jpg' -o -name '[7-9]-*.jpg' \) ; find "$dir" -maxdepth 1 -type f \( -name btop.theme -o -name neovim.lua \); } | LC_ALL=C sort)
  extras_joined=$(IFS=,; echo "${extra_list[*]}")
  extras_joined=${extras_joined//,/, }
  feel_rows+=("| $name (light) | $accent on $paper | $CONF_PERSONALITY | $CONF_FEELING | $tagline |")
  motion_rows+=("| $name (light) | $CONF_CURSOR_FX | $(turn_words "$CONF_ROTATE") | $CONF_GLOW_RANGE | $CONF_DIM | $CONF_EMBER_STYLE |")
  extras_rows+=("| $name (light) | ${extras_joined:-none} |")
  echo "built $name: light edition, accent $accent on paper $paper"
done

{
  echo "# Afterburn editions"
  echo
  echo "Generated by \`tools/make-editions.sh\`. Do not hand-edit; change the script or an edition's \`tools/edition-extras/<name>/edition.conf\` and rerun it."
  echo
  echo "Each edition keeps the base palette structure and five hue-rotated alternative stills, with a bespoke default still and signature live loop. Orange's three live loops remain exclusive to the base theme. See docs/wallpapers/README.md for artwork and motion details."
  echo "Each also carries its own cool and hot heat wallpapers in \`heat-wallpapers/\`, which the \`afterburn\` command swaps in at those heat levels."
  echo
  echo "Lite is the light edition: ink on warm paper instead of light on black. Its palette is hand-made (\`tools/edition-extras/lite/colors.toml\`, every text colour at least 4.5:1 on the paper), the six base stills are printed onto the paper colour, and it has no glow: a short warm shadow instead. A light wallpaper would jar in the dark themes, so Lite's art is not copied into the shared \`backgrounds/\` folder."
  echo
  echo "## Who they are"
  echo
  echo "| Edition | Accent | Personality | Feeling | Tagline |"
  echo "| --- | --- | --- | --- | --- |"
  printf '%s\n' "${feel_rows[@]}"
  echo
  echo "## How they move"
  echo
  echo "Each edition ships an \`edition.conf\`. The theme-set hook and the \`afterburn\` command read it for the active theme, check every value, and use it as the default for these settings. A value you save yourself in \`~/.config/afterburn/afterburn.conf\` (or with \`afterburn set\`) always wins; \`afterburn unset KEY\` hands the setting back to the edition."
  echo
  echo "| Edition | Cursor effect | Border turn | Glow range | Dim | Lock embers |"
  echo "| --- | --- | --- | --- | --- | --- |"
  printf '%s\n' "${motion_rows[@]}"
  echo
  echo "Lock embers: \`rise\` drifts up (the base), \`fall\` rains down, \`drift\` floats and fades, \`spark\` crackles, \`pulse\` swells on a beat, \`burst\` fires sudden bursts between stillness."
  echo
  echo "## What only they have"
  echo
  echo "| Edition | Extra files (live wallpapers, btop and Neovim themes) |"
  echo "| --- | --- |"
  printf '%s\n' "${extras_rows[@]}"
} > "$STAGE/README.md"

rm -rf .editions
chmod 755 "$STAGE"
mv "$STAGE" .editions
trap - EXIT

# Expose every edition in the top-level background picker and GitHub folder.
# Copy original bytes; do not resize or recolour the signature art.
for spec in "${EDITIONS[@]}"; do
  name=${spec%%|*}
  loops=(".editions/$name/backgrounds/"live-*.mp4)
  [[ ${#loops[@]} -eq 1 && -f ${loops[0]} ]] || die "$name: expected one signature loop"
  artwork=${loops[0]##*/}
  artwork=${artwork#live-}
  artwork=${artwork%.mp4}
  cp ".editions/$name/backgrounds/1-horizon.jpg" "backgrounds/$name-$artwork.jpg"
  cp "${loops[0]}" "backgrounds/$name-$artwork-live.mp4"
done

echo "done: .editions/ and shared background copies regenerated from base files"
