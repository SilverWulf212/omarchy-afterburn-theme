#!/usr/bin/env bash
# Rebuild every Afterburn colour edition from the base theme files.
#
# Writes editions/<name>/ (one complete Omarchy theme dir per edition, with its
# own cool/hot heat wallpapers in heat-wallpapers/) and editions/README.md, plus
# the base unlock.png and preview-unlock.png at the repo root. Everything under
# editions/ is derived: the script builds a fresh tree and swaps it in, so never
# hand-edit those files. Change this script. The output is byte-for-byte
# repeatable, so rerunning it only changes git where its inputs or rules changed.
#
# Method: hue-rotate, don't repaint. The Codex art keeps its shapes and
# lighting; only the warm colours move around the wheel. Neutrals (backgrounds,
# greys, muted) stay put because they have almost no saturation.
#   - images: ImageMagick -modulate works in HSL. Its hue argument is
#     100 + degrees/1.8 (so 100 = no change, 200 = +180 deg, not 360).
#   - videos: ffmpeg hue=h=<degrees> rotates chroma in YUV, so the landed hue
#     is a few degrees off the HSL target. The per-frame filter keeps the 8 s
#     loops seamless: no re-timing, same fps, same frame count.
#   - heat wallpapers: the base theme's extras/heat-wallpapers/{cool,hot}/ get
#     the same grade as the stills, so `afterburn level` swaps within an edition.
#   - the optional warm-band field squeezes the base's whole warm range (red to
#     yellow, 0-70 deg) into a narrow band. Redline needs it: its saturated
#     yellow highlights (the prompt text, the cursor) would otherwise rotate
#     only as far as orange, and orange is 30 deg from red.
#
# Requires: magick, ffmpeg, ffprobe, python3, fc-match, JetBrains Mono.
# Usage: tools/make-editions.sh
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

for tool in magick ffmpeg ffprobe python3 fc-match; do
  command -v "$tool" >/dev/null || { echo "make-editions: missing $tool" >&2; exit 1; }
done
for f in colors.toml hyprland.lua icons.theme preview.png backgrounds extras/heat-wallpapers/cool extras/heat-wallpapers/hot; do
  [[ -e $f ]] || { echo "make-editions: base file missing: $f" >&2; exit 1; }
done
FONT=$(fc-match -f '%{file}' 'JetBrainsMono Nerd Font:style=Bold')
[[ $FONT == *JetBrains* && -f $FONT ]] || { echo "make-editions: JetBrains Mono not installed" >&2; exit 1; }
FONT_REGULAR=$(fc-match -f '%{file}' 'JetBrainsMono Nerd Font:style=Regular')
[[ $FONT_REGULAR == *JetBrains* && -f $FONT_REGULAR ]] || { echo "make-editions: JetBrains Mono Regular not installed" >&2; exit 1; }

BASE_ACCENT=$(sed -n 's/^accent = "#\([0-9a-fA-F]\{6\}\)".*/\1/p' colors.toml)
BG=$(sed -n 's/^background = "\(#[0-9a-fA-F]\{6\}\)".*/\1/p' colors.toml)
[[ -n $BASE_ACCENT && -n $BG ]] || { echo "make-editions: could not read accent/background" >&2; exit 1; }

# name | target accent hue (deg) | Yaru icon variant | tagline | lightness x | saturation x | warm band
# Lightness/saturation multipliers are optional tuning; 1.0 keeps the base feel.
# Warm band (optional, LO:HI deg): the base's 0-70 deg lands on LO..HI in the stills and the preview.
EDITIONS=(
  "voltage|185|Yaru-prussiangreen-dark|Cold current on black glass.|1.00|1.00|"
  "cyber|115|Yaru-olive-dark|Acid green. The grid is listening.|1.00|1.00|"
  "overdrive|315|Yaru-magenta-dark|Magenta past the limiter.|1.00|1.00|"
  "redline|355|Yaru-red-dark|Blood red at the limiter. Hold it.|0.78|1.00|350:4"
  "phantom|270|Yaru-purple-dark|Ultraviolet. Here, then gone.|1.00|1.00|"
)
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
elif cmd == "hypr":  # hypr SRC DST NAME SHIFT LMUL SMUL
    src, dst, name = sys.argv[2], sys.argv[3], sys.argv[4]
    shift, lmul, smul = float(sys.argv[5]), float(sys.argv[6]), float(sys.argv[7])
    text = open(src, encoding="utf-8").read()
    head = f"-- Afterburn {name.title()} edition (generated by tools/make-editions.sh; do not hand-edit)\n"
    open(dst, "w", encoding="utf-8").write(head + recolour(text, shift, lmul, smul))
else:
    sys.exit(f"unknown command {cmd}")
PYEOF
)

# ImageMagick stamps the time into every PNG it writes, which would make each run change every PNG
# in git. These keep the output repeatable.
NODATE=(+set date:create +set date:modify +set date:timestamp -define png:exclude-chunk=tIME)

