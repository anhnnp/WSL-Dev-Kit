# golden-image/export-golden.ps1
# Export a "golden" WSL image for the team (tar + manifest)
# Run PowerShell as Administrator (recommended)

param(
  [string]$EnvPath = "",
  [string]$OutputTar = "",
  [switch]$NoShutdown
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

# --- minimal env parser (same logic style as scripts/lib/env.ps1) ---
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
    # strip surrounding quotes
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
$nodeVersion = Get-Env $envMap "NODE_VERSION" "lts"
$phpVersions = Get-Env $envMap "PHP_VERSIONS" "8.1,8.2,8.3"
$phpDefault = Get-Env $envMap "PHP_DEFAULT" "8.2"

# --- choose golden output dir ---
$goldenDir = Get-Env $envMap "GOLDEN_DIR" (Join-Path $targetRoot "golden")
if (-not (Test-Path $goldenDir)) {
  Info "Creating golden dir: $goldenDir"
  New-Item -ItemType Directory -Path $goldenDir | Out-Null
}

# --- prepare tar name ---
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputTar)) {
  $OutputTar = Join-Path $goldenDir "$($distro)-golden-$ts.tar"
} else {
  # allow relative path
  if (-not [System.IO.Path]::IsPathRooted($OutputTar)) {
    $OutputTar = Join-Path $goldenDir $OutputTar
  }
}

# --- pre-flight checks ---
Info "Checking distro exists: $distro"
$distros = (& wsl.exe -l -q) 2>$null
if (-not $distros -or -not ($distros -contains $distro)) {
  Fail "WSL distro not found: $distro"
  Fail "Run scripts/setup-wsl.ps1 first, or verify name via: wsl -l -v"
  exit 1
}

# check disk free for output drive
$driveLetter = ($OutputTar.Substring(0,1)).ToUpper()
$drive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
if ($drive) {
  $freeGB = [math]::Round($drive.Free/1GB, 2)
  Info "Free space on $driveLetter`: = $freeGB GB"
  if ($freeGB -lt 10) {
    Warn "Low free space (<10GB). Export may fail if distro is large."
  }
}

# shutdown for consistency
if (-not $NoShutdown) {
  Info "Shutting down WSL for consistent export..."
  & wsl.exe --shutdown | Out-Null
  Ok "WSL shutdown."
} else {
  Warn "NoShutdown enabled. Export may be inconsistent if distro is active."
}

# --- export ---
Info "Exporting '$distro' -> $OutputTar"
& wsl.exe --export $distro $OutputTar
Ok "Export completed."

# --- write manifest ---
$manifest = @{
  exported_at = (Get-Date).ToString("o")
  distro_name = $distro
  dev_user    = $devUser
  node_policy = @{
    node_version = $nodeVersion
    pkg_manager  = (Get-Env $envMap "PKG_MANAGER" "pnpm")
  }
  php_policy  = @{
    php_versions = $phpVersions
    php_default  = $phpDefault
  }
  source_env  = @{
    TARGET_DRIVE = $targetDrive
    TARGET_ROOT  = $targetRootRel
    WSL_MEMORY   = Get-Env $envMap "WSL_MEMORY" ""
    WSL_CPUS     = Get-Env $envMap "WSL_CPUS" ""
    WSL_SWAP     = Get-Env $envMap "WSL_SWAP" ""
  }
}

$manifestPath = [System.IO.Path]::ChangeExtension($OutputTar, ".manifest.json")
Info "Writing manifest -> $manifestPath"
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding UTF8
Ok "Manifest written."

Write-Host ""
Ok "Golden export done."
Info "Tar:      $OutputTar"
Info "Manifest: $manifestPath"
Write-Host ""
Info "Next: share the .tar (and manifest) with the team, then run golden-image/import-golden.ps1 on new machines."