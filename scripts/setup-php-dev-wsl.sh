#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Multi-PHP Dev Setup for WSL Ubuntu 22.04 (Windows host)
# Stack: Nginx + PHP-FPM (8.1/8.2/8.3) + Laravel + WordPress
# DB: MariaDB/MySQL
# Repo: Ondrej PHP PPA
# ------------------------------------------------------------

# ---- Helpers ----
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m"

log()  { echo -e "${GREEN}==> ${NC}$*"; }
warn() { echo -e "${YELLOW}==> ${NC}$*"; }
err()  { echo -e "${RED}==> ${NC}$*" 1>&2; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Vui lòng chạy script bằng sudo: sudo bash setup-php-dev-wsl.sh"
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---- Start ----
need_root

log "Cập nhật apt + cài tool nền tảng..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release software-properties-common apt-transport-https

# ---- Ondrej PPA (safe add) ----
if ! grep -R "ondrej/php" -n /etc/apt/sources.list /etc/apt/sources.list.d/*.list >/dev/null 2>&1; then
  log "Thêm Ondřej PHP PPA..."
  add-apt-repository -y ppa:ondrej/php
else
  log "Ondřej PHP PPA đã tồn tại, bỏ qua."
fi

log "Cập nhật apt sau khi có PPA..."
apt-get update -y

# ---- Core tools ----
log "Cài công cụ dev: git, zip/unzip, composer, nodejs/npm, supervisor..."
apt-get install -y git unzip zip composer nodejs npm supervisor

# ---- Web server ----
log "Cài Nginx..."
apt-get install -y nginx nginx-extras

# ---- DB (MariaDB) ----
log "Cài MariaDB server/client..."
apt-get install -y mariadb-server mariadb-client

# ---- PHP versions ----
PHP_VERSIONS=("8.1" "8.2" "8.3")

# ---- Extensions sets ----
# Core for Laravel + WordPress
EXT_CORE=(
  "common" "cli" "fpm"
  "bcmath" "curl" "mbstring" "intl" "zip" "xml" "gd" "mysql" "soap" "opcache" "readline"
)

# Recommended extras
EXT_EXTRA=(
  "imagick" "redis" "memcached"
)

# Optional (debug)
EXT_DEBUG=(
  "xdebug"
)

log "Cài PHP multi-version + extensions (Laravel + WordPress)..."
pkgs=()
for v in "${PHP_VERSIONS[@]}"; do
  for e in "${EXT_CORE[@]}"; do
    pkgs+=("php${v}-${e}")
  done
  for e in "${EXT_EXTRA[@]}"; do
    pkgs+=("php${v}-${e}")
  done
  for e in "${EXT_DEBUG[@]}"; do
    pkgs+=("php${v}-${e}")
  done
done

# Install everything in one apt call
apt-get install -y "${pkgs[@]}"

# ---- Enable + restart FPM services ----
log "Enable & restart php-fpm services..."
for v in "${PHP_VERSIONS[@]}"; do
  systemctl enable --now "php${v}-fpm" >/dev/null 2>&1 || true
  systemctl restart "php${v}-fpm" || true
done

log "Restart/reload nginx..."
systemctl enable --now nginx >/dev/null 2>&1 || true
nginx -t
systemctl reload nginx || systemctl restart nginx

# ---- WP-CLI ----
log "Cài WP-CLI..."
if ! have_cmd wp; then
  tmp="/tmp/wp-cli.phar"
  curl -fsSL -o "${tmp}" https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  php "${tmp}" --info >/dev/null
  chmod +x "${tmp}"
  mv "${tmp}" /usr/local/bin/wp
else
  log "WP-CLI đã có sẵn, bỏ qua."
fi

# ---- Convenience: ensure mariadb is up ----
log "Enable & start MariaDB..."
systemctl enable --now mariadb >/dev/null 2>&1 || true
systemctl restart mariadb || true

# ---- Summary / Checklist ----
echo
echo "============================================================"
echo -e "${GREEN}✅ SETUP HOÀN TẤT: PHP Dev Environment (Laravel + WordPress)${NC}"
echo "============================================================"
echo

# WSL detection (best-effort)
if grep -qi microsoft /proc/version 2>/dev/null; then
  echo -e "WSL: ${GREEN}Yes${NC}  (detected)"
else
  echo -e "WSL: ${YELLOW}Unknown${NC}"
fi

echo
echo "---- Versions ----"
echo -n "PHP (CLI): "; php -v | head -n 1 || true
echo -n "Composer: "; composer --version 2>/dev/null || true
echo -n "Nginx: "; nginx -v 2>&1 || true
echo -n "Node: "; node -v 2>/dev/null || true
echo -n "NPM: "; npm -v 2>/dev/null || true
echo -n "WP-CLI: "; wp --version 2>/dev/null || true
echo -n "MariaDB: "; mariadb --version 2>/dev/null || mysql --version 2>/dev/null || true

echo
echo "---- Services ----"
for svc in nginx mariadb php8.1-fpm php8.2-fpm php8.3-fpm; do
  state="$(systemctl is-active "${svc}" 2>/dev/null || true)"
  if [[ "${state}" == "active" ]]; then
    echo -e "${svc}: ${GREEN}${state}${NC}"
  else
    echo -e "${svc}: ${YELLOW}${state}${NC}"
  fi
done

echo
echo "---- PHP-FPM sockets ----"
ls -lah /run/php/ 2>/dev/null | egrep "php(8\.1|8\.2|8\.3)-fpm\.sock" || echo "(Không thấy socket trong /run/php - kiểm tra service php-fpm)"

echo
echo "---- Extension checklist (dom/xml/mbstring/curl/zip/gd/imagick/intl/mysqli/pdo_mysql/opcache/redis) ----"
check_exts='dom|xml|mbstring|curl|zip|gd|imagick|intl|mysqli|pdo_mysql|opcache|redis'
echo "[CLI]"; php -m | egrep "${check_exts}" | sort -u || true

for v in "${PHP_VERSIONS[@]}"; do
  echo
  echo "[FPM ${v}]"
  if have_cmd "php-fpm${v}"; then
    "php-fpm${v}" -m | egrep "${check_exts}" | sort -u || true
    echo -n "Loaded php.ini: "
    "php-fpm${v}" -i 2>/dev/null | grep -i "Loaded Configuration File" | head -n 1 || true
  else
    echo "php-fpm${v} not found"
  fi
done

echo
echo "---- Next steps (gợi ý) ----"
cat <<'TXT'
1) Map vhost Nginx -> đúng socket:
   fastcgi_pass unix:/run/php/php8.2-fpm.sock;  (hoặc 8.1/8.3 tuỳ dự án)

2) Nếu composer vẫn báo thiếu ext ở dự án nào:
   - kiểm tra đúng FPM version đang chạy cho vhost đó
   - kiểm tra module: php-fpm8.x -m

3) (Tuỳ chọn) Bật/Config Xdebug chỉ khi cần debug để tránh chậm.
TXT

echo
echo -e "${GREEN}✅ Ready for Laravel + WordPress development on WSL Ubuntu 22.04.${NC}"