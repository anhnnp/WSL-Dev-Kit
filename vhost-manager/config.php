<?php
// config.php (DEV) - no login, auto provision on Create/Save

return [
  // Default selections
  'default_server_type' => 'nginx',
  'default_php_version' => '8.1',

  // Nginx paths
  'nginx_available' => '/etc/nginx/sites-available',
  'nginx_enabled'   => '/etc/nginx/sites-enabled',

  // PHP version mapping (Ubuntu 22.04)
  'php_map' => [
    '7.4' => [
      'service' => 'php7.4-fpm',
      'socket'  => 'unix:/run/php/php7.4-fpm.sock',
    ],
    '8.1' => [
      'service' => 'php8.1-fpm',
      'socket'  => 'unix:/run/php/php8.1-fpm.sock',
    ],
    '8.2' => [
      'service' => 'php8.2-fpm',
      'socket'  => 'unix:/run/php/php8.2-fpm.sock',
    ],
  ],

  // DB (SQLite)
  'db_path' => __DIR__ . '/data.sqlite',

  // CSRF secret (giữ lại dù không login, vì form vẫn nên có CSRF)
  'csrf_secret' => 'dev-secret-change-me',

  // Hosts tag để app quản lý dòng /etc/hosts
  'hosts_tag' => 'vhost-manager',
];

