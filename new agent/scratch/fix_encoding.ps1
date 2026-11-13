$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$f1 = "start_server.ps1"
$c1 = [System.IO.File]::ReadAllText($f1, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($f1, $c1, $utf8Bom)

$f2 = "src\api_engine.ps1"
$c2 = [System.IO.File]::ReadAllText($f2, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($f2, $c2, $utf8Bom)

Write-Host "UTF8 BOM Applied to $f1 and $f2 successfully."

