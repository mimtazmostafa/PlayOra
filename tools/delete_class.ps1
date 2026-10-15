param(
  [Parameter(Mandatory=$true)][string]$Path,
  [Parameter(Mandatory=$true)][string]$ClassName
)
$lines = Get-Content -LiteralPath $Path
$out = New-Object System.Collections.Generic.List[string]
$skip = $false
$depth = 0
$pattern = "^class $ClassName extends StatelessWidget \{$"
foreach ($l in $lines) {
  if (-not $skip -and $l -match $pattern) {
    $skip = $true
    $depth = 1
    continue
  }
  if ($skip) {
    if ($l -match '^\{') { $depth++ }
    elseif ($l -match '^\}') {
      $depth--
      if ($depth -le 0) { $skip = $false }
      continue
    }
    continue
  }
  $out.Add($l)
}
Set-Content -LiteralPath $Path -Value $out -Encoding UTF8
Write-Output ("deleted $ClassName; lines now " + $out.Count)