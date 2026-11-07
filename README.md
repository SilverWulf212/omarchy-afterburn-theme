# ❯ afterburn

![Afterburn](preview.png)

**Orange-on-black cyber theme for [Omarchy](https://omarchy.org).** Ember-gradient window borders with a soft orange glow, animated ember cursors in Ghostty, and nine wallpapers: six stills and three live loops.

## Install: the full stack (recommended)

```bash
omarchy theme install https://github.com/silverwulf212/omarchy-afterburn-theme && ~/.config/omarchy/themes/afterburn/extras/install.sh
```

> [!IMPORTANT]
> **This replaces your default terminal with Ghostty** and installs third-party software. See [What the full stack changes](#what-the-full-stack-changes) before you run it.

The second half shows a summary of what it will change, then asks before each step:

1. **Ghostty**: installs it and makes it your default terminal, if needed
2. **cursor-fx**: animated Ghostty cursors. Afterburn uses *embers*: typing kicks up glowing embers that rise and cool
3. **Glow**: the orange halo around the focused window
4. **Subtle pack** (optional): a slow-turning border, dimmed background windows, heat levels, quiet fullscreen, battery saver, a red prompt with a fail flash, and the `afterburn` command. See [Subtle pack](#subtle-pack)
5. **Lock screen** (optional, asked separately): embers on the lock screen. See [Lock screen](#lock-screen)
6. **Colour editions** (optional, asked separately): Voltage, Cyber, Overdrive, Redline and Phantom, the same theme in other colours. See [Editions](#editions)
7. **Boot and login screen** (optional, needs `sudo`, default No): sets Omarchy's boot splash and login screen to the current theme. See [Boot and login screen](#boot-and-login-screen)

Add `--yes` to answer yes to every question. Two exceptions: `--yes` never changes your heat source (it is `time` on a first install, so it never turns on the weather source, the only part that calls the network once running), and the boot and login screen is never changed by `--yes` because it needs `sudo`. Re-running the installer is safe: it keeps your settings, including the heat source. To undo, run `~/.config/omarchy/themes/afterburn/extras/uninstall.sh`. Switching to another theme also puts your previous cursor effect back.

## Install: theme only

```bash
omarchy theme install https://github.com/silverwulf212/omarchy-afterburn-theme
```

You get the colors, the ember-gradient borders, the wallpapers and the icons. The glow and the cursors need the extras, because Omarchy doesn't run code from a theme by itself.

## What the full stack changes

> [!WARNING]
> **The full-stack installer replaces your default terminal with Ghostty** and installs third-party code. It lists everything below and asks before each step. Read this section before you say yes.

| Change | Details | How to undo |
|---|---|---|
| **Default terminal** | Installs Ghostty with pacman (needs `sudo`) and/or makes it your default terminal. Super + Return, "open in terminal" and Omarchy's TUIs all open in Ghostty instead of your current terminal. | `uninstall.sh` restores the previous default. |
| **Font** | Sets your system font (terminals, bar, menus) to JetBrainsMono Nerd Font, Omarchy's default, if you've changed it. | `uninstall.sh` restores your previous font. |
| **Third-party code** | Clones [ghostty-cursor-fx](https://github.com/Avarce/ghostty-cursor-fx) by Avarce (MIT), pinned to commit `252df6c`, and runs its `install.sh`. Read that repo before you trust it, as with any script from the internet. | See the commands that `uninstall.sh` prints. |
| **Ghostty config** | cursor-fx writes `~/.config/ghostty/shaders/`, `~/.config/ghostty/cursor-effects/` and `~/.local/bin/cursor-fx`, and adds a `config-file = cursor-effects/…` line to `~/.config/ghostty/config`. It backs up anything it replaces to `~/ghostty-savepoints/`. | Restore from `~/ghostty-savepoints/`, or `cursor-fx off`. |
| **pi agent** (only if `~/.pi/agent` exists) | cursor-fx adds a pi extension and sets `showHardwareCursor: true` in pi's settings. | Delete `~/.pi/agent/extensions/cursor-fx.ts`. |
| **Omarchy hook** | Adds `~/.config/omarchy/hooks/theme-set.d/50-afterburn-extras`. It runs on **every** theme change: on Afterburn or one of its colour editions it adds the glow in that theme's colours, sets the embers cursor, recolours the lock-screen embers, applies the subtle pack's settings and restarts the watcher. On other themes it stops the watcher, restores your previous cursor effect and puts the lock embers back to orange. | `uninstall.sh` |
| **Subtle pack** | Links `afterburn` and `afterburn-watch` into `~/.local/bin`, writes `~/.config/afterburn/afterburn.conf`, and copies the "Afterburn colors" launcher entry to `~/.local/share/applications/`. | `uninstall.sh` removes the links, the conf file and the launcher entry. |
| **Watcher service** | Installs and starts a user systemd service, `afterburn-watch`, that handles fullscreen, battery and heat changes. | `uninstall.sh` disables and removes it. |
| **Network calls** | Only if you choose the weather heat source: `api.weather.gov` (station and observations, at most every 20 minutes) and `api.zippopotam.us` (one ZIP lookup when you enter your ZIP). No other option makes a network call. | Choose another `HEAT_SOURCE`, or run `uninstall.sh`. |
| **Shell and prompt** | Adds one guarded line to `~/.bashrc` that sources the fail flash, and sets `error_symbol` in `~/.config/starship.toml` so a failed command shows a red `❯`. Only the original `error_symbol` line is remembered, and a whole-file copy is kept in `~/.local/state/afterburn/` as a safety copy. If you have no starship.toml, the prompt is left alone. | `uninstall.sh` removes the line and puts the original `error_symbol` back, only if that line is still Afterburn's. Other edits to your starship.toml are kept. |
| **Lock screen** (asked separately) | Clones Omarchy's lock plugin with its official clone command and adds an ember layer to the clone. The clone does not get Omarchy's lock-screen updates until you uninstall. | `uninstall.sh` runs `lock-embers.sh uninstall`. |
| **Colour editions** (asked separately) | Copies each `.editions/<name>/` folder of the installed theme to `~/.config/omarchy/themes/afterburn-<name>`. A folder that is already there is **never** overwritten, and the installer records only what it created. On a re-run, a folder it created gets only the files it lacks (a newer release's wallpapers, say); nothing existing is changed. If `.editions/` is missing, the step is skipped. | `uninstall.sh` removes only the folders the installer created. If one is your active theme, it switches you to base `afterburn` first. |
| **Boot and login screen** (asked separately, default No) | Runs Omarchy's `omarchy-plymouth-set-by-theme <theme>` for the current theme, which changes the boot splash and the login screen. **Needs `sudo`.** `--yes` skips it. The installer records that it did this. | `omarchy-plymouth-reset` (needs `sudo`), which `uninstall.sh` offers to run, or prints the command if it gets no answer. |
| **State files** | `~/.local/state/afterburn/` (your previous terminal and cursor effect, the starship backup, the colours the fail flash uses, and markers for the lock screen, bashrc, editions and boot screen) and `~/.local/share/afterburn/` (the cursor-fx checkout). | `uninstall.sh` |

**Also worth knowing:**
- **GPU and battery:** while a cursor effect is on, Ghostty redraws constantly, so expect a little extra GPU use and battery drain on laptops. `cursor-fx off` turns it off.
- **Motion and flashing:** the cursor effects animate, and some flash. If you're sensitive to motion or flashing light, skip cursor-fx or run `cursor-fx subtle on`.
- **Uninstall doesn't remove Ghostty or cursor-fx.** It puts back your terminal and cursor settings, and prints the commands to remove the rest.
- **Uninstall removes only what the installer created.** That covers the files in `~/.config/afterburn/` and `~/.local/share/afterburn/` (the folders go too, but only when empty) and the edition folders it copied. An `afterburn-<name>` folder you made yourself is never touched. If an edition is your active theme, `uninstall.sh` switches you to base `afterburn` first. If it can't, it keeps that folder and tells you to switch theme and delete it.
- **The boot and login screen is not undone silently.** If you said yes to it, `uninstall.sh` asks before running `omarchy-plymouth-reset` (needs `sudo`), and prints that command if it gets no answer.
- **No warranty.** This is a personal hobby project, provided as is under the MIT licence. The installer changes your dotfiles, so commit or back them up first if you keep them in git.
- **Not affiliated** with Omarchy, Basecamp, Ghostty, Termix or Avarce. Their names are used here only to give credit and to say what this works with.

## Subtle pack

Optional, part of the full-stack install (step 4). Every setting lives in `~/.config/afterburn/afterburn.conf` as `KEY=VALUE`. `afterburn set KEY VALUE` saves a change and re-applies it. `afterburn get [KEY]` prints a setting, and `afterburn status` shows the heat level, quiet and saver state, and cursor effect.

| Feature | Config key (default) | What it does | Command |
|---|---|---|---|
| Slow-turning border | `ROTATE` (`slow`) | The ember gradient turns around the focused window: `off`, `slow` (60 s per turn), `medium` (20 s) or `fast` (8 s). | `afterburn set ROTATE medium` |
| Dimmed background windows | `DIM` (`0.08`) | Dims unfocused windows by this amount. `0` turns it off. | `afterburn set DIM 0.15` |
| Heat levels | `HEAT_WALLPAPERS` (`yes`) | `cool`, `normal` and `hot` change the border colour and glow. With `HEAT_WALLPAPERS=yes` a still wallpaper also swaps to its cool or hot version, from the active theme's own set (orange on Afterburn, the edition's colours on an edition). | `afterburn level hot` |
| Heat source: time | `HEAT_SOURCE=time`, `EVENING_HOURS` (`19-07`) | Cool inside the evening window, normal outside it. | `afterburn set EVENING_HOURS 20-06` |
| Heat source: CPU load | `HEAT_SOURCE=pressure` | Reads CPU pressure (`/proc/pressure/cpu`, 10-second average): cool below 5, hot above 35. | `afterburn set HEAT_SOURCE pressure` |
| Heat source: weather | `HEAT_SOURCE=weather`, `ZIP`, `HOT_F` (`90`), `COOL_F` (`50`) | Reads the nearest National Weather Service station (`api.weather.gov`), at most every 20 minutes. Hot at or above `HOT_F`, cool at or below `COOL_F`, cool in rain, snow or storms, and one level cooler at night. US only. | `afterburn locate 10001`, then `afterburn set HEAT_SOURCE weather` |
| Quiet fullscreen | `FULLSCREEN_QUIET` (`yes`) | In fullscreen: no shadow, no spin, cursor effect off. Restored when you leave fullscreen. | `afterburn quiet on` / `off` |
| Laptop saver | `LAPTOP_MODE` (`auto`) | On battery: no shadow, no spin, and a subtle cursor effect. `auto` follows the power source. `on` and `off` force it. | `afterburn laptop auto` |
| Red prompt and fail flash | `FAIL_FX` (`random`) | A failed command gets a red `❯` in Starship and a short flash: `burn`, `cascade` or `dissolve`. `random` picks one. Interrupted commands (Ctrl-C, Ctrl-Z) don't flash. Set `NO_MOTION` in your shell to turn the flash off. | `afterburn set FAIL_FX off` |
| Colours | none | Afterburn's named colours. In a terminal, `afterburn colors` shows swatches and copies the one you pick. The "Afterburn colors" launcher entry opens the menu and copies the hex. | `afterburn colors` |

Other commands: `afterburn apply` (rebuilds the glow from the conf and reloads Hyprland), `afterburn level cool|normal|hot`, `afterburn saver on|off`. The watcher runs as a user service. Check it with `systemctl --user status afterburn-watch`.

## Lock screen

The installer asks this separately (step 5). It runs `extras/lock/lock-embers.sh install`, which clones Omarchy's built-in lock plugin with its official clone command and adds an ember layer to the clone. Omarchy's own lock screen is not edited.

The embers follow the active theme: orange on Afterburn, and the edition's own colours on Voltage, Cyber, Overdrive, Redline and Phantom. The theme-set hook rewrites the colours in the clone's copy of the ember layer on each theme change, and puts the orange back on any other theme.

Because it is a clone, the lock screen **stops getting Omarchy's lock-screen updates** until you uninstall. To remove it, run `uninstall.sh` (or `extras/lock/lock-embers.sh uninstall`).

## Editions

The same theme in five more colours. Each edition is a complete Omarchy theme with its own colours, wallpapers, icons and boot image. They live in the hidden folder `.editions/` of the repo (Omarchy skips dot folders when it stages a theme, so switching to the base theme does not copy them). See [`.editions/README.md`](.editions/README.md) for previews and the details.

| Edition | Theme name | Colour |
|---|---|---|
| Voltage | `afterburn-voltage` | cyan |
| Cyber | `afterburn-cyber` | green |
| Overdrive | `afterburn-overdrive` | magenta |
| Redline | `afterburn-redline` | red |
| Phantom | `afterburn-phantom` | violet |

The installer's edition question (step 6) copies them next to the base theme. Switch with the Omarchy theme menu or `omarchy theme set afterburn-voltage`. `omarchy theme install` alone installs only the base theme: the editions sit in its hidden `.editions/` folder as plain theme directories, so without the installer, copy one to `~/.config/omarchy/themes/afterburn-<name>` yourself (you get its colours, wallpapers and icons, but not the glow and the other extras).

With the extras installed, **every** edition gets the same treatment as base Afterburn, in its own colours: the glow and the slow-turning border, the heat levels, the red-prompt fail flash, `afterburn colors`, the lock-screen embers and the watcher. The colours are read from the active theme's `colors.toml` on every theme change (the cool level's middle stop comes from the `afterburn_cool` key each edition carries). The heat wallpapers follow the edition too: every edition has its own cool and hot set in `heat-wallpapers/`, so `afterburn level hot` swaps a still for its hot version in the edition's colours. A copy of an edition without that folder keeps its wallpaper.

## Boot and login screen

Optional, step 7 of the installer, off unless you say yes (`--yes` never does it). It runs `omarchy-plymouth-set-by-theme <theme>` for the current theme, which uses that theme's `unlock.png`, background and foreground colours for Omarchy's boot splash and login screen. It needs `sudo` and changes system files outside your home folder, so the installer says so before it asks. To undo it, run `omarchy-plymouth-reset` (also needs `sudo`). `uninstall.sh` offers to run that for you if the installer did the change, and prints the exact command if it gets no answer.

## Palette

The base theme's palette. Editions swap the orange for their own colour.

| | |
|---|---|
| Accent | `#f59145` |
| Background | `#0c0d0b` |
| Foreground | `#e8e4dc` |
| Ember | `#ff5a1f` |
| Font | JetBrains Mono |

## Wallpapers

Six still wallpapers at 3440×1440, plus three live loops. Press **Super + Ctrl + Space** to rotate through them.

| | | |
|---|---|---|
| `1-horizon`: grid and ember sun | `2-prompt`: glowing prompt | `3-circuit`: circuit traces |
| `4-nozzle`: afterburner nozzle | `5-flow`: light trails over a night city | `6-ember`: macro shot of a glowing ember |
| `7-nozzle-live` (live) | `8-ember-live` (live) | `9-horizon-live` (live) |

**Live loops** (`backgrounds/7-nozzle-live.mp4`, `8-ember-live.mp4`, `9-horizon-live.mp4`) play natively through Omarchy's OWE wallpaper engine, so they need no install step. They pause in fullscreen and follow OWE's battery policy. Heat levels change the borders and glow but keep the live loops as they are.

**Heat variants:** 12 in total, six cool and six hot, in `extras/heat-wallpapers/cool/` and `extras/heat-wallpapers/hot/`. Each has the same file name as its still. With `HEAT_WALLPAPERS=yes`, `afterburn level cool` or `hot` swaps a still wallpaper for its variant, and `afterburn level normal` swaps it back. Each colour edition has its own 12 in `.editions/<name>/heat-wallpapers/`, made from these by `tools/make-editions.sh`.

`4`–`6` are AI-generated images (made with OpenAI's image model through Codex, then upscaled). `1`–`3` are generated in code. To re-render them, or change the text on `prompt`:

```bash
uv run --with numpy --with pillow python extras/wallpaper-gen.py backgrounds
```

## Credits

- Animated cursors: **[ghostty-cursor-fx](https://github.com/Avarce/ghostty-cursor-fx)** by Avarce (MIT). Go star it.
- Palette inspired by the default dark UI of [Termix](https://github.com/LukeGus/Termix).
- Built for [Omarchy](https://omarchy.org) by DHH and contributors.

MIT © 2026 SilverWulf
