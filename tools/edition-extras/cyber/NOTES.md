> **Wallpaper refresh (2026-11-08):** The live wallpapers described below are historical and have been retired. Current artwork, rendering, installation and rollback instructions: [docs/wallpapers/README.md](../../../docs/wallpapers/README.md). Other edition effects remain unchanged.

# Afterburn Cyber: polish pass (five enhancements)

> **Status: integrated.** `tools/make-editions.sh` copies `files/` and `edition.conf` into `.editions/cyber/`; the hook, the `afterburn` command and `extras/lock/` read them (see `README.md`, "Editions"). Final knobs: Cyber: cursor phosphor, border slow, dim 0.12, glow 17, fall embers. The tagline went back to the original generated one (quiet control, not shouting). Where the wiring notes below say "proposal" or "must wire", that is now done; the numbers in this file are the polish pack's originals.

Source: `tools/edition-extras/cyber/`. Nothing here is installed; the integrator copies `files/` into
`.editions/cyber/` and wires `edition.conf` (see "Integrator wiring").

## The five enhancements

1. **Phosphor cursor** (`edition.conf`: `CURSOR_FX=phosphor`). Ghostty's cursor-fx glow effect in place of
   the base embers, so typing leaves green phosphor sparks. Unique to cyber because the edition's
   own accent is the phosphor colour; the other editions keep their own hue.
   How to see it: switch to cyber and type in Ghostty. Not verified on this machine (cursor-fx not
   installed here); check the effect looks right in the real terminal.
2. **Matrix-rain live wallpaper** (`files/backgrounds/live-matrix-rain.mp4`). Seamless 8 s, 2560x1072, 30 fps
   h264. Acid-green columns of hex and symbol glyphs fall over a dormant glyph field, with a phosphor bloom,
   scanlines and a faint CRT vignette. Nothing else in the theme looks like this.
   How to see it: Super + Ctrl + Space to cycle to it, or set it as the wallpaper. Each column has a
   1-2 wrap per loop speed; some columns stay dark.
   Seam check: the loop's wrap step is 0.72 mean gray levels against 0.16 for ordinary frames and about 0.4
   at the glyph-flicker blocks. Frame 0 is the only I-frame, so the residual is most likely encoder drift.
   It is not visible in motion.
3. **Digital-rain lock embers** (`edition.conf`: `EMBER_STYLE=fall`). Lock-screen embers drop straight down
   at an even pace, with a slight sideways wobble, instead of rising. Each ember is a short vertical streak
   that blinks once or twice on the way down, the way terminal glyphs do.
   The style key must be read by the lock layer, which is a proposal (see below).
4. **Acid-phosphor Neovim palette** (`files/neovim.lua`). tokyonight-night, retuned: keywords and functions in
   the accent green (#54f545), strings in pale phosphor (#b8f08a), comments in a dim green (#4f7a4a), and a
   search highlight in the bright green. Uses only the palette in `colors.toml`.
5. **Phosphor btop theme** (`files/btop.theme`). Graphs climb from a dark green trace to acid green and flash
   to near-white at the top. Boxes are green, and the process list is dimmed. Same keys as Omarchy's
   `btop.theme.tpl` (50 keys, checked against the template).

## Mood knobs (edition.conf, not counted as enhancements)

- `ROTATE=medium`: 5 s per turn for the border gradient.
- `DIM=0.12`: a little stronger than the base 0.08, so background windows sink like a dimmed CRT.
- `GLOW_RANGE=18`: a slightly wider halo than base; the cyber colour is the brightest of the set.
- `TAGLINE="ACCESS GRANTED. Follow the green."`: replaces the tagline "Acid green. The grid is listening." in
  `.editions/README.md`.

## Files

| File | Size | Notes |
|---|---|---|
| `files/backgrounds/live-matrix-rain.mp4` | 3.1 MB | 240 frames, 8 s, yuv420p, High profile |
| `files/neovim.lua` | ~1.6 KB | luac -p ok |
| `files/btop.theme` | ~2.4 KB | bash -n ok; keys match the template |
| `edition.conf` | ~0.2 KB | bash -n ok |
| `make-matrix-rain.py` | ~5 KB | regenerates the mp4 (see below) |

Regenerate the wallpaper (about 90 s, uses cached numpy and Pillow from uv):

```bash
uv run --with numpy --with pillow python3 tools/edition-extras/cyber/make-matrix-rain.py \
  tools/edition-extras/cyber/files/backgrounds/live-matrix-rain.mp4
```

## Integrator wiring

- Copy `files/neovim.lua` to `.editions/cyber/neovim.lua` and `files/btop.theme` to `.editions/cyber/btop.theme`.
  Both override the templated files of the same name.
- Copy `files/backgrounds/live-matrix-rain.mp4` to `.editions/cyber/backgrounds/`. The `live-` prefix keeps it
  clear of the base wallpapers. Consider adding it to `make-editions.sh`'s wallpaper list only if you want it
  in the heat-wallpaper set (it is not a still, so it does not need a heat variant).
- `edition.conf`: the runtime reads it through the theme-set hook. Its keys are `CURSOR_FX`, `ROTATE`, `DIM`,
  `GLOW_RANGE`, `EMBER_STYLE`, `TAGLINE`. Only `ROTATE` and `DIM` are read by the current `afterburn` command,
  and `CURSOR_FX` by the hook. `GLOW_RANGE`, `EMBER_STYLE` and `TAGLINE` need wiring.

## Proposals (not implemented in extras/)

- **EMBER_STYLE=fall**: `EmberLayer.qml` should apply vertical-only motion with a small sine wobble in x,
  about 4-6 px amplitude, and a per-ember blink (opacity 1 to 0.3 two times over its life). Colour is the
  cyber accent, `#54f545`, halo at 25% alpha as now.
- **GLOW_RANGE**: maps to the Hyprland shadow `range` in `hyprland.lua` (base 14).
- **TAGLINE**: shown in `.editions/README.md` and on the edition's preview, if the integrator wants it there.

## Undo

Delete `.editions/cyber/neovim.lua`, `.editions/cyber/btop.theme` and `.editions/cyber/backgrounds/live-matrix-rain.mp4`.
Restore the cyber `edition.conf` keys to their defaults.
