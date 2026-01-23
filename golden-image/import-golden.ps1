# golden-image/import-golden.ps1
# Import a "golden" WSL image tar into {TARGET_DRIVE}:\WSL and configure defaults
# Run PowerShell as Administrator (recommended)

param(
  [string]$EnvPath = "",
  [string]$TarPath = "",
  [switch]$SetAsDefault,
  [switch]$ForceOverwrite
)

$ErrorActionPreference = "Stop"

function Info($m){ Write-Host "[INFO]  $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[OK]    $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[WARN]  $m" -ForegroundColor Yellow }
function Fail($m){ Write-Host "[FAIL]  $m" -ForegroundColor Red }

# --- locate repo root and setup.env ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

if ([string]::IsNullOrWhiteSpace($EnvPath)) {
  $EnvPath = Join-Path $repoRoot "setup.env"
}
if (-not (Test-Path $EnvPath)) {
  Fail "Missing env file: $EnvPath"
  Fail "Tip: copy setup.env.example -> setup.env and edit."
  exit 1
}

# --- minimal env parser ---
function Read-EnvFile([string]$Path) {
  $map = @{}
  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0) { return }
    if ($line.StartsWith("#")) { return }
    $idx = $line.IndexOf("=")
    if ($idx -lt 1) { return }
    $k = $line.Substring(0, $idx).Trim()
    $v = $line.Substring($idx + 1).Trim()
    if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
      $v = $v.Substring(1, $v.Length - 2)
    }
    $map[$k] = $v
  }
  return $map
}
function Get-Env($envMap, [string]$Key, [string]$Default="") {
  if ($envMap.ContainsKey($Key) -and $envMap[$Key].Trim().Length -gt 0) { return $envMap[$Key].Trim() }
  return $Default
}

$envMap = Read-EnvFile $EnvPath

$distro = Get-Env $envMap "DISTRO_NAME" "Ubuntu-22.04"
$targetDrive = (Get-Env $envMap "TARGET_DRIVE" "D").TrimEnd(":").ToUpper()
$targetRootRel = Get-Env $envMap "TARGET_ROOT" "\WSL"
$targetRoot = "${targetDrive}:$targetRootRel"
$devUser = Get-Env $envMap "DEV_USER" "dev"

if (-not (Test-Path $targetRoot)) {
  Info "Creating target root: $targetRoot"
  New-Item -ItemType Directory -Path $targetRoot | Out-Null
}

# --- resolve tar path ---
if ([string]::IsNullOrWhiteSpace($TarPath)) {
  $TarPath = Read-Host "Enter path to golden .tar (e.g. D:\WSL\golden\Ubuntu-22.04-golden-YYYYMMDD-HHMMSS.tar)"
}
if ([string]::IsNullOrWhiteSpace($TarPath)) {
  Fail "No tar path provided."
  exit 1
}
if (-not (Test-Path $TarPath)) {
  Fail "Tar not found: $TarPath"
  exit 1
}

# --- prepare import dir ---
$safeName = ($distro -replace '[^\w\.\-]+','_')
$importDir = Join-Path $targetRoot $safeName

# If distro exists, confirm overwrite
$existingDistros = (& wsl.exe -l -q) 2>$null
$alreadyInstalled = $false
if ($existingDistros) { $alreadyInstalled = ($existingDistros -contains $distro) }

if ($alreadyInstalled) {
  Warn "Distro already installed: $distro"
  if (-not $ForceOverwrite) {
    $ans = Read-Host "Overwrite existing distro (this will unregister and re-import)? (y/N)"
    if ($ans.Trim().ToLower() -ne "y") {
      Warn "Aborted by user."
      exit 0
    }
  }
  Info "Shutting down WSL..."
  & wsl.exe --shutdown | Out-Null

  Info "Unregistering existing distro: $distro"
  & wsl.exe --unregister $distro
  Ok "Unregistered."
}

