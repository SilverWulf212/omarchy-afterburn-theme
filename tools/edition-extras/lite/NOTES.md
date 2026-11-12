# Lite: the light edition

> **Status: integrated.** `tools/make-editions.sh` builds `.editions/lite/` from this folder (`LIGHT_EDITIONS`), the installer offers it with the other editions, and the runtime knows a light theme from a dark one (`AB_MODE` in `extras/afterburn-theme.sh`). Tests: `tests/test_lite_edition.py`.

Edition: lite (burnt orange `#c2410c` on warm paper `#f5efe4`). The idea: the dark editions are light on black, so they glow. Lite is ink on paper, so nothing glows. The same fire, printed.

## What is different from the colour editions

1. **A hand-made palette** (`colors.toml`, `mode = "light"`), not a hue rotation. The build refuses it if body text, the accent or an ANSI colour (or its bright variant) is under 4.5:1 on the paper. `muted` and `dark_foreground` are deliberately fainter (about 3:1) and `orange` is 3.75:1; the build does not check those three. ANSI red, yellow and green keep their meaning; blue is the accent and cyan and magenta are umber and rust, like the base theme's warm family.
2. **Printed stills.** The build inverts lightness in Lab and multiplies by the paper colour (`print_grade`), so black becomes blank paper and the brightest glow becomes the heaviest ink. The base's `1-horizon` becomes `7-sunprint`, because Lite brings its own `1-horizon`.
3. **Heat levels in ink.** A hot source is brighter, so it prints darker: hot means more ink, cool means less. At runtime the hot border stop is the ember deepened with black instead of a near-white that would vanish on paper.
4. **A shadow, not a glow.** Range 10, the accent at a third opacity under the focused window and a faint rust shadow (`7a3e16` at 15%) under the others, where the dark themes use black.
5. **Calm motion.** No border turn, dimming 0.03 (dimming greys paper out), embers that drift on the lock screen. The cursor keeps `embers`: cursor-fx draws its effects as ink on a light background. Because base and Lite use the same effect, the theme-set hook switches the effect again whenever the background goes from dark to light or back (cursor-fx only reads the background when it switches).
6. **Its art stays in its own folder.** A bright wallpaper in the dark themes' picker would jar, so nothing is copied to the shared `backgrounds/`.

## Files

| File | What |
| --- | --- |
| `colors.toml` | The palette. The only hand-edited colour source |
| `edition.conf` | Knobs and the three README texts |
| `files/backgrounds/1-horizon.jpg` | "Contrail": an engraved jet trail on paper, 3440x1440 |
| `files/backgrounds/8-heat-shield.jpg` | "Heat Shield": ceramic tiles with heat in the seams, 3440x1440 |
| `files/backgrounds/live-heat-shield.mp4` | The seams glow, shimmer and settle. 2560x1072, 30 fps, 360 frames, 12 s, h264 High, no audio, seamless |
| `files/heat-wallpapers/{cool,hot}/` | Cool and hot variants of the two stills above |

About 6.6 MB added here, about 19 MB in `.editions/lite/` once the six prints and their heat variants are built.

## Where the art came from

- Stills: generated with an image model (prompts below), then upscaled to 5024x2160 with an AI upscaler, fitted to 3440x1440 and nudged so the paper matches the theme background. AI-generated art may not be copyrightable; like the rest of the repo it is offered under the MIT licence.
  - Contrail: "a vast expanse of warm cream paper as the sky; one long jet contrail arcing across the right two thirds, drawn as a risograph or copperplate engraving in burnt orange ink with rust hatching; a tiny delta-wing aircraft at its head with a pin-point of afterburner flame; a faint horizon line and tick marks like a flight chart; the left third empty paper".
  - Heat Shield: "a softly lit macro of matte bone-white ceramic heat-shield tiles at a raking angle; on the right third the gaps between a few tiles glow molten orange, with a soft bloom and a rust scorch on two tiles; the left two thirds calm pale ceramic".
- Loop: an image-to-video model animated the Heat Shield still for 8 s from and back to the same frame ("locked camera, tiles perfectly still, only the molten light in the gaps breathes, faint heat shimmer"). `tools/wallpapers/loopify.py` then crossfades its end into its start and resamples it to exactly 360 periodic frames, so the loop has no jump (`tools/wallpapers/verify.py` checks the boundary).
- Heat variants of the two stills: `magick IN -modulate 101,60,100` (cool: less ink) and `magick IN -modulate 98,130,100 -gamma 0.95` (hot: more ink), JPEG quality 80.

## Rebuild

```bash
tools/make-editions.sh                 # rebuilds .editions/ (Lite included) and .editions/README.md
python3 tools/wallpapers/verify.py     # loop spec, seamless boundary, staged copies
python3 -m unittest discover -s tests  # palette contrast, runtime, built folder
```

To remake the loop from a new clip: `uv run --with numpy python tools/wallpapers/loopify.py CLIP.mp4 tools/edition-extras/lite/files/backgrounds/live-heat-shield.mp4 --fade 24`.

## Not checked on a real desktop yet

Built and tested with stubs and a throwaway home folder. Still to look at with real eyes after `omarchy theme set afterburn-lite`: the shadow strength on a bright wallpaper, the ink cursor effect in Ghostty, the lock-screen embers on a light lock screen, and `hyprctl configerrors`.

## Undo

Delete `tools/edition-extras/lite/`, drop the `lite` row from `LIGHT_EDITIONS` in `tools/make-editions.sh`, and rerun the build (the installer and the wallpaper tools read the folders, so they need no edit). An installed copy: remove `~/.config/omarchy/themes/afterburn-lite` (or run `extras/uninstall.sh`).
