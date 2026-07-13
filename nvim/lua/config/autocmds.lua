-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Neovim's bundled ftplugins for the css family (ftplugin/css.vim, sass.vim —
-- scss sources the latter) add `-` to 'iskeyword', so kebab-case identifiers
-- like `hello-there` count as one word for w / ciw / *. Restore native vim
-- word motions; runs on FileType, after the runtime ftplugin has set it.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("kebab_word_motions", { clear = true }),
  pattern = { "css", "scss", "sass", "less" },
  callback = function()
    vim.opt_local.iskeyword:remove("-")
  end,
})
