param(
  [Parameter(Mandatory=$true)][string]$DistroName,
  [Parameter(Mandatory=$true)][string]$TargetRoot
)

$ErrorActionPreference = "Stop"

function Info($m){ Write-Host "[INFO]  $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[OK]    $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[WARN]  $m" -ForegroundColor Yellow }

if (-not (Test-Path $TargetRoot)) { New-Item -ItemType Directory -Path $TargetRoot | Out-Null }

Info "Shutting down WSL..."
wsl.exe --shutdown | Out-Null

$safeName = ($DistroName -replace '[^\w\.\-]+','_')
$backupDir = Join-Path $TargetRoot "_backups"
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }

$tarPath = Join-Path $backupDir "${safeName}-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').tar"
$importDir = Join-Path $TargetRoot $safeName
if (-not (Test-Path $importDir)) { New-Item -ItemType Directory -Path $importDir | Out-Null }

Info "Exporting $DistroName -> $tarPath"
wsl.exe --export $DistroName $tarPath
Ok "Export done."

Info "Unregistering $DistroName (removes old instance)"
wsl.exe --unregister $DistroName
Ok "Unregister done."

Info "Importing $DistroName -> $importDir"
wsl.exe --import $DistroName $importDir $tarPath --version 2
Ok "Import done."

Info "WSL shutdown to finalize..."
wsl.exe --shutdown | Out-Null
Ok "Migration completed."