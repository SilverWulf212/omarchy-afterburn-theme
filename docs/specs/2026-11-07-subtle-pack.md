# Afterburn subtle pack: spec (2026-11-07)

Repo: this worktree (`~/src/afterburn-work/subtle-pack`, branch `subtle-pack`). Theme installs to `~/.config/omarchy/themes/afterburn/`, so runtime paths use `$THEME_DIR=~/.config/omarchy/themes/afterburn`. Shell: bash, `set -u`, no deps beyond Omarchy defaults (hyprctl, jq, curl, notify-send, wl-copy, walker, upower if present). Match style of `extras/install.sh` (orange `o`/`ok`/`skip` helpers).

**Hard rule for builders:** never touch the live system. No `hyprctl`, `systemctl`, `omarchy`, `cursor-fx` calls, no writes outside the worktree. Test only with `bash -n` and a fake `HOME` under `$CLAUDE_JOB_DIR/tmp` with stub commands on `PATH`.

## Config
`${XDG_CONFIG_HOME:-$HOME/.config}/afterburn/afterburn.conf`, shell `KEY=VALUE`, sourced. Defaults (written by `afterburn` if missing):
```
ROTATE=slow          # off|slow|medium|fast  (border gradient turn: 60s|20s|8s per turn)
DIM=0.08             # dim_inactive strength, 0 = off
HEAT_SOURCE=time     # off|time|pressure|weather
EVENING_HOURS=19-07  # time source: cool inside this window
ZIP=                 # weather source (US only); LAT/LON filled by `afterburn locate`
LAT=
LON=
HOT_F=90
COOL_F=50
HEAT_WALLPAPERS=yes  # swap wallpaper to the level's variant
FULLSCREEN_QUIET=yes
LAPTOP_MODE=auto     # auto|on|off
FAIL_FX=random       # random|burn|cascade|dissolve|off
```
State dir: `${XDG_STATE_HOME:-$HOME/.local/state}/afterburn/` (files: `level`, `quiet`, `saver`, `prev-cursor-fx` (the effect from before Afterburn took over, kept by the hook), `cursor-pre-quiet` (the effect to put back when quiet and saver end), `weather.json` cache).

## Heat levels (cool / normal / hot)
| level | active border | shadow range | shadow color | wallpaper |
|---|---|---|---|---|
| cool | `rgba(7a3e16ee) rgba(e8703aee) rgba(ff5a1fcc) 45deg` | 8 | `rgba(e8703a33)` | `extras/heat-wallpapers/cool/<same name>.jpg` |
| normal | `rgba(f59145ee) rgba(ff5a1fee) rgba(ffc48aee) 45deg` | 14 | `rgba(f5914555)` | `backgrounds/<name>.jpg` |
| hot | `rgba(ffc48aff) rgba(fff1e0ff) rgba(ff5a1fff) 45deg` | 22 | `rgba(ffb37a77)` | `extras/heat-wallpapers/hot/<name>.jpg` |

