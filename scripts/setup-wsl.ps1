# scripts/setup-wsl.ps1
$ErrorActionPreference = "Stop"

function Info($m){ Write-Host "[INFO]  $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[OK]    $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[WARN]  $m" -ForegroundColor Yellow }
function Fail($m){ Write-Host "[FAIL]  $m" -ForegroundColor Red }

function Prompt-YesNo([string]$q, [bool]$defaultNo=$true) {
  $suffix = $(if ($defaultNo) { "(y/N)" } else { "(Y/n)" })
  $ans = Read-Host "$q $suffix"
  $ans = $ans.Trim().ToLower()
  if ($ans -eq "") { return (-not $defaultNo) }
  return ($ans -eq "y" -or $ans -eq "yes")
}

function Show-RebootAndExit([string]$reason) {
  Warn $reason
  Warn "Please REBOOT Windows, then re-run: .\scripts\setup-wsl.ps1"
  Warn "Tip: after reboot, open PowerShell as Administrator."
  exit 0
}

function Check-WindowsOptionalFeatureEnabled([string]$featureName) {
  try {
    $f = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop
    return ($f.State -eq "Enabled")
  } catch {
    return $false
  }
}

function Ensure-WSLPrereqs {
  Info "Preflight: checking Windows features for WSL2..."

  $needReboot = $false
  $required = @("Microsoft-Windows-Subsystem-Linux","VirtualMachinePlatform")

  foreach ($feat in $required) {
    if (-not (Check-WindowsOptionalFeatureEnabled $feat)) {
      Warn "Windows feature not enabled: $feat"
      if (Prompt-YesNo "Enable feature '$feat' now?" $true) {
        Info "Enabling $feat..."
        Enable-WindowsOptionalFeature -Online -FeatureName $feat -NoRestart | Out-Null
        Ok "Enabled: $feat (pending reboot)"
        $needReboot = $true
      } else {
        Fail "Cannot proceed until feature '$feat' is enabled."
        Warn "Manual steps (run in Admin PowerShell):"
        Warn "  Enable-WindowsOptionalFeature -Online -FeatureName $feat -All"
        exit 1
      }
    } else {
      Ok "Feature enabled: $feat"
    }
  }

  # Virtualization firmware check (best-effort; may not exist on some systems)
  try {
    $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    if ($null -ne $cpu.VirtualizationFirmwareEnabled -and -not $cpu.VirtualizationFirmwareEnabled) {
      Warn "CPU VirtualizationFirmwareEnabled = False"
      Warn "WSL2 requires virtualization enabled in BIOS/UEFI (Intel VT-x / AMD SVM)."
      Warn "If you continue, WSL2 may fail to start."
      if (-not (Prompt-YesNo "Continue anyway?" $true)) { exit 1 }
    } else {
      Ok "Virtualization firmware looks OK (best-effort)."
    }
  } catch {
    Warn "Cannot read virtualization status (skipping)."
  }

  if ($needReboot) {
    Show-RebootAndExit "Windows features were enabled."
  }
}

function Try-WSL([scriptblock]$cmd, [string]$context) {
  try {
    & $cmd | Out-Null
    return $true
  } catch {
    Fail $context
    Warn $_.Exception.Message
    return $false
  }
}

