# ============================================================
# 05_Set-LogonHours-GPO.ps1
# Configura horarios de inicio de sesion en AD:
#   GrupoCuates:   08:00 - 15:00 (lunes a viernes)
#   GrupoNoCuates: 15:00 - 02:00 (lunes a viernes)
#
# Crea y vincula GPO para forzar cierre de sesion al expirar
# el horario (EnableForcedLogOff).
#
# CORRECCION: usa Set-ADUser -Replace directamente,
# sin ldifde (que era poco confiable).
#
# Ejecutar en Windows Server 2022 como Administrador del dominio
# ============================================================

Import-Module ActiveDirectory
Import-Module GroupPolicy

# ============================================================
# FUNCION: Construye el arreglo de 21 bytes de logonHours
#
# AD divide la semana en 168 horas (7 dias x 24 horas).
# Cada bit representa 1 hora en UTC.
# Los 168 bits se empaquetan en 21 bytes, comenzando el
# domingo a las 00:00 UTC.
#
# Orden de dias en el arreglo:
#   Bytes 0-2   = Domingo
#   Bytes 3-5   = Lunes
#   Bytes 6-8   = Martes
#   Bytes 9-11  = Miercoles
#   Bytes 12-14 = Jueves
#   Bytes 15-17 = Viernes
#   Bytes 18-20 = Sabado
#
# Zona horaria: UTC-6 (Mexico Centro)
#   Hora local 08:00 = UTC 14:00
#   Hora local 15:00 = UTC 21:00
#   Hora local 02:00 = UTC 08:00 (dia siguiente)
# ============================================================
function New-LogonHoursBytes {
    param(
        [int]$HoraInicioUTC,   # hora UTC de inicio (0-23)
        [int]$HoraFinUTC,      # hora UTC de fin    (0-23), excluida
        [string[]]$Dias        # dias a habilitar: "Lunes","Martes"...
    )

    # Mapa de dia -> indice de bloque de 3 bytes en el arreglo
    $diaIndex = @{
        "Domingo"   = 0
        "Lunes"     = 1
        "Martes"    = 2
        "Miercoles" = 3
        "Jueves"    = 4
        "Viernes"   = 5
        "Sabado"    = 6
    }

    $bytes = [byte[]]::new(21)   # 21 bytes = 168 bits, todo en 0

    foreach ($dia in $Dias) {
        $bloque = $diaIndex[$dia]   # que bloque de 3 bytes le toca

        if ($HoraInicioUTC -lt $HoraFinUTC) {
            # Rango normal: ej. 14:00 -> 21:00
            for ($h = $HoraInicioUTC; $h -lt $HoraFinUTC; $h++) {
                $byteIndex = $bloque * 3 + [math]::Floor($h / 8)
                $bitPos    = $h % 8
                $bytes[$byteIndex] = $bytes[$byteIndex] -bor ([byte](1 -shl $bitPos))
            }
        } else {
            # Rango que cruza medianoche: ej. 21:00 -> 08:00 (+1 dia)
            # Parte 1: desde HoraInicioUTC hasta fin del dia (hora 23)
            for ($h = $HoraInicioUTC; $h -lt 24; $h++) {
                $byteIndex = $bloque * 3 + [math]::Floor($h / 8)
                $bitPos    = $h % 8
                $bytes[$byteIndex] = $bytes[$byteIndex] -bor ([byte](1 -shl $bitPos))
            }
            # Parte 2: desde medianoche hasta HoraFinUTC en el dia siguiente
            $bloqueSig = ($bloque + 1) % 7
            for ($h = 0; $h -lt $HoraFinUTC; $h++) {
                $byteIndex = $bloqueSig * 3 + [math]::Floor($h / 8)
                $bitPos    = $h % 8
                $bytes[$byteIndex] = $bytes[$byteIndex] -bor ([byte](1 -shl $bitPos))
            }
        }
    }

    return $bytes
}

# ============================================================
# Calcular bytes para cada grupo (UTC-6, Mexico Centro)
#
# GrupoCuates:   08:00-15:00 local = 14:00-21:00 UTC  (lun-vie)
# GrupoNoCuates: 15:00-02:00 local = 21:00-08:00 UTC  (lun-vie, cruza medianoche)
# ============================================================
$diasLaborales = @("Lunes","Martes","Miercoles","Jueves","Viernes")

$bytesCuates = New-LogonHoursBytes `
    -HoraInicioUTC 14 `
    -HoraFinUTC    21 `
    -Dias          $diasLaborales

$bytesNoCuates = New-LogonHoursBytes `
    -HoraInicioUTC 21 `
    -HoraFinUTC    8  `
    -Dias          $diasLaborales

