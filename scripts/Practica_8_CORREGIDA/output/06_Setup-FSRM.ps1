# ============================================================
# 06_Setup-FSRM.ps1
# Configura FSRM:
#   - Cuota 10 MB para GrupoCuates
#   - Cuota  5 MB para GrupoNoCuates
#   - Active Screening: bloquea .mp3 .mp4 .exe .msi en perfiles
# ============================================================

Import-Module ActiveDirectory

# ============================================================
# 1. Instalar el rol FSRM si no esta instalado
# ============================================================
Write-Host "`n=== Instalando FSRM ===" -ForegroundColor Cyan

$feature = Get-WindowsFeature FS-Resource-Manager
if (-not $feature.Installed) {
    Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools
    Write-Host "[OK] FSRM instalado" -ForegroundColor Green
} else {
    Write-Host "[--] FSRM ya esta instalado" -ForegroundColor Yellow
}

# Iniciar servicio y esperar a que este listo
Write-Host "[..] Iniciando servicio SrmSvc..." -ForegroundColor Yellow
Start-Service -Name SrmSvc -ErrorAction SilentlyContinue
Start-Sleep -Seconds 15

$svc = Get-Service SrmSvc
if ($svc.Status -ne "Running") {
    Write-Host "[ERROR] El servicio SrmSvc no pudo iniciarse." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Servicio SrmSvc corriendo" -ForegroundColor Green

Import-Module FileServerResourceManager

$perfilesBase = "C:\Perfiles"

# ============================================================
# 2. Crear plantillas de cuota (sin -SoftLimit, es hard por defecto)
# ============================================================
Write-Host "`n=== Creando plantillas de cuota ===" -ForegroundColor Cyan

if (-not (Get-FsrmQuotaTemplate -Name "Cuota-Cuates-10MB" -ErrorAction SilentlyContinue)) {
    New-FsrmQuotaTemplate -Name "Cuota-Cuates-10MB" -Size (10MB)
    Write-Host "[OK] Plantilla Cuota-Cuates-10MB creada (10 MB hard limit)" -ForegroundColor Green
} else {
    Write-Host "[--] Plantilla Cuota-Cuates-10MB ya existe" -ForegroundColor Yellow
}

if (-not (Get-FsrmQuotaTemplate -Name "Cuota-NoCuates-5MB" -ErrorAction SilentlyContinue)) {
    New-FsrmQuotaTemplate -Name "Cuota-NoCuates-5MB" -Size (5MB)
    Write-Host "[OK] Plantilla Cuota-NoCuates-5MB creada (5 MB hard limit)" -ForegroundColor Green
} else {
    Write-Host "[--] Plantilla Cuota-NoCuates-5MB ya existe" -ForegroundColor Yellow
}

# ============================================================
# 3. Aplicar cuotas a carpetas de usuario
# ============================================================
Write-Host "`n=== Aplicando cuotas a carpetas de usuario ===" -ForegroundColor Cyan

Get-ADGroupMember "GrupoCuates" | ForEach-Object {
    $ruta = "$perfilesBase\$($_.SamAccountName)"
    if (Test-Path $ruta) {
        Remove-FsrmQuota -Path $ruta -Confirm:$false -ErrorAction SilentlyContinue
        New-FsrmQuota -Path $ruta -Template "Cuota-Cuates-10MB"
        Write-Host "[10 MB] $ruta" -ForegroundColor Green
    } else {
        Write-Warning "Carpeta no encontrada: $ruta"
    }
}

Get-ADGroupMember "GrupoNoCuates" | ForEach-Object {
    $ruta = "$perfilesBase\$($_.SamAccountName)"
    if (Test-Path $ruta) {
        Remove-FsrmQuota -Path $ruta -Confirm:$false -ErrorAction SilentlyContinue
        New-FsrmQuota -Path $ruta -Template "Cuota-NoCuates-5MB"
        Write-Host "[ 5 MB] $ruta" -ForegroundColor Yellow
    } else {
        Write-Warning "Carpeta no encontrada: $ruta"
    }
}

# ============================================================
# 4. Crear grupo de archivos bloqueados
# ============================================================
Write-Host "`n=== Configurando File Screening ===" -ForegroundColor Cyan

if (-not (Get-FsrmFileGroup -Name "Archivos-Bloqueados" -ErrorAction SilentlyContinue)) {
    New-FsrmFileGroup -Name "Archivos-Bloqueados" `
        -IncludePattern @(
            "*.mp3", "*.mp4", "*.avi", "*.mkv", "*.mov",
            "*.wav", "*.flac", "*.wma", "*.aac",
            "*.exe", "*.msi", "*.bat", "*.cmd", "*.vbs"
        )
    Write-Host "[OK] Grupo Archivos-Bloqueados creado" -ForegroundColor Green
} else {
    Write-Host "[--] Grupo Archivos-Bloqueados ya existe" -ForegroundColor Yellow
}

# ============================================================
# 5. Crear plantilla de screening activo
# Active Screening bloquea la escritura del archivo en tiempo real
# Se usa -Notification @() para evitar el error de parametro
# ============================================================
if (-not (Get-FsrmFileScreenTemplate -Name "Screening-Activo-Multimedia" -ErrorAction SilentlyContinue)) {
    New-FsrmFileScreenTemplate -Name "Screening-Activo-Multimedia" `
        -IncludeGroup @("Archivos-Bloqueados") `
        -Active
    Write-Host "[OK] Plantilla Screening-Activo-Multimedia creada" -ForegroundColor Green
} else {
    Write-Host "[--] Plantilla ya existe" -ForegroundColor Yellow
}

# ============================================================
# 6. Aplicar screening a todas las carpetas de perfil
# ============================================================
Get-ChildItem -Path $perfilesBase -Directory | ForEach-Object {
    Remove-FsrmFileScreen -Path $_.FullName -Confirm:$false -ErrorAction SilentlyContinue
    New-FsrmFileScreen -Path $_.FullName -Template "Screening-Activo-Multimedia"
    Write-Host "[SCREEN] $($_.FullName)" -ForegroundColor Magenta
}

Write-Host "`n[DONE] FSRM configurado correctamente.`n" -ForegroundColor Cyan

# ============================================================
# 7. Resumen
# ============================================================
Write-Host "=== Resumen FSRM ===" -ForegroundColor Cyan
Write-Host "Cuotas activas:" -ForegroundColor White
Get-FsrmQuota | Select-Object Path, @{N="LimiteMB";E={[math]::Round($_.Size/1MB,0)}} | Format-Table -AutoSize

Write-Host "Screenings activos:" -ForegroundColor White
Get-FsrmFileScreen | Select-Object Path, MatchesTemplate | Format-Table -AutoSize
