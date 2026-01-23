<?php
// lib.php

function h($s) { return htmlspecialchars($s ?? '', ENT_QUOTES, 'UTF-8'); }

function cfg() {
  static $cfg = null;
  if ($cfg === null) $cfg = require __DIR__ . '/config.php';
  return $cfg;
}

function db() {
  static $pdo = null;
  if ($pdo) return $pdo;

  $pdo = new PDO('sqlite:' . cfg()['db_path']);
  $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

  // Schema
  $pdo->exec("
    CREATE TABLE IF NOT EXISTS sites (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      domain TEXT NOT NULL UNIQUE,
      server_type TEXT NOT NULL CHECK(server_type IN ('nginx')),
      php_version TEXT NOT NULL CHECK(php_version IN ('7.4','8.1','8.2')),
      source_path TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
  ");

  return $pdo;
}

function now_iso() { return gmdate('c'); }

function csrf_token() {
  $raw = session_id() . '|' . cfg()['csrf_secret'];
  return hash('sha256', $raw);
}
function csrf_check($t) { return hash_equals(csrf_token(), (string)$t); }

// -------------------- Validators --------------------

// Domain validation: cho phép .test / .local / domain thường
function validate_domain($domain) {
  $domain = strtolower(trim($domain));
  if ($domain === '') return [false, "Domain không hợp lệ. Ví dụ: myapp.test"];
  if (strlen($domain) > 253) return [false, "Domain quá dài."];

  // Cho phép a-z0-9- và dấu chấm, TLD >= 2
  if (!preg_match('/^(?=.{1,253}$)([a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/', $domain)) {
    return [false, "Domain không hợp lệ. Ví dụ: myapp.test"];
  }
  return [true, $domain];
}

function validate_php_version($v) {
  $v = trim((string)$v);
  if (!isset(cfg()['php_map'][$v])) return [false, "PHP version chỉ được: 7.4 / 8.1 / 8.2"];
  return [true, $v];
}

// BỎ allowed_source_roots: cho phép bất cứ đâu, miễn thư mục tồn tại
function validate_source_path(string $path): array {
  $path = trim($path);
  if ($path === '' || $path[0] !== '/') return [false, 'Source path phải là absolute path (bắt đầu bằng /)'];
  if (str_contains($path, "\0")) return [false, 'Source path không hợp lệ'];
  if (str_contains($path, '..')) return [false, 'Source path không hợp lệ (chứa ..)'];

  // Nếu folder không tồn tại thật
  if (!file_exists($path)) return [false, 'Thư mục source không tồn tại (file_exists=false)'];

  // Tồn tại nhưng không phải dir
  if (!is_dir($path)) return [false, 'Source path tồn tại nhưng không phải thư mục'];

  // Nếu www-data không traverse được, realpath thường fail
  $real = @realpath($path);
  if ($real === false) {
    return [false, 'Thư mục có thể tồn tại nhưng PHP-FPM (www-data) không có quyền truy cập (realpath=false). Hãy kiểm tra chmod/permission.'];
  }

  // Kiểm tra readable/executable
  if (!is_readable($real)) return [false, 'Thư mục không readable bởi user chạy PHP-FPM (www-data).'];
  if (!is_executable($real)) return [false, 'Thư mục không executable (traverse) bởi user chạy PHP-FPM (www-data).'];

  return [true, rtrim($real, '/')];
}

// -------------------- Paths --------------------

function vhost_filename($domain) { return $domain . '.conf'; }

function nginx_conf_available($domain) {
  return rtrim(cfg()['nginx_available'], '/') . '/' . vhost_filename($domain);
}
function nginx_conf_enabled($domain) {
  return rtrim(cfg()['nginx_enabled'], '/') . '/' . vhost_filename($domain);
}

// -------------------- Templates --------------------

function render_nginx_vhost($domain, $root, $phpSocket) {
  return <<<CONF
server {
  listen 80;
  server_name {$domain};

  root {$root};
  index index.php index.html;

  access_log off;
  error_log  /var/log/nginx/{$domain}.error.log;

  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location ~ \.php\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass {$phpSocket};
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include fastcgi_params;
  }

  location ~ /\.(?!well-known).* {
    deny all;
  }
}
CONF;
}

// -------------------- Exec helpers --------------------

function exec_available(): bool {
  $disabled = ini_get('disable_functions') ?: '';
  $disabled = array_map('trim', explode(',', $disabled));
  return !in_array('exec', $disabled, true);
}

function sh($cmd, &$out = null, &$code = null) {
  $output = [];
  $exit = 0;

  // Nếu exec bị disable, báo fail rõ ràng
  if (!exec_available()) {
    $out = "PHP exec() is disabled via disable_functions. Please enable exec for this app.\nCommand: {$cmd}";
    $code = 127;
    return false;
  }

  exec($cmd . ' 2>&1', $output, $exit);
  $out = implode("\n", $output);
  $code = $exit;
  return $exit === 0;
}

function sudo_can_run(&$log): bool {
  // -n: non-interactive, nếu cần password sẽ fail ngay
  $cmd = "sudo -n true";
  $ok = sh($cmd, $out, $code);
  $log .= "\n$cmd\n$out\n";
  return $ok;
}

function sudo_write_file($path, $content, &$log) {
  $b64 = base64_encode($content);
  $cmd = "printf %s " . escapeshellarg($b64) . " | base64 -d | sudo -n /usr/bin/tee " . escapeshellarg($path) . " >/dev/null";
  $ok = sh($cmd, $out, $code);
  $log .= "\n$cmd\n$out\n";
  return $ok;
}

function sudo_symlink_enable($available, $enabled, &$log) {
  $cmd = "sudo -n /bin/ln -sf " . escapeshellarg($available) . " " . escapeshellarg($enabled);
  $ok = sh($cmd, $out, $code);
  $log .= "\n$cmd\n$out\n";
  return $ok;
}

function sudo_remove($path, &$log) {
  $cmd = "sudo -n /bin/rm -f " . escapeshellarg($path);
  $ok = sh($cmd, $out, $code);
  $log .= "\n$cmd\n$out\n";
  return $ok;
}

// -------------------- Nginx actions with WSL fallback --------------------

function nginx_test(&$log) {
  $cmd = "sudo -n /usr/sbin/nginx -t";
  $ok = sh($cmd, $out, $code);
  $log .= "\n$cmd\n$out\n";
  return $ok;
}

function nginx_reload(&$log) {
  // 1) systemctl (nếu WSL bật systemd)
  $cmd = "sudo -n /bin/systemctl reload nginx";
  $ok = sh($cmd, $out, $code);
  $log .= "\n$cmd\n$out\n";
  if ($ok) return true;

  // 2) nginx -s reload
  $cmd2 = "sudo -n /usr/sbin/nginx -s reload";
  $ok2 = sh($cmd2, $out2, $code2);
  $log .= "\n$cmd2\n$out2\n";
  if ($ok2) return true;

  // 3) service nginx reload
  $cmd3 = "sudo -n /usr/sbin/service nginx reload";
  $ok3 = sh($cmd3, $out3, $code3);
  $log .= "\n$cmd3\n$out3\n";
  return $ok3;
}

// PHP-FPM reload/restart with WSL fallback
function php_fpm_reload(string $phpVersion, &$log) {
  $svc = cfg()['php_map'][$phpVersion]['service'] ?? null;
  if (!$svc) { $log .= "\nNo php service mapping.\n"; return false; }

  $cmd = "sudo -n /bin/systemctl reload " . escapeshellarg($svc);
  $ok = sh($cmd, $out, $code);
  $log .= "\n$cmd\n$out\n";
  if ($ok) return true;

  $cmd2 = "sudo -n /usr/sbin/service " . escapeshellarg($svc) . " reload";
  $ok2 = sh($cmd2, $out2, $code2);
  $log .= "\n$cmd2\n$out2\n";
  if ($ok2) return true;

  $cmd3 = "sudo -n /usr/sbin/service " . escapeshellarg($svc) . " restart";
  $ok3 = sh($cmd3, $out3, $code3);
  $log .= "\n$cmd3\n$out3\n";
  return $ok3;
}

// -------------------- /etc/hosts management --------------------

function hosts_entry_line($domain) {
  $tag = cfg()['hosts_tag'];
  return "127.0.0.1\t{$domain}\t# {$tag}";
}

function hosts_add_domain($domain, &$log) {
  $hosts = @file_get_contents('/etc/hosts');
  if ($hosts === false) { $log .= "\nCannot read /etc/hosts\n"; return false; }

  // Nếu đã có domain trong hosts (bất kể tag), coi như OK
  if (preg_match('/\s' . preg_quote($domain, '/') . '(\s|$)/', $hosts)) {
    $log .= "\n/etc/hosts already contains {$domain}\n";
    return true;
  }

  $newHosts = rtrim($hosts, "\n") . "\n" . hosts_entry_line($domain) . "\n";
  return sudo_write_file('/etc/hosts', $newHosts, $log);
}

function hosts_remove_domain($domain, &$log) {
  $hosts = @file_get_contents('/etc/hosts');
  if ($hosts === false) { $log .= "\nCannot read /etc/hosts\n"; return false; }

  $tag = cfg()['hosts_tag'];
  $lines = preg_split("/\r\n|\n|\r/", $hosts);
  $outLines = [];

  foreach ($lines as $ln) {
    $isOur = (str_contains($ln, "# {$tag}") && preg_match('/\s' . preg_quote($domain, '/') . '(\s|$)/', $ln));
    if ($isOur) continue;
    $outLines[] = $ln;
  }

  $newHosts = implode("\n", $outLines);
  if (!str_ends_with($newHosts, "\n")) $newHosts .= "\n";
  return sudo_write_file('/etc/hosts', $newHosts, $log);
}

// -------------------- Provision (auto apply) --------------------

function provision_site(array $site, string &$log): bool {
  $domain  = $site['domain'];
  $phpv    = $site['php_version'];
  $src     = $site['source_path'];
  $enabled = (int)$site['enabled'] === 1;

  $log .= "== Preflight ==\n";
  if (!sudo_can_run($log)) {
    $log .= "\nERROR: sudo NOPASSWD not configured for web user (likely www-data).\n";
    return false;
  }

  if (!is_dir(cfg()['nginx_available']) || !is_dir(cfg()['nginx_enabled'])) {
    $log .= "\nERROR: nginx sites-available/sites-enabled path not found. Check config.php.\n";
    return false;
  }

  if (!isset(cfg()['php_map'][$phpv])) {
    $log .= "\nERROR: php version mapping missing.\n";
    return false;
  }

  $phpSocket = cfg()['php_map'][$phpv]['socket'];

  $log .= "\n== Step 1: /etc/hosts ==\n";
  $ok = $enabled ? hosts_add_domain($domain, $log) : hosts_remove_domain($domain, $log);
  if (!$ok) return false;

  $log .= "\n== Step 2: write vhost + enable/disable ==\n";
  $avail = nginx_conf_available($domain);
  $enab  = nginx_conf_enabled($domain);
  $conf  = render_nginx_vhost($domain, $src, $phpSocket);

  $ok = sudo_write_file($avail, $conf, $log);
  if (!$ok) return false;

  if ($enabled) {
    $ok = sudo_symlink_enable($avail, $enab, $log);
  } else {
    $ok = sudo_remove($enab, $log);
  }
  if (!$ok) return false;

  $log .= "\n== Step 3: nginx -t & reload ==\n";
  $ok = nginx_test($log);
  if (!$ok) return false;

  $ok = nginx_reload($log);
  if (!$ok) return false;

  $log .= "\n== Step 4: reload PHP-FPM ==\n";
  $ok = php_fpm_reload($phpv, $log);
  if (!$ok) return false;

  return true;
}

function remove_site_provision(array $site, string &$log): bool {
  $domain  = $site['domain'];

  $log .= "== Preflight ==\n";
  if (!sudo_can_run($log)) {
    $log .= "\nERROR: sudo NOPASSWD not configured.\n";
    return false;
  }

  $log .= "\n== Step 1: remove hosts ==\n";
  $ok = hosts_remove_domain($domain, $log);
  if (!$ok) return false;

  $log .= "\n== Step 2: remove vhost files ==\n";
  $avail = nginx_conf_available($domain);
  $enab  = nginx_conf_enabled($domain);

  $ok = sudo_remove($enab, $log);
  if (!$ok) return false;

  $ok = sudo_remove($avail, $log);
  if (!$ok) return false;

  $log .= "\n== Step 3: nginx -t & reload ==\n";
  $ok = nginx_test($log);
  if (!$ok) return false;

  $ok = nginx_reload($log);
  if (!$ok) return false;

  return true;
}

