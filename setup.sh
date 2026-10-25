#!/usr/bin/env bash
# ============================================================
# Portable dev environment bootstrap — Martin Popov
# Targets Ubuntu/Debian (apt) and macOS (Homebrew, installed if missing).
# Usage: bash setup.sh
# Idempotent: safe to re-run.
# ============================================================
set -euo pipefail

GIT_NAME="Martin Popov"
GIT_EMAIL="me@martinpopov.com"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

# --- sudo shim (some boxes are root, some have no sudo) ------
ARCH="$(uname -m)"
OS="$(uname -s)"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else
    warn "not root and no sudo — skipping system package installs"
    SUDO="skip"
  fi
fi

# --- component selection --------------------------------------
# Interactive checklist (Enter = everything). Non-interactive runs
# (curl | bash, CI) install everything; preselect with e.g.
#   COMPONENTS="base go" bash setup.sh
COMPONENTS_ALL="base node neovim cli starship claude go rust macos macapps"
[ $# -gt 0 ] && COMPONENTS="$*" # or positionally: bash setup.sh go rust
for c in ${COMPONENTS:-}; do
  case " $COMPONENTS_ALL " in *" $c "*) ;; *) warn "unknown component: $c" ;; esac
done
if [ -z "${COMPONENTS:-}" ]; then
  if [ -t 0 ]; then
    cat <<'MENU'
What should this box get?
  1) base      zsh, tmux, git, curl, ripgrep, fzf, htop, jq + build tools
  2) node      nvm + node LTS + pnpm
  3) neovim    latest tarball + LazyVim config from this repo
  4) cli       fd, lazygit, gh
  5) starship  prompt
  6) claude    claude code + settings (opus, vim mode)
  7) go        latest toolchain -> /usr/local/go (brew on macOS)
  8) rust      rustup + stable toolchain
  9) macos     system defaults: keyboard/dock/finder (Darwin only)
 10) macapps   brew bundle: casks + mac CLI extras (Darwin only)
MENU
    read -rp "Numbers separated by spaces [Enter = all]: " PICK
    COMPONENTS=""
    for n in $PICK; do
      case "$n" in
        1) COMPONENTS+=" base" ;;
        2) COMPONENTS+=" node" ;;
        3) COMPONENTS+=" neovim" ;;
        4) COMPONENTS+=" cli" ;;
        5) COMPONENTS+=" starship" ;;
        6) COMPONENTS+=" claude" ;;
        7) COMPONENTS+=" go" ;;
        8) COMPONENTS+=" rust" ;;
        9) COMPONENTS+=" macos" ;;
        10) COMPONENTS+=" macapps" ;;
        *) warn "unknown option: $n" ;;
      esac
    done
    [ -n "$COMPONENTS" ] || COMPONENTS="$COMPONENTS_ALL"
  else
    COMPONENTS="$COMPONENTS_ALL"
  fi
fi
want() { case " $COMPONENTS " in *" $1 "*) ;; *) return 1 ;; esac; }
log "components:$COMPONENTS"
# Config files (.zshrc, .tmux.conf, nvim/starship links, git config) are
# always written — that's the point of a dotfiles repo. Only installs are gated.

# --- homebrew (macOS) ----------------------------------------
# A fresh Mac has no brew, and everything below (tmux, fzf, neovim, gh, go,
# the Brewfile casks…) comes from it. brew isn't on the default PATH either,
# so put it there for this run; new shells get it from the .zshrc below.
brew_env() {
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && { eval "$("$b" shellenv)"; return 0; }
  done
  return 1
}
if [ "$OS" = "Darwin" ] && ! command -v brew >/dev/null 2>&1 && ! brew_env; then
  log "installing homebrew (asks for your password once)"
  # The installer goes non-interactive when stdin isn't a tty (curl | bash
  # feeds it this script) and then only tries `sudo -n`, so cache sudo via
  # the tty first; </dev/null stops it eating the rest of the piped script.
  if sudo -v; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null \
      && brew_env || warn "homebrew install failed — install it from https://brew.sh and re-run"
  else
    warn "no sudo for homebrew — install it from https://brew.sh and re-run; skipping brew packages"
  fi
fi

