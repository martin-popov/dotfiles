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
PKGS="zsh tmux git curl wget unzip ripgrep fzf htop"
if [ "$SUDO" != "skip" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    log "installing packages (apt): $PKGS"
    $SUDO apt-get update -qq
    # shellcheck disable=SC2086
    $SUDO apt-get install -y -qq $PKGS
  elif command -v dnf >/dev/null 2>&1; then
    log "installing packages (dnf): $PKGS"
    $SUDO dnf install -y -q $PKGS
  elif command -v pacman >/dev/null 2>&1; then
    log "installing packages (pacman): $PKGS"
    $SUDO pacman -S --noconfirm --needed $PKGS
  elif command -v apk >/dev/null 2>&1; then
    log "installing packages (apk): $PKGS"
    $SUDO apk add --no-cache $PKGS shadow
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
