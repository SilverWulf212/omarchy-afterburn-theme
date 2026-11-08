# Overdrive polish: five enhancements

> **Status: integrated.** `tools/make-editions.sh` copies `files/` and `edition.conf` into `.editions/overdrive/`; the hook, the `afterburn` command and `extras/lock/` read them (see `README.md`, "Editions"). Final knobs: Overdrive: cursor neon, border medium (20 s), dim 0.04, glow 22, pulse embers (a 110 BPM beat; the pack proposed spark). Where the wiring notes below say "proposal" or "must wire", that is now done; the numbers in this file are the polish pack's originals.

Magenta edition (`afterburn-overdrive`). Everything here is an extra. Nothing in `extras/`, `tools/make-editions.sh` or `.editions/` was touched. The integrator copies `files/` into `.editions/overdrive/` and wires `edition.conf` into the runtime.

## The five

1. **Neon cursor.** `CURSOR_FX=neon`. Ghostty's neon tube cursor replaces the embers on this edition. It lights up on every keystroke and breathes between them. Only overdrive's neon-pink palette makes it read as a sign and not a spark. (Honest note: any edition can set this knob. The uniqueness is the pick, not the code.)
2. **Speed-streak live wallpaper.** `files/backgrounds/live-speed-streaks.mp4`. Magenta light streaks rush left over black, in two layers at different speeds, so it has depth. A seamless 8 s loop, 2560x1072, 30 fps, h264. No other edition has this loop, and it shows speed rather than a sun or a grid, which the base horizon already does.
3. **Hot-pink Neovim palette.** `files/neovim.lua`. Same shape as Omarchy's `neovim.lua.tpl` (aether.nvim, LazyVim), with the values filled in from the overdrive `colors.toml`. Two neon twists: the cursor is `#ff1fed` (the same pink as the window border) and the accent is the brighter pink `#ff6bda`.
4. **Spark lock-screen embers.** `EMBER_STYLE=spark`. Lock-screen embers shoot up in short fast bursts and cool quickly, like sparks off a tube on ignition. The base style drifts up slowly. The colour still follows the theme through the existing hook.
5. **Speed-tuned border and glow.** `ROTATE=medium` and `GLOW_RANGE=18`. The gradient turns every 5 s (base is 10 s) and the glow sits between the normal (14) and hot (22) ranges. It is subtle, but the spin matches the outrun speed theme. Change `ROTATE=fast` for 8 s per turn if you want it louder.

## How to see each one

- **Cursor:** after the integrator wires `CURSOR_FX`, switch to overdrive and type in Ghostty. Check with `cursor-fx status` or by looking at the cursor.
- **Wallpaper:** copy `live-speed-streaks.mp4` into `.editions/overdrive/backgrounds/`, then press Super + Ctrl + Space to cycle. It plays through OWE like the other live loops.
- **Neovim:** copy `files/neovim.lua` to `.editions/overdrive/neovim.lua` and open nvim. The cursor is hot pink, and highlighted words use the brighter accent.
- **Lock screen:** lock the screen after the integrator adds the `EMBER_STYLE` switch. Sparks should be quick bursts, not a slow drift.
- **Border:** switch to overdrive and watch the focused window. The turn is 5 s per revolution.

## What the integrator must wire

- `edition.conf`: `CURSOR_FX`, `ROTATE`, `GLOW_RANGE`, `EMBER_STYLE`. These are contract keys. None is read by `extras/` yet.
- `ROTATE` and `GLOW_RANGE`: the `afterburn` command's `normal` level should take `GLOW_RANGE` (default 14) and `ROTATE` as the per-edition default. `ROTATE` is already a user key in `afterburn.conf`, so the edition value must act as the default only, not overwrite a saved user choice.
- `CURSOR_FX`: the theme-set hook currently runs `cursor-fx embers`. It should use the edition's value when set. The neon effect's own `cursor-color` (`#ff5ed2` in `neon.conf`) is cursor-fx's default and is close to overdrive's magenta. Setting it to `#f545c9` would match the palette exactly. That is a proposal, not implemented.
- `EMBER_STYLE`: `EmberLayer.qml` has only one motion. Proposed `spark` values for the emitter (not implemented): `lifeSpan` 1100 ms with variation 300, `emitRate` 36, `velocity` magnitude 90 with variation 40, `angleVariation` 30, and the colour ramp `#fff0ff` to `#ff1fed` to `#5a0f4a`.
- `files/neovim.lua`: copy into the edition dir. Omarchy uses a theme's own file of the same name in place of the template output.
- `files/backgrounds/live-speed-streaks.mp4`: the `live-` prefix keeps it clear of the base `1`–`9` names and sorts after the stills in any locale. The integrator may need to add it to the edition's wallpaper list if that list is not built from the directory.

## Sizes and checks

| File | Size |
|---|---|
| `files/backgrounds/live-speed-streaks.mp4` | 791,519 bytes (0.79 MB) |
| `files/neovim.lua` | 1,416 bytes |
| `edition.conf` | 164 bytes |
| total added | about 0.8 MB, well under the 15 MB limit |

- The video: `ffprobe` gives h264, 2560x1072, yuv420p, 30/1 fps, 240 frames, 8.000 s. The loop is seamless. The frame-to-frame RMSE is 0.0405 for a normal step and 0.0408 for the last-to-first wrap, so the seam is not visible. Built from periodic streak tiles and a `crop` with `mod(8*n,1920)` (near layer) and `mod(4*n,960)` (far layer). Both layers loop exactly over the 240 frames.
- The Lua: `luac -p files/neovim.lua` passes.
- The conf: `bash -n edition.conf` passes.
- Not checked: the Omarchy neovim reload on a live machine. aether v3 accepts these keys because they match the template.

## Higgsfield

0 credits used. Local ffmpeg and ImageMagick made the wallpaper.

## Undo

Delete `tools/edition-extras/overdrive/` in the worktree. Once the integrator copies these files, remove `.editions/overdrive/backgrounds/live-speed-streaks.mp4` and `.editions/overdrive/neovim.lua` and rerun `tools/make-editions.sh`.