# --- system packages -----------------------------------------
PKGS="zsh tmux git curl unzip ripgrep fzf htop jq"
if command -v brew >/dev/null 2>&1; then # macOS — no sudo, and brew covers the binary installs below too
  BREW_PKGS="" # zsh/git/curl/unzip ship with macOS
  want base     && BREW_PKGS+=" tmux ripgrep fzf htop jq"
  want cli      && BREW_PKGS+=" fd lazygit gh"
  want starship && BREW_PKGS+=" starship"
  want neovim   && BREW_PKGS+=" neovim"
  want go       && BREW_PKGS+=" go"
  want macos    && BREW_PKGS+=" dockutil"
  if [ -n "$BREW_PKGS" ]; then
    log "installing packages (brew):$BREW_PKGS"
    # shellcheck disable=SC2086
    brew install $BREW_PKGS || warn "some brew installs failed — check output above"
  fi
  want neovim && { brew upgrade neovim 2>/dev/null || true; } # parity with the linux latest-tarball behavior
  if want base; then
    brew list --cask ghostty >/dev/null 2>&1 || brew install --cask --adopt ghostty || warn "ghostty install failed"
  fi
elif want base && [ "$OS" != "Darwin" ] && [ "$SUDO" != "skip" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    log "installing packages (apt): $PKGS + build-essential"
    $SUDO apt-get update -qq
    # shellcheck disable=SC2086
    $SUDO apt-get install -y -qq $PKGS build-essential
  else
    warn "no apt — install manually: $PKGS + a C toolchain"
  fi
fi

mkdir -p "$HOME/.local/bin" "$HOME/.config" "$HOME/.zsh" "$HOME/Developer" # projects live here; ghostty + zsh start in it
# so command -v sees tools we installed on previous runs (idempotency)
export PATH="$HOME/.local/bin:$PATH"

# auth for api.github.com calls — shared CI runner IPs get rate-limited without it
GH_AUTH=()
[ -n "${GITHUB_TOKEN:-}" ] && GH_AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")

# Release cooldown: GitHub downloads take the newest release that's at least
# a week old — a compromised release is usually caught and pulled by then.
# npm/pnpm get the same window below. Highest version wins, so a backport
# patch published after a newer major doesn't downgrade us.
RELEASE_AGE_DAYS=7
RELEASE_CUTOFF="$(date -u -d "$RELEASE_AGE_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -v-"$RELEASE_AGE_DAYS"d +%Y-%m-%dT%H:%M:%SZ)" # GNU || BSD date
gh_latest_tag() { # repo -> newest tag (e.g. v1.2.3) published before the cutoff
  curl -fsSL ${GH_AUTH[@]+"${GH_AUTH[@]}"} "https://api.github.com/repos/$1/releases?per_page=30" \
    | awk -F'"' -v cutoff="$RELEASE_CUTOFF" '
        /"tag_name":/     { tag = $4 }
        /"prerelease":/   { pre = /true/ }
        /"published_at":/ { if (!pre && tag ~ /^v?[0-9]/ && $4 != "" && $4 <= cutoff) print tag }' \
    | sort -V | tail -1
}

# --- neovim (latest tarball, updates in place; apt's is old) --
if want neovim && [ "$OS" = "Linux" ] && [ "$ARCH" = "x86_64" ] && [ "$SUDO" != "skip" ]; then
  NVIM_LATEST="$(gh_latest_tag neovim/neovim)" || true
  NVIM_HAVE=""
  command -v nvim >/dev/null 2>&1 && NVIM_HAVE="v$(nvim --version | head -1 | sed 's/^NVIM v//')"
  if [ -n "$NVIM_LATEST" ] && [ "$NVIM_HAVE" != "$NVIM_LATEST" ]; then
    log "installing neovim $NVIM_LATEST (had: ${NVIM_HAVE:-none})"
    curl -fsSL -o /tmp/nvim.tar.gz \
      "https://github.com/neovim/neovim/releases/download/$NVIM_LATEST/nvim-linux-x86_64.tar.gz"
    $SUDO rm -rf /opt/nvim-linux-x86_64
    $SUDO tar -C /opt -xzf /tmp/nvim.tar.gz
    $SUDO ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
    rm -f /tmp/nvim.tar.gz
  else
    log "neovim up to date: ${NVIM_HAVE:-unknown}"
  fi
