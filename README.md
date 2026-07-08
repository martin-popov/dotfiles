# dotfiles

One-file bootstrap for any Ubuntu/Debian (or Fedora/Arch/Alpine) box I ssh into.

## Usage

On a fresh box:

```bash
curl -fsSL https://raw.githubusercontent.com/martin-popov/dotfiles/main/setup.sh | bash
```

Or without hosting, straight over ssh:

```bash
ssh user@box 'bash -s' < setup.sh
```

Idempotent — re-run any time to update (pulls latest neovim, keeps configs in sync).

## What it sets up

- **zsh** as default shell — vi mode, shared history, autosuggestions, syntax highlighting
- **starship** prompt (minimal single-line: dir + git + prompt char)
- **fzf** (fuzzy Ctrl-R / Ctrl-T), **ripgrep**, **htop**, **tmux**
- **neovim** — latest release tarball into `/opt`, updated on re-run
- **nvm** + Node LTS + pnpm (corepack)
- **Claude Code**
- git identity (only if unset)

Degrades gracefully without root/sudo: system packages are skipped, starship goes to `~/.local/bin`, and if `chsh` is blocked it adds a bash→zsh handoff instead.

Existing `~/.zshrc` is backed up to `~/.zshrc.pre-setup` on first run.
