-- Afterburn Cyber: tokyonight-night, retuned to a phosphor-green CRT.
-- Keywords and functions take the acid accent, strings glow pale phosphor,
-- comments sit in a dim green so the code reads like a terminal log.
return {
  {
    "folke/tokyonight.nvim",
    name = "tokyonight",
    priority = 1000,
    opts = {
      style = "night",
      transparent = false,
      on_colors = function(c)
        c.bg = "#0c0d0b"
        c.bg_dark = "#090a08"
        c.bg_highlight = "#181917"
        c.bg_visual = "#173d14"
        c.fg = "#e8e4dc"
        c.comment = "#4f7a4a"
        c.blue = "#54f545"       -- keywords and functions: the cyber accent
        c.cyan = "#8cff8a"       -- types and builtins
        c.green = "#b8f08a"      -- strings: pale phosphor
        c.orange = "#ffdc70"     -- constants and numbers
        c.magenta = "#c678dd"
        c.red = "#ff6467"
        c.yellow = "#f3ca3e"
      end,
      on_highlights = function(hl, c)
        hl.Comment = { fg = c.comment, italic = true }
        hl.CursorLine = { bg = "#131512" }
        hl.CursorLineNr = { fg = "#54f545", bold = true }
        hl.LineNr = { fg = "#2b2a28" }
        hl.Visual = { bg = "#173d14" }
        hl.Search = { bg = "#30ff1a", fg = "#0c0d0b" }
        hl.IncSearch = { bg = "#dfffd8", fg = "#0c0d0b" }
        hl.Pmenu = { bg = "#090a08", fg = "#e8e4dc" }
        hl.PmenuSel = { bg = "#173d14", fg = "#54f545" }
        hl.FloatBorder = { fg = "#54f545", bg = "#090a08" }
      end,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "tokyonight-night",
    },
  },
}