# make_unlock OUT ACCENT_HEX LABEL: 800x188 transparent wordmark with a soft glow.
make_unlock() {
  local out=$1 accent=$2 label=$3
  local tmp
  tmp=$(mktemp -d)
  magick -size 800x188 xc:none -font "$FONT" -pointsize 120 -kerning 8 \
    -gravity center -fill "$accent" -annotate +0-14 'AFTERBURN' "$tmp/word.png"
  if [[ -n $label ]]; then
    magick "$tmp/word.png" -font "$FONT" -pointsize 30 -kerning 14 \
      -gravity center -fill "$accent" -annotate +0+62 "$label" "$tmp/label.png"
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

# relabel IMG HEX [JPEG_QUALITY]: preview.png and 2-prompt.jpg carry the base accent as a caption
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

# Base theme: top-level unlock art (orange, no edition label).
make_unlock unlock.png "#$BASE_ACCENT" ""
make_preview unlock.png preview-unlock.png

# Build in a scratch dir next to editions/ and swap it in at the end, so a failed run (a missing
# codec, Ctrl-C) never leaves a half-wiped editions/ behind.
STAGE=$(mktemp -d "$ROOT/.editions-build.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

rows=("| afterburn (base) | #$BASE_ACCENT | Orange on black. The original burn. |")

for spec in "${EDITIONS[@]}"; do
  IFS='|' read -r name target icon tagline lmul smul band <<<"$spec"
  dir="$STAGE/$name"
  mkdir -p "$dir/backgrounds" "$dir/heat-wallpapers/cool" "$dir/heat-wallpapers/hot"

  info=$(python3 -I -c "$PY" info "$target" "$BASE_ACCENT" "$lmul" "$smul")
  read -r shift accent vgamma <<<"$info"
  im_hue=$(awk -v s="$shift" 'BEGIN { printf "%.3f", 100 + s / 1.8 }')
  label="· ${name^^} ·"

  python3 -I -c "$PY" toml colors.toml "$dir/colors.toml" "$name" "$tagline" "$shift" "$lmul" "$smul"
  python3 -I -c "$PY" hypr hyprland.lua "$dir/hyprland.lua" "$name" "$shift" "$lmul" "$smul"
  printf '%s\n' "$icon" > "$dir/icons.theme"

  im_light=$(awk -v l="$lmul" 'BEGIN { printf "%.1f", 100 * l }')
  im_sat=$(awk -v s="$smul" 'BEGIN { printf "%.1f", 100 * s }')
  band_expr=""
  [[ -z $band ]] || band_expr=$(band_fx "${band%%:*}" "${band##*:}")
  grade preview.png "$dir/preview.png"
  relabel "$dir/preview.png" "${accent#\#}"

  for level in cool hot; do
    for src in "extras/heat-wallpapers/$level"/*.jpg; do
      grade "$src" "$dir/heat-wallpapers/$level/$(basename "$src")" "$HEAT_QUALITY"
      [[ $src != */2-prompt.jpg ]] || relabel "$dir/heat-wallpapers/$level/2-prompt.jpg" "${accent#\#}" "$HEAT_QUALITY"
    done
  done

  for src in backgrounds/*; do
    file=$(basename "$src")
    case "$file" in
      *.jpg)
        grade "$src" "$dir/backgrounds/$file" 94
        [[ $file != 2-prompt.jpg ]] || relabel "$dir/backgrounds/$file" "${accent#\#}" 94 ;;
      *.mp4)
        ffmpeg -v error -y -i "$src" -vf "hue=h=$shift,eq=gamma=$vgamma" -an -map_metadata -1 \
          -c:v libx264 -preset medium -crf 18 -profile:v high -pix_fmt yuv420p \
          -movflags +faststart "$dir/backgrounds/$file" ;;
      *)
        echo "make-editions: skipping unknown background $file" >&2 ;;
    esac
  done

  make_unlock "$dir/unlock.png" "$accent" "$label"
  make_preview "$dir/unlock.png" "$dir/preview-unlock.png"

  rows+=("| $name | $accent | $tagline |")
  echo "built $name: shift ${shift} deg, accent $accent"
done

{
  echo "# Afterburn editions"
  echo
  echo "Generated by \`tools/make-editions.sh\`. Do not hand-edit; change the script and rerun it."
  echo
  echo "Each edition is the base theme with its warm colours hue-rotated. Neutrals (backgrounds, greys) are unchanged, and the art keeps its shapes."
  echo "Each also carries its own cool and hot heat wallpapers in \`heat-wallpapers/\`, which the \`afterburn\` command swaps in at those heat levels."
  echo
  echo "| Edition | Accent | Tagline |"
  echo "| --- | --- | --- |"
  printf '%s\n' "${rows[@]}"
} > "$STAGE/README.md"

rm -rf editions
chmod 755 "$STAGE"
mv "$STAGE" editions
trap - EXIT

echo "done: editions/ regenerated from base files"
