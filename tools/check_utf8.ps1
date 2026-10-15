$path = 'c:\Users\Asus\Playora\playhub_bd\lib\features\game_player\ludo\ludo_game.dart'
$bytes = [System.IO.File]::ReadAllBytes($path)
# Search for the byte sequence of 'Your turn ' (UTF-8) and dump the next 25 bytes
$pattern = [System.Text.Encoding]::UTF8.GetBytes('Your turn ')
$idx = -1
for ($i = 0; $i -le $bytes.Length - $pattern.Length; $i++) {
  $match = $true
  for ($j = 0; $j -lt $pattern.Length; $j++) {
    if ($bytes[$i + $j] -ne $pattern[$j]) { $match = $false; break }
  }
  if ($match) { $idx = $i; break }
}
if ($idx -ge 0) {
  Write-Output ('Offset: ' + $idx)
  for ($k = 0; $k -lt 25; $k++) {
    Write-Output (('  byte[{0}] = 0x{1:X2}' -f $k, $bytes[$idx + $pattern.Length + $k]))
  }
}