elif want neovim && ! command -v nvim >/dev/null 2>&1; then
  warn "skipping neovim tarball (arch=$ARCH, sudo=$SUDO) — falling back to package manager version if present"
fi

# --- fd + lazygit + gh (binaries -> ~/.local/bin, no sudo needed) --
fetch_bin() { # <name> <repo> <asset printf pattern> <full|strip — version form in asset>
  local name="$1" repo="$2" pattern="$3" tag v dir
  command -v "$name" >/dev/null 2>&1 && return 0
  tag="$(gh_latest_tag "$repo")" || true
  [ -n "$tag" ] || { warn "$name install failed (no release tag)"; return 0; }
  v="$tag"; [ "$4" = strip ] && v="${tag#v}"
  log "installing $name $tag"
  dir="$(mktemp -d)"
  # shellcheck disable=SC2059
  if curl -fsSL "https://github.com/$repo/releases/download/$tag/$(printf "$pattern" "$v")" | tar -xz -C "$dir"; then
    find "$dir" -type f -name "$name" -exec mv {} "$HOME/.local/bin/" \;
  else
    warn "$name install failed"
  fi
  rm -rf "$dir"
}
if want cli && [ "$OS" = "Linux" ] && [ "$ARCH" = "x86_64" ]; then
  fetch_bin fd      sharkdp/fd            'fd-%s-x86_64-unknown-linux-gnu.tar.gz' full
  fetch_bin lazygit jesseduffield/lazygit 'lazygit_%s_linux_x86_64.tar.gz'        strip
  fetch_bin gh      cli/cli               'gh_%s_linux_amd64.tar.gz'              strip
fi

# --- starship prompt (~/.local/bin works with or without sudo) --
if want starship; then
  command -v starship >/dev/null 2>&1 \
    || curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
fi

# --- zsh plugins ---------------------------------------------
if want base; then
  for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    [ -d "$HOME/.zsh/$plugin" ] \
      || git clone --depth 1 "https://github.com/zsh-users/$plugin" "$HOME/.zsh/$plugin"
  done
fi

# --- nvm + node LTS + pnpm -----------------------------------
if want node; then
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
    # pnpm is standalone now (below); drop corepack's shims so they can't win
    command -v corepack >/dev/null 2>&1 && { corepack disable pnpm 2>/dev/null || true; }
    # npm stays only for tools that shell out to it (nvm, Mason) — the .zshrc
    # blocks typing it — so it gets the same cooldown in days
    npm config set min-release-age "$RELEASE_AGE_DAYS" 2>/dev/null || warn "couldn't set npm min-release-age"
    # fontawesome: repos route the @fortawesome scope in their .npmrc; the
    # auth token belongs in ~/.npmrc so pnpm/npm find it without any .env.
    if ! grep -qs 'npm\.fontawesome\.com/:_authToken' "$HOME/.npmrc"; then
      if [ -n "${FONTAWESOME_NPM_AUTH_TOKEN:-}" ]; then
        printf '//npm.fontawesome.com/:_authToken=%s\n' "$FONTAWESOME_NPM_AUTH_TOKEN" >> "$HOME/.npmrc"
        log "wrote fontawesome token to ~/.npmrc"
      else
        log "fontawesome token missing: FONTAWESOME_NPM_AUTH_TOKEN=<token> ./setup.sh node (or add it to ~/.npmrc yourself)"
      fi
    fi
  fi
fi

