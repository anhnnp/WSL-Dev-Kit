function Read-EnvFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) { throw "Missing env file: $Path" }

  $map = @{}
  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0) { return }
    if ($line.StartsWith("#")) { return }
    $idx = $line.IndexOf("=")
    if ($idx -lt 1) { return }
    $k = $line.Substring(0, $idx).Trim()
    $v = $line.Substring($idx + 1).Trim()
    $map[$k] = $v
  }
  return $map
}

function Get-Env {
  param($envMap, [string]$Key, [string]$Default = "")
  if ($envMap.ContainsKey($Key) -and $envMap[$Key].Trim().Length -gt 0) { return $envMap[$Key].Trim() }
  return $Default
}