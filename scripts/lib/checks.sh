#!/usr/bin/env bash
set -euo pipefail

# scripts/lib/checks.sh
# Common health checks for WSL Dev Kit

_color() {
  local code="$1"; shift
  printf "\033[%sm%s\033[0m" "$code" "$*"
}
info(){ echo "$(_color 36 '[INFO]')  $*"; }
ok(){   echo "$(_color 32 '[OK]')    $*"; }
warn(){ echo "$(_color 33 '[WARN]')  $*"; }
fail(){ echo "$(_color 31 '[FAIL]')  $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

is_wsl() {
  grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null
}

ubuntu_version() {
  if have lsb_release; then
    lsb_release -rs 2>/dev/null || true
  elif [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "${VERSION_ID:-}"
  else
    echo ""
  fi
}

is_ubuntu_2204() {
  [[ "$(ubuntu_version)" == "22.04" ]]
}

is_windows_mount_path() {
  # true if path is under /mnt/<drive> (common Windows mount)
  local p="${1:-$PWD}"
  [[ "$p" =~ ^/mnt/[a-zA-Z]/ ]]
}

check_not_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    warn "You are running as root. Recommended: use your normal user for development."
    return 1
  fi
  ok "Running as non-root user: $(whoami)"
}

check_in_wsl() {
  if is_wsl; then
    ok "Running inside WSL."
  else
    fail "Not running inside WSL. This kit is intended for WSL Ubuntu."
    return 1
  fi
}

check_ubuntu_2204() {
  local v
  v="$(ubuntu_version)"
  if [[ -n "$v" ]]; then
    info "Ubuntu version detected: $v"
  fi

  if is_ubuntu_2204; then
    ok "Ubuntu 22.04 confirmed."
  else
    warn "Ubuntu is not 22.04 (detected: ${v:-unknown}). This kit targets Ubuntu 22.04."
    return 1
  fi
}

check_fs_location() {
  local p="${1:-$PWD}"
  if is_windows_mount_path "$p"; then
    warn "You are working under Windows mount: $p"
    warn "Best practice: keep repos under /home/<user>/projects for best performance."
    return 1
  else
    ok "Working directory is in Linux filesystem: $p"
  fi
}

check_systemd_enabled_hint() {
  # In WSL, systemd "enabled" means /etc/wsl.conf has [boot] systemd=true
  if [[ -f /etc/wsl.conf ]] && grep -qiE '^\s*\[boot\]' /etc/wsl.conf && grep -qiE '^\s*systemd\s*=\s*true' /etc/wsl.conf; then
    ok "systemd is configured in /etc/wsl.conf (takes effect after: wsl --shutdown)."
  else
    warn "systemd is not configured in /etc/wsl.conf. Recommended for Docker/services."
    return 1
  fi
}

check_disk_quick() {
  info "Disk usage (home + root):"
  df -h / /home 2>/dev/null || df -h 2>/dev/null || true
}

check_memory_quick() {
  info "Memory (free -h):"
  free -h 2>/dev/null || true
}

check_node_stack() {
  local okCount=0
  if have node; then ok "node: $(node -v)"; ((okCount++)); else warn "node not found."; fi
  if have npm;  then ok "npm:  $(npm -v)"; ((okCount++)); else warn "npm not found."; fi
  if have pnpm; then ok "pnpm: $(pnpm -v)"; ((okCount++)); else warn "pnpm not found."; fi
  if have yarn; then ok "yarn: $(yarn -v)"; ((okCount++)); else warn "yarn not found."; fi
  if have tsc;  then ok "tsc:  $(tsc -v)"; ((okCount++)); else warn "tsc not found."; fi
  return 0
}

check_php_stack() {
  if have php; then ok "php: $(php -v | head -n 1)"; else warn "php not found."; fi
  if have composer; then ok "composer: $(composer -V)"; else warn "composer not found."; fi
  if have switch-php; then ok "switch-php helper found."; else warn "switch-php not found (multi-php helper)."; fi
  return 0
}

summary_banner() {
  echo "------------------------------------------------------------"
  echo "$(_color 35 'WSL Dev Kit Checks')"
  echo "------------------------------------------------------------"
}

run_all_checks() {
  summary_banner

  local failed=0

  check_in_wsl || failed=1
  check_ubuntu_2204 || true
  check_not_root || true
  check_fs_location "$PWD" || true
  check_systemd_enabled_hint || true

  echo ""
  info "Tooling checks:"
  check_node_stack || true
  check_php_stack || true

  echo ""
  check_disk_quick || true
  check_memory_quick || true

  echo ""
  if [[ "$failed" -eq 0 ]]; then
    ok "Core checks done."
  else
    warn "Some core checks failed. See messages above."
  fi
  echo ""
}

# If executed directly: run checks
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_all_checks
fi