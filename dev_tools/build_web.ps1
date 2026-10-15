Set-Location 'c:\Users\Asus\Playora\playhub_bd'
$out = & flutter build web --release 2>&1
$out | ForEach-Object { Write-Host $_ }
exit $LASTEXITCODE