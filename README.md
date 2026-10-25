# dotfiles

One-file bootstrap for any Ubuntu/Debian box I ssh into — and macOS (via brew).

## Usage

On a fresh box:

```bash
curl -fsSL https://raw.githubusercontent.com/martin-popov/dotfiles/main/setup.sh | bash
```

It clones the repo to `~/dotfiles` (fetch over https, push over ssh).

On a fresh Mac it installs Homebrew first (one sudo password prompt); every
brew-provided tool and the Brewfile depend on it.

Or without hosting, straight over ssh:

```bash
ssh user@box 'bash -s' < setup.sh
```

Idempotent — re-run any time to update (pulls newer neovim/go/pnpm, keeps configs in sync).

Run from a terminal, it asks which components to install (Enter = everything).
Non-interactive runs (`curl | bash`, CI, ssh heredoc) install everything;
preselect instead with e.g.:

```bash
bash setup.sh base go        # or: COMPONENTS="base go" bash setup.sh
```

## Components

- **base** — zsh (default shell; vi mode, shared history, autosuggestions, syntax highlighting), tmux, git, **fzf** (fuzzy Ctrl-R / Ctrl-T), **ripgrep**, **htop**, jq, build tools
- **node** — nvm + Node LTS + standalone pnpm (no corepack — Node 25+ dropped it). pnpm only: typing `npm`/`npx` in zsh is blocked (`command npm` bypasses), npm stays installed for nvm and Mason. npm and pnpm only install package versions at least 7 days old. Global JS CLIs (sql-formatter for Zed) come from `pnpm add -g`
- **neovim** — newest release tarball at least 7 days old into `/opt`, updated on re-run; config is the repo's `nvim/` (LazyVim + catppuccin, explorer right, BG phonetic langmap, lang extras), symlinked to `~/.config/nvim` with plugins pinned via `lazy-lock.json`
- **cli** — fd, lazygit, gh (release binaries into `~/.local/bin`)
- **starship** prompt (minimal single-line: dir + git + prompt char)
- **claude** — Claude Code + settings: opus at high effort, vim editor mode, classic renderer; merges into an existing settings.json without clobbering it
- **go** — latest official tarball into `/usr/local/go`, updated on re-run (brew on macOS)
- **rust** — rustup + stable toolchain into `~/.cargo`
- **macos** — system defaults (fast key repeat, dock autohide/size/no-recents/scale minimize, finder path bar + list view, no `.DS_Store` on network/USB drives, dock with just Zen + Ghostty via dockutil); no-op on Linux
- **macapps** — `brew bundle` of the Brewfile: casks (zed, zen, raycast, karabiner-elements, obsidian, docker-desktop, …) + mac-only CLI extras (git-lfs, uv, mas, xcode-build-server); no-op on Linux

Config files (`.zshrc`, `.tmux.conf`, nvim/starship/zed links, karabiner +
ghostty links on macOS, `~/.ssh/config` if missing, git identity + defaults if unset)
are always written regardless of selection. `~/Developer` is created too, and
new Ghostty windows and zsh shells start there. Private ssh hosts belong in the
untracked `~/.ssh/config.local`.

Git defaults: `main` as the default branch, rebase on pull (with autostash),
first push sets the upstream, global ignore for `.DS_Store`. Once
`~/.ssh/martin-popov.pub` exists, commits and tags are signed with it.

`lid` (macOS) keeps the Mac awake with the lid closed while you're away:
`lid off` (default 8h, or e.g. `lid off 3h` / `lid off 90m`), `lid on`, and
plain `lid` for the current state. It reverts on its own when the time is up or
the battery drops below 20% on battery power, via a LaunchAgent that checks
every minute. A sudoers rule (installed with the `macos` component, one password
prompt) lets it run exactly `pmset -a disablesleep 0|1` without a password.

