-- Afterburn: three-stop ember gradient on the focused window, plus a soft orange glow.
local active_border_color = { colors = { "rgba(f59145ee)", "rgba(ff5a1fee)", "rgba(ffc48aee)" }, angle = 45 }
local inactive_border_color = "rgba(2b2a28aa)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },

  decoration = {
    shadow = {
      enabled = true,
      range = 14,
      render_power = 3,
      color = "rgba(f5914555)",
      color_inactive = "rgba(00000066)",
    },
  },
})

-- TUIs use their own app IDs. Explicitly opt terminals into the theme glow,
-- including after Omarchy's floating-workspace rules disable shadows globally.
o.window(
  "(Alacritty|kitty|com.mitchellh.ghostty|foot|org\\.codeberg\\.dnkl\\.foot|wezterm|org\\.omarchy\\..*|TUI\\..*)",
  { no_shadow = false }
)
