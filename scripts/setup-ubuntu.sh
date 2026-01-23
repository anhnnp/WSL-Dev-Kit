#!/usr/bin/env bash
set -euo pipefail

info(){ echo -e "\e[36m[INFO]\e[0m  $*"; }
ok(){ echo -e "\e[32m[OK]\e[0m    $*"; }
warn(){ echo -e "\e[33m[WARN]\e[0m  $*"; }

DEV_USER="${DEV_USER:-dev}"

info "Ubuntu base setup. DEV_USER=$DEV_USER"

# Ensure base packages
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y sudo ca-certificates curl wget git unzip zip \
  build-essential pkg-config jq htop tmux openssh-client \
  python3 python3-pip python3-venv software-properties-common

ok "Base packages installed."

# Create user if missing
if id "$DEV_USER" >/dev/null 2>&1; then
  ok "User $DEV_USER already exists."
else
  info "Creating user $DEV_USER ..."
  useradd -m -s /bin/bash "$DEV_USER"
  passwd -l "$DEV_USER" >/dev/null 2>&1 || true
  ok "User created."
fi

usermod -aG sudo "$DEV_USER"
ok "Added $DEV_USER to sudo group."

# Enable systemd (safe)
info "Enabling systemd..."
mkdir -p /etc
touch /etc/wsl.conf
if ! grep -q '^\[boot\]' /etc/wsl.conf; then
  printf "\n[boot]\nsystemd=true\n" >> /etc/wsl.conf
else
  # ensure systemd=true somewhere
  grep -q '^systemd=true' /etc/wsl.conf || printf "systemd=true\n" >> /etc/wsl.conf
fi
ok "systemd enabled (takes effect after wsl --shutdown)."

# Best-practice note file
cat > /etc/profile.d/wsl-best-practices.sh <<'EOF'
# Best practices:
# - Keep projects inside WSL filesystem: /home/<user>/projects
# - Avoid heavy builds on /mnt/c (slow)
EOF

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/checks.sh" || true
run_all_checks || true

ok "Base Ubuntu setup done."