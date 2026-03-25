# ============================================================
# 08_Verificar-Todo.ps1
# Verifica que todos los componentes de la Tarea 08 esten
# configurados correctamente.
#
# CORRECCION: La verificacion de AppLocker ahora busca
# correctamente la regla Allow (por nombre "Allow Everyone")
# y la regla Deny (FileHashRule con "NoCuates"), en vez de
# buscar una FilePathRule con nombre "*Cuates*" que no existe.
# ============================================================

Import-Module ActiveDirectory
Import-Module GroupPolicy
Import-Module FileServerResourceManager

$domainDN = (Get-ADDomain).DistinguishedName
$errores  = 0

function Check {
    param([string]$descripcion, [bool]$resultado)
    if ($resultado) {
        Write-Host "  [OK]   $descripcion" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $descripcion" -ForegroundColor Red
        $script:errores++
    }
}

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host " VERIFICACION TAREA 08 - GOBERNANZA AD"      -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

# ============================================================
Write-Host "--- 1. Estructura de UOs y Grupos ---" -ForegroundColor Yellow

$ouCuates   = Get-ADOrganizationalUnit -Filter "Name -eq 'Cuates'"   -ErrorAction SilentlyContinue
$ouNoCuates = Get-ADOrganizationalUnit -Filter "Name -eq 'NoCuates'" -ErrorAction SilentlyContinue
$grpCuates  = Get-ADGroup "GrupoCuates"   -ErrorAction SilentlyContinue
$grpNoC     = Get-ADGroup "GrupoNoCuates" -ErrorAction SilentlyContinue

Check "OU Cuates existe"      ($null -ne $ouCuates)
Check "OU NoCuates existe"    ($null -ne $ouNoCuates)
Check "Grupo GrupoCuates"     ($null -ne $grpCuates)
Check "Grupo GrupoNoCuates"   ($null -ne $grpNoC)

# ============================================================
Write-Host "`n--- 2. Usuarios en AD ---" -ForegroundColor Yellow

$usCuates   = @(Get-ADUser -Filter * -SearchBase "OU=Cuates,$domainDN"   -ErrorAction SilentlyContinue)
$usNoCuates = @(Get-ADUser -Filter * -SearchBase "OU=NoCuates,$domainDN" -ErrorAction SilentlyContinue)

Check "5 usuarios en OU Cuates"   ($usCuates.Count   -eq 5)
Check "5 usuarios en OU NoCuates" ($usNoCuates.Count -eq 5)

Write-Host "`n  Usuarios en OU Cuates:" -ForegroundColor Gray
$usCuates   | ForEach-Object { Write-Host "    - $($_.SamAccountName)" -ForegroundColor Gray }
Write-Host "`n  Usuarios en OU NoCuates:" -ForegroundColor Gray
$usNoCuates | ForEach-Object { Write-Host "    - $($_.SamAccountName)" -ForegroundColor Gray }

# ============================================================
Write-Host "`n--- 3. Logon Hours ---" -ForegroundColor Yellow

$primerCuate   = Get-ADUser ($usCuates[0].SamAccountName)   -Properties logonHours -ErrorAction SilentlyContinue
$primerNoCuate = Get-ADUser ($usNoCuates[0].SamAccountName) -Properties logonHours -ErrorAction SilentlyContinue

$tieneHorasCuate   = ($null -ne $primerCuate)   -and (($primerCuate.logonHours   | Where-Object { $_ -ne 0 }).Count -gt 0)
$tieneHorasNoCuate = ($null -ne $primerNoCuate) -and (($primerNoCuate.logonHours | Where-Object { $_ -ne 0 }).Count -gt 0)

Check "LogonHours configurados en GrupoCuates ($($usCuates[0].SamAccountName))"   $tieneHorasCuate
Check "LogonHours configurados en GrupoNoCuates ($($usNoCuates[0].SamAccountName))" $tieneHorasNoCuate

# ============================================================
Write-Host "`n--- 4. GPOs ---" -ForegroundColor Yellow

$gpoCierre    = Get-GPO -Name "GPO-CerrarSesionHorario" -ErrorAction SilentlyContinue
$gpoApplocker = Get-GPO -Name "GPO-AppLocker"           -ErrorAction SilentlyContinue

Check "GPO-CerrarSesionHorario existe" ($null -ne $gpoCierre)
Check "GPO-AppLocker existe"           ($null -ne $gpoApplocker)

$links = Get-GPInheritance -Target $domainDN | Select-Object -ExpandProperty GpoLinks

$linkCierre    = ($links | Where-Object { $_.DisplayName -eq "GPO-CerrarSesionHorario" }).Count
$linkApplocker = ($links | Where-Object { $_.DisplayName -eq "GPO-AppLocker" }).Count

Check "GPO-CerrarSesionHorario vinculada al dominio" ($linkCierre    -gt 0)
Check "GPO-AppLocker vinculada al dominio"           ($linkApplocker -gt 0)

