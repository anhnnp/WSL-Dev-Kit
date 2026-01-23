### Cách chạy (khuyến nghị)

Tại repo root: `Set-ExecutionPolicy Bypass -Scope Process -Force .\golden-image\export-golden.ps1`

### Tuỳ chọn

    *   Xuất ra tên file cụ thể: `.\golden-image\export-golden.ps1 -OutputTar "ubuntu2204-golden.tar"`
    
    *   Không shutdown (không khuyến nghị): `.\golden-image\export-golden.ps1 -NoShutdown`