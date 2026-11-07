# ❯ afterburn

![Afterburn](preview.png)

**Orange-on-black cyber theme for [Omarchy](https://omarchy.org).** Ember-gradient window borders with a soft orange glow, animated ember cursors in Ghostty, and six 3440×1440 wallpapers.

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

Add `--yes` to skip the questions. To undo, run `~/.config/omarchy/themes/afterburn/extras/uninstall.sh`. Switching to another theme also puts your previous cursor effect back.

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
| **Omarchy hook** | Adds `~/.config/omarchy/hooks/theme-set.d/50-afterburn-extras`. It runs on **every** theme change: on Afterburn it adds the glow and sets the embers cursor, and on other themes it restores your previous cursor effect. | `uninstall.sh` |
| **State files** | `~/.local/state/afterburn/` (your previous terminal and cursor effect) and `~/.local/share/afterburn/` (the cursor-fx checkout). | `uninstall.sh` |

**Also worth knowing:**
- **GPU and battery:** while a cursor effect is on, Ghostty redraws constantly, so expect a little extra GPU use and battery drain on laptops. `cursor-fx off` turns it off.
- **Motion and flashing:** the cursor effects animate, and some flash. If you're sensitive to motion or flashing light, skip cursor-fx or run `cursor-fx subtle on`.
- **Uninstall doesn't remove Ghostty or cursor-fx.** It puts back your terminal and cursor settings, and prints the commands to remove the rest.
- **No warranty.** This is a personal hobby project, provided as is under the MIT licence. The installer changes your dotfiles, so commit or back them up first if you keep them in git.
- **Not affiliated** with Omarchy, Basecamp, Ghostty, Termix or Avarce. Their names are used here only to give credit and to say what this works with.

## Palette

| | |
|---|---|
| Accent | `#f59145` |
| Background | `#0c0d0b` |
| Foreground | `#e8e4dc` |
| Ember | `#ff5a1f` |
| Font | JetBrains Mono |

## Wallpapers

Six wallpapers at 3440×1440. Press **Super + Ctrl + Space** to rotate through them.

| | | |
|---|---|---|
| `1-horizon`: grid and ember sun | `2-prompt`: glowing prompt | `3-circuit`: circuit traces |
| `4-nozzle`: afterburner nozzle | `5-flow`: light trails over a night city | `6-ember`: macro shot of a glowing ember |

`4`–`6` are AI-generated images (made with OpenAI's image model through Codex, then upscaled). `1`–`3` are generated in code. To re-render them, or change the text on `prompt`:

```bash
uv run --with numpy --with pillow python extras/wallpaper-gen.py backgrounds
```

## Credits

- Animated cursors: **[ghostty-cursor-fx](https://github.com/Avarce/ghostty-cursor-fx)** by Avarce (MIT). Go star it.
- Palette inspired by the default dark UI of [Termix](https://github.com/LukeGus/Termix).
- Built for [Omarchy](https://omarchy.org) by DHH and contributors.

MIT © 2026 SilverWulf
