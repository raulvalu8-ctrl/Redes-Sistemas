# ==============================================================
#                 GESTION DE SERVIDOR FTP (IIS)
# ==============================================================
#requires -RunAsAdministrator

# --- CONFIGURACION DE RUTAS ---
$BASE_PATH   = "C:\inetpub\ftp"
$GROUPS_DIR  = "$BASE_PATH\grupos"
$USERS_HOME  = "$BASE_PATH\$env:COMPUTERNAME"
$PUBLIC_DIR   = "$BASE_PATH\publica"

$GROUP_A    = "reprobados"
$GROUP_B    = "recursadores"
$GROUP_BASE = "ftp_users"

# --- FUNCIONES DE LOGGING (SIN ACENTOS) ---
function Log-Info { param($msg) Write-Host "[INFO] $msg" }
function Log-Error { param($msg) Write-Host "[ERROR] $msg" }

# --- VALIDACION DE PRIVILEGIOS ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Log-Host "Se requieren permisos de administrador."
    exit 1
}

# --- FUNCION: DESACTIVAR POLITICAS DE CONTRASENA ---
function Desactivar-Politicas-Pass {
    Log-Info "Desactivando requisitos de complejidad y longitud de contrasenas..."
    $cfgFile = "$env:TEMP\sec.cfg"
    $logFile = "$env:TEMP\sec.log"
    
    # Exportar politica actual
    secedit /export /cfg $cfgFile /quiet
    
    # Modificar valores en el archivo temporal
    (Get-Content $cfgFile) | ForEach-Object {
        $_ -replace "PasswordComplexity = 1", "PasswordComplexity = 0" `
           -replace "MinimumPasswordLength = .*", "MinimumPasswordLength = 0"
    } | Set-Content $cfgFile
    
    # Importar y aplicar politica modificada
    secedit /configure /db "$env:TEMP\sec.sdb" /cfg $cfgFile /areas SECURITYPOLICY /log $logFile /quiet
    
    # Forzar cambio mediante comando net
    net accounts /minpwlen:0 /maxpwage:unlimited /minpwage:0 /force | Out-Null
    
    Log-Info "Politicas de seguridad relajadas correctamente."
}

# --- 1. INSTALACION Y RECURSOS ---
function Setup-IIS-FTP {
    Desactivar-Politicas-Pass
    
    Log-Info "Verificando componentes de IIS y FTP..."
    $features = @("Web-Server", "Web-Ftp-Server", "Web-Ftp-Service", "Web-Mgmt-Console")
    foreach ($f in $features) {
        if ((Get-WindowsFeature -Name $f).InstallState -ne "Installed") {
            Log-Info "Instalando $f..."
            Install-WindowsFeature -Name $f -IncludeManagementTools | Out-Null
        }
    }
    
    # Estructura de Carpetas
    Log-Info "Generando estructura de directorios..."
    $dirs = @($BASE_PATH, $GROUPS_DIR, $USERS_HOME, $PUBLIC_DIR, "$GROUPS_DIR\$GROUP_A", "$GROUPS_DIR\$GROUP_B")
    foreach ($d in $dirs) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

    # Grupos Locales
    Log-Info "Asegurando grupos de seguridad..."
    foreach ($g in @($GROUP_A, $GROUP_B, $GROUP_BASE)) {
        if (-not (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $g | Out-Null
        }
    }
}

# --- 2. CONFIGURACION DEL SITIO FTP ---
function Configure-FTP-Site {
    Import-Module WebAdministration
    $SiteName = "ServidorFTP"
    Log-Info "Desplegando Sitio FTP '$SiteName'..."
    
    try {
        if (Get-Website -Name $SiteName -ErrorAction SilentlyContinue) {
            Remove-Website -Name $SiteName -ErrorAction SilentlyContinue
        }
    } catch {
        Log-Error "Aviso: No se pudo limpiar el sitio previo, intentando continuar..."
    }
    
    New-WebFtpSite -Name $SiteName -PhysicalPath $BASE_PATH -Port 21 -Force | Out-Null
    
    # Configuracion nativa via IIS (Sin Acentos en Strings):
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$SiteName']/ftpServer/userIsolation" -Name "mode" -Value "IsolateAllDirectories"
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$SiteName']/ftpServer/security/authentication/basicAuthentication" -Name "enabled" -Value $true
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$SiteName']/ftpServer/security/authentication/anonymousAuthentication" -Name "enabled" -Value $false
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$SiteName']/ftpServer/security/ssl" -Name "controlChannelPolicy" -Value "SslAllow"
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$SiteName']/ftpServer/security/ssl" -Name "dataChannelPolicy" -Value "SslAllow"
    
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Location $SiteName -Value @{accessType="Allow"; users="*"; permissions="Read, Write"}
    
    Restart-Service ftpsvc
    Log-Info "Sitio FTP listo en puerto 21."
}

# --- 3. GESTION DE USUARIOS ---
function Add-FTP-User {
    $user = Read-Host "Nombre del nuevo usuario"
    $passText = Read-Host "Contrasena (Puede ser simple)"
    $pass = ConvertTo-SecureString $passText -AsPlainText -Force
    $group = $GROUP_A

    if (-not (Get-LocalUser -Name $user -ErrorAction SilentlyContinue)) {
        try {
            New-LocalUser -Name $user -Password $pass -PasswordNeverExpires -ErrorAction Stop | Out-Null
            
            Add-LocalGroupMember -Group $GROUP_BASE -Member $user
            Add-LocalGroupMember -Group $group -Member $user
            
            $homePath = "$USERS_HOME\$user"
            New-Item -ItemType Directory -Path $homePath -Force | Out-Null
            
            # Carpeta Personal (Local al home del usuario)
            New-Item -ItemType Directory -Path "$homePath\usuario" -Force | Out-Null
            
            # Otorgar permisos de modificacion al usuario en su carpeta
            icacls "$homePath\usuario" /grant "${user}:(OI)(CI)M" | Out-Null

            # Junctions (Mklink) para carpetas compartidas
            cmd /c "mklink /J ""$homePath\publica"" ""$PUBLIC_DIR""" | Out-Null
            cmd /c "mklink /J ""$homePath\$group"" ""$GROUPS_DIR\$group""" | Out-Null
            
            # Limpiar carpeta tmp si existe
            if (Test-Path "$homePath\tmp") { Remove-Item "$homePath\tmp" -Recurse -Force }

            Log-Info "Usuario '$user' configurado con carpetas: publica, $group y usuario."
        } catch {
            Log-Error "Error al crear el usuario. Revisa si las politicas se aplicaron correctamente."
        }
    } else {
        Log-Error "Error: El usuario '$user' ya existe."
    }
}

function Remove-FTP-User {
    $user = Read-Host "Usuario a dar de baja"
    if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
        $homePath = "$USERS_HOME\$user"
        if (Test-Path $homePath) { Remove-Item $homePath -Recurse -Force }
        Remove-LocalUser -Name $user
        Log-Info "Baja de '$user' completada."
    }
}

# --- 4. CAMBIO DE PERFIL (GRUPO) ---
function Change-User-Group {
    $user = Read-Host "Usuario a migrar"
    if (-not (Get-LocalUser -Name $user -ErrorAction SilentlyContinue)) {
        Log-Error "Error: Usuario '$user' no encontrado."
        return
    }

    $cGroup = ""
    if (Get-LocalGroupMember -Group $GROUP_A | Where-Object { $_.Name -like "*\$user" }) { $cGroup = $GROUP_A }
    elseif (Get-LocalGroupMember -Group $GROUP_B | Where-Object { $_.Name -like "*\$user" }) { $cGroup = $GROUP_B }

    Log-Info "Usuario: $user | Actual: $cGroup"
    Write-Host "Mover a: 1) $GROUP_A  2) $GROUP_B"
    $opt = Read-Host "Nueva seleccion"
    $nGroup = if ($opt -eq "2") { $GROUP_B } else { $GROUP_A }

    if ($cGroup -eq $nGroup) {
        Log-Info "El usuario ya esta en el grupo $nGroup."
        return
    }

    if ($cGroup) { Remove-LocalGroupMember -Group $cGroup -Member $user }
    Add-LocalGroupMember -Group $nGroup -Member $user

    $hPath = "$USERS_HOME\$user"
    if (Test-Path "$hPath\$cGroup") { cmd /c "rmdir ""$hPath\$cGroup""" }
    cmd /c "mklink /J ""$hPath\$nGroup"" ""$GROUPS_DIR\$nGroup""" | Out-Null

    # Asegurar que las carpetas base existen
    if (-not (Test-Path "$hPath\usuario")) { New-Item -ItemType Directory -Path "$hPath\usuario" -Force | Out-Null }
    if (-not (Test-Path "$hPath\publica")) { cmd /c "mklink /J ""$hPath\publica"" ""$PUBLIC_DIR""" | Out-Null }

    # Limpiar carpeta tmp si existe
    if (Test-Path "$hPath\tmp") { Remove-Item "$hPath\tmp" -Recurse -Force }

    Log-Info "Migracion de '$user' a '$nGroup' exitosa."
}

# --- BUCLE DE MENU ---
$currentChoice = "0"
while ($currentChoice -ne "7") {
    Clear-Host
    Write-Host "-------------------------------------------"
    Write-Host "    CONTROL DE SERVIDOR FTP - WINDOWS      "
    Write-Host "-------------------------------------------"
    Write-Host "1) Despliegue de IIS y Sitio FTP"
    Write-Host "2) Registrar un Usuario Nuevo"
    Write-Host "3) Eliminar un Usuario del Sistema"
    Write-Host "4) Cambiar Perfil (Grupo) de Usuario"
    Write-Host "5) Auditoria de Cuentas por Grupo"
    Write-Host "6) Forzar Reinicio del Servicio"
    Write-Host "7) Finalizar Salida"
    Write-Host "-------------------------------------------"
    $currentChoice = Read-Host "Ingrese seleccion"

    switch ($currentChoice) {
        "1" { Setup-IIS-FTP; Configure-FTP-Site; break }
        "2" { Add-FTP-User; break }
        "3" { Remove-FTP-User; break }
        "4" { Change-User-Group; break }
        "5" { 
              Write-Host "Listado ${GROUP_A}:"
              Get-LocalGroupMember -Group $GROUP_A | Select-Object Name
              Write-Host "Listado ${GROUP_B}:"
              Get-LocalGroupMember -Group $GROUP_B | Select-Object Name
              break 
            }
        "6" { Restart-Service ftpsvc; Log-Info "Servicio FTP reiniciado."; break }
        "7" { Log-Info "Saliendo..."; break }
    }
    if ($currentChoice -ne "7") { Read-Host "...Presione Enter" }
}