#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# env.sh
# Safe loader + helpers for setup.env
# - Avoids "source setup.env" (security + portability)
# - Exposes: env_load, env_get, env_required, env_bool, env_list
# =========================================================

# shellcheck disable=SC2154
ENV_LOADED=false
ENV_FILE_PATH=""

# Trim helpers
_env_trim() {
  local s="$1"
  # remove leading/trailing whitespace
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf "%s" "$s"
}

_env_strip_quotes() {
  local v="$1"
  if [[ "$v" =~ ^\".*\"$ ]]; then
    v="${v:1:${#v}-2}"
  elif [[ "$v" =~ ^\'.*\'$ ]]; then
    v="${v:1:${#v}-2}"
  fi
  printf "%s" "$v"
}

# Parse a single KEY=VALUE line safely (VALUE may contain '=')
_env_parse_line() {
  local line="$1"
  # remove CR for Windows CRLF
  line="${line%$'\r'}"

  # ignore empty or comment lines
  local trimmed="$(_env_trim "$line")"
  [[ -z "$trimmed" ]] && return 1
  [[ "$trimmed" == \#* ]] && return 1

  # Must contain '='
  [[ "$trimmed" != *"="* ]] && return 1

  local key="${trimmed%%=*}"
  local val="${trimmed#*=}"

  key="$(_env_trim "$key")"
  val="$(_env_trim "$val")"
  val="$(_env_strip_quotes "$val")"

  # Basic key validation: A-Z a-z 0-9 _
  if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    # invalid key - skip
    return 1
  fi

  printf "%s\0%s" "$key" "$val"
  return 0
}

env_load() {
  local path="$1"
  [[ -f "$path" ]] || { echo "[FAIL] Missing env file: $path" >&2; return 1; }

  ENV_FILE_PATH="$path"

  while IFS= read -r line || [[ -n "$line" ]]; do
    local parsed
    if parsed="$(_env_parse_line "$line")"; then
      local key val
      key="${parsed%%$'\0'*}"
      val="${parsed#*$'\0'}"

      # Respect existing environment variables (override policy):
      # If key already exported in environment, keep it. Else set from file.
      if [[ -z "${!key+x}" ]]; then
        export "$key=$val"
      fi
    fi
  done < "$path"

  ENV_LOADED=true
  return 0
}

env_require_loaded() {
  [[ "${ENV_LOADED}" == "true" ]] || { echo "[FAIL] Env not loaded. Call env_load <setup.env> first." >&2; return 1; }
}

env_get() {
  # usage: env_get KEY DEFAULT
  local key="$1"
  local def="${2:-}"
  if [[ -n "${!key:-}" ]]; then
    printf "%s" "${!key}"
  else
    printf "%s" "$def"
  fi
}

env_required() {
  # usage: env_required KEY
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "[FAIL] Missing required env key: $key (file: ${ENV_FILE_PATH:-unknown})" >&2
    return 1
  fi
}

env_bool() {
  # usage: env_bool KEY DEFAULT(true/false)
  # returns 0(true) or 1(false)
  local key="$1"
  local def="${2:-false}"
  local v
  v="$(env_get "$key" "$def")"
  v="$(printf "%s" "$v" | tr '[:upper:]' '[:lower:]')"

  case "$v" in
    1|true|yes|y|on)  return 0 ;;
    0|false|no|n|off) return 1 ;;
    *)                # unknown -> treat as default
      v="$(printf "%s" "$def" | tr '[:upper:]' '[:lower:]')"
      [[ "$v" == "true" || "$v" == "1" || "$v" == "yes" || "$v" == "y" || "$v" == "on" ]]
      ;;
  esac
}

env_list() {
  # usage: env_list KEY DEFAULT
  # prints items, one per line (comma-separated)
  local key="$1"
  local def="${2:-}"
  local raw
  raw="$(env_get "$key" "$def")"
  # remove spaces around commas
  raw="$(printf "%s" "$raw" | sed 's/[[:space:]]*,[[:space:]]*/,/g')"
  if [[ -z "$raw" ]]; then
    return 0
  fi
  IFS=',' read -r -a arr <<< "$raw"
  for item in "${arr[@]}"; do
    item="$(_env_trim "$item")"
    [[ -n "$item" ]] && printf "%s\n" "$item"
  done
}

env_resolve_toggle() {
  # usage: env_resolve_toggle KEY QUESTION DEFAULT(ask/true/false)
  # if value is ask -> prompt; returns 0=true or 1=false
  local key="$1"
  local question="$2"
  local def="${3:-ask}"

  local v
  v="$(env_get "$key" "$def")"
  v="$(printf "%s" "$v" | tr '[:upper:]' '[:lower:]')"

  case "$v" in
    true|yes|y)  return 0 ;;
    false|no|n)  return 1 ;;
    ask|*)
      read -rp "$question (y/N): " ans
      [[ "$(printf "%s" "$ans" | tr '[:upper:]' '[:lower:]')" == "y" ]]
      ;;
  esac
}