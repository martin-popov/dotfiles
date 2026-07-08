#!/usr/bin/env bash
# ============================================================
# Portable dev environment bootstrap — Martin Popov
# Usage:  bash setup.sh
# Idempotent: safe to re-run.
# ============================================================
set -euo pipefail

GIT_NAME="Martin Popov"
GIT_EMAIL="me@martinpopov.com"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

# --- sudo shim (some boxes are root, some have no sudo) ------
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else
    warn "not root and no sudo — skipping system package installs"
    SUDO="skip"
  fi
fi

# --- system packages -----------------------------------------
PKGS="zsh tmux git curl wget unzip ripgrep fzf htop jq"
if [ "$SUDO" != "skip" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    log "installing packages (apt): $PKGS + build-essential"
    $SUDO apt-get update -qq
    # shellcheck disable=SC2086
    $SUDO apt-get install -y -qq $PKGS build-essential
  elif command -v dnf >/dev/null 2>&1; then
    log "installing packages (dnf): $PKGS + gcc make"
    $SUDO dnf install -y -q $PKGS gcc make
  elif command -v pacman >/dev/null 2>&1; then
    log "installing packages (pacman): $PKGS + base-devel"
    $SUDO pacman -S --noconfirm --needed $PKGS base-devel
  elif command -v apk >/dev/null 2>&1; then
    log "installing packages (apk): $PKGS + build-base"
    $SUDO apk add --no-cache $PKGS build-base shadow
  else
    warn "no known package manager — install manually: $PKGS"
  fi
fi

mkdir -p "$HOME/.local/bin" "$HOME/.config" "$HOME/.zsh"

# --- neovim (latest tarball, updates in place; apt's is old) --
ARCH="$(uname -m)"
if [ "$ARCH" = "x86_64" ] && [ "$SUDO" != "skip" ]; then
  NVIM_LATEST="$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest \
    | grep -m1 '"tag_name"' | sed -E 's/.*"(v[^"]+)".*/\1/' || true)"
  NVIM_HAVE=""
  command -v nvim >/dev/null 2>&1 && NVIM_HAVE="v$(nvim --version | head -1 | sed 's/^NVIM v//')"
  if [ -n "$NVIM_LATEST" ] && [ "$NVIM_HAVE" != "$NVIM_LATEST" ]; then
    log "installing neovim $NVIM_LATEST (had: ${NVIM_HAVE:-none})"
    curl -fsSL -o /tmp/nvim.tar.gz \
      https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
    $SUDO rm -rf /opt/nvim-linux-x86_64
    $SUDO tar -C /opt -xzf /tmp/nvim.tar.gz
    $SUDO ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
    rm -f /tmp/nvim.tar.gz
  else
    log "neovim up to date: ${NVIM_HAVE:-unknown}"
  fi
elif ! command -v nvim >/dev/null 2>&1; then
  warn "skipping neovim tarball (arch=$ARCH, sudo=$SUDO) — falling back to package manager version if present"
fi

# --- fd + lazygit (binaries -> ~/.local/bin, no sudo needed) --
gh_latest_tag() { # repo -> tag_name (e.g. v1.2.3)
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | grep -m1 '"tag_name"' | sed -E 's/.*"(v?[^"]+)".*/\1/'
}
if ! command -v fd >/dev/null 2>&1 && [ "$(uname -m)" = "x86_64" ]; then
  FD_V="$(gh_latest_tag sharkdp/fd)" && [ -n "$FD_V" ] && {
    log "installing fd $FD_V"
    curl -fsSL "https://github.com/sharkdp/fd/releases/download/${FD_V}/fd-${FD_V}-x86_64-unknown-linux-gnu.tar.gz" \
      | tar -xz -C /tmp
    mv "/tmp/fd-${FD_V}-x86_64-unknown-linux-gnu/fd" "$HOME/.local/bin/"
    rm -rf "/tmp/fd-${FD_V}-x86_64-unknown-linux-gnu"
  } || warn "fd install failed"
fi
if ! command -v lazygit >/dev/null 2>&1 && [ "$(uname -m)" = "x86_64" ]; then
  LG_V="$(gh_latest_tag jesseduffield/lazygit)" && [ -n "$LG_V" ] && {
    log "installing lazygit $LG_V"
    curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/${LG_V}/lazygit_${LG_V#v}_linux_x86_64.tar.gz" \
      | tar -xz -C "$HOME/.local/bin" lazygit
  } || warn "lazygit install failed"
fi

# --- starship prompt -----------------------------------------
if ! command -v starship >/dev/null 2>&1; then
  log "installing starship"
  if [ "$SUDO" != "skip" ]; then
    curl -sS https://starship.rs/install.sh | sh -s -- -y
  else
    curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
  fi
else
  log "starship already installed"
fi

# --- zsh plugins ---------------------------------------------
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  if [ ! -d "$HOME/.zsh/$plugin" ]; then
    log "cloning $plugin"
    git clone --depth 1 "https://github.com/zsh-users/$plugin" "$HOME/.zsh/$plugin"
  else
    log "$plugin already present (git -C ~/.zsh/$plugin pull to update)"
  fi
done

# --- nvm + node LTS + pnpm -----------------------------------
export NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  log "installing nvm"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
# shellcheck disable=SC1091
if [ -s "$NVM_DIR/nvm.sh" ]; then
  \. "$NVM_DIR/nvm.sh"
  if ! nvm ls 'lts/*' >/dev/null 2>&1; then
    log "installing node lts"
    nvm install --lts
    nvm alias default 'lts/*'
  fi
  command -v corepack >/dev/null 2>&1 && corepack enable pnpm 2>/dev/null || true
fi

# --- claude code ---------------------------------------------
if ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
  log "installing claude code"
  curl -fsSL https://claude.ai/install.sh | bash || warn "claude code install failed (fine on locked-down boxes)"
fi

# --- LazyVim (stock starter, only if no nvim config yet) -----
if command -v nvim >/dev/null 2>&1 && [ ! -d "$HOME/.config/nvim" ]; then
  log "installing LazyVim starter (stock)"
  git clone --depth 1 https://github.com/LazyVim/starter "$HOME/.config/nvim"
  rm -rf "$HOME/.config/nvim/.git"
  nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || warn "plugin sync had errors — run :Lazy sync inside nvim"
fi

# --- claude code settings (plugins, vim mode, theme) ---------
# Claude Code reconciles enabledPlugins/extraKnownMarketplaces on startup,
# so listing them here is enough — plugins auto-install on first run.
mkdir -p "$HOME/.claude"
CLAUDE_SETTINGS_NEW="$(mktemp)"
cat > "$CLAUDE_SETTINGS_NEW" <<'EOF'
{
  "model": "claude-fable-5[1m]",
  "enabledPlugins": {
    "frontend-design@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "playwright@claude-plugins-official": true,
    "github@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true,
    "gopls-lsp@claude-plugins-official": true,
    "rust-analyzer-lsp@claude-plugins-official": true,
    "ponytail@ponytail": true
  },
  "extraKnownMarketplaces": {
    "ponytail": {
      "source": {
        "source": "github",
        "repo": "DietrichGebert/ponytail"
      }
    }
  },
  "theme": "auto",
  "editorMode": "vim"
}
EOF
if [ ! -f "$HOME/.claude/settings.json" ]; then
  log "writing ~/.claude/settings.json"
  mv "$CLAUDE_SETTINGS_NEW" "$HOME/.claude/settings.json"
elif command -v jq >/dev/null 2>&1; then
  log "merging claude code settings into existing ~/.claude/settings.json"
  jq -s '.[0] * .[1]' "$HOME/.claude/settings.json" "$CLAUDE_SETTINGS_NEW" \
    > "$HOME/.claude/settings.json.tmp" \
    && mv "$HOME/.claude/settings.json.tmp" "$HOME/.claude/settings.json"
  rm -f "$CLAUDE_SETTINGS_NEW"
else
  warn "~/.claude/settings.json exists and jq is missing — merge manually from the repo's setup.sh"
  rm -f "$CLAUDE_SETTINGS_NEW"
fi

# --- git identity (only if unset) ----------------------------
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "$GIT_NAME"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "$GIT_EMAIL"

# --- ~/.config/starship.toml ---------------------------------
log "writing ~/.config/starship.toml"
cat > "$HOME/.config/starship.toml" <<'EOF'
# Put everything on one line — no newline before the input
add_newline = false

# Define the exact order so it reads left-to-right on that line
format = "$directory$git_branch$git_status$character"

[character]
vimcmd_symbol = "[N](bold green)"
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
EOF

# --- ~/.zshrc ------------------------------------------------
if [ -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.zshrc.pre-setup" ]; then
  cp "$HOME/.zshrc" "$HOME/.zshrc.pre-setup"
  log "backed up existing .zshrc -> ~/.zshrc.pre-setup"
fi
log "writing ~/.zshrc"
cat > "$HOME/.zshrc" <<'EOF'
# History (so autosuggestions have something to suggest)
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS INC_APPEND_HISTORY

# Completion menu
autoload -Uz compinit && compinit

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# --- vi mode ---
bindkey -v
export KEYTIMEOUT=1
bindkey -M viins '^R' history-incremental-search-backward
bindkey -M viins '^A' beginning-of-line
bindkey -M viins '^E' end-of-line

# Autosuggestions
[ -f ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh ] && \
  source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# fzf keybindings (Ctrl-R fuzzy history, Ctrl-T file picker) if available
command -v fzf >/dev/null 2>&1 && source <(fzf --zsh 2>/dev/null) || true

export PATH="$HOME/.local/bin:$PATH"

# Reuse one ssh-agent across shells (keys are passphrase-protected;
# AddKeysToAgent in ~/.ssh/config caches them on first use)
if [ -d "$HOME/.ssh" ]; then
  export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
  ssh-add -l >/dev/null 2>&1
  if [ $? -eq 2 ]; then
    rm -f "$SSH_AUTH_SOCK"
    eval "$(ssh-agent -a "$SSH_AUTH_SOCK")" >/dev/null
  fi
fi

# Prompt
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

# Syntax highlighting — MUST be sourced last
[ -f ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && \
  source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF

# --- default shell -> zsh ------------------------------------
ZSH_PATH="$(command -v zsh || true)"
if [ -n "$ZSH_PATH" ] && [ "${SHELL:-}" != "$ZSH_PATH" ]; then
  if chsh -s "$ZSH_PATH" 2>/dev/null; then
    log "default shell changed to zsh (takes effect on next login)"
  else
    warn "couldn't chsh (no password / restricted box) — adding zsh handoff to ~/.bashrc"
    if ! grep -q 'exec zsh' "$HOME/.bashrc" 2>/dev/null; then
      printf '\n# hand off interactive sessions to zsh\nif [ -t 1 ] && [ -x %s ] && [ -z "${ZSH_VERSION:-}" ]; then exec %s -l; fi\n' \
        "$ZSH_PATH" "$ZSH_PATH" >> "$HOME/.bashrc"
    fi
  fi
fi

log "done. start a new shell or run: exec zsh"
