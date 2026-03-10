# ==============================================================
#                 GESTION DE SERVIDOR FTP (IIS)
# ==============================================================
#requires -RunAsAdministrator

# --- CONFIGURACION DE RUTAS ---
$BASE_PATH   = "C:\inetpub\ftp"
$GROUPS_DIR  = "$BASE_PATH\grupos"
$USERS_HOME  = "$BASE_PATH\LocalUser"
$PUBLIC_DIR   = "$BASE_PATH\publica"
$ANON_HOME   = "$USERS_HOME\Public"

$GROUP_A    = "reprobados"
$GROUP_B    = "recursadores"
$GROUP_BASE = "ftp_users"

function Log-Info { param($msg) Write-Host "[+] $msg" -ForegroundColor Green }
function Log-Error { param($msg) Write-Host "[-] $msg" -ForegroundColor Red }
function Log-Warning { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Log-Header { param($msg) Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Log-Error "Se requieren privilegios de Administrador."; exit 1
}

function Setup-IIS-FTP {
    Log-Info "Preparando componentes y carpetas..."
    $features = @("Web-Server", "Web-Ftp-Server", "Web-Ftp-Service")
    foreach ($f in $features) {
        if ((Get-WindowsFeature -Name $f).InstallState -ne "Installed") {
            Install-WindowsFeature -Name $f | Out-Null
        }
    }
    
    $dirs = @($BASE_PATH, $GROUPS_DIR, $USERS_HOME, $PUBLIC_DIR, $ANON_HOME)
    foreach ($d in $dirs) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

    # Junction para Anonimo (Solo carpeta 'general')
    $j = "$ANON_HOME\general"; cmd /c "if exist ""$j"" rmdir ""$j"""
    cmd /c "mklink /J ""$j"" ""$PUBLIC_DIR""" | Out-Null
    
    # Limpieza estricta de la carpeta anonima para que solo vea 'general'
    Get-ChildItem $ANON_HOME | Where-Object { $_.Name -ne "general" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # Grupos
    foreach ($g in @($GROUP_A, $GROUP_B, $GROUP_BASE)) {
        if (-not (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $g | Out-Null }
    }
}

function Configure-FTP-Site {
    $SiteName = "ServidorFTP"
    Log-Header "Configurando Sitio FTP"
    Import-Module WebAdministration
    
    if (Get-Website -Name $SiteName -ErrorAction SilentlyContinue) { Remove-Website -Name $SiteName | Out-Null }
    New-WebFtpSite -Name $SiteName -PhysicalPath $BASE_PATH -Port 21 -Force | Out-Null
    
    # AISLAMIENTO: StartInUsersDirectory (Modo 1 - LocalUser\<Usuario>)
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$SiteName']/ftpServer/userIsolation" -Name "mode" -Value "StartInUsersDirectory"
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$SiteName']/ftpServer/security/authentication/basicAuthentication" -Name "defaultLogonDomain" -Value "."
    
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$SiteName']/ftpServer/security/authentication/basicAuthentication" -Name "enabled" -Value $true
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$SiteName']/ftpServer/security/authentication/anonymousAuthentication" -Name "enabled" -Value $true
    
    # SSL: Permitir pero no requerir (Para evitar error 534)
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$SiteName']/ftpServer/security/ssl" -Name "controlChannelPolicy" -Value "SslAllow"
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$SiteName']/ftpServer/security/ssl" -Name "dataChannelPolicy" -Value "SslAllow"
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$SiteName']/ftpServer/security/ssl" -Name "serverCertificateRollbackContext" -Value $null
    Clear-WebConfiguration -Filter "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Location $SiteName
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Location $SiteName -Value @{accessType="Allow"; users="?"; permissions="Read, Write"}
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Location $SiteName -Value @{accessType="Allow"; users="*"; permissions="Read, Write"}
    
    # Permisos Globales para evitar el 530
    icacls "$BASE_PATH" /grant "*S-1-1-0:(F)" /Q | Out-Null
    icacls "$USERS_HOME" /grant "*S-1-1-0:(F)" /Q | Out-Null
    
    Restart-Service ftpsvc -Force
    Log-Info "Sitio configurado y servicio FTP reiniciado."
}

function Add-FTP-User {
    param($userIn = $null)
    Log-Header "Registrar/Reparar Usuario FTP"
    
    $user = if ($userIn) { $userIn } else { Read-Host "Nombre del usuario" }
    
    if (-not (Get-LocalUser -Name $user -ErrorAction SilentlyContinue)) {
        $passText = Read-Host "Contrasena para nuevo usuario"
        $pass = ConvertTo-SecureString $passText -AsPlainText -Force
        New-LocalUser -Name $user -Password $pass -PasswordNeverExpires | Out-Null
        Add-LocalGroupMember -Group $GROUP_BASE -Member $user
        Add-LocalGroupMember -Group $GROUP_A -Member $user
        Log-Info "Usuario '$user' creado."
    }

    $p = "$USERS_HOME\$user"
    if (-not (Test-Path $p)) { New-Item -ItemType Directory $p -Force | Out-Null }
    
    # Permisos criticos del Home
    icacls "$p" /inheritance:r | Out-Null
    icacls "$p" /grant "${user}:(OI)(CI)F" /grant "*S-1-5-32-544:(OI)(CI)F" /grant "*S-1-5-18:(OI)(CI)F" | Out-Null

    # Subcarpetas (publica, grupo, user)
    if (-not (Test-Path "$p\user")) { New-Item -ItemType Directory "$p\user" -Force | Out-Null }
    
    $j1 = "$p\publica"; cmd /c "if exist ""$j1"" rmdir ""$j1"""
    cmd /c "mklink /J ""$j1"" ""$PUBLIC_DIR""" | Out-Null
    
    $cGroup = if (Get-LocalGroupMember -Group $GROUP_B | Where-Object { $_.Name -like "*\$user" }) { $GROUP_B } else { $GROUP_A }
    $j2 = "$p\$cGroup"; cmd /c "if exist ""$j2"" rmdir ""$j2"""
    cmd /c "mklink /J ""$j2"" ""$GROUPS_DIR\$cGroup""" | Out-Null

    # LIMPIEZA ESTRICTA: Solo las 3 carpetas que el usuario debe ver
    Get-ChildItem $p | Where-Object { $_.Name -notin "publica", $cGroup, "user" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Restart-Service ftpsvc -Force
    Log-Info "Usuario '$user' blindado con vista de 3 carpetas (publica, grupo, user)."
}

function Remove-FTP-User {
    $user = Read-Host "Usuario a eliminar"
    if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
        Remove-LocalUser -Name $user; Remove-Item "$USERS_HOME\$user" -Recurse -Force
        Log-Info "Usuario y su carpeta eliminados."
    }
}

function Change-User-Group {
    $user = Read-Host "Nombre de usuario a migrar"
    if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
        $opt = Read-Host "Mover a: 1) $GROUP_A 2) $GROUP_B"
        $nGroup = if ($opt -eq "2") { $GROUP_B } else { $GROUP_A }
        
        Remove-LocalGroupMember -Group $GROUP_A -Member $user -ErrorAction SilentlyContinue
        Remove-LocalGroupMember -Group $GROUP_B -Member $user -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group $nGroup -Member $user
        
        # Eliminar carpeta del grupo antiguo si existe para evitar duplicidad visual
        $oldJ = "$USERS_HOME\$user\grupo"
        if (Test-Path $oldJ) { Remove-Item $oldJ -Force }
        $oldJ_A = "$USERS_HOME\$user\$GROUP_A"
        if (Test-Path $oldJ_A -and ($nGroup -ne $GROUP_A)) { Remove-Item $oldJ_A -Force }
        $oldJ_B = "$USERS_HOME\$user\$GROUP_B"
        if (Test-Path $oldJ_B -and ($nGroup -ne $GROUP_B)) { Remove-Item $oldJ_B -Force }

        Add-FTP-User -userIn $user
        Log-Info "Migracion completada."
    }
}

$opt = "0"
while ($opt -ne "7") {
    Clear-Host
    Write-Host "1) Despliegue FTP (Arregla Error 530)`n2) Registrar/Reparar Usuario`n3) Eliminar Usuario`n4) Cambiar Grupo`n5) Auditoria`n6) Reiniciar Servicio`n7) Salir"
    $opt = Read-Host "Opcion"
    switch ($opt) {
        "1" { Setup-IIS-FTP; Configure-FTP-Site; break }
        "2" { Add-FTP-User; break }
        "3" { Remove-FTP-User; break }
        "4" { Change-User-Group; break }
        "5" { Get-LocalGroupMember -Group $GROUP_A; Get-LocalGroupMember -Group $GROUP_B; break }
        "6" { Restart-Service ftpsvc; break }
    }
    if ($opt -ne "7") { Read-Host "Presione Enter" }
}