# Verificar EnableForcedLogOff en la GPO de horario
if ($null -ne $gpoCierre) {
    try {
        $regVal = Get-GPRegistryValue -Name "GPO-CerrarSesionHorario" `
            -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
            -ValueName "EnableForcedLogOff" -ErrorAction Stop
        Check "EnableForcedLogOff = 1 en GPO horario" ($regVal.Value -eq 1)
    } catch {
        Check "EnableForcedLogOff = 1 en GPO horario" $false
    }
}

# ============================================================
Write-Host "`n--- 5. FSRM - Cuotas ---" -ForegroundColor Yellow

$cuotas   = @(Get-FsrmQuota -ErrorAction SilentlyContinue)
$cuotas10 = @($cuotas | Where-Object { $_.Size -eq (10MB) })
$cuotas5  = @($cuotas | Where-Object { $_.Size -eq (5MB)  })

Check "Cuotas de 10 MB para Cuates (5 carpetas)"   ($cuotas10.Count -eq 5)
Check "Cuotas de 5 MB para NoCuates (5 carpetas)"  ($cuotas5.Count  -eq 5)

Write-Host "`n  Cuotas activas:" -ForegroundColor Gray
$cuotas | ForEach-Object {
    $mb = [math]::Round($_.Size / 1MB, 0)
    Write-Host "    $($_.Path) -> $mb MB (Hard limit)" -ForegroundColor Gray
}

# ============================================================
Write-Host "`n--- 6. FSRM - File Screening ---" -ForegroundColor Yellow

$screens = @(Get-FsrmFileScreen -ErrorAction SilentlyContinue)
$grupo   = Get-FsrmFileGroup -Name "Archivos-Bloqueados" -ErrorAction SilentlyContinue

Check "Grupo Archivos-Bloqueados existe"        ($null -ne $grupo)
Check "10 screenings aplicados (uno por user)"  ($screens.Count -eq 10)
Check ".mp3 incluido en grupo de bloqueo"       ($null -ne $grupo -and $grupo.IncludePattern -contains "*.mp3")
Check ".mp4 incluido en grupo de bloqueo"       ($null -ne $grupo -and $grupo.IncludePattern -contains "*.mp4")
Check ".exe incluido en grupo de bloqueo"       ($null -ne $grupo -and $grupo.IncludePattern -contains "*.exe")
Check ".msi incluido en grupo de bloqueo"       ($null -ne $grupo -and $grupo.IncludePattern -contains "*.msi")

# ============================================================
Write-Host "`n--- 7. AppLocker ---" -ForegroundColor Yellow

$appidSvc = Get-Service AppIDSvc -ErrorAction SilentlyContinue
Check "Servicio AppIDSvc corriendo" ($null -ne $appidSvc -and $appidSvc.Status -eq "Running")

# Obtener GUID de la GPO de AppLocker para leer la politica
if ($null -ne $gpoApplocker) {
    $gpoGuid  = $gpoApplocker.Id.ToString()
    $ldapPath = "LDAP://CN={$gpoGuid},CN=Policies,CN=System,DC=lab,DC=local"

    try {
        $xmlPol = [xml](Get-AppLockerPolicy -Ldap $ldapPath -Xml -ErrorAction Stop)
        $colExe = $xmlPol.AppLockerPolicy.RuleCollection | Where-Object { $_.Type -eq "Exe" }

        # Verificar que existe la regla base Allow Everyone
        $allowBase = $colExe.FilePathRule | Where-Object { $_.UserOrGroupSid -eq "S-1-1-0" -and $_.Action -eq "Allow" }
        Check "Regla base Allow Everyone existe"       ($null -ne $allowBase)

        # Verificar que existe la regla Deny por Hash para GrupoNoCuates
        $denyHash = $colExe.FileHashRule | Where-Object { $_.Action -eq "Deny" -and $_.Name -like "*NoCuates*" }
        Check "Regla Deny-Hash para GrupoNoCuates existe" ($null -ne $denyHash)

        # Verificar que el modo de enforcement es Enabled
        Check "AppLocker en modo Enabled (Exe)" ($colExe.EnforcementMode -eq "Enabled")

        if ($null -ne $denyHash) {
            $hashData = $denyHash.Conditions.FileHashCondition.FileHash.Data
            Write-Host "`n  Hash bloqueado: $hashData" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  No se pudo leer la politica AppLocker desde la GPO: $_" -ForegroundColor Yellow
        Check "Politica AppLocker legible en GPO" $false
    }
} else {
    Check "GPO AppLocker existe (requerida para verificar)" $false
}

# ============================================================
Write-Host "`n============================================" -ForegroundColor Cyan
if ($errores -eq 0) {
    Write-Host " RESULTADO: TODO CORRECTO - 0 errores" -ForegroundColor Green
} else {
    Write-Host " RESULTADO: $errores error(es) encontrado(s)" -ForegroundColor Red
    Write-Host " Revisa los items marcados [FAIL] arriba." -ForegroundColor Red
}
Write-Host "============================================`n" -ForegroundColor Cyan
