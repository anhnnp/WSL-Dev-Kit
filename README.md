# WSL Dev Kit (Windows 11 + WSL2 + Ubuntu 22.04)
Chuẩn hoá môi trường dev cho team PHP + NodeJS (React/Vue/TypeScript).  
Mục tiêu: 1 command setup, WSL luôn nằm ở D:\WSL hoặc E:\WSL, dễ clone/golden image.

---

## Requirements
- Windows 11
- PowerShell (Run as Administrator)
- D hoặc E còn trống (khuyến nghị)

---

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

Backup WSL: `wsl --export Ubuntu-22.04 D:\WSL\_backups\ubuntu2204.tar`

Restore: `wsl --import Ubuntu-22.04 D:\WSL\Ubuntu-22.04 D:\WSL\_backups\ubuntu2204.tar --version 2`