# --- pnpm (standalone binary, no node or corepack needed) ------
# Node 25+ no longer ships corepack, so pnpm comes from its own release
# tarball (binary + dist/, kept together) and updates in place on re-run.
if want node; then
  case "$OS-$ARCH" in
    Darwin-arm64) PNPM_ASSET=darwin-arm64 ;; Darwin-x86_64) PNPM_ASSET=darwin-x64 ;;
    Linux-x86_64) PNPM_ASSET=linux-x64 ;;    Linux-aarch64)  PNPM_ASSET=linux-arm64 ;;
    *) PNPM_ASSET="" ;;
  esac
  PNPM_TAG="$(gh_latest_tag pnpm/pnpm)" || true
  PNPM_HAVE="$("$HOME/.local/share/pnpm-dist/pnpm" --version 2>/dev/null || true)"
  if [ -z "$PNPM_ASSET" ] || [ -z "$PNPM_TAG" ]; then
    warn "skipping pnpm (arch=$ARCH, tag=${PNPM_TAG:-none})"
  elif [ "v$PNPM_HAVE" != "$PNPM_TAG" ]; then
    log "installing pnpm $PNPM_TAG (had: ${PNPM_HAVE:-none})"
    rm -rf "$HOME/.local/share/pnpm-dist" && mkdir -p "$HOME/.local/share/pnpm-dist"
    curl -fsSL "https://github.com/pnpm/pnpm/releases/download/$PNPM_TAG/pnpm-$PNPM_ASSET.tar.gz" \
      | tar -xz -C "$HOME/.local/share/pnpm-dist" || warn "pnpm install failed"
  fi
  [ -x "$HOME/.local/share/pnpm-dist/pnpm" ] && ln -sf "$HOME/.local/share/pnpm-dist/pnpm" "$HOME/.local/bin/pnpm"
  # week-long cooldown for packages (minutes; pnpm's own default is a day).
  # Explicitly set, pnpm also blocks younger versions outright.
  "$HOME/.local/bin/pnpm" config set --global minimumReleaseAge $((RELEASE_AGE_DAYS * 24 * 60)) >/dev/null 2>&1 \
    || warn "couldn't set pnpm minimumReleaseAge"
  # global JS CLIs (zed formats SQL with sql-formatter); bins land in
  # $PNPM_HOME/bin and run on nvm's node
  export PNPM_HOME="$HOME/.local/share/pnpm" PATH="$HOME/.local/share/pnpm/bin:$PATH"
  PNPM_GLOBALS="sql-formatter"
  for tool in $PNPM_GLOBALS; do
    [ -x "$PNPM_HOME/bin/$tool" ] || "$HOME/.local/bin/pnpm" add -g "$tool" >/dev/null 2>&1 \
      || warn "pnpm add -g $tool failed"
  done
fi

# --- go (official tarball; apt's lags several releases) --------
if want go && [ "$OS" = "Linux" ] && [ "$ARCH" = "x86_64" ] && [ "$SUDO" != "skip" ]; then
  GO_LATEST="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1 || true)" # e.g. go1.25.4
  GO_HAVE=""
  [ -x /usr/local/go/bin/go ] && GO_HAVE="$(/usr/local/go/bin/go version | awk '{print $3}')"
  if [ -n "$GO_LATEST" ] && [ "$GO_HAVE" != "$GO_LATEST" ]; then
    log "installing go $GO_LATEST (had: ${GO_HAVE:-none})"
    curl -fsSL -o /tmp/go.tar.gz "https://go.dev/dl/${GO_LATEST}.linux-amd64.tar.gz"
    $SUDO rm -rf /usr/local/go
    $SUDO tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz
  else
    log "go up to date: ${GO_HAVE:-unknown}"
  fi
elif want go && ! command -v go >/dev/null 2>&1; then # macOS gets go via brew above
  warn "skipping go (arch=$ARCH, sudo=$SUDO) — install manually from https://go.dev/dl/"
fi

# --- rust (rustup -> ~/.cargo, no sudo; .zshrc sources cargo env) --
if want rust && [ ! -x "$HOME/.cargo/bin/cargo" ] && ! command -v cargo >/dev/null 2>&1; then
  log "installing rust (rustup)"
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path || warn "rust install failed"
fi

# --- claude code ---------------------------------------------
if want claude && ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
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
  # fetch keyless over https; push over ssh once keys are in place
  git -C "$DOTS" remote set-url --push origin git@github.com:martin-popov/dotfiles
fi
if [ -e "$HOME/.config/nvim" ] && [ ! -L "$HOME/.config/nvim" ]; then
  mv "$HOME/.config/nvim" "$HOME/.config/nvim.pre-setup"
  log "backed up existing ~/.config/nvim -> ~/.config/nvim.pre-setup"
