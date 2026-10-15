$root = 'c:\Users\Asus\Playora\playhub_bd'
$json = Get-Content -Raw (Join-Path $root 'assets\data\games_seed.json')
$entries = $json | ConvertFrom-Json
Write-Host ('{0,-22} {1,-6} {2,-22} {3}  {4}' -f 'id','type','entry','cs','title')
Write-Host ('-' * 80)
foreach ($g in $entries) {
    $cs = if ($g.comingSoon) { 'Y' } else { '.' }
    $ep = if ($g.entryPoint) { $g.entryPoint } else { '-' }
    Write-Host ('{0,-22} {1,-6} {2,-22} {3}  {4}' -f $g.id, $g.gameType, $ep, $cs, $g.title)
}