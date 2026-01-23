#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# Node.js + React + TypeScript Dev Setup
# For WSL Ubuntu 22.04
# - nvm + Node LTS
# - corepack + pnpm
# - build tools, git, ssh client
# - optional: create a Vite React TS template
# ==========================================

# -------- Team-configurable vars ----------
DEV_USER="${DEV_USER:-$USER}"                 # recommended: set to your normal user (not root)
NODE_LTS="${NODE_LTS:-lts/*}"                 # or "20", "22", etc.
PKG_MGR="${PKG_MGR:-pnpm}"                    # pnpm | yarn | npm
CREATE_SAMPLE_APP="${CREATE_SAMPLE_APP:-false}" # true/false
APP_NAME="${APP_NAME:-my-react-ts-app}"       # used if CREATE_SAMPLE_APP=true
APP_DIR="${APP_DIR:-$HOME/projects}"          # where to create sample app
GIT_NAME="${GIT_NAME:-}"                      # optional
GIT_EMAIL="${GIT_EMAIL:-}"                    # optional
# -----------------------------------------

info(){ echo -e "\e[36m[INFO]\e[0m  $*"; }
ok(){   echo -e "\e[32m[OK]\e[0m    $*"; }
warn(){ echo -e "\e[33m[WARN]\e[0m  $*"; }

if [[ "$(id -u)" -eq 0 ]]; then
  warn "You're running as root. Recommended: run as your normal user (e.g. anhnnp)."
fi

# Ensure apt base dependencies
info "Updating apt + installing base dependencies..."
sudo apt-get update -y
sudo apt-get install -y \
  ca-certificates curl wget git unzip zip \
  build-essential pkg-config \
  openssh-client \
  jq htop tmux \
  python3 python3-pip python3-venv

ok "Base packages installed."

# Git config (optional)
if [[ -n "$GIT_NAME" ]]; then
  git config --global user.name "$GIT_NAME" || true
fi
if [[ -n "$GIT_EMAIL" ]]; then
  git config --global user.email "$GIT_EMAIL" || true
fi
git config --global init.defaultBranch main || true

# Install nvm (idempotent)
info "Installing nvm (if missing)..."
export NVM_DIR="$HOME/.nvm"
if [[ ! -d "$NVM_DIR" ]]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  ok "nvm installed."
else
  ok "nvm already installed."
fi

# Load nvm into current shell
# shellcheck disable=SC1090
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
if ! command -v nvm >/dev/null 2>&1; then
  warn "nvm not loaded automatically. Re-open terminal or run: source ~/.nvm/nvm.sh"
  # Try again in a login shell later
fi

info "Installing Node ($NODE_LTS) via nvm..."
nvm install "$NODE_LTS"
nvm alias default "$NODE_LTS"
nvm use default
ok "Node installed: $(node -v)"

# Corepack for pnpm/yarn (Node >=16)
info "Enabling corepack..."
corepack enable || true
ok "corepack enabled."

# Install preferred package manager
case "$PKG_MGR" in
  pnpm)
    info "Activating pnpm..."
    corepack prepare pnpm@latest --activate || true
    ok "pnpm: $(pnpm -v)"
    ;;
  yarn)
    info "Activating yarn..."
    corepack prepare yarn@stable --activate || true
    ok "yarn: $(yarn -v)"
    ;;
  npm)
    ok "Using npm: $(npm -v)"
    ;;
  *)
    warn "Unknown PKG_MGR=$PKG_MGR. Falling back to pnpm."
    corepack prepare pnpm@latest --activate || true
    ;;
esac

# Recommended global utilities (kept minimal)
info "Installing common dev utilities (minimal)..."
# Use npm for global tools to avoid pnpm global store confusion across team
npm install -g npm@latest >/dev/null 2>&1 || true
npm install -g eslint prettier typescript ts-node >/dev/null 2>&1 || true
ok "Global tools installed: eslint, prettier, typescript, ts-node"

# Create sample React+TS app (Vite)
if [[ "$CREATE_SAMPLE_APP" == "true" ]]; then
  info "Creating sample React+TS app with Vite..."
  mkdir -p "$APP_DIR"
  cd "$APP_DIR"

  if [[ -d "$APP_NAME" ]]; then
    warn "Folder $APP_DIR/$APP_NAME already exists. Skipping project creation."
  else
    case "$PKG_MGR" in
      pnpm) pnpm create vite@latest "$APP_NAME" -- --template react-ts ;;
      yarn) yarn create vite "$APP_NAME" --template react-ts ;;
      npm)  npm create vite@latest "$APP_NAME" -- --template react-ts ;;
      *)    pnpm create vite@latest "$APP_NAME" -- --template react-ts ;;
    esac

    cd "$APP_NAME"

    info "Installing dependencies..."
    case "$PKG_MGR" in
      pnpm) pnpm install ;;
      yarn) yarn ;;
      npm)  npm install ;;
      *)    pnpm install ;;
    esac

    ok "Project created at: $APP_DIR/$APP_NAME"
  fi
fi

# Smoke test
info "Running environment checks..."
node -v
npm -v
command -v pnpm >/dev/null 2>&1 && pnpm -v || true
command -v yarn >/dev/null 2>&1 && yarn -v || true
tsc -v || true
ok "All checks completed."

cat << 'NEXT'

--------------------------------------------
NEXT STEPS (recommended)
1) Create your projects inside WSL filesystem:
   /home/<user>/projects
   (Avoid /mnt/c for performance)

2) Start a Vite React+TS app:
   cd ~/projects/my-react-ts-app
   pnpm dev

3) VS Code:
   Use the "Remote - WSL" extension and open the folder from WSL.
--------------------------------------------

NEXT

ok "Setup finished."

