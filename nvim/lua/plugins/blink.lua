return {
  "saghen/blink.cmp",
  opts = {
    keymap = {
      -- Tab accepts the highlighted completion alongside Enter (preset
      -- "enter" stays). Defining <Tab> here suppresses LazyVim's default
      -- Tab chain, so re-add it after select_and_accept: snippet jump,
      -- sidekick next-edit, AI ghost text, then a literal Tab.
      ["<Tab>"] = {
        "select_and_accept",
        function()
          return LazyVim.cmp.map({ "snippet_forward", "ai_nes", "ai_accept" })()
        end,
        "fallback",
      },
    },
    sources = {
      providers = {
        -- show the menu as soon as the fastest LSP responds instead of
        -- waiting for all of them (tailwind LSP is slow and blocks the menu)
        lsp = { async = true },
      },
    },
  },
}
