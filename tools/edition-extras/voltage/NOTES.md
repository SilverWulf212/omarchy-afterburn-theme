# Voltage polish: five enhancements

> **Status: integrated.** `tools/make-editions.sh` copies `files/` and `edition.conf` into `.editions/voltage/`; the hook, the `afterburn` command and `extras/lock/` read them (see `README.md`, "Editions"). Final knobs: Voltage: cursor lightning, border fast (8 s), dim 0.06, glow 12, spark embers (the pack proposed medium/0.12/18; retuned for a restless, charged personality). Where the wiring notes below say "proposal" or "must wire", that is now done; the numbers in this file are the polish pack's originals.

Edition: voltage (electric cyan, #45e6f5). Built in worktree `polish-voltage`, branch `polish-voltage`.
Everything here lives under `tools/edition-extras/voltage/`. Nothing in `extras/`, `.editions/`, `tools/make-editions.sh` or `README.md` was touched.

## The five enhancements

1. **Lightning cursor** (`CURSOR_FX=lightning`). Typing throws a cyan bolt instead of the orange embers the other editions keep. Unique to voltage because it is the only edition that names a different cursor effect.
2. **Arc-grid live wallpaper** (`files/backgrounds/10-voltage-arcgrid.mp4`). Pylons, sagging phase wires and earth wire, with a white-hot energy packet running along each wire. Every 8 s, lightning arcs jump between conductors and crackle with sparks, and the arc light lifts the grid. It is a new scene that no other edition has, so the `10-` prefix keeps it from clashing with the base set.
3. **Spark lock-screen embers** (`EMBER_STYLE=spark`). Instead of slow rising embers, the lock screen gets short, fast crackle sparks. Unique to voltage because only this edition asks for the spark motion.
4. **Charge-meter btop** (`files/btop.theme`). CPU, memory, network and disk meters ramp deep teal, then cyan, then white-hot at high load, so a busy machine looks like a loaded line. Temperature keeps its green, yellow, red semantics. The CPU box outline is cyan. Only voltage gets this ramp.
5. **Mood tuning** (`ROTATE=medium`, `DIM=0.12`, `GLOW_RANGE=18`, `TAGLINE`). A slower border turn than the base's fast spin, slightly darker background windows so the cyan reads, and a wider halo. The tagline is "Live wire on black glass.", replacing the generated "Cold current on black glass."

## Files

| File | Size | What |
| --- | --- | --- |
| `files/backgrounds/10-voltage-arcgrid.mp4` | 649 KB | 2560x1072, 30 fps, 240 frames, 8.000 s, h264 yuv420p, seamless loop |
| `files/btop.theme` | about 3 KB | Full btop theme, all placeholders filled from voltage colours.toml |
| `edition.conf` | under 1 KB | The knobs above |
| `gen/arcgrid.py` | about 10 KB | Generator for the wallpaper, reproducible |

Total added: about 0.66 MB.

## How to see it

- Wallpaper: play it with `mpv --loop tools/edition-extras/voltage/files/backgrounds/10-voltage-arcgrid.mp4`, or wait for the rotation. The base wallpaper cycle includes it once copied into the edition.
- Cursor: set `CURSOR_FX=lightning`, then `cursor-fx lightning` in a Ghostty window, and type.
- btop: copy to `~/.config/btop/themes/` and select it in btop, or check it through the edition theme dir.

## Integrator wiring

- Copy `files/backgrounds/10-voltage-arcgrid.mp4` into `.editions/voltage/backgrounds/`. The integrator decides whether to add it to heat rotation. It is not a heat variant.
- Copy `files/btop.theme` into `.editions/voltage/`, so the theme dir ships it. Omarchy uses a theme-provided file over its own template of the same name.
- Read `edition.conf` in the hook. Today `afterburn` supports ROTATE, DIM and others, but not `GLOW_RANGE`, `EMBER_STYLE`, `CURSOR_FX` or `TAGLINE`.
  - `CURSOR_FX`: the hook currently hardcodes `cursor-fx embers` for every edition. Use this value when set, and fall back to `embers`.
  - `GLOW_RANGE`: this sets `decoration.shadow.range`, which is 14 in the base. Proposed as a new `afterburn` key with a 4 to 30 check.
  - `EMBER_STYLE`: a new lock-screen key (see below).
  - `TAGLINE`: `make-editions.sh` owns the tagline. Use this value in the generated `.editions/README.md` and in the edition colours.toml header.
- Lock screen (`EMBER_STYLE=spark`): this is a proposal, not implemented. In `EmberLayer.qml`, replace the 12 per second slow emitter with a short-lived one: about 30 per second, lifeSpan 500 to 1100 ms, angle -90 with ±35 degrees, magnitude 90 to 160 with high variation, and a lateral jitter that changes each frame. Keep the flicker timer. Each ember draws as a thin 1-by-8 px streak with a fast fade. Keep the palette from the existing `recolor` args. The spark style should stay cheap, so cap `maximumEmitted` at about 80.

## Generator

Rerun the wallpaper (numpy, Pillow and scipy come from uv, nothing installed globally):

```bash
uv run --quiet --with numpy --with pillow --with scipy python tools/edition-extras/voltage/gen/arcgrid.py OUT.mp4
```

The scene is deterministic (seeded). The moving parts are periodic in 8 s, so the loop is seamless.

## Undo

Nothing in the base or any other edition changed. Delete `tools/edition-extras/voltage/` to drop these additions. If the integrator has already copied the files into `.editions/voltage/`, rerun `tools/make-editions.sh` and remove the copied files.
