# Changelog

Dates are 2026. The theme installs from `main`, so the 2.0.2 section below is the current release.

## 2.0.2 — 2026-11-12

### Fixed
- Fullscreen quiet follows the screen: leaving fullscreen on one monitor keeps quiet on while a window on another visible workspace is still fullscreen, and the watcher's start-up check looks at every visible workspace.
- The theme-set hook ignores a theme switch that was already superseded by a newer one.
- `afterburn apply` always puts the cursor effect back in line with quiet and saver, so an interrupted mode change can no longer leave it off.
- A Ghostty config named `config.ghostty` is found, and Omarchy's own state is read from where Omarchy keeps it even when `XDG_STATE_HOME` is moved.
- Battery saver leaves a mixed per-shader subtle setting alone.
- A heat wallpaper swap only replaces the theme's own wallpapers, never a personal one with the same file name.

## 2.0.1 — 2026-11-12

### Added
- **Afterburn Lite**, the first light edition: burnt-orange ink on warm paper. Its own palette (body text, the accent and the ANSI colours and their bright variants are at least 4.5:1 on the paper, checked by the build; muted and secondary text is deliberately fainter at about 3:1, and `orange` is 3.75:1), eight wallpapers, the live loop `live-heat-shield`, and boot and login art. Install it with the other editions, then `omarchy theme set afterburn-lite`.
- `afterburn doctor`: a read-only report of why effects are on or off (theme, quiet and saver flags with the reason, every power supply and whether it counts, watcher state, cursor-fx and Ghostty, Hyprland config errors).
- `afterburn status` now says why quiet or saver mode is on.
- A test suite for the code that runs on your machine (lock screen, battery detection, the light edition, the installer's edition list).
- A signature wallpaper and a 12-second live loop made for each colour edition: Resonance (Voltage), Phosphor Path (Cyber), Midnight Ribbon (Overdrive), Crimson Turbine (Redline) and Spectral Veil (Phantom). They replace recoloured copies of the orange art.
- All nineteen wallpapers in the shared `backgrounds/` folder, and `WALLPAPERS.md` with direct links to every still and loop at full resolution.
- `tools/wallpapers/selector-previews.py install`, which refreshes the theme-selector previews of an existing install.

### Fixed
- **Watcher.** It re-applies the heat level after a Hyprland config reload (while a cool or hot level is set) and after a reconnect. It skips dead Hyprland instances (leftover sockets) and talks to the live one. The user service now stops with the graphical session (`PartOf=graphical-session.target`).
- `afterburn set LAPTOP_MODE` now behaves like `afterburn laptop`. `EVENING_HOURS` must be 0-23, `LAT` -90 to 90 and `LON` -180 to 180.
- **Uninstall and re-install.** Uninstall restores the default terminal for a user who had no terminal list before install: it removes the list the installer created, only if Ghostty is its only entry. Terminal and font are left alone if you changed them since. A failed starship or `.bashrc` restore keeps the original and reports "not restored". Preview backups are kept. The watcher stops before the cursor effect is restored. Uninstall restores the cursor effect from before install; it does not detect one you picked afterwards. Re-installing restarts an already-running watcher.
- **Lock embers.** They change on the next lock after a theme switch or `afterburn set EMBER_STYLE`, with no restart or re-login (the clone now has a small loader, `EmberLayer.qml`, and each set of embers in a new `embers.<n>/` folder). An install made before 2.0.1 gets the new loader at its next recolour (a theme switch, `afterburn set EMBER_STYLE` or re-running the installer). The lock keeps the previous embers until your next login; from then on they change at each lock. Uninstall leaves no hidden `.afterburn.lock.bak.*` folder.
- **Heat levels.** On current Hyprland (a Lua config) the cool and hot levels never reached the screen: the border and glow stayed at normal while `afterburn status` reported the new level. The level is now sent in the form Hyprland accepts and shows at once.
- **Lock screen (#5).** With the login name `omarchy`, saying yes to lock-screen embers could leave you with no lock screen. The clone is now always `afterburn.lock`, and any failure re-enables the built-in lock before the script exits. Another lock screen you use is detected from its plugin manifest and left alone.
- **Desktops losing their effects (#3, #4).** A wireless mouse or keyboard battery was mistaken for a laptop battery, which switched the battery saver on. Only the machine's own battery counts now, and a saver left on by the old behaviour is cleared.
- Cursor effect on battery: it comes back after fullscreen ends, and a new edition's cursor effect or `afterburn set CURSOR_FX` applies on battery.
- The heat wallpaper now swaps in battery saver and fullscreen too; only the glow change waits.
- `afterburn laptop auto` puts the saver in line with the power source at once, and leaving fullscreen always ends quiet mode.
- The installer saves the heat source even if the config lacks the line.
- Uninstalling lock-screen embers no longer reports a false "no lock screen" or skips its cleanup.
- `afterburn locate` works in locales that use a decimal comma.
- The fail flash no longer replays when you press Enter on an empty line after a failed command, and no longer plays on the first prompt of a new shell.
- Uninstall keeps your settings as `afterburn.conf.bak` instead of deleting them, and removes only the exact line the installer added to `~/.bashrc` (it used to remove any line ending in `# afterburn`).
- `afterburn apply` writes the glow file in one step, so Hyprland can never read half a file.
- The light and dark cursor effect: switching between a dark edition and Lite re-applies the effect so it is drawn for the right background.
- README and the first-run config comment now match the code: what the installer asks about, what Super + Ctrl + Space does, which shell the fail flash needs, and the border turn times (10 s, 5 s, 2.5 s).
- Border turn speeds stay inside Hyprland 0.56's limit, so switching editions no longer raises config errors.

### Changed
- **History rewrite (12 Nov 2026).** `omarchy theme update` fails on installs from before that day. One-time fix in the README's Update section.
- The watcher and the `afterburn` command start far fewer helper processes: the theme name, power supplies and settings are read by bash itself, the weather cache needs one helper process per sample instead of four, and the battery check runs once per watcher start (`afterburn status` takes about half the time).
- The watcher ignores compositor events it does not need before doing any work (it used to re-read its config on every window focus change).
- The installer builds its list of editions from the folders that exist, so a new edition needs no code change there.
- README: install, requirements, undo and update come first, with a note on what live wallpapers cost in memory.
- On a light edition the hot heat level deepens the border colour instead of whitening it, and unfocused windows get a faint warm shadow instead of a black one. Dark editions are unchanged.
- Theme-selector previews show each edition's real default wallpaper instead of the wordmark.
- Cyber's cursor effect is `cyber` (data rain) instead of `phosphor`.

## 1.0.0 (8 November)

First release: the orange base theme, five colour editions (Voltage, Cyber, Overdrive, Redline, Phantom), the optional extras installer (Ghostty, cursor effects, glow, the subtle pack with heat levels, quiet fullscreen and battery saver, the fail flash, lock-screen embers), live wallpapers, and an uninstaller that undoes each change.
