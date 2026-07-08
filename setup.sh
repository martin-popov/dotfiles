#!/usr/bin/env bash
# ============================================================
# Portable dev environment bootstrap — Martin Popov
# Targets Ubuntu/Debian (apt). Usage: bash setup.sh
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
PKGS="zsh tmux git curl unzip ripgrep fzf htop jq"
if [ "$SUDO" != "skip" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    log "installing packages (apt): $PKGS + build-essential"
    $SUDO apt-get update -qq
    # shellcheck disable=SC2086
    $SUDO apt-get install -y -qq $PKGS build-essential
  else
    warn "no apt — install manually: $PKGS + a C toolchain"
  fi
fi

mkdir -p "$HOME/.local/bin" "$HOME/.config" "$HOME/.zsh"
# so command -v sees tools we installed on previous runs (idempotency)
export PATH="$HOME/.local/bin:$PATH"

# auth for api.github.com calls — shared CI runner IPs get rate-limited without it
GH_AUTH=()
[ -n "${GITHUB_TOKEN:-}" ] && GH_AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")

# --- neovim (latest tarball, updates in place; apt's is old) --
ARCH="$(uname -m)"
if [ "$ARCH" = "x86_64" ] && [ "$SUDO" != "skip" ]; then
  NVIM_LATEST="$(curl -fsSL "${GH_AUTH[@]}" https://api.github.com/repos/neovim/neovim/releases/latest \
    | sed -nE 's/.*"tag_name": *"(v[^"]+)".*/\1/p' || true)"
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
  curl -fsSL "${GH_AUTH[@]}" "https://api.github.com/repos/$1/releases/latest" \
    | sed -nE 's/.*"tag_name": *"(v?[^"]+)".*/\1/p'
}
if ! command -v fd >/dev/null 2>&1 && [ "$ARCH" = "x86_64" ]; then
  FD_V="$(gh_latest_tag sharkdp/fd)" && [ -n "$FD_V" ] && {
    log "installing fd $FD_V"
    curl -fsSL "https://github.com/sharkdp/fd/releases/download/${FD_V}/fd-${FD_V}-x86_64-unknown-linux-gnu.tar.gz" \
      | tar -xz -C /tmp
    mv "/tmp/fd-${FD_V}-x86_64-unknown-linux-gnu/fd" "$HOME/.local/bin/"
    rm -rf "/tmp/fd-${FD_V}-x86_64-unknown-linux-gnu"
  } || warn "fd install failed"
fi
if ! command -v lazygit >/dev/null 2>&1 && [ "$ARCH" = "x86_64" ]; then
  LG_V="$(gh_latest_tag jesseduffield/lazygit)" && [ -n "$LG_V" ] && {
    log "installing lazygit $LG_V"
    curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/${LG_V}/lazygit_${LG_V#v}_linux_x86_64.tar.gz" \
      | tar -xz -C "$HOME/.local/bin" lazygit
  } || warn "lazygit install failed"
fi

# --- starship prompt (~/.local/bin works with or without sudo) --
command -v starship >/dev/null 2>&1 \
  || curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"

# --- zsh plugins ---------------------------------------------
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  [ -d "$HOME/.zsh/$plugin" ] \
    || git clone --depth 1 "https://github.com/zsh-users/$plugin" "$HOME/.zsh/$plugin"
done

# --- nvm + node LTS + pnpm -----------------------------------
export NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  NVM_V="$(gh_latest_tag nvm-sh/nvm)" || true
  log "installing nvm ${NVM_V:-v0.40.3 (fallback)}"
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_V:-v0.40.3}/install.sh" | bash
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

# --- neovim config (LazyVim + tweaks, lives in this repo) ----
DOTS="$HOME/dotfiles"
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -d "$(cd "$(dirname "$SELF")" && pwd)/nvim" ]; then
  DOTS="$(cd "$(dirname "$SELF")" && pwd)" # running from a checkout — use it
elif [ ! -d "$DOTS/nvim" ]; then
  log "cloning dotfiles repo -> $DOTS"
  git clone --depth 1 https://github.com/martin-popov/dotfiles "$DOTS"
fi
if [ -e "$HOME/.config/nvim" ] && [ ! -L "$HOME/.config/nvim" ]; then
  mv "$HOME/.config/nvim" "$HOME/.config/nvim.pre-setup"
  log "backed up existing ~/.config/nvim -> ~/.config/nvim.pre-setup"
fi
ln -sfn "$DOTS/nvim" "$HOME/.config/nvim"
if command -v nvim >/dev/null 2>&1; then
  log "restoring nvim plugins from lazy-lock.json"
  nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1 || warn "plugin restore had errors — run :Lazy restore inside nvim"
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

# --- ~/.tmux.conf --------------------------------------------
log "writing ~/.tmux.conf"
cat > "$HOME/.tmux.conf" <<'EOF'
set -g mouse on
setw -g mode-keys vi
EOF

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

# ls aliases (oh-my-zsh style)
alias ls='ls --color=tty'
alias l='ls -lah'
alias ll='ls -lh'
alias la='ls -lAh'
alias lsa='ls -lah'

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