fi
ln -sfn "$DOTS/nvim" "$HOME/.config/nvim"
if command -v nvim >/dev/null 2>&1; then
  log "restoring nvim plugins from lazy-lock.json"
  nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1 || warn "plugin restore had errors — run :Lazy restore inside nvim"
  # a first install clones at HEAD and rewrites the lock; a second pass
  # against the committed pins checks out the pinned commits. status prints
  # nothing when git refuses the repo (CI: checkout owned by another uid),
  # so that case and a read-only checkout both just skip the second pass.
  if [ -n "$(git -C "$DOTS" status --porcelain -- nvim/lazy-lock.json 2>/dev/null)" ] \
    && git -C "$DOTS" checkout -- nvim/lazy-lock.json 2>/dev/null; then
    nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1 || true
  fi
fi

# --- claude code settings (model, effort, vim mode, theme) ----
# No plugins: effort lives under modelSettings (top-level effortLevel is
# ignored for Opus 5.5+ and shadowed by the per-model entry anyway).
if want claude; then
mkdir -p "$HOME/.claude"
CLAUDE_SETTINGS="$(cat <<'EOF'
{
  "model": "opus",
  "modelSettings": {
    "claude-opus-5-5": { "effortLevel": "high" }
  },
  "theme": "auto",
  "tui": "default",
  "editorMode": "vim",
  "remoteControlAtStartup": false,
  "agentPushNotifEnabled": true
}
EOF
)"
if [ ! -f "$HOME/.claude/settings.json" ]; then
  log "writing ~/.claude/settings.json"
  printf '%s\n' "$CLAUDE_SETTINGS" > "$HOME/.claude/settings.json"
elif command -v jq >/dev/null 2>&1; then
  log "merging claude code settings into existing ~/.claude/settings.json"
  printf '%s' "$CLAUDE_SETTINGS" | jq -s '.[0] * .[1]' "$HOME/.claude/settings.json" - \
    > "$HOME/.claude/settings.json.tmp" \
    && mv "$HOME/.claude/settings.json.tmp" "$HOME/.claude/settings.json"
else
  # shellcheck disable=SC2088 # the ~ is message prose, not a path
  warn "~/.claude/settings.json exists and jq is missing — merge manually from the repo's setup.sh"
fi
fi # want claude

# --- ~/.tmux.conf --------------------------------------------
log "writing ~/.tmux.conf"
cat > "$HOME/.tmux.conf" <<'EOF'
set -g mouse on
setw -g mode-keys vi
set -g focus-events on

# new windows and splits open in the current pane's directory
bind c new-window -c "#{pane_current_path}"
bind '"' split-window -c "#{pane_current_path}"
bind % split-window -h -c "#{pane_current_path}"

# true color (RGB) passthrough — without this 24-bit colors get
# quantized to the 256-color palette (Latte #EFF1F5 -> #EEEEEE)
set -g default-terminal "tmux-256color"
set -as terminal-features ',xterm-256color:RGB'

# Catppuccin status bar + pane borders, generated by the `theme` command
source-file -q ~/.config/tmux/theme.conf

# Session persistence across restarts: resurrect (prefix+C-s / prefix+C-r)
# + continuum (autosave every 15m, autorestore on server start)
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @continuum-restore 'on'
run '~/.tmux/plugins/tpm/tpm'
EOF

# tmux plugin manager + plugins (idempotent, like the zsh plugins above)
[ -d "$HOME/.tmux/plugins/tpm" ] \
  || git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
if command -v tmux >/dev/null 2>&1; then
  # install_plugins needs a server that has sourced the conf above (tpm sets
  # TMUX_PLUGIN_MANAGER_PATH): reload a running server, else boot a throwaway one
  tmux source-file "$HOME/.tmux.conf" 2>/dev/null \
    || tmux new-session -d -s _setup 2>/dev/null || true
  "$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null 2>&1 \
    || warn "tmux plugin install failed — press prefix+I inside tmux"
  tmux kill-session -t _setup 2>/dev/null || true
fi

# --- ~/.ssh/config (only if missing — keys/hosts are per-machine) --
# AddKeysToAgent pairs with the shared ssh-agent block in .zshrc; private
# host entries live in the untracked ~/.ssh/config.local
if [ ! -e "$HOME/.ssh/config" ]; then
  log "writing ~/.ssh/config"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  {
    echo "Include ~/.ssh/config.local"
    echo ""
    echo "Host *"
    echo "  AddKeysToAgent yes"
    [ "$OS" = "Darwin" ] && echo "  UseKeychain yes" # invalid option on Linux ssh
  } > "$HOME/.ssh/config"
  chmod 600 "$HOME/.ssh/config"
