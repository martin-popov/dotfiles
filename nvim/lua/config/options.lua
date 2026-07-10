-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- This install's lazyvim.json predates install_version 8, so LazyVim's
-- legacy fallback silently enables the neo-tree extra as default explorer —
-- which double-opens alongside our snacks explorer (plugins/explorer.lua)
-- when nvim is started on a directory. Pin the modern default instead.
vim.g.lazyvim_explorer = "snacks"

-- Indent with real tabs, rendered 4 wide. shiftwidth must match tabstop or
-- indent guides (snacks indent) draw multiple lines per level.
vim.opt.expandtab = false
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4

-- Soft wrap (LazyVim disables it): break at word boundaries, keep the
-- wrapped remainder aligned with the line's indent.
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true

-- Theme (catppuccin maps light -> Latte, dark -> Mocha): on macOS pull the
-- live system appearance so nvim can never drift from it; elsewhere follow
-- the `theme` command's state file. Without an explicit value nvim can
-- guess wrong inside tmux.
local mode
if vim.fn.has("mac") == 1 then
  mode = vim.fn.system("defaults read -g AppleInterfaceStyle 2>/dev/null"):find("Dark") and "dark" or "light"
else
  local theme_file = io.open(vim.fn.expand("~/.local/state/theme"))
  mode = theme_file and theme_file:read("*l") or "light"
  if theme_file then theme_file:close() end
end
vim.o.background = mode == "dark" and "dark" or "light"

-- Cyrillic (Bulgarian Phonetic) → command-key langmap for normal/visual/operator
-- modes. Lets you drive Vim with the keyboard physically in Bulgarian Phonetic
-- layout without switching to English. Insert mode is unaffected (you still type
-- Cyrillic). In this layout ; , . / ' : " stay on their ASCII keys, so f / ; , .
-- : marks and registers all work natively — only the letters plus the
-- [ ] { } ` ~ \ | keys (which carry ч ш щ ю) need remapping here.
vim.opt.langmap = table.concat({
  -- uppercase letters (A–Z, by phonetic key position)
  "АБЦДЕФГХИЙКЛМНОПЯРСТУЖВЬЪЗ;ABCDEFGHIJKLMNOPQRSTUVWXYZ",
  -- lowercase letters (a–z)
  "абцдефгхийклмнопярстужвьъз;abcdefghijklmnopqrstuvwxyz",
  -- keys carrying the remaining letters ч ш щ ю (+ shifts), pairs form;
  -- the only special char is '\' (ю's target), escaped as \\
  "ч`Ч~ш[Ш{щ]Щ}ю\\\\Ю|",
}, ",")
