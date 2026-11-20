#!/bin/bash
# Install the cursor effects into Ghostty's config directory and `cursor-fx` into ~/.local/bin.
# Anything replaced is first copied to ~/ghostty-savepoints/<time>-before-install/.
set -euo pipefail

here="$(cd -- "$(dirname -- "$0")" && pwd)"
bin_dir="$HOME/.local/bin"
backup="$HOME/ghostty-savepoints/$(date +%Y%m%d-%H%M%S)-before-install"

command -v python3 >/dev/null || { echo "python3 is needed for cursor-fx."; exit 1; }
config_file="$(python3 "$here/bin/cursor-fx" config-path)"
[ -f "$config_file" ] || { echo "No Ghostty config at $config_file. Start Ghostty once, then run this again."; exit 1; }
config_dir="$(dirname "$config_file")"

# Ghostty hands shaders y-down pixels on macOS (Metal), y-up on Linux (OpenGL).
y_down=false; [ "$(uname -s)" = Darwin ] && y_down=true
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

mkdir -p "$config_dir/shaders" "$config_dir/cursor-effects" "$bin_dir"
# Upgrading: what you changed (in the panel, with cursor-fx, or by hand) goes back into the new version.
python3 "$here/bin/cursor-fx" _keep-save "$here" "$tmp/yours.json"
for f in "$here"/shaders/*.glsl "$here"/cursor-effects/*.conf; do
  sub="$(basename "$(dirname "$f")")"
  target="$config_dir/$sub/$(basename "$f")"
  if [ "$sub" = shaders ]; then
    sed "s/^#define Y_DOWN .*/#define Y_DOWN $y_down/" "$f" > "$tmp/$(basename "$f")"
    f="$tmp/$(basename "$f")"
  fi
  if [ -f "$target" ] && ! cmp -s "$f" "$target"; then
    mkdir -p "$backup/$sub" && cp -p "$target" "$backup/$sub/"
  fi
  cp -p "$f" "$target"
done
if [ -f "$bin_dir/cursor-fx" ] && ! cmp -s "$here/bin/cursor-fx" "$bin_dir/cursor-fx"; then
  mkdir -p "$backup" && cp -p "$bin_dir/cursor-fx" "$backup/cursor-fx"
fi
cp -p "$here/bin/cursor-fx" "$bin_dir/cursor-fx"
chmod +x "$bin_dir/cursor-fx"
python3 "$bin_dir/cursor-fx" _keep-apply "$tmp/yours.json" "$here"
python3 "$bin_dir/cursor-fx" _switches  # see-through windows, light themes and panes, from your setup

pi_dir="$HOME/.pi/agent"
if [ -d "$pi_dir" ]; then
  pi_ext="$pi_dir/extensions/cursor-fx.ts"
  mkdir -p "$pi_dir/extensions"
  if [ -f "$pi_ext" ] && ! cmp -s "$here/hooks/pi-extension.ts" "$pi_ext"; then
    mkdir -p "$backup" && cp -p "$pi_ext" "$backup/"
  fi
  cp -p "$here/hooks/pi-extension.ts" "$pi_ext"
  python3 - "$pi_dir/settings.json" "$backup" <<'PYSET'
import json, os, shutil, sys
path, backup = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except ValueError:
        data = None
if not isinstance(data, dict):
    print(f"Note: {path} isn't valid JSON, so it was left alone. "
          "Turn on \"Show hardware cursor\" in pi's /settings for the effects.")
elif data.get("showHardwareCursor") is not True:
    if os.path.exists(path):
        os.makedirs(backup, exist_ok=True)
        shutil.copy2(path, backup)
    data["showHardwareCursor"] = True
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
PYSET
fi

echo "Installed cursor-fx $(python3 "$bin_dir/cursor-fx" --version | cut -d' ' -f2) into $config_dir (shaders/, cursor-effects/) and $bin_dir/cursor-fx."
[ -d "$backup" ] && echo "Replaced files were saved in $backup"
case ":$PATH:" in *":$bin_dir:"*) ;; *) echo "Note: $bin_dir is not on your PATH." ;; esac
cat <<EOF

Next:
  cursor-fx lightning        pick an effect (Ghostty reloads)
  cursor-fx edit             tune it in your browser
  hooks/claude-code-hook.json and hooks/zsh-hook.zsh   the Enter and done signals (see README)
  pi (if ~/.pi/agent exists): /reload to load the extension
EOF