# Ensure importDir exists & is empty-ish
if (Test-Path $importDir) {
  if (-not $ForceOverwrite) {
    # If contains ext4.vhdx or any files, warn
    $items = Get-ChildItem -Path $importDir -ErrorAction SilentlyContinue
    if ($items -and $items.Count -gt 0) {
      Warn "Import folder not empty: $importDir"
      $ans2 = Read-Host "Continue and overwrite files in import folder? (y/N)"
      if ($ans2.Trim().ToLower() -ne "y") {
        Warn "Aborted by user."
        exit 0
      }
    }
  }
} else {
  New-Item -ItemType Directory -Path $importDir | Out-Null
}

# Shutdown WSL before import
Info "Shutting down WSL..."
& wsl.exe --shutdown | Out-Null
Ok "WSL shutdown."

# Import
Info "Importing $distro -> $importDir"
& wsl.exe --import $distro $importDir $TarPath --version 2
Ok "Import completed."

# Set default distro (auto if SetAsDefault or env says so)
if ($SetAsDefault) {
  Info "Setting default distro: $distro"
  & wsl.exe --set-default $distro
  Ok "Default distro set."
} else {
  $ansDef = Read-Host "Set '$distro' as default WSL distro? (y/N)"
  if ($ansDef.Trim().ToLower() -eq "y") {
    & wsl.exe --set-default $distro
    Ok "Default distro set."
  }
}

# Best-effort set default user for Store Ubuntu launchers
function TrySetDefaultUser($distroName, $userName) {
  if ([string]::IsNullOrWhiteSpace($userName)) { return }

  $launcher = $null
  switch -Regex ($distroName) {
    "^Ubuntu-22\.04$" { $launcher = "ubuntu2204.exe"; break }
    "^Ubuntu-24\.04$" { $launcher = "ubuntu2404.exe"; break }
    "^Ubuntu$"        { $launcher = "ubuntu.exe"; break }
    default           { $launcher = $null; break }
  }

  if ($launcher) {
    try {
      Info "Setting default user via $launcher -> $userName"
      & $launcher config --default-user $userName | Out-Null
      Ok "Default user set to '$userName'."
      return
    } catch {
      Warn "Could not set default user via $launcher."
    }
  } else {
    Warn "Unknown launcher for distro '$distroName'."
  }

  Warn "Fallback: create shortcut target:"
  Warn "  C:\Windows\System32\wsl.exe -d $distroName -u $userName"
}

# Ask to set default user
$ansUser = Read-Host "Set default WSL user to '$devUser'? (y/N)"
if ($ansUser.Trim().ToLower() -eq "y") {
  TrySetDefaultUser -distroName $distro -userName $devUser
}

# Verify inside WSL (best-effort)
Info "Verifying inside WSL..."
try {
  & wsl.exe -d $distro -- bash -lc "echo 'whoami=' && whoami && echo 'uname=' && uname -a" | Out-Host
  & wsl.exe -d $distro -- bash -lc "command -v node >/dev/null 2>&1 && node -v || echo 'node not installed'" | Out-Host
  & wsl.exe -d $distro -- bash -lc "command -v pnpm >/dev/null 2>&1 && pnpm -v || echo 'pnpm not installed'" | Out-Host
  & wsl.exe -d $distro -- bash -lc "php -v 2>/dev/null | head -n 1 || echo 'php not installed'" | Out-Host
  & wsl.exe -d $distro -- bash -lc "composer -V 2>/dev/null || echo 'composer not installed'" | Out-Host
} catch {
  Warn "Verification had issues. You can manually open WSL and run: node -v ; php -v"
}

# final shutdown
Info "Final WSL shutdown..."
& wsl.exe --shutdown | Out-Null
Ok "Done."

Write-Host ""
Ok "Golden import complete."
Info "Distro:     $distro"
Info "Imported to: $importDir"
Info "Tar used:    $TarPath"
Write-Host ""
Info "Open from Start Menu or run:"
Info "  wsl -d $distro"
if (-not [string]::IsNullOrWhiteSpace($devUser)) {
  Info "Or to force user:"
  Info "  wsl -d $distro -u $devUser"
}