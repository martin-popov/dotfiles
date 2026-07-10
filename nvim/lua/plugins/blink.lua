return {
  "saghen/blink.cmp",
  opts = {
    sources = {
      providers = {
        -- show the menu as soon as the fastest LSP responds instead of
        -- waiting for all of them (tailwind LSP is slow and blocks the menu)
        lsp = { async = true },
      },
    },
  },
}
