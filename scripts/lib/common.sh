#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# common.sh
# Shared helpers for WSL Dev Kit bash scripts
# =========================================================

# ---------- Colors & logging ----------
_color() {
  local code="$1"; shift
  printf "\033[%sm%s\033[0m" "$code" "$*"
}

log_info()  { echo "$(_color 36 '[INFO]')  $*"; }
log_ok()    { echo "$(_color 32 '[OK]')    $*"; }
log_warn()  { echo "$(_color 33 '[WARN]')  $*"; }
log_fail()  { echo "$(_color 31 '[FAIL]')  $*"; }

die() {
  log_fail "$*"
  exit 1
}

# ---------- Command helpers ----------
have() { command -v "$1" >/dev/null 2>&1; }

run() {
  log_info "RUN: $*"
  "$@"
}

run_quiet() {
  "$@" >/dev/null 2>&1
}

run_if_missing() {
  # usage: run_if_missing <command> <install-cmd...>
  local check="$1"; shift
  if have "$check"; then
    log_ok "'$check' already exists"
  else
    log_info "Installing missing command: $check"
    "$@"
  fi
}

# ---------- Sudo helpers ----------
is_root() { [[ "$(id -u)" -eq 0 ]]; }

as_root() {
  if is_root; then
    "$@"
  else
    sudo "$@"
  fi
}

require_root() {
  is_root || die "This action requires root privileges."
}

# ---------- OS / WSL detection ----------
is_wsl() {
  grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null
}

require_wsl() {
  is_wsl || die "This script must be run inside WSL."
}

ubuntu_version() {
  if have lsb_release; then
    lsb_release -rs 2>/dev/null || true
  elif [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${VERSION_ID:-}"
  else
    echo ""
  fi
}

is_ubuntu_2204() {
  [[ "$(ubuntu_version)" == "22.04" ]]
}

# ---------- Filesystem helpers ----------
is_windows_mount() {
  # true if path under /mnt/<drive>
  local p="${1:-$PWD}"
  [[ "$p" =~ ^/mnt/[a-zA-Z]/ ]]
}

expand_path() {
  # expand ~ and variables safely
  local p="$1"
  echo "${p/#\~/$HOME}"
}

ensure_dir() {
  local d="$1"
  [[ -d "$d" ]] || mkdir -p "$d"
}

# ---------- setup.env loader ----------
ENV_LOADED=false

load_env() {
  local env_file="$1"

  [[ -f "$env_file" ]] || die "Missing env file: $env_file"

  log_info "Loading env from: $env_file"

  while IFS='=' read -r key value; do
    key="$(echo "$key" | xargs)"
    value="$(echo "$value" | xargs)"
    [[ -z "$key" ]] && continue
    [[ "$key" == \#* ]] && continue
    export "$key=$value"
  done < "$env_file"

  ENV_LOADED=true
  log_ok "Env loaded."
}

require_env() {
  [[ "$ENV_LOADED" == "true" ]] || die "Env not loaded. Call load_env first."
}

env_default() {
  # usage: env_default VAR DEFAULT
  local var="$1"
  local def="$2"
  if [[ -z "${!var:-}" ]]; then
    export "$var=$def"
  fi
}

# ---------- ask / true / false resolver ----------
resolve_toggle() {
  # usage: resolve_toggle <value> <question>
  # value: ask | true | false
  local v="${1:-ask}"
  local q="$2"

  v="$(echo "$v" | tr '[:upper:]' '[:lower:]')"

  case "$v" in
    true|yes|y)  return 0 ;;
    false|no|n)  return 1 ;;
    ask|*)
      read -rp "$q (y/N): " ans
      [[ "$(echo "$ans" | tr '[:upper:]' '[:lower:]')" == "y" ]]
      ;;
  esac
}

# ---------- Package helpers ----------
apt_install() {
  require_root
  log_info "apt install: $*"
  apt-get install -y "$@"
}

apt_update_once() {
  require_root
  if [[ -z "${_APT_UPDATED:-}" ]]; then
    log_info "apt update"
    apt-get update -y
    export _APT_UPDATED=true
  fi
}

# ---------- User helpers ----------
ensure_user() {
  local user="$1"
  if id "$user" >/dev/null 2>&1; then
    log_ok "User exists: $user"
  else
    require_root
    log_info "Creating user: $user"
    useradd -m -s /bin/bash "$user"
    passwd -l "$user" >/dev/null 2>&1 || true
    log_ok "User created: $user"
  fi
}

ensure_sudo() {
  local user="$1"
  require_root
  usermod -aG sudo "$user"
  log_ok "User '$user' added to sudo group."
}

# ---------- Version helpers ----------
version_ge() {
  # usage: version_ge 8.2 8.1  -> true
  printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# ---------- Banner ----------
banner() {
  echo "============================================================"
  echo "$(_color 35 "$1")"
  echo "============================================================"
}