fi

# --- git identity + defaults (each only if unset) -------------
git_default() { git config --global "$1" >/dev/null 2>&1 || git config --global "$1" "$2"; }
git_default user.name  "$GIT_NAME"
git_default user.email "$GIT_EMAIL"
git_default init.defaultBranch main
git_default push.autoSetupRemote true # first push of a new branch needs no -u
git_default pull.rebase true
git_default rebase.autoStash true
# global ignores: git reads ~/.config/git/ignore without any core.excludesFile
mkdir -p "$HOME/.config/git"
grep -qsx '.DS_Store' "$HOME/.config/git/ignore" || echo '.DS_Store' >> "$HOME/.config/git/ignore"
# Sign commits and tags with the GitHub ssh key once it's on this machine
# (copied per machine, never in the repo). GitHub shows them Verified once
# the same key is added there as a signing key; allowed_signers lets
# `git log --show-signature` verify locally too.
SIGNING_KEY="$HOME/.ssh/martin-popov.pub"
if [ -f "$SIGNING_KEY" ]; then
  git_default gpg.format ssh
  git_default user.signingkey "$SIGNING_KEY"
  git_default commit.gpgsign true
  git_default tag.gpgsign true
  git_default gpg.ssh.allowedSignersFile "$HOME/.config/git/allowed_signers"
  printf '%s namespaces="git" %s\n' "$GIT_EMAIL" "$(cut -d' ' -f1,2 "$SIGNING_KEY")" \
    > "$HOME/.config/git/allowed_signers"
fi

# --- ~/.config/starship.toml (lives in this repo) ------------
log "linking ~/.config/starship.toml"
ln -sf "$DOTS/starship.toml" "$HOME/.config/starship.toml"

# --- ghostty (macOS) — catppuccin follows system appearance ---
if [ "$OS" = "Darwin" ]; then
  mkdir -p "$HOME/.config/ghostty"
  ln -sf "$DOTS/ghostty" "$HOME/.config/ghostty/config"
fi

# --- zed (all platforms) + karabiner (macOS) configs ----------
mkdir -p "$HOME/.config/zed"
ln -sf "$DOTS/zed/settings.json" "$HOME/.config/zed/settings.json"
ln -sf "$DOTS/zed/keymap.json" "$HOME/.config/zed/keymap.json"
# whole dir: karabiner replaces a symlinked file on save, a dir link survives
if [ "$OS" = "Darwin" ]; then
  if [ -e "$HOME/.config/karabiner" ] && [ ! -L "$HOME/.config/karabiner" ]; then
    mv "$HOME/.config/karabiner" "$HOME/.config/karabiner.pre-setup"
    log "backed up existing ~/.config/karabiner -> ~/.config/karabiner.pre-setup"
  fi
  ln -sfn "$DOTS/karabiner" "$HOME/.config/karabiner"
fi

# --- macos apps (brew bundle) ----------------------------------
if want macapps && [ "$OS" = "Darwin" ]; then
  log "brew bundle (Brewfile: casks + mac CLI extras)"
  brew bundle --file "$DOTS/Brewfile" || warn "brew bundle had failures — check output above"
  command -v git-lfs >/dev/null 2>&1 && git lfs install
fi

