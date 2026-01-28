#!/usr/bin/env bash
# scripts/setup-ubuntu.sh
set -euo pipefail

info(){ echo -e "\e[36m[INFO]\e[0m  $*"; }
ok(){   echo -e "\e[32m[OK]\e[0m    $*"; }
warn(){ echo -e "\e[33m[WARN]\e[0m  $*"; }
fail(){ echo -e "\e[31m[FAIL]\e[0m  $*"; }

# -----------------------------
# Inputs (from setup-wsl.ps1)
# -----------------------------
DEV_USER="${DEV_USER:-dev}"
ENABLE_SYSTEMD="${ENABLE_SYSTEMD:-true}"

# Normalize boolean-ish strings
to_bool() {
  local v="${1:-}"
  v="${v,,}" # lower
  case "$v" in
    1|true|t|yes|y|on) echo "true" ;;
    0|false|f|no|n|off|"") echo "false" ;;
    *) echo "false" ;;
  esac
}
ENABLE_SYSTEMD="$(to_bool "$ENABLE_SYSTEMD")"

# -----------------------------
# Safety checks
# -----------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  fail "This script must be run as root (it is invoked as root by setup-wsl.ps1)."
  warn "Try: sudo DEV_USER=dev ENABLE_SYSTEMD=true bash scripts/setup-ubuntu.sh"
  exit 1
fi

info "Ubuntu base setup. DEV_USER=$DEV_USER, ENABLE_SYSTEMD=$ENABLE_SYSTEMD"

# -----------------------------
# Base packages
# -----------------------------
export DEBIAN_FRONTEND=noninteractive

info "Updating apt indexes..."
apt-get update -y

info "Installing base packages..."
apt-get install -y --no-install-recommends \
  sudo ca-certificates curl wget git unzip zip \
  build-essential pkg-config jq htop tmux openssh-client \
  python3 python3-pip python3-venv \
  software-properties-common \
  lsb-release gnupg apt-transport-https

ok "Base packages installed."

# Ensure certs are up-to-date (helpful for curl/git)
update-ca-certificates >/dev/null 2>&1 || true

# -----------------------------
# Create dev user (idempotent)
# -----------------------------
if id "$DEV_USER" >/dev/null 2>&1; then
  ok "User $DEV_USER already exists."
else
  info "Creating user $DEV_USER ..."
  useradd -m -s /bin/bash "$DEV_USER"
  # Lock password (user will login via WSL default user or sudo)
  passwd -l "$DEV_USER" >/dev/null 2>&1 || true
  ok "User created."
fi

# Add to sudo group
usermod -aG sudo "$DEV_USER"
ok "Added $DEV_USER to sudo group."

# Optional: passwordless sudo for smoother dev experience
# Comment out if your org policy requires password prompts.
SUDOERS_D="/etc/sudoers.d"
SUDOERS_FILE="${SUDOERS_D}/99-${DEV_USER}-nopasswd"
mkdir -p "$SUDOERS_D"
if [[ ! -f "$SUDOERS_FILE" ]]; then
  info "Configuring passwordless sudo for $DEV_USER (can be removed later: $SUDOERS_FILE)..."
  echo "$DEV_USER ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
  chmod 0440 "$SUDOERS_FILE"
  ok "Passwordless sudo enabled for $DEV_USER."
else
  ok "Passwordless sudo already configured for $DEV_USER."
fi

# -----------------------------
# Recommended dev folders
# -----------------------------
DEV_HOME="$(getent passwd "$DEV_USER" | cut -d: -f6 || true)"
if [[ -n "$DEV_HOME" && -d "$DEV_HOME" ]]; then
  if [[ ! -d "$DEV_HOME/projects" ]]; then
    info "Creating $DEV_HOME/projects ..."
    mkdir -p "$DEV_HOME/projects"
    chown -R "$DEV_USER:$DEV_USER" "$DEV_HOME/projects"
    ok "Created $DEV_HOME/projects."
  else
    ok "$DEV_HOME/projects already exists."
  fi
else
  warn "Could not resolve home directory for $DEV_USER (skipping projects folder)."
fi

# -----------------------------
# systemd in WSL (optional)
# -----------------------------
if [[ "$ENABLE_SYSTEMD" == "true" ]]; then
  info "Enabling systemd in /etc/wsl.conf ..."
  mkdir -p /etc
  touch /etc/wsl.conf

  # If no [boot] section, append clean block.
  if ! grep -qE '^\s*\[boot\]\s*$' /etc/wsl.conf; then
    printf "\n[boot]\nsystemd=true\n" >> /etc/wsl.conf
  else
    # If boot section exists, ensure systemd=true is present somewhere after it.
    # Simple safe approach: if no systemd=true anywhere, append at end.
    if ! grep -qE '^\s*systemd\s*=\s*true\s*$' /etc/wsl.conf; then
      printf "\nsystemd=true\n" >> /etc/wsl.conf
    fi
  fi

  ok "systemd configured. It takes effect after Windows runs: wsl --shutdown"
else
  warn "Skipping systemd enable (ENABLE_SYSTEMD=$ENABLE_SYSTEMD)."
  warn "If you later need it: set ENABLE_SYSTEMD=true in setup.env and re-run setup."
fi

# -----------------------------
# Best-practice note (shown to users on login)
# -----------------------------
cat > /etc/profile.d/wsl-best-practices.sh <<'EOF'
# WSL best practices:
# - Keep projects inside WSL filesystem: /home/<user>/projects
# - Avoid heavy builds on /mnt/c (slow)
# - If you enable systemd in /etc/wsl.conf, it takes effect after: wsl --shutdown (run from Windows)
EOF
chmod 0644 /etc/profile.d/wsl-best-practices.sh

# -----------------------------
# Run health checks (best-effort)
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/lib/checks.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/checks.sh" || true
  run_all_checks || true
else
  warn "Missing checks file: $SCRIPT_DIR/lib/checks.sh (skipping checks)"
fi

echo ""
ok "Base Ubuntu setup done."
echo ""
info "Next steps:"
info "  - Close WSL terminals, then from Windows PowerShell run: wsl --shutdown"
info "  - Re-open '$DEV_USER' shell (or your distro) and continue with Node/PHP install steps if enabled."