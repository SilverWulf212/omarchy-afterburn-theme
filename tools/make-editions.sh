#!/usr/bin/env bash
# Rebuild every Afterburn colour edition from the base theme files.
#
# Writes editions/<name>/ (one complete Omarchy theme dir per edition) and
# editions/README.md, plus the base unlock.png and preview-unlock.png at the
# repo root. Everything under editions/ is derived: the script wipes that dir
# and regenerates it, so never hand-edit those files. Change this script.
#
# Method: hue-rotate, don't repaint. The Codex art keeps its shapes and
# lighting; only the warm colours move around the wheel. Neutrals (backgrounds,
# greys, muted) stay put because they have almost no saturation.
#   - images: ImageMagick -modulate works in HSL. Its hue argument is
#     100 + degrees/1.8 (so 100 = no change, 200 = +180 deg, not 360).
#   - videos: ffmpeg hue=h=<degrees> rotates chroma in YUV, so the landed hue
#     is a few degrees off the HSL target. The per-frame filter keeps the 8 s
#     loops seamless: no re-timing, same fps, same frame count.
#
# Requires: magick, ffmpeg, ffprobe, python3, fc-match, JetBrains Mono.
# Usage: tools/make-editions.sh
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

for tool in magick ffmpeg ffprobe python3 fc-match; do
  command -v "$tool" >/dev/null || { echo "make-editions: missing $tool" >&2; exit 1; }
done
for f in colors.toml hyprland.lua icons.theme preview.png backgrounds; do
  [[ -e $f ]] || { echo "make-editions: base file missing: $f" >&2; exit 1; }
done
FONT=$(fc-match -f '%{file}' 'JetBrainsMono Nerd Font:style=Bold')
[[ $FONT == *JetBrains* && -f $FONT ]] || { echo "make-editions: JetBrains Mono not installed" >&2; exit 1; }

BASE_ACCENT=$(sed -n 's/^accent = "#\([0-9a-fA-F]\{6\}\)".*/\1/p' colors.toml)
BG=$(sed -n 's/^background = "\(#[0-9a-fA-F]\{6\}\)".*/\1/p' colors.toml)
[[ -n $BASE_ACCENT && -n $BG ]] || { echo "make-editions: could not read accent/background" >&2; exit 1; }

# name | target accent hue (deg) | Yaru icon variant | tagline | lightness x | saturation x
# Lightness/saturation multipliers are optional tuning; 1.0 keeps the base feel.
EDITIONS=(
  "voltage|185|Yaru-prussiangreen-dark|Cold current on black glass.|1.00|1.00"
  "cyber|115|Yaru-olive-dark|Acid green. The grid is listening.|1.00|1.00"
  "overdrive|315|Yaru-magenta-dark|Magenta past the limiter.|1.00|1.00"
  "redline|355|Yaru-red-dark|Blood red at the limiter. Hold it.|0.78|1.00"
  "phantom|270|Yaru-purple-dark|Ultraviolet. Here, then gone.|1.00|1.00"
)

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
    -gravity center -extent 800x188 +repage PNG32:"$out"
  rm -rf "$tmp"
}

# make_preview UNLOCK OUT: 1920x1080 frame in the theme background colour.
make_preview() {
  magick -size 1920x1080 "xc:$BG" "$1" -gravity center -composite PNG24:"$2"
}

# Base theme: top-level unlock art (orange, no edition label).
make_unlock unlock.png "#$BASE_ACCENT" ""
make_preview unlock.png preview-unlock.png

rm -rf editions
mkdir -p editions

rows=("| afterburn (base) | #$BASE_ACCENT | Orange on black. The original burn. |")

for spec in "${EDITIONS[@]}"; do
  IFS='|' read -r name target icon tagline lmul smul <<<"$spec"
  dir="editions/$name"
  mkdir -p "$dir/backgrounds"

  info=$(python3 -I -c "$PY" info "$target" "$BASE_ACCENT" "$lmul" "$smul")
  read -r shift accent vgamma <<<"$info"
  im_hue=$(awk -v s="$shift" 'BEGIN { printf "%.3f", 100 + s / 1.8 }')
  label="· ${name^^} ·"

  python3 -I -c "$PY" toml colors.toml "$dir/colors.toml" "$name" "$tagline" "$shift" "$lmul" "$smul"
  python3 -I -c "$PY" hypr hyprland.lua "$dir/hyprland.lua" "$name" "$shift" "$lmul" "$smul"
  printf '%s\n' "$icon" > "$dir/icons.theme"

  im_light=$(awk -v l="$lmul" 'BEGIN { printf "%.1f", 100 * l }')
  im_sat=$(awk -v s="$smul" 'BEGIN { printf "%.1f", 100 * s }')
  magick preview.png -modulate "$im_light,$im_sat,$im_hue" "$dir/preview.png"

  for src in backgrounds/*; do
    file=$(basename "$src")
    case "$file" in
      *.jpg)
        magick "$src" -modulate "$im_light,$im_sat,$im_hue" -quality 94 "$dir/backgrounds/$file" ;;
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
  echo
  echo "| Edition | Accent | Tagline |"
  echo "| --- | --- | --- |"
  printf '%s\n' "${rows[@]}"
} > editions/README.md

echo "done: editions/ regenerated from base files"