# --- macos system defaults (harmless to re-run) ---------------
if want macos && [ "$OS" = "Darwin" ]; then
  log "applying macOS defaults (keyboard/dock/finder)"
  # keyboard: fast repeat, full keyboard UI navigation
  defaults write NSGlobalDomain KeyRepeat -int 2
  defaults write NSGlobalDomain InitialKeyRepeat -int 15
  defaults write NSGlobalDomain AppleKeyboardUIMode -int 2
  # sound: feedback click when changing volume
  defaults write NSGlobalDomain com.apple.sound.beep.feedback -int 1
  # dock: autohide instantly, big tiles + magnification, no recents,
  # keep Spaces order, minimize into app icon, no bottom-right hot corner
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.dock autohide-delay -float 0
  defaults write com.apple.dock tilesize -int 93
  defaults write com.apple.dock magnification -bool true
  defaults write com.apple.dock mru-spaces -bool false
  defaults write com.apple.dock show-recents -bool false
  defaults write com.apple.dock minimize-to-application -bool true
  defaults write com.apple.dock mineffect -string scale
  defaults write com.apple.dock wvous-br-corner -int 1
  # finder: path bar, list view, folders first, new windows open Desktop
  defaults write com.apple.finder ShowPathbar -bool true
  defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
  defaults write com.apple.finder _FXSortFoldersFirst -bool true
  defaults write com.apple.finder NewWindowTarget -string "PfDe"
  # no .DS_Store litter on network shares (the NAS) or USB drives
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
  # dock contents: Zen + Ghostty only
  if command -v dockutil >/dev/null 2>&1; then
    dockutil --remove all --no-restart || true
    [ -d /Applications/Zen.app ] && dockutil --add /Applications/Zen.app --no-restart
    [ -d /Applications/Ghostty.app ] && dockutil --add /Applications/Ghostty.app --no-restart
  else
    warn "dockutil not installed — skipping Dock contents"
  fi
  killall Dock Finder 2>/dev/null || true
  log "keyboard/sound defaults apply after logging out and back in"
fi

# --- theme switcher (catppuccin light/dark everywhere) --------
ln -sf "$DOTS/theme" "$HOME/.local/bin/theme"
[ -f "$HOME/.local/state/theme" ] || "$DOTS/theme" light

# --- theme-sync LaunchAgent (macOS): follow appearance changes --
# Fires `theme sync` whenever global prefs change (appearance toggles in
# System Settings, scheduled light/dark, or the theme script's own push);
# sync exits immediately unless the appearance drifted from the state file.
if [ "$OS" = "Darwin" ]; then
  log "installing theme-sync LaunchAgent"
  mkdir -p "$HOME/Library/LaunchAgents"
  THEME_PLIST="$HOME/Library/LaunchAgents/com.martinpopov.theme-sync.plist"
  cat > "$THEME_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.martinpopov.theme-sync</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HOME/.local/bin/theme</string>
    <string>sync</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>WatchPaths</key>
  <array><string>$HOME/Library/Preferences/.GlobalPreferences.plist</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
  launchctl bootout "gui/$(id -u)/com.martinpopov.theme-sync" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$THEME_PLIST" 2>/dev/null \
    || warn "launchctl bootstrap failed — theme-sync loads on next login"
fi

# --- lid (macOS): stay awake with the lid closed, auto-reverting --
# `lid off` needs pmset as root; a sudoers rule allows exactly the two
# disablesleep commands without a password (one sudo prompt to install it).
# The LaunchAgent runs `lid check` every minute to enforce the deadline and
# battery floor — a no-op unless lid is holding sleep off.
if [ "$OS" = "Darwin" ]; then
  ln -sf "$DOTS/lid" "$HOME/.local/bin/lid"
  # look for the rule itself: `sudo -l <cmd>` passes for any admin, since
  # they may run anything — with a password
  if want macos && ! sudo -n -l 2>/dev/null | grep -qF 'NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1'; then
    log "installing sudoers rule for lid (asks for your password)"
    LID_RULE="$(mktemp)"
    echo "$(id -un) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > "$LID_RULE"
    { sudo visudo -cqf "$LID_RULE" && sudo install -m 0440 -o root -g wheel "$LID_RULE" /etc/sudoers.d/lid; } \
      || warn "couldn't install the lid sudoers rule — lid off/on will fail until it's there"
    rm -f "$LID_RULE"
  fi
  LID_PLIST="$HOME/Library/LaunchAgents/com.martinpopov.lid.plist"
  cat > "$LID_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.martinpopov.lid</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HOME/.local/bin/lid</string>
    <string>check</string>
  </array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
  launchctl bootout "gui/$(id -u)/com.martinpopov.lid" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$LID_PLIST" 2>/dev/null \
    || warn "launchctl bootstrap failed — the lid check loads on next login"
fi