The table is the base theme (orange). Each colour edition carries its own `afterburn_cool` colour (the cool border's middle stop) and its own set at `.editions/<name>/heat-wallpapers/{cool,hot}/<same name>.jpg`, installed to `~/.config/omarchy/themes/afterburn-<name>/heat-wallpapers/`. `.editions/` is a hidden folder so Omarchy's theme staging (a `*` glob) does not copy it on every switch to the base theme.

Sources: **time**: inside EVENING_HOURS = cool else normal. **pressure**: `/proc/pressure/cpu` `some avg10` <5 cool, 5–35 normal, >35 hot; change only after 2 equal readings in a row. **weather**: NWS. `GET https://api.weather.gov/points/$LAT,$LON` → `properties.observationStations` (first station) and `forecastHourly`; latest obs `/stations/<id>/observations/latest` → `temperature.value` (°C, convert), `textDescription`. Header `User-Agent: afterburn-theme (github.com/silverwulf212/omarchy-afterburn-theme)`. Fetch at most every 20 min, cache to `weather.json`; on network failure keep last level. Map: temp ≥ HOT_F hot, ≤ COOL_F cool, else normal; rain/drizzle/showers/snow/thunder in description → cool; hourly forecast period 0 `isDaytime=false` → one level cooler.

## Components and owners

### A. `extras/bin/afterburn` (CLI) + `extras/afterburn-theme-set-hook` (update)
Subcommands:
- `apply`: write `$THEME_DIR/../../current/theme/hyprland.lua` equivalent: generate from the root `hyprland.lua` content plus ROTATE (`animations` → `borderangle` loop with speed; off = no loop) and DIM (`decoration.dim_inactive`/`dim_strength`) in the same `hl.config` Lua style as the root `hyprland.lua`, then `hyprctl reload`, then re-apply current level.
- `set KEY VALUE` (validate against allowed values, rewrite conf line, then `apply`), `get [KEY]`, `status` (pretty print config + level + quiet + saver).
- `level cool|normal|hot`: live via `hyprctl keyword general:col.active_border ...`, `decoration:shadow:range`, `decoration:shadow:color`; if HEAT_WALLPAPERS=yes swap wallpaper to the variant matching the current wallpaper's basename (find how Omarchy sets/reads the bg: inspect `/usr/bin/omarchy-theme-bg-set` and `omarchy-theme-bg-current`). Write state `level`. Skip visual changes while `quiet` or `saver` is on (still record level).
- `quiet on|off`: on = shadow off, borderangle loop off, `cursor-fx off` (save current effect to `cursor-pre-quiet` first); off = restore all and re-apply level. (An earlier draft used `prev-cursor-fx` for this too, which made the watcher's start-up `quiet off` undo the embers the hook had just set.)
- `saver on|off`: on = shadow off, rotation off, `cursor-fx subtle on`; off = restore. `laptop auto|on|off` sets LAPTOP_MODE then `on`→`saver on`, `off`→`saver off`, `auto`→ decided by watcher.
- `colors`: palette from `colors.toml` + names (accent, ember #ff5a1f, flare #ffc48a, etc.). If stdout is a tty and `--menu` not given: print each as truecolor swatch + name + hex, then prompt to pick a number and copy. Else (`--menu`, or launched from desktop entry): pipe `"name  #hex"` lines to Omarchy's dmenu-style launcher (inspect how `omarchy menu` scripts call walker with `--dmenu`), copy pick with `wl-copy`, `notify-send "Copied ember #ff5a1f"`. Also ship `extras/afterburn-colors.desktop` (Name=Afterburn colors, Exec=afterburn colors --menu).
- `locate ZIP`: `curl https://api.zippopotam.us/us/$ZIP` → lat/lon (4 decimals) into conf, plus ZIP.
- Hook: keep existing behaviour; on afterburn also run `afterburn apply` and `systemctl --user restart afterburn-watch.service` (ignore failures); on other themes `systemctl --user stop afterburn-watch.service` and `afterburn quiet off` is NOT needed (restore cursor-fx as today).

### B. `extras/bin/afterburn-watch` + `extras/afterburn-watch.service`
Long-running. Every loop, if current theme (`${XDG_STATE_HOME}/omarchy/current/theme.name` or how the existing hook detects it; inspect) isn't afterburn: sleep 60 and continue. Three concerns, each in a background subshell, killed together on exit (trap):
1. Fullscreen: read `socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` (fall back to `nc -U` if no socat) lines `fullscreen>>1`/`fullscreen>>0` → `afterburn quiet on|off` when FULLSCREEN_QUIET=yes.
2. Power (LAPTOP_MODE=auto only): `upower --monitor` if present, else poll `/sys/class/power_supply/*/online` (type Mains) every 30s; on battery → `afterburn saver on`, on AC → `saver off`. Act only on change. No battery present → do nothing.
3. Heat: every 60s compute level per HEAT_SOURCE (see above); call `afterburn level X` only on change. Re-source config each tick.
Unit: `[Service] ExecStart=%h/.local/bin/afterburn-watch`, `Restart=on-failure`, `WantedBy=graphical-session.target`.

### C. `extras/afterburn-fail.bash` (sourced from `~/.bashrc`)
Prepends to `PROMPT_COMMAND` a function capturing `$?`. If nonzero, not 130/148 (Ctrl-C, Ctrl-Z), interactive tty, `FAIL_FX` (read from conf, cached per shell, re-read if conf mtime changes) not `off`, and `NO_MOTION` unset: play one effect on a line reading `✗ <last command, max 40 chars>  exit <N>`, total ≤ 450 ms, pure bash + ANSI truecolor, then erase the line so the prompt draws clean. Effects: **burn**: left to right with jitter, each char steps flare #ffc48a → ember #ff5a1f → rust #7a3e16 → ash #5e5b55 → gone. **cascade**: chars drop out in staggered order through `▀ ▄ _ .` glyphs. **dissolve**: random order, each char → `▓ ▒ ░` → gone. `random` picks one each failure. Must not change `$?` seen by the rest of PROMPT_COMMAND / Starship (re-set it before returning). Starship: installer changes `error_symbol` to `"[❯](bold red)"` (see D).

### D. Installer, uninstaller, README, demo (after A–C)
`install.sh`: new step "Add the subtle pack?" lists: slow-turning border, dim background windows, heat levels, fullscreen quiet, laptop mode, red ❯ + fail effect, `afterburn colors`. If yes: symlink `extras/bin/*` into `~/.local/bin`, write default conf, ask heat source (time / system load / weather / off; weather asks ZIP and runs `afterburn locate`), install + enable the user unit, back up `~/.config/starship.toml` to state dir and set error_symbol, append guarded line to `~/.bashrc` (`[[ -f ~/.config/omarchy/themes/afterburn/extras/afterburn-fail.bash ]] && source ...  # afterburn`), copy desktop entry to `~/.local/share/applications/`. `uninstall.sh` reverses each. README: new section + rows in "What the full stack changes" (network: NWS + zippopotam only in weather mode; user service; bashrc line; starship edit).