# ============================================================
# 1. Aplicar logonHours a cada usuario usando Set-ADUser
# ============================================================
Write-Host "`n=== Configurando Logon Hours ===" -ForegroundColor Cyan

Write-Host "`n[Cuates] 08:00-15:00 hora local (14:00-21:00 UTC):" -ForegroundColor Yellow
Get-ADGroupMember "GrupoCuates" | Where-Object {$_.objectClass -eq "user"} | ForEach-Object {
    try {
        Set-ADUser $_.SamAccountName -Replace @{ logonHours = $bytesCuates }
        Write-Host "  [OK] $($_.SamAccountName)" -ForegroundColor Green
    } catch {
        Write-Host "  [ERR] $($_.SamAccountName): $_" -ForegroundColor Red
    }
}

Write-Host "`n[NoCuates] 15:00-02:00 hora local (21:00-08:00 UTC):" -ForegroundColor Yellow
Get-ADGroupMember "GrupoNoCuates" | Where-Object {$_.objectClass -eq "user"} | ForEach-Object {
    try {
        Set-ADUser $_.SamAccountName -Replace @{ logonHours = $bytesNoCuates }
        Write-Host "  [OK] $($_.SamAccountName)" -ForegroundColor Green
    } catch {
        Write-Host "  [ERR] $($_.SamAccountName): $_" -ForegroundColor Red
    }
}

# ============================================================
# 2. Verificacion rapida
# ============================================================
Write-Host "`n=== Verificacion ===" -ForegroundColor Cyan
$u = Get-ADUser "jgarcia" -Properties logonHours
$nullBytes = ($u.logonHours | Where-Object { $_ -ne 0 }).Count
if ($nullBytes -gt 0) {
    Write-Host "[OK] jgarcia tiene logonHours configurados ($nullBytes bytes != 0)" -ForegroundColor Green
} else {
    Write-Host "[FAIL] jgarcia no tiene logonHours configurados" -ForegroundColor Red
}

$u2 = Get-ADUser "rperez" -Properties logonHours
$nullBytes2 = ($u2.logonHours | Where-Object { $_ -ne 0 }).Count
if ($nullBytes2 -gt 0) {
    Write-Host "[OK] rperez tiene logonHours configurados ($nullBytes2 bytes != 0)" -ForegroundColor Green
} else {
    Write-Host "[FAIL] rperez no tiene logonHours configurados" -ForegroundColor Red
}

# ============================================================
# 3. Crear GPO para forzar cierre de sesion al expirar horario
#    Clave: EnableForcedLogOff = 1
#    Esto hace que Windows cierre la sesion activa al llegar
#    al limite de tiempo, en vez de solo bloquear nuevos logins.
# ============================================================
Write-Host "`n=== Creando GPO de cierre forzado de sesion ===" -ForegroundColor Cyan

$gpoName  = "GPO-CerrarSesionHorario"
$domainDN = (Get-ADDomain).DistinguishedName

if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
    New-GPO -Name $gpoName -Comment "Cierra sesion activa cuando expira el horario de inicio de sesion" | Out-Null
    Write-Host "[OK] GPO '$gpoName' creada" -ForegroundColor Green
} else {
    Write-Host "[--] GPO '$gpoName' ya existe, actualizando..." -ForegroundColor Yellow
}

# Configurar EnableForcedLogOff = 1 en la GPO
Set-GPRegistryValue -Name $gpoName `
    -Key       "HKLM\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
    -ValueName "EnableForcedLogOff" `
    -Type      DWord `
    -Value     1
Write-Host "[OK] EnableForcedLogOff = 1 configurado en la GPO" -ForegroundColor Green

# Vincular GPO al dominio si no esta vinculada
$yaVinculada = Get-GPInheritance -Target $domainDN |
    Select-Object -ExpandProperty GpoLinks |
    Where-Object { $_.DisplayName -eq $gpoName }

if (-not $yaVinculada) {
    New-GPLink -Name $gpoName -Target $domainDN -Enforced Yes | Out-Null
    Write-Host "[OK] GPO vinculada al dominio con Enforced=Yes" -ForegroundColor Green
} else {
    Write-Host "[--] GPO ya estaba vinculada" -ForegroundColor Yellow
}

# Forzar aplicacion de politicas
gpupdate /force | Out-Null
Write-Host "[OK] Politicas actualizadas (gpupdate /force)" -ForegroundColor Green

Write-Host "`n[DONE] Horarios y GPO configurados.`n" -ForegroundColor Cyan
