$ErrorActionPreference = "Stop"

function Info($m){ Write-Host "[INFO]  $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[OK]    $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[WARN]  $m" -ForegroundColor Yellow }
function Fail($m){ Write-Host "[FAIL]  $m" -ForegroundColor Red }

# Admin check
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Fail "Please run PowerShell as Administrator."
  exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "lib\env.ps1")
. (Join-Path $scriptDir "lib\prompts.ps1")

$repoRoot = Split-Path -Parent $scriptDir
$envPath = Join-Path $repoRoot "setup.env"
if (-not (Test-Path $envPath)) {
  Fail "Missing setup.env. Copy from setup.env.example and edit first."
  exit 1
}

$envMap = Read-EnvFile $envPath

$distro = Get-Env $envMap "DISTRO_NAME" "Ubuntu-22.04"
$devUser = Get-Env $envMap "DEV_USER" "dev"
$targetDrive = (Get-Env $envMap "TARGET_DRIVE" "D").TrimEnd(":").ToUpper()
$targetRootRel = Get-Env $envMap "TARGET_ROOT" "\WSL"
$targetRoot = "${targetDrive}:$targetRootRel"

$wslMem = Get-Env $envMap "WSL_MEMORY" "8GB"
$wslCpus = Get-Env $envMap "WSL_CPUS" "6"
$wslSwap = Get-Env $envMap "WSL_SWAP" "2GB"
$swapDrive = (Get-Env $envMap "WSL_SWAP_DRIVE" $targetDrive).TrimEnd(":").ToUpper()

$autoMigrate = (Get-Env $envMap "AUTO_MIGRATE_IF_ON_C" "true").ToLower() -eq "true"

$installNodeSetting = Get-Env $envMap "INSTALL_NODEJS" "ask"
$installPhpSetting  = Get-Env $envMap "INSTALL_PHP" "ask"

# ensure target root exists
if (-not (Test-Path $targetRoot)) { New-Item -ItemType Directory -Path $targetRoot | Out-Null }

# Write .wslconfig
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$swapFile = "${swapDrive}:\WSL\swap.vhdx"
if (-not (Test-Path "${swapDrive}:\WSL")) { New-Item -ItemType Directory -Path "${swapDrive}:\WSL" | Out-Null }

Info "Writing .wslconfig -> $wslConfigPath"
@"
[wsl2]
memory=$wslMem
processors=$wslCpus
swap=$wslSwap
swapFile=$swapFile
localhostForwarding=true
"@ | Set-Content -Path $wslConfigPath -Encoding ASCII

Ok ".wslconfig updated."
Info "Shutting down WSL..."
wsl.exe --shutdown | Out-Null

# Ensure WSL installed & default v2
Info "Ensuring WSL2 default..."
wsl.exe --set-default-version 2 | Out-Null

# Ensure distro exists (install if missing)
$distros = (& wsl.exe -l -q) 2>$null
if (-not $distros -or -not ($distros -contains $distro)) {
  Warn "$distro not found. Installing..."
  wsl.exe --install -d $distro | Out-Null
  Ok "Install triggered. If Windows asks reboot, reboot then re-run this script."
}

# Decide if migrate needed (best-effort heuristic)
# If distro already imported to targetRoot, ext4.vhdx should exist there.
$safeName = ($distro -replace '[^\w\.\-]+','_')
$expectedVhd = Join-Path (Join-Path $targetRoot $safeName) "ext4.vhdx"

if ($autoMigrate -and -not (Test-Path $expectedVhd)) {
  Warn "Distro '$distro' is NOT detected under $targetRoot (expected: $expectedVhd)."
  $doMigrate = Resolve-AskToggle -Value "ask" -Question "Migrate '$distro' to $targetRoot now (export/import) to avoid filling C:?"
  if ($doMigrate) {
    Info "Running migration..."
    & (Join-Path $scriptDir "migrate-wsl.ps1") -DistroName $distro -TargetRoot $targetRoot
  } else {
    Warn "Skipped migration. Note: disk may remain on C:."
  }
} else {
  Ok "Distro appears to be located under target root (or auto migrate disabled)."
}

