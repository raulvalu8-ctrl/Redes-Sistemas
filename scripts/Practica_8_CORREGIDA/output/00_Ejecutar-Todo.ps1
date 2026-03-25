# ============================================================
# 00_Ejecutar-Todo.ps1
# Script maestro: ejecuta todos los pasos de la Tarea 08
# en el orden correcto.
#
# ORDEN DE EJECUCION:
#   1. Crear OUs y grupos
#   2. Importar usuarios desde CSV
#   3. Configurar Logon Hours + GPO cierre de sesion
#   4. Instalar FSRM, cuotas y file screening
#   5. Configurar AppLocker
#   6. Verificar todo
#
# PREREQUISITOS:
#   - Windows Server 2022 con AD DS instalado
#   - Ejecutar como Administrador del dominio
#   - Colocar usuarios.csv en C:\Scripts\usuarios.csv
#   - Los scripts deben estar en C:\Scripts\
# ============================================================

$scriptsPath = "C:\Scripts"

# Verificar que existe el directorio de scripts
if (-not (Test-Path $scriptsPath)) {
    New-Item -ItemType Directory -Path $scriptsPath | Out-Null
}

Write-Host @"
============================================================
   TAREA 08: GOBERNANZA, CUOTAS Y CONTROL DE APLICACIONES
   Active Directory - Windows Server 2022
============================================================
"@ -ForegroundColor Cyan

function Ejecutar-Script {
    param([string]$nombre, [string]$ruta)
    Write-Host "`n>>> Ejecutando: $nombre" -ForegroundColor Yellow
    Write-Host "    $ruta`n" -ForegroundColor DarkGray
    & $ruta
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Fallo el script: $nombre" -ForegroundColor Red
        exit 1
    }
}

# Paso 1
Ejecutar-Script "Crear OUs y Grupos" "$scriptsPath\01_Crear-OUs.ps1"

# Paso 2
Ejecutar-Script "Importar Usuarios desde CSV" "$scriptsPath\02_Importar-Usuarios.ps1"

# Paso 3
Ejecutar-Script "Logon Hours + GPO Cierre de Sesion" "$scriptsPath\05_Set-LogonHours-GPO.ps1"

# Paso 4
Ejecutar-Script "FSRM: Cuotas y File Screening" "$scriptsPath\06_Setup-FSRM.ps1"

# Paso 5
Ejecutar-Script "AppLocker: Control de Ejecucion" "$scriptsPath\07_Set-AppLocker.ps1"

# Paso 6 - Verificacion final
Ejecutar-Script "Verificacion General" "$scriptsPath\08_Verificar-Todo.ps1"

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "   TAREA 08 COMPLETADA" -ForegroundColor Green
Write-Host "   Ahora une los clientes al dominio:" -ForegroundColor White
Write-Host "   - Windows 10: ejecuta 03_Union-Windows10.ps1 en el cliente" -ForegroundColor White
Write-Host "   - Alpine Linux: ejecuta 04_union-alpine-dominio.sh como root" -ForegroundColor White
Write-Host "============================================================`n" -ForegroundColor Cyan
