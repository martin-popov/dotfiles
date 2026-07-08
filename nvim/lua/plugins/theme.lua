return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      -- light = Latte, dark = Mocha, following vim.o.background
      background = {
        light = "latte",
        dark = "mocha",
      },
    },
  },

  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },
}
