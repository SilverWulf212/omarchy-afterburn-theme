-- Afterburn Overdrive: Neovim palette. Same shape as Omarchy's neovim.lua.tpl, with the
-- values resolved from the overdrive colors.toml, plus two neon twists: a hot-pink cursor
-- (the same #ff1fed as the window border) and a brighter pink accent for highlights.
return {
  {
    "omacom/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = {
      colors = {
        bg = "#0c0d0b",
        dark_bg = "#090a08",
        darker_bg = "#060705",
        lighter_bg = "#181917",

        fg = "#e8e4dc",
        dark_fg = "#5e5b55",
        light_fg = "#a4a4a4",
        bright_fg = "#fafafa",
        muted = "#2b2a28",

        red = "#ff6467",
        yellow = "#f3ca3e",
        orange = "#ff1ac9",
        green = "#8ee07a",
        cyan = "#d9a5c3",
        blue = "#f545c9",
        magenta = "#c678dd",
        brown = "#7a1664",

        bright_red = "#ff8a8c",
        bright_yellow = "#ffdc70",
        bright_green = "#b8f08a",
        bright_cyan = "#f2cfe3",
        bright_blue = "#ff6bda",
        bright_magenta = "#dd9aee",

        accent = "#ff6bda",
        cursor = "#ff1fed",
        foreground = "#e8e4dc",
        background = "#0c0d0b",
        selection = "#3d1432",
        selection_foreground = "#fafafa",
        selection_background = "#3d1432",
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aether",
    },
  },
}