Release cooldown: GitHub release downloads (neovim, fd, lazygit, gh, nvm, pnpm) take the newest release that's at least 7 days old, and npm/pnpm get the same window (`RELEASE_AGE_DAYS` in `setup.sh`). Homebrew, go and the rustup/starship/claude installers still install their latest.

Degrades gracefully without root/sudo: system packages are skipped, starship goes to `~/.local/bin`, and if `chsh` is blocked it adds a bash→zsh handoff instead.

Existing `~/.zshrc` is backed up to `~/.zshrc.pre-setup` on first run. Machine-specific PATHs/aliases go in `~/.zshrc.local` (sourced if present, never touched by setup).

## After setup

What the script can't do on its own, roughly in order:

1. **ssh key** — copy the GitHub key into `~/.ssh/` (`chmod 600`), add a
   `Host github.com` entry with its `IdentityFile` to `~/.ssh/config.local`,
   check with `ssh -T git@github.com`, then re-run `setup.sh` so commit
   signing picks it up. Give it a passphrase (`ssh-keygen -p -f
   ~/.ssh/martin-popov`) and store that in the Keychain once with
   `ssh-add --apple-use-keychain ~/.ssh/martin-popov`; new shells load it
   into the agent, so neither ssh nor signing asks again.
2. **GitHub CLI** — `gh auth login` (GitHub.com → SSH → the existing key).
3. **Verified commits** — register the same key for signing:
   `gh auth refresh -s admin:ssh_signing_key`, then
   `gh ssh-key add ~/.ssh/martin-popov.pub --type signing`.
4. **Font Awesome** — `FONTAWESOME_NPM_AUTH_TOKEN=<token> bash setup.sh node`.
5. **Log out and back in** — key repeat and sound defaults only apply then.
6. **App permissions** — open Karabiner-Elements and Raycast once and grant
   what they ask for (Input Monitoring, Accessibility); Docker Desktop has a
   first-launch setup.

## Windows key remaps

`windows/` replaces PowerToys Keyboard Manager — same six remaps, but they
don't drop out. Clone this repo on the Windows side (the logon task needs a
local NTFS path; a `\\wsl.localhost\…` path isn't there yet when the task
fires), then from an **elevated** PowerShell:

```powershell
git clone https://github.com/martin-popov/dotfiles $env:USERPROFILE\dotfiles
& $env:USERPROFILE\dotfiles\windows\setup.ps1
```

| Key | Sends | Where |
| --- | --- | --- |
| Caps Lock | Esc | registry |
| F3 | Win+Tab (Task View) | `keys.ahk` |
| LCtrl+←/→ | Win+Ctrl+←/→ (virtual desktop) | `keys.ahk` |
| LCtrl+Q | Alt+F4 | `keys.ahk` |
| Ctrl+Tab | Alt+Tab (hold Ctrl to keep cycling) | `keys.ahk` |

Caps Lock → Esc is a `Scancode Map` value under
`HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout`: the keyboard driver
does it, so there's no process to crash and it works at the login screen.
Needs one reboot.

The rest is `keys.ahk` (AutoHotkey v2), registered as a **logon scheduled task
at highest privileges**. That's the actual fix for PowerToys dropping out — an
unelevated keyboard hook is ignored while an admin window has focus.

Turn PowerToys Keyboard Manager **off** afterwards or the two will fight.
Re-run `setup.ps1` after editing `keys.ahk` (it validates the syntax, restarts
the task, and re-verifies the registry value). Idempotent.

## Testing

Throwaway Ubuntu box with real ssh (fresh box each `docker rm -f` + re-run):

```bash
docker build -t setup-test -f test-box.Dockerfile .
docker run -d --name setup-test -p 2222:22 -v "$PWD":/home/dev/dotfiles:ro setup-test
ssh dev@localhost -p 2222   # password: dev, passwordless sudo
```

CI (`.github/workflows/test.yml`) runs a fresh install + idempotent re-run on
Ubuntu and Debian containers and a macOS runner, weekly and on push.
