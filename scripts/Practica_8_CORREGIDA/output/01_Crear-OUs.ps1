# ============================================================
# 01_Crear-OUs.ps1
# Crea las Unidades Organizativas: Cuates y NoCuates
# Crea los grupos de seguridad para cada OU
# Ejecutar en Windows Server 2022 como Administrador del dominio
# ============================================================

Import-Module ActiveDirectory

$domainDN = (Get-ADDomain).DistinguishedName

Write-Host "`n=== Creando Unidades Organizativas ===" -ForegroundColor Cyan

# Crear OU Cuates
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Cuates'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name "Cuates" -Path $domainDN -ProtectedFromAccidentalDeletion $false
    Write-Host "[OK] OU Cuates creada" -ForegroundColor Green
} else {
    Write-Host "[--] OU Cuates ya existe" -ForegroundColor Yellow
}

# Crear OU NoCuates
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'NoCuates'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name "NoCuates" -Path $domainDN -ProtectedFromAccidentalDeletion $false
    Write-Host "[OK] OU NoCuates creada" -ForegroundColor Green
} else {
    Write-Host "[--] OU NoCuates ya existe" -ForegroundColor Yellow
}

Write-Host "`n=== Creando Grupos de Seguridad ===" -ForegroundColor Cyan

$ouCuates   = "OU=Cuates,$domainDN"
$ouNoCuates = "OU=NoCuates,$domainDN"

if (-not (Get-ADGroup -Filter "Name -eq 'GrupoCuates'" -ErrorAction SilentlyContinue)) {
    New-ADGroup -Name "GrupoCuates" -SamAccountName "GrupoCuates" -GroupScope Global -Path $ouCuates
    Write-Host "[OK] Grupo GrupoCuates creado en OU Cuates" -ForegroundColor Green
} else {
    Write-Host "[--] GrupoCuates ya existe" -ForegroundColor Yellow
}

if (-not (Get-ADGroup -Filter "Name -eq 'GrupoNoCuates'" -ErrorAction SilentlyContinue)) {
    New-ADGroup -Name "GrupoNoCuates" -SamAccountName "GrupoNoCuates" -GroupScope Global -Path $ouNoCuates
    Write-Host "[OK] Grupo GrupoNoCuates creado en OU NoCuates" -ForegroundColor Green
} else {
    Write-Host "[--] GrupoNoCuates ya existe" -ForegroundColor Yellow
}

# Crear directorio base de perfiles
if (-not (Test-Path "C:\Perfiles")) {
    New-Item -ItemType Directory -Path "C:\Perfiles" | Out-Null
    Write-Host "[OK] Directorio C:\Perfiles creado" -ForegroundColor Green
}

Write-Host "`n[DONE] OUs y grupos listos.`n" -ForegroundColor Cyan
