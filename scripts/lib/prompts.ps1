function Resolve-AskToggle {
  param(
    [string]$Value,  # ask/true/false
    [string]$Question
  )
  $v = $Value.Trim().ToLower()
  if ($v -eq "true" -or $v -eq "yes" -or $v -eq "y") { return $true }
  if ($v -eq "false" -or $v -eq "no" -or $v -eq "n") { return $false }

  # ask (default)
  $ans = Read-Host "$Question (y/N)"
  return ($ans.Trim().ToLower() -eq "y")
}