try {
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

  $enableSystemd = Get-Env $envMap "ENABLE_SYSTEMD" "true"

  # Preflight (Win11 fresh install)
  Ensure-WSLPrereqs

  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Fail "wsl.exe not found. This Windows build may not support WSL or PATH is broken."
    exit 1
  }

  # Validate TARGET_DRIVE exists (nice UX for fresh machines)
  if (-not (Test-Path "${targetDrive}:\")) {
    Warn "TARGET_DRIVE '${targetDrive}:' does not exist."
    $newDrive = Read-Host "Enter a valid drive letter for TARGET_DRIVE (e.g. D, E, F)"
    $newDrive = $newDrive.Trim().TrimEnd(":").ToUpper()
    if ([string]::IsNullOrWhiteSpace($newDrive) -or -not (Test-Path "${newDrive}:\")) {
      Fail "Drive '${newDrive}:' still not found. Please edit setup.env and re-run."
      exit 1
    }
    $targetDrive = $newDrive
    $targetRoot = "${targetDrive}:$targetRootRel"
    Ok "Using TARGET_DRIVE=${targetDrive}:"
  }

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

  # Best-effort: update WSL kernel (may be unsupported on some environments)
  Info "Best-effort: wsl --update (ignore if not supported)..."
  try { wsl.exe --update | Out-Null } catch { Warn "wsl --update failed/unsupported. Continuing..." }

  # Ensure default WSL2
  Info "Ensuring WSL2 default..."
  if (-not (Try-WSL { wsl.exe --set-default-version 2 } "Failed to set default WSL version to 2")) {
    Warn "If you see errors about kernel/virtualization, check:"
    Warn "  - Virtualization enabled in BIOS/UEFI"
    Warn "  - Windows Features: WSL + VirtualMachinePlatform"
    exit 1
  }
  Ok "Default WSL version set to 2."

  # Ensure distro exists (install if missing)
  $distros = (& wsl.exe -l -q) 2>$null
  if (-not $distros -or -not ($distros -contains $distro)) {
    Warn "$distro not found. Installing..."
    Try-WSL { wsl.exe --install -d $distro } "wsl --install failed"

    Ok "Install triggered for '$distro'."
    Warn "IMPORTANT (fresh Windows):"
    Warn "  1) If Windows prompts reboot -> reboot now."
    Warn "  2) After reboot, open '$distro' once from Start Menu to finish initialization if required."
    Warn "  3) Then re-run this script."
    exit 0
  }

  # Probe distro readiness (first launch/init issues)
  Info "Probing distro readiness..."
  $probeOk = Try-WSL { wsl.exe -d $distro -- bash -lc "echo WSL_READY" } "Distro is not ready to run commands yet"
  if (-not $probeOk) {
    Warn "Likely first-launch initialization not completed."
    Warn "Action:"
    Warn "  - Open '$distro' from Start Menu once, wait until it finishes setup,"
    Warn "  - Close it, then re-run .\scripts\setup-wsl.ps1"
    exit 1
  }
  Ok "Distro is ready."

  # Decide if migrate needed (best-effort heuristic)
  # If distro already imported to targetRoot, ext4.vhdx should exist there.
  $safeName = ($distro -replace '[^\w\.\-]+','_')
  $expectedVhd = Join-Path (Join-Path $targetRoot $safeName) "ext4.vhdx"

  if ($autoMigrate -and -not (Test-Path $expectedVhd)) {
    Warn "Distro '$distro' is NOT detected under $targetRoot (expected: $expectedVhd)."
    Warn "This usually means the distro is still stored under C:\Users\<you>\AppData..."
    $doMigrate = Resolve-AskToggle -Value "ask" -Question "Migrate '$distro' to $targetRoot now (export/import) to avoid filling C:?"
    if ($doMigrate) {
      Info "Running migration..."
      & (Join-Path $scriptDir "migrate-wsl.ps1") -DistroName $distro -TargetRoot $targetRoot

      # Re-probe after migration
      Info "Re-probing distro readiness after migration..."
      $probeOk2 = Try-WSL { wsl.exe -d $distro -- bash -lc "echo WSL_READY" } "Distro not ready after migration"
      if (-not $probeOk2) {
        Warn "Migration completed but distro is not ready yet."
        Warn "Open '$distro' from Start Menu once, then re-run this script if needed."
      } else {
        Ok "Distro ready after migration."
      }
    } else {
      Warn "Skipped migration. Note: disk may remain on C:."
    }
  } else {
    Ok "Distro appears to be located under target root (or auto migrate disabled)."
  }

  # Copy ubuntu scripts into WSL and run
  $setupUbuntu = Join-Path $scriptDir "setup-ubuntu.sh"
  if (-not (Test-Path $setupUbuntu)) { throw "Missing: $setupUbuntu" }

  Info "Running setup-ubuntu.sh inside WSL..."
  $bashCmd = "cat > /tmp/setup-ubuntu.sh << 'EOF'
$(Get-Content -Raw $setupUbuntu)
EOF
chmod +x /tmp/setup-ubuntu.sh
DEV_USER='$devUser' ENABLE_SYSTEMD='$enableSystemd' bash /tmp/setup-ubuntu.sh
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

} catch {
  Fail "Unhandled error."
  Warn $_.Exception.Message
  if ($_.ScriptStackTrace) { Warn $_.ScriptStackTrace }
  exit 1
}