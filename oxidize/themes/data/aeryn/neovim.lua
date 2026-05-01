return {
  {
    "neanias/everforest-nvim",
    priority = 1000,
    opts = {
      style = "medium",
      background = "dark",
      transparent_background_level = 0,
      italics = true,
      disable_italic_comments = false,
      ui_contrast = "low",
      colours_override = function(palette)
        palette.bg_dim = "#151A16"
        palette.bg0 = "#151A16"
        palette.bg1 = "#1E2520"
        palette.bg2 = "#273028"
        palette.bg3 = "#323A31"
        palette.bg4 = "#3E473A"
        palette.bg5 = "#4B5544"
        palette.fg = "#CFCAB2"
        palette.red = "#C07A4F"
        palette.orange = "#F0BB78"
        palette.yellow = "#E6DDC7"
        palette.green = "#A4B465"
        palette.aqua = "#7FA696"
        palette.blue = "#7F9168"
        palette.purple = "#8F947F"
        palette.grey0 = "#626F47"
        palette.grey1 = "#7E7A66"
        palette.grey2 = "#8F947F"
      end,
      on_highlights = function(hl, palette)
        hl.Normal = { fg = "#CFCAB2", bg = "#151A16" }
        hl.NormalFloat = { fg = "#CFCAB2", bg = "#1E2520" }
        hl.FloatBorder = { fg = "#626F47", bg = "#1E2520" }
        hl.CursorLine = { bg = "#1E2520" }
        hl.Visual = { fg = "#151A16", bg = "#A4B465" }
        hl.Search = { fg = "#151A16", bg = "#F0BB78" }
        hl.IncSearch = { fg = "#151A16", bg = "#F5ECD5" }
        hl.Comment = { fg = "#7E7A66", italic = true }
        hl.String = { fg = "#A4B465" }
        hl.Number = { fg = "#F0BB78" }
        hl.Boolean = { fg = "#F0BB78" }
        hl.Function = { fg = "#7F9168" }
        hl.Keyword = { fg = "#8F947F" }
        hl.Type = { fg = "#E6DDC7" }
        hl.Identifier = { fg = "#CFCAB2" }
        hl.Operator = { fg = "#7FA696" }
        hl.DiagnosticError = { fg = "#C07A4F" }
        hl.DiagnosticWarn = { fg = "#F0BB78" }
        hl.DiagnosticInfo = { fg = "#7FA696" }
        hl.DiagnosticHint = { fg = "#A4B465" }
        hl.GitSignsAdd = { fg = "#A4B465" }
        hl.GitSignsChange = { fg = "#F0BB78" }
        hl.GitSignsDelete = { fg = "#C07A4F" }
      end,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "everforest",
      background = "medium",
    },
  },
}