# Copy ubuntu scripts into WSL and run
$setupUbuntu = Join-Path $scriptDir "setup-ubuntu.sh"
if (-not (Test-Path $setupUbuntu)) { throw "Missing: $setupUbuntu" }

# push setup-ubuntu.sh
Info "Running setup-ubuntu.sh inside WSL..."
$bashCmd = "cat > /tmp/setup-ubuntu.sh << 'EOF'
$(Get-Content -Raw $setupUbuntu)
EOF
chmod +x /tmp/setup-ubuntu.sh
DEV_USER='$devUser' bash /tmp/setup-ubuntu.sh
"
wsl.exe -d $distro -u root -- bash -lc $bashCmd
Ok "Base Ubuntu setup done."

# Prompt Node then PHP
$installNode = Resolve-AskToggle -Value $installNodeSetting -Question "Install NodeJS dev environment (nvm + LTS + pnpm + TS tooling)?"
if ($installNode) {
  $nodeScript = Join-Path $scriptDir "setup-node-dev-wsl.sh"
  if (-not (Test-Path $nodeScript)) { throw "Missing: $nodeScript" }

  $nodeVersion = Get-Env $envMap "NODE_VERSION" "lts"
  $pkgMgr = Get-Env $envMap "PKG_MANAGER" "pnpm"
  $installTs = Get-Env $envMap "INSTALL_GLOBAL_TS_TOOLS" "true"
  $createApp = Get-Env $envMap "CREATE_SAMPLE_APP" "false"
  $appName = Get-Env $envMap "SAMPLE_APP_NAME" "my-react-ts-app"
  $appDir  = Get-Env $envMap "SAMPLE_APP_DIR" "~/projects"

  Info "Installing NodeJS dev stack..."
  $bashNode = "cat > /tmp/setup-node-dev-wsl.sh << 'EOF'
$(Get-Content -Raw $nodeScript)
EOF
chmod +x /tmp/setup-node-dev-wsl.sh
DEV_USER='$devUser' NODE_VERSION='$nodeVersion' PKG_MANAGER='$pkgMgr' INSTALL_GLOBAL_TS_TOOLS='$installTs' CREATE_SAMPLE_APP='$createApp' SAMPLE_APP_NAME='$appName' SAMPLE_APP_DIR='$appDir' bash /tmp/setup-node-dev-wsl.sh
"
  wsl.exe -d $distro -- bash -lc $bashNode
  Ok "NodeJS dev environment installed."
} else {
  Warn "Skipped NodeJS install."
}

$installPhp = Resolve-AskToggle -Value $installPhpSetting -Question "Install PHP dev environment (multi versions 8.1/8.2/8.3, default 8.2)?"
if ($installPhp) {
  $phpScript = Join-Path $scriptDir "setup-php-dev-wsl.sh"
  if (-not (Test-Path $phpScript)) { throw "Missing: $phpScript" }

  $phpVers = Get-Env $envMap "PHP_VERSIONS" "8.1,8.2,8.3"
  $phpDefault = Get-Env $envMap "PHP_DEFAULT" "8.2"
  $phpExt = Get-Env $envMap "INSTALL_PHP_EXTENSIONS" "mbstring,curl,xml,zip,intl,gd,mysql,pgsql"
  $composer = Get-Env $envMap "INSTALL_COMPOSER" "true"

  Info "Installing PHP dev stack..."
  $bashPhp = "cat > /tmp/setup-php-dev-wsl.sh << 'EOF'
$(Get-Content -Raw $phpScript)
EOF
chmod +x /tmp/setup-php-dev-wsl.sh
DEV_USER='$devUser' PHP_VERSIONS='$phpVers' PHP_DEFAULT='$phpDefault' INSTALL_PHP_EXTENSIONS='$phpExt' INSTALL_COMPOSER='$composer' bash /tmp/setup-php-dev-wsl.sh
"
  wsl.exe -d $distro -- bash -lc $bashPhp
  Ok "PHP dev environment installed."
} else {
  Warn "Skipped PHP install."
}

Info "Final: shutting down WSL once to apply systemd/.wslconfig cleanly..."
wsl.exe --shutdown | Out-Null
Ok "Done. Open '$distro' from Start Menu."