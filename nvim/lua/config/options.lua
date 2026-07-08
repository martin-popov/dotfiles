-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

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
