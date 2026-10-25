# macOS apps + mac-only CLI extras (the `macapps` component).
# CLI basics (git, gh, ripgrep, fzf, neovim, lazygit, starship, go…) are
# handled by their own setup.sh components — don't duplicate them here.
# adopt: take ownership of identical apps already in /Applications instead
# of failing (machines that predate this Brewfile)
cask_args adopt: true
brew "git-lfs"
brew "tree"
brew "sql-formatter"
brew "uv"
# sw: make lint needs shellcheck; secrets/ are sops+age (go tools are pinned via go run)
brew "shellcheck"
brew "sops"
brew "age"
# swift/xcode
brew "xcode-build-server"
brew "mas"

# apps
cask "zed"
cask "docker-desktop"
cask "tableplus"
cask "claude-code"
cask "affinity"
cask "zen"
cask "raycast"
cask "karabiner-elements"
cask "obsidian"
cask "spotify"
cask "stremio"
cask "hiddenbar"
cask "font-jetbrains-mono-nerd-font"
cask "font-jetbrains-mono"