# --- ~/.zshrc ------------------------------------------------
if [ -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.zshrc.pre-setup" ]; then
  cp "$HOME/.zshrc" "$HOME/.zshrc.pre-setup"
  log "backed up existing .zshrc -> ~/.zshrc.pre-setup"
fi
log "writing ~/.zshrc"
cat > "$HOME/.zshrc" <<'EOF'
# No duplicate PATH entries when shells nest (tmux, editors, claude). Both
# halves: tools prepend via the PATH string, which -U on path alone ignores
typeset -U PATH path FPATH fpath

# History (so autosuggestions have something to suggest)
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE INC_APPEND_HISTORY

# Homebrew (macOS): not on the default PATH; completions must precede compinit
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [ -x "$b" ] && { eval "$("$b" shellenv)"; fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath); break; }
done
unset b

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

# editor
if command -v nvim >/dev/null 2>&1; then
  export EDITOR=nvim
  alias vim=nvim
fi

# ls aliases (oh-my-zsh style); GNU ls needs --color, BSD/macOS uses CLICOLOR
export CLICOLOR=1
ls --color=tty ~ >/dev/null 2>&1 && alias ls='ls --color=tty'
alias l='ls -lah'
alias ll='ls -lh'
alias la='ls -lAh'
alias lsa='ls -lah'

export PATH="$HOME/.local/bin:$PATH"

# pnpm only. Global installs (pnpm add -g) land in $PNPM_HOME/bin. npm/npx stay
# installed for tools that call them (nvm, Mason) but typing them is
# blocked; `command npm …` gets through when something really needs it.
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME/bin:$PATH"
npm() { print -u2 "npm is off here — use pnpm (escape hatch: command npm $*)"; return 1; }
npx() { print -u2 "npx is off here — use pnpm dlx (escape hatch: command npx $*)"; return 1; }
alias pnpx='pnpm dlx'

# Start in ~/Developer. Ghostty sets this itself; this covers Terminal.app,
# ssh, tmux. Only from $HOME, so editor terminals keep their project dir.
[[ $PWD == "$HOME" && -d ~/Developer ]] && cd ~/Developer

# Toolchains from setup.sh — no-ops on boxes that skipped them
[ -d /usr/local/go/bin ] && export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# Reuse one ssh-agent across shells (keys are passphrase-protected;
# AddKeysToAgent in ~/.ssh/config caches them on first use).
# macOS already runs a launchd agent with keychain integration — keep it,
# and load the keys whose passphrases are in the Keychain so git commit
# signing (which needs the agent for a passphrased key) never prompts.
if [ "$(uname)" = "Darwin" ]; then
  ssh-add --apple-load-keychain -q 2>/dev/null
elif [ -d "$HOME/.ssh" ]; then
  export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
  ssh-add -l >/dev/null 2>&1
  if [ $? -eq 2 ]; then
    rm -f "$SSH_AUTH_SOCK"
    eval "$(ssh-agent -a "$SSH_AUTH_SOCK")" >/dev/null
  fi
fi

# Machine-local extras (PATHs, aliases — kept out of the repo)
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"

# Prompt
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

# Syntax highlighting — MUST be sourced last
[ -f ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && \
  source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF

# --- default shell -> zsh ------------------------------------
ZSH_PATH="$(command -v zsh || true)"
if [ -n "$ZSH_PATH" ] && [ "${SHELL:-}" != "$ZSH_PATH" ]; then
  # chsh may password-prompt; allow it only on a tty (CI / curl|bash would
  # hang or eat piped input) — everyone else gets the bashrc handoff below
  if [ -t 0 ] && chsh -s "$ZSH_PATH"; then
    log "default shell changed to zsh (takes effect on next login)"
  else
    warn "couldn't chsh (no password / restricted box) — adding zsh handoff to ~/.bashrc"
    if ! grep -q 'hand off interactive sessions to zsh' "$HOME/.bashrc" 2>/dev/null; then
      printf '\n# hand off interactive sessions to zsh\nif [ -t 1 ] && [ -x %s ] && [ -z "${ZSH_VERSION:-}" ]; then exec %s -l; fi\n' \
        "$ZSH_PATH" "$ZSH_PATH" >> "$HOME/.bashrc"
    fi
  fi
fi

log "done. start a new shell or run: exec zsh"
