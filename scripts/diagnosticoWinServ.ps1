Write-Host "-----------------------------"
Write-Host "Diagnostico del equipo"
Write-Host "-----------------------------"

$nombre = hostname
Write-Host "Equipo: $nombre"

$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.50.*" }).IPAddress
Write-Host "IP actual: $ip"

$disco = Get-PSDrive C | Select-Object @{n="Libre"; e={[math]::Round($_.Free/1GB, 2)}}
Write-Host "Disco C libre: $($disco.Libre) GB"

Write-Host "-----------------------------"

Read-Host "Enter para salir"