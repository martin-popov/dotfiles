# dotfiles

One-file bootstrap for any Ubuntu/Debian box I ssh into — and macOS (via brew).

## Usage

On a fresh box:

```bash
curl -fsSL https://raw.githubusercontent.com/martin-popov/dotfiles/main/setup.sh | bash
```

Or without hosting, straight over ssh:

```bash
ssh user@box 'bash -s' < setup.sh
```

Idempotent — re-run any time to update (pulls latest neovim/go, keeps configs in sync).

Run from a terminal, it asks which components to install (Enter = everything).
Non-interactive runs (`curl | bash`, CI, ssh heredoc) install everything;
preselect instead with e.g.:

```bash
COMPONENTS="base go" bash setup.sh
```

## Components

- **base** — zsh (default shell; vi mode, shared history, autosuggestions, syntax highlighting), tmux, git, **fzf** (fuzzy Ctrl-R / Ctrl-T), **ripgrep**, **htop**, jq, build tools
- **node** — nvm + Node LTS + pnpm (corepack)
- **neovim** — latest release tarball into `/opt`, updated on re-run; config is the repo's `nvim/` (LazyVim + catppuccin, explorer right, BG phonetic langmap, lang extras), symlinked to `~/.config/nvim` with plugins pinned via `lazy-lock.json`
- **cli** — fd, lazygit, gh (release binaries into `~/.local/bin`)
- **starship** prompt (minimal single-line: dir + git + prompt char)
- **claude** — Claude Code + settings: vim editor mode, plugins (superpowers, context7, playwright, github, frontend-design, TS/Go/Rust LSPs, ponytail) — auto-installed by Claude Code on first run; merges into an existing settings.json without clobbering it
- **go** — latest official tarball into `/usr/local/go`, updated on re-run (brew on macOS)
- **rust** — rustup + stable toolchain into `~/.cargo`
- **macos** — system defaults (fast key repeat, dock autohide/size/no-recents, finder path bar + list view, dock contents via dockutil); no-op on Linux
- **macapps** — `brew bundle` of the Brewfile: casks (zed, zen, raycast, karabiner-elements, obsidian, docker-desktop, …) + mac-only CLI extras (git-lfs, uv, mas, xcode-build-server); no-op on Linux

Config files (`.zshrc`, `.tmux.conf`, nvim/starship/zed links, karabiner +
ghostty links on macOS, `~/.ssh/config` if missing, git identity if unset)
are always written regardless of selection. Private ssh hosts belong in the
untracked `~/.ssh/config.local`.

Degrades gracefully without root/sudo: system packages are skipped, starship goes to `~/.local/bin`, and if `chsh` is blocked it adds a bash→zsh handoff instead.

Existing `~/.zshrc` is backed up to `~/.zshrc.pre-setup` on first run. Machine-specific PATHs/aliases go in `~/.zshrc.local` (sourced if present, never touched by setup).

## Testing

Throwaway Ubuntu box with real ssh (fresh box each `docker rm -f` + re-run):

```bash
docker build -t setup-test -f test-box.Dockerfile .
docker run -d --name setup-test -p 2222:22 -v "$PWD":/home/dev/dotfiles:ro setup-test
ssh dev@localhost -p 2222   # password: dev, passwordless sudo
```

CI (`.github/workflows/test.yml`) runs a fresh install + idempotent re-run on
Ubuntu and Debian containers weekly and on push.
