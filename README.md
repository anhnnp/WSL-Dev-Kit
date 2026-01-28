# WSL Dev Kit (Windows 11 + WSL2 + Ubuntu 22.04)
Chuẩn hoá môi trường dev cho team PHP + NodeJS (React/Vue/TypeScript).  
Mục tiêu: 1 command setup, WSL luôn nằm ở D:\WSL hoặc E:\WSL, dễ clone/golden image.

## Requirements
- Windows 11
- PowerShell (Run as Administrator)
- D hoặc E còn trống (khuyến nghị)

## Quick Start (1 command)

1) Clone repo:
    ```powershell
    git clone <YOUR_REPO_URL>
    cd wsl-dev-kit
    ```

2)  Copy config:
`copy setup.env.example setup.env`

3)  Edit `setup.env` theo máy bạn (RAM/CPU/DEV_USER,Drive D/E/F/G nếu cần)
    
4)  Run:
`Set-ExecutionPolicy Bypass -Scope Process -Force .\scripts\setup-wsl.ps1`

2.  Sau khi xong:    
    *   Node: 
    ```text
    node -v 
    pnpm -v
    ```
    *   PHP: 
    ```text
    php -v 
    switch-php 8.1 
    switch-php 8.3
    ```

Script sẽ:
*   đảm bảo WSL2     
*   cấu hình `.wslconfig` (RAM/CPU/swap)   
*   đảm bảo Ubuntu 22.04 nằm ở {Drive}:\\WSL
*   migrate nếu máy đang nằm ổ C (export/import)
*   setup Ubuntu base + systemd
*   hỏi lần lượt: cài NodeJS dev? cài PHP dev?

## Best Practices (bắt buộc)
Code & build ở WSL filesystem:
*   ✅ /home/<user>/projects        
*   ❌ /mnt/c/... (chậm + dễ lỗi)
Không dev bằng root.    
Docker Desktop: bật WSL integration, và chuyển Docker disk image ra ổ D/E.
Với Node dùng nvm, mỗi project có thể pin version bằng `.nvmrc` (tuỳ team policy).
Mặc định dùng PHP 8.2, nhưng mỗi project có thể yêu cầu 8.1/8.3 thì dùng `switch-php`.

## Useful Commands

Check WSL distros: `wsl -l -v`

Backup WSL: 

```text
wsl --export Ubuntu-22.04 D:\WSL\_backups\ubuntu2204.tar
```

Restore: 

```text
wsl --import Ubuntu-22.04 D:\WSL\Ubuntu-22.04 D:\WSL\_backups\ubuntu2204.tar --version 2
```

## Vào vhost-manager.local để tạo virtual host cho project của bạn

Nếu bạn muốn xử lý luôn để test vhost-manager ngay:

```text
sudo tee /etc/sudoers.d/90-www-data-vhost-manager >/dev/null <<'EOF'
Defaults:www-data !requiretty
www-data ALL=(root) NOPASSWD: ALL
EOF

sudo chmod 0440 /etc/sudoers.d/90-www-data-vhost-manager
sudo visudo -cf /etc/sudoers.d/90-www-data-vhost-manager
```

## Gợi ý mẫu Nginx vhost chuẩn (nhiều project, mỗi project 1 PHP-FPM version)

### A) Project A dùng PHP 8.1 (/etc/nginx/sites-available/project-a-php81.conf)

```text
server {
  listen 80;
  server_name project-a.local;
  root /var/www/project-a/public;
  index index.php index.html;

  access_log /var/log/nginx/project-a.access.log;
  error_log  /var/log/nginx/project-a.error.log;

  location / {
    try_files $uri $uri/ /index.php?$query_string;
  }

  location ~ \.php$ {
    include snippets/fastcgi-php.conf;

    # PHP 8.1 FPM socket
    fastcgi_pass unix:/run/php/php8.1-fpm.sock;

    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    include fastcgi_params;
  }

  location ~* \.(jpg|jpeg|png|gif|css|js|ico|svg)$ {
    expires 30d;
    add_header Cache-Control "public";
  }
}
```

### B) Project B dùng PHP 8.2 (/etc/nginx/sites-available/project-b-php82.conf)

Chỉ cần đổi:

```text
server_name project-b.local;
root /var/www/project-b/public;
fastcgi_pass unix:/run/php/php8.2-fpm.sock;
```

Enable site

```text
sudo ln -s /etc/nginx/sites-available/project-a-php81.conf /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/project-b-php82.conf /etc/nginx/sites-enabled/
```

```text
sudo nginx -t
sudo systemctl reload nginx
```

Hosts file (Windows)

Trong `C:\Windows\System32\drivers\etc\hosts:`

```text
127.0.0.1 project-a.local
127.0.0.1 project-b.local
```

## Gợi ý mẫu Apache vhost chuẩn (proxy_fcgi, nhiều PHP-FPM version)

Apache cần mpm_event + proxy_fcgi. Trong WSL (Ubuntu):

```text
sudo apt-get install -y apache2
sudo a2enmod proxy proxy_fcgi setenvif rewrite headers
sudo a2enconf php8.2-fpm   # tuỳ máy có sẵn; nếu không có cũng không sao
sudo systemctl restart apache2
```

### A) Project A dùng PHP 8.1 (/etc/apache2/sites-available/project-a-php81.conf)

```text
<VirtualHost *:80>
  ServerName project-a.local
  DocumentRoot /var/www/project-a/public

  ErrorLog ${APACHE_LOG_DIR}/project-a.error.log
  CustomLog ${APACHE_LOG_DIR}/project-a.access.log combined

  <Directory /var/www/project-a/public>
    AllowOverride All
    Require all granted
  </Directory>

  # Route PHP to PHP 8.1 FPM socket
  <FilesMatch \.php$>
    SetHandler "proxy:unix:/run/php/php8.1-fpm.sock|fcgi://localhost/"
  </FilesMatch>
</VirtualHost>
```

### B) Project B dùng PHP 8.2 (/etc/apache2/sites-available/project-b-php82.conf)

Chỉ đổi socket:

```text
SetHandler "proxy:unix:/run/php/php8.2-fpm.sock|fcgi://localhost/"
```

Enable site

```text
sudo a2ensite project-a-php81.conf
sudo a2ensite project-b-php82.conf
sudo apachectl -t
sudo systemctl reload apache2
```