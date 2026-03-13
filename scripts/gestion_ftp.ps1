# ==============================================================
#                      SERVIDOR FTP - PRACTICA
#                   VERSION WINDOWS SERVER (IIS FTP)
# ==============================================================
#requires -RunAsAdministrator

# --- Definicion de Rutas y Constantes ---
$RAIZ_FTP          = "C:\inetpub\ftp"
$DIR_ISOLATION     = "${RAIZ_FTP}\LocalUser"
$DIR_GRUPOS        = "${RAIZ_FTP}\grupos"
$DIR_ANONIMO       = "${DIR_ISOLATION}\Public" # IIS busca 'Public' para anonimos en Modo 2
$DIR_PERSONAL      = "${RAIZ_FTP}\personal"
$DIR_HOME_LOGICO   = "${RAIZ_FTP}\users"
$DIR_PUBLICO       = "${RAIZ_FTP}\publica"

$MAQUINA           = $env:COMPUTERNAME
$DIR_IIS_USERS     = "${DIR_ISOLATION}\${MAQUINA}"

$GRP_A    = "reprobados"
$GRP_B    = "recursadores"
$GRP_BASE = "ftp_users"

# --- Funciones de Utilidad y Estetica ---
function Info   { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan   }
function Exito  { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green  }
function Error_ { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red    }
function Aviso  { param($msg) Write-Host "[AVISO] $msg" -ForegroundColor Yellow }

# --- Verificacion de privilegios ---
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Error_ "Se requieren privilegios de Administrador para continuar."
    exit 1
}

