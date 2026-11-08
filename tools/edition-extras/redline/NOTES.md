# Redline polish: five enhancements

> **Status: integrated.** `tools/make-editions.sh` copies `files/` and `edition.conf` into `.editions/redline/`; the hook, the `afterburn` command and `extras/lock/` read them (see `README.md`, "Editions"). Final knobs: Redline: cursor katana, border off, dim 0.15, glow 8, burst embers (the pack proposed medium/18/spark; the spark spec below became the burst style). Where the wiring notes below say "proposal" or "must wire", that is now done; the numbers in this file are the polish pack's originals.

Layout: `files/` goes into the edition theme dir as-is. `edition.conf` holds the runtime knobs. Nothing here touches `extras/`, `tools/make-editions.sh`, `.editions/` or `README.md`. The integrator wires those.

## The five

1. **Katana cursor** (`CURSOR_FX=katana`). Typing in Ghostty leaves a blade-slash trail instead of rising embers. Only Redline asks for it, so the edition feels like a sword rather than a fire.
2. **Tachometer live loop** (`files/backgrounds/live-tachometer.mp4`, 2560x1072, 8 s, 30 fps, h264 High, yuv420p, 438 KB). A redline gauge: the needle sweeps idle to the limiter and back, the 7000-8000 band glows, the limiter flutters with integer harmonics, sparks lift off the arc above 7000, and a digital RPM readout sits under the hub with a LIMITER tag. It loops seamlessly. No other edition has a gauge.
3. **Heat-haze live loop** (`files/backgrounds/live-heat-haze.mp4`, same spec, 722 KB). An exhaust glow on a black horizon. Hot air rises as thin vertical columns that scroll exactly one frame height per loop, and a shimmer warps the glow with integer-harmonic waves, so the loop is seamless. The horizon line is the redline accent.
4. **Spark lock-screen embers** (`EMBER_STYLE=spark`). Grinder-style sparks instead of floating embers: see the spec under "Lock screen" below.
5. **Redline btop meters** (`files/btop.theme`). Every meter is one red ramp, brown at idle, blood red through the limiter, white-hot (`#ff8a8c`) at the top. Temperatures run past red into yellow-hot (`#ffdc70`) like a glowing exhaust. Box outlines and selection use the accent. It is built on Omarchy's btop template with Redline's colours.

Mood knobs in `edition.conf` (`ROTATE=medium`, `DIM=0.12`, `GLOW_RANGE=18`) are defaults, not enhancements. They make the border turn at the 20 s pace, dim background windows a little more, and push the glow out to 18.

## How to see it

- Live loops: `ffplay -loop 0 tools/edition-extras/redline/files/backgrounds/live-tachometer.mp4` (and `live-heat-haze.mp4`). Or copy them into a Redline theme dir and pick them from the wallpaper menu.
- Cursor: after the integrator wires `CURSOR_FX`, switch to Redline and type in Ghostty.
- btop: copy `files/btop.theme` over the Redline theme's `btop.theme` (or the same name in `~/.config/omarchy/themes/afterburn-redline/`) and run `btop`.
- Lock screen: wire `EMBER_STYLE=spark` (below), then lock with the Redline theme active.

## Integrator must wire

- **Copy the files into the Redline build.** `tools/make-editions.sh` wipes `.editions/` and only grades files from the base `backgrounds/` (it hue-rotates every file there for every edition). Do NOT add the live-* loops to the base `backgrounds/` (that would put them in all six themes). Instead, add a step to the Redline loop in `make-editions.sh`: copy `tools/edition-extras/redline/files/*` into `$dir`, keeping `backgrounds/live-*` as-is (no grade). Without this, a rebuild drops them. `btop.theme` lands in the theme dir root, which Omarchy's btop template gives way to (same-name file overrides the template).
- **Wallpaper rotation.** Super+Ctrl+Space cycles `backgrounds/`. Check that the rotation picks up the two new files. They are videos, so the heat-level swap (`afterburn level`) ignores them, as it does for the base live loops.
- **CURSOR_FX.** `extras/afterburn-theme-set-hook` hard-codes `cursor-fx embers` and checks `[[ $cur != embers ]]`. Read `CURSOR_FX` from the active edition's `edition.conf` (default `embers`), and make that check compare against the configured effect. `afterburn status` and the quiet/saver logic also name `embers`; keep those working for any effect. Valid names include `katana` (present in the local `cursor-effects` install).
- **EMBER_STYLE.** `extras/lock/EmberLayer.qml` has one motion, today's `rise`: an `Emitter` at the bottom edge, `emitRate: 12`, `lifeSpan: 9000`, `angle: -90`, `magnitude: 26`, and a `#ffc48a -> #ff5a1f -> #7a3e16` ramp. Add a `style` property (default `rise`), read it in `lock-embers.sh`, and branch the emitter and delegate on it. The rest of the layer (glow, breathing scale, input transparency) stays.
- **ROTATE, DIM, GLOW_RANGE.** `ROTATE` and `DIM` already exist as `afterburn` keys. `GLOW_RANGE` is new. `bin/afterburn` `level_vals()` sets the shadow range per heat level (cool 8, normal 14, hot 22, all via `hyprctl keyword decoration:shadow:range`). Make `normal` read `GLOW_RANGE` (default 14) and scale cool and hot by the same ratios (8/14, 22/14), so the levels keep their order. Add it to `DEFAULT` and the `set` validation (4..30).
- **TAGLINE.** Used by the edition README generator. The text already matches `.editions/README.md`, so no change is needed unless the integrator wants the menu label.

## Lock screen: EMBER_STYLE=spark (spec)

Sparks, not embers. They burst from the bottom glow in short fast arcs and cool to nothing.

- Emit from the bottom edge, in a fan spread about 40 degrees either side of straight up.
- Life 0.6-1.2 s, a hot core that fades to redline (`#ff8a8c` to accent over life), size 1.5-3 px.
- Gravity-driven: they arc up then fall, with a little random drag so bursts vary.
- Emit in short bursts (about 1 per second, 6-14 sparks each), not a steady stream. Quiet between bursts so the password field stays calm.
- Keep the existing bottom glow and its slow breathing. The spark bursts ride on top.

## Proposals (not implemented, not in the contract)

- A `FLICKER` knob for the spark bursts' rate (off, slow, fast). Not needed for v1.
- A tachometer variant for the other editions, so the gauge is not unique to Redline. Left out on purpose: the brief says each enhancement stays unique to Redline.

## Assets and checks

- `live-tachometer.mp4`: rendered from numpy and Pillow frames, piped into libx264 `-crf 20 -preset slow`. Seam check: mean frame step 0.62, last-to-first 0.26 (on a 320-wide grey downsample). A frame from t=2.0 s reads 3 123 RPM, and t=0 reads 850 RPM at idle.
- `live-heat-haze.mp4`: numpy frames, libx264 `-crf 21 -preset slow`. Seam check: mean step 0.048, last-to-first 0.154 (within codec noise on a 0-255 scale).
- `btop.theme`: all 50 keys present (no template token left), generated from Omarchy's btop template.
- `edition.conf`: parsed with `bash -n` and sourced (`CURSOR_FX=katana ROTATE=medium DIM=0.12 GLOW_RANGE=18 EMBER_STYLE=spark`).
- No Higgsfield generation. Credits used: 0.
- Total added: about 1.2 MB.

## Undo

Delete `tools/edition-extras/redline/` in this worktree (the commit can be reverted with `git revert`). Nothing outside it was changed.
