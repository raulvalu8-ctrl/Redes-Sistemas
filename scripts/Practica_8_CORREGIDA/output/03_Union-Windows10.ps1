# ============================================================
# 03_Union-Windows10.ps1
# Une el equipo Windows 10 al dominio lab.local
# Ejecutar en el cliente Windows 10 como Administrador local
# ============================================================

$dominio = "lab.local"
$dcIP    = "192.168.56.10"

Write-Host "`n=== Union de Windows 10 al dominio $dominio ===" -ForegroundColor Cyan

# 1. Configurar DNS apuntando al DC
Write-Host "`n[1] Configurando DNS hacia el DC ($dcIP)..." -ForegroundColor Yellow
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $dcIP
Write-Host "[OK] DNS configurado en $($adapter.Name) -> $dcIP" -ForegroundColor Green

# 2. Verificar conectividad con el DC
Write-Host "`n[2] Verificando conectividad con el DC..." -ForegroundColor Yellow
if (Test-Connection -ComputerName $dcIP -Count 2 -Quiet) {
    Write-Host "[OK] DC accesible en $dcIP" -ForegroundColor Green
} else {
    Write-Host "[ERROR] No se puede alcanzar el DC. Verifica la red." -ForegroundColor Red
    exit 1
}

# 3. Solicitar credenciales del administrador del dominio
Write-Host "`n[3] Ingresa las credenciales del Administrador del dominio:" -ForegroundColor Yellow
$cred = Get-Credential -Message "Credenciales para unirse a $dominio" -UserName "lab\Administrator"

# 4. Unir al dominio (el equipo se reiniciara automaticamente)
Write-Host "`n[4] Uniendose al dominio $dominio..." -ForegroundColor Yellow
try {
    Add-Computer `
        -DomainName $dominio `
        -Credential $cred `
        -Force

    Write-Host "[OK] Equipo unido correctamente a $dominio" -ForegroundColor Green
    Write-Host "[!]  El equipo se reiniciara en 10 segundos..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force

} catch {
    Write-Host "[ERROR] No se pudo unir al dominio: $_" -ForegroundColor Red
}