# --- Funcion central de permisos restringidos (Evita borrar/renombrar) ---
function Set-PermisoRestringido {
    param($Path, $Identity)
    $acl = Get-Acl $Path
    $rLeer = [System.Security.AccessControl.FileSystemRights] "ReadAndExecute, ListDirectory"
    $ruleLeer = New-Object System.Security.AccessControl.FileSystemAccessRule($Identity, $rLeer, "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($ruleLeer)

    $rEsc = [System.Security.AccessControl.FileSystemRights] "CreateFiles, CreateDirectories, AppendData, WriteData, WriteAttributes, WriteExtendedAttributes"
    $ruleEsc = New-Object System.Security.AccessControl.FileSystemAccessRule($Identity, $rEsc, "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($ruleEsc)

    $rDeny = [System.Security.AccessControl.FileSystemRights] "Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership"
    $ruleDeny = New-Object System.Security.AccessControl.FileSystemAccessRule($Identity, $rDeny, "ContainerInherit,ObjectInherit", "None", "Deny")
    $acl.AddAccessRule($ruleDeny)
    Set-Acl -Path $Path -AclObject $acl
}

# --- Permiso completo solo para carpeta personal ---
function Set-PermisoPersonal {
    param($Path, $Identity)
    $acl  = Get-Acl $Path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($Identity, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl -Path $Path -AclObject $acl
}

# --- Permiso de solo lectura estricto ---
function Set-PermisoAnonimo {
    param($Path)
    try {
        $acl = Get-Acl $Path
        foreach ($id in @("NT AUTHORITY\SERVICIO DE INTERNET", "Todos")) {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($id, "ReadAndExecute, ListDirectory", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.AddAccessRule($rule)
        }
        # Denegar cualquier escritura o borrado
        $rDeny = [System.Security.AccessControl.FileSystemRights] "Write, Delete, DeleteSubdirectoriesAndFiles, ChangePermissions"
        $ruleDeny = New-Object System.Security.AccessControl.FileSystemAccessRule("Todos", $rDeny, "ContainerInherit,ObjectInherit", "None", "Deny")
        $acl.AddAccessRule($ruleDeny)
        Set-Acl -Path $Path -AclObject $acl
    } catch { Aviso "Error en permisos anonimos de ${Path}" }
}

# 1. INICIALIZAR SISTEMA
function Inicializar-Sistema {
    Info "Validando instalaciones..."
    $iis = Get-WindowsFeature -Name Web-Server, Web-Ftp-Server, Web-Ftp-Service | Where-Object { $_.InstallState -eq "Installed" }
    if ($iis.Count -lt 3) {
        Info "Instalando componentes necesarios..."
        Install-WindowsFeature -Name Web-Server, Web-Ftp-Server, Web-Ftp-Service -IncludeManagementTools | Out-Null
    }
    fsutil behavior set SymlinkEvaluation L2L:1 L2R:1 R2L:1 R2R:1 | Out-Null
    Exito "Sistema listo."
}

# 2. PREPARAR ENTORNO FTP
function Preparar-EntornoFTP {
    Info "Creando estructura en ${RAIZ_FTP}..."
    $directorios = @($DIR_ISOLATION, $DIR_GRUPOS, $DIR_PERSONAL, $DIR_HOME_LOGICO, $DIR_IIS_USERS, $DIR_ANONIMO, $DIR_PUBLICO)
    foreach ($dir in $directorios) { if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null } }

    foreach ($g in @($GRP_A, $GRP_B, $GRP_BASE)) {
        if (-not (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $g | Out-Null }
    }

    # Permisos de travesia RX para evitar 530
    icacls $RAIZ_FTP /grant "*S-1-1-0:(OI)(CI)RX" /Q | Out-Null
    icacls $DIR_ISOLATION /grant "*S-1-1-0:(OI)(CI)RX" /Q | Out-Null

    # Firewall
    if (-not (Get-NetFirewallRule -DisplayName "FTP-Control" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP-Control" -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow | Out-Null
        New-NetFirewallRule -DisplayName "FTP-Passive" -Direction Inbound -Protocol TCP -LocalPort 5000-5100 -Action Allow | Out-Null
    }
    Exito "Entorno configurado."
}

# 3. DESPLEGAR CONFIGURACION IIS
function Desplegar-Configuracion {
    Import-Module WebAdministration
    $site = "ServidorFTP"
    if (Get-Website -Name $site -ErrorAction SilentlyContinue) { Remove-Website -Name $site | Out-Null }
    New-WebFtpSite -Name $site -PhysicalPath $RAIZ_FTP -Port 21 -Force | Out-Null

    # Aislamiento Modo 2
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$site']/ftpServer/userIsolation" -Name "mode" -Value "IsolateAllDirectories"
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$site']/ftpServer/security/authentication/basicAuthentication" -Name "enabled" -Value $true
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='$site']/ftpServer/security/authentication/anonymousAuthentication" -Name "enabled" -Value $true
    Set-WebConfigurationProperty -Filter "/system.ftpServer/firewallSupport" -Name "lowDataPort" -Value 5000
    Set-WebConfigurationProperty -Filter "/system.ftpServer/firewallSupport" -Name "highDataPort" -Value 5100

    Clear-WebConfiguration -Filter "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Location $site
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Location $site -Value @{accessType="Allow"; users="?"; permissions="Read"}
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Location $site -Value @{accessType="Allow"; users="*"; permissions="Read, Write"}

    # --- ANONIMO: SOLO CARPETA PUBLICA ---
    if (Test-Path $DIR_ANONIMO) { Get-ChildItem $DIR_ANONIMO | ForEach-Object { if ($_.LinkType -eq "Junction") { cmd /c "rmdir /Q ""$($_.FullName)""" } else { Remove-Item $_.FullName -Recurse -Force } } }
    New-Item -ItemType Directory -Path $DIR_ANONIMO -Force | Out-Null
    cmd /c "mklink /J ""${DIR_ANONIMO}\publica"" ""${DIR_PUBLICO}""" | Out-Null
    
    Set-PermisoAnonimo $DIR_ANONIMO
    Set-PermisoAnonimo "${DIR_ANONIMO}\publica"
    
    Restart-Service ftpsvc -Force
    Exito "Servidor FTP Desplegado. Anonimo: solo 'publica' (Solo Lectura)."
}

# 4. REGISTRAR USUARIOS
function Registrar-UsuariosFTP {
    $total = Read-Host "Cuentas a crear"
    for ($c = 1; $c -le [int]$total; $c++) {
        $user_id = Read-Host "[$c/$total] Alias"
        $passText = Read-Host "Password para ${user_id}"
        $user_key = ConvertTo-SecureString $passText -AsPlainText -Force
        
        Write-Host "Perfil: A) ${GRP_A} | B) ${GRP_B}"
        $optP = Read-Host "Opcion (A/B)"
        $perfil_sel = if ($optP -ieq "B") { $GRP_B } else { $GRP_A }

        if (-not (Get-LocalUser -Name $user_id -ErrorAction SilentlyContinue)) {
            New-LocalUser -Name $user_id -Password $user_key -Description "Usuario FTP" -PasswordNeverExpires | Out-Null
        } else { Set-LocalUser -Name $user_id -Password $user_key }

        Add-LocalGroupMember -Group $GRP_BASE -Member $user_id -ErrorAction SilentlyContinue
        foreach ($g in @($GRP_A, $GRP_B)) { Remove-LocalGroupMember -Group $g -Member $user_id -ErrorAction SilentlyContinue }
        Add-LocalGroupMember -Group $perfil_sel -Member $user_id -ErrorAction SilentlyContinue

        $home = "${DIR_IIS_USERS}\${user_id}"
        if (-not (Test-Path $home)) { New-Item -ItemType Directory -Path $home -Force | Out-Null }
        
        $pers = "${DIR_PERSONAL}\${user_id}"
        if (-not (Test-Path $pers)) { New-Item -ItemType Directory -Path $pers -Force | Out-Null }

        # Limpiar junctions
        Get-ChildItem $home | Where-Object { $_.LinkType -eq "Junction" } | ForEach-Object { cmd /c "rmdir /Q ""$($_.FullName)""" }
        
        cmd /c "mklink /J ""${home}\publica"" ""${DIR_PUBLICO}""" | Out-Null
        cmd /c "mklink /J ""${home}\user"" ""${pers}""" | Out-Null
        cmd /c "mklink /J ""${home}\${perfil_sel}"" ""${DIR_GRUPOS}\${perfil_sel}""" | Out-Null

        Set-PermisoRestringido -Path $home -Identity $user_id
        Set-PermisoPersonal -Path $pers -Identity $user_id
        Exito "Usuario '${user_id}' listo."
    }
}

# 5. MIGRAR USUARIO
function Migrar-Usuario {
    $target = Read-Host "Usuario a modificar"
    if (Get-LocalUser -Name $target -ErrorAction SilentlyContinue) {
        Write-Host "Nuevo perfil: 1) ${GRP_A} | 2) ${GRP_B}"
        $o = Read-Host "Seleccion"
        $nuevo = if ($o -eq "2") { $GRP_B } else { $GRP_A }
        $viejo = if ($o -eq "2") { $GRP_A } else { $GRP_B }

        Remove-LocalGroupMember -Group $viejo -Member $target -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group $nuevo -Member $target -ErrorAction SilentlyContinue
        
        $home = "${DIR_IIS_USERS}\${target}"
        if (Test-Path "${home}\${viejo}") { cmd /c "rmdir /Q ""${home}\${viejo}""" }
        cmd /c "mklink /J ""${home}\${nuevo}"" ""${DIR_GRUPOS}\${nuevo}""" | Out-Null
        Exito "Migrado a ${nuevo}."
    }
}

# 6. BAJA DE USUARIO
function Baja-Usuario {
    $u = Read-Host "Usuario a borrar"
    if (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) {
        Remove-LocalUser -Name $u
        Remove-Item "${DIR_IIS_USERS}\${u}" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "${DIR_PERSONAL}\${u}" -Recurse -Force -ErrorAction SilentlyContinue
        Exito "Eliminado."
    }
}

# 7. VALIDAR ESTRUCTURA
function Validar-Login {
    $u = Read-Host "Nombre de usuario"
    if (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) {
        $home = "${DIR_IIS_USERS}\${u}"
        if (Test-Path $home) { Get-ChildItem $home | Select Name, Attributes } else { Error_ "Home inexistente!" }
    } else { Error_ "No encontrado." }
    Read-Host "Enter..."
}

# --- MENU ---
$opc = 0
while ($opc -ne 7) {
    Clear-Host
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "   GESTOR FTP (IIS) - RDS                       " -ForegroundColor White
    Write-Host "   Maquina: ${MAQUINA}"                          -ForegroundColor White
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "  1) Despliegue: Instalar y Configurar IIS FTP"
    Write-Host "  2) Usuarios: Registro de Cuentas"
    Write-Host "  3) Auditoria: Ver Usuarios en Sistema"
    Write-Host "  4) Gestion: Modificar Perfil de Usuario"
    Write-Host "  5) Seguridad: Eliminar Cuenta de Usuario"
    Write-Host "  6) Simulacion: Prueba de Directorios"
    Write-Host "  7) Finalizar Aplicacion"
    Write-Host "------------------------------------------------"
    $in = Read-Host "Seleccion [1-7]"
    $opc = if ($in -match '^[1-7]$') { [int]$in } else { 0 }
    
    switch ($opc) {
        1 { Inicializar-Sistema; Preparar-EntornoFTP; Desplegar-Configuracion }
        2 { Registrar-UsuariosFTP }
        3 { Get-LocalUser | Where-Object { $_.Description -eq "Usuario FTP" } | Select Name, Enabled | Format-Table -AutoSize; Read-Host "Enter..." }
        4 { Migrar-Usuario }
        5 { Baja-Usuario }
        6 { Validar-Login }
        7 { Exito "Cerrando..." }
    }
    if ($opc -notin @(7,3,6)) { Start-Sleep -Seconds 1 }
}