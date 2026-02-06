Write-Host "---------------------------"
Write-Host "Diagnostico Practica"
Write-Host "---------------------------"

$nombre = hostname
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.50.*" }).IPAddress
$info = Get-PSDrive C
$libre = [math]::Round($info.Free / 1GB, 2)

Write-Host "Equipo: $nombre"
Write-Host "IP: $ip"
Write-Host "Disco: $libre GB"

Write-Host "---------------------------"