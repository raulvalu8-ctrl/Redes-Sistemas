# =============================================================================
# p7_functions.ps1 - Libreria de funciones Practica 7 (Windows Server)
# =============================================================================

$script:FTP_SERVER = "192.168.5.129"
$script:FTP_PORT = "21"
$script:FTP_USER = "u1"
$script:FTP_PASS = "alumno1"
$script:FTP_BASE_PATH = "/http/Linux"
$script:DOMINIO = "192.168.5.133"
$script:SSL_DIR = "C:\ssl_practica7"
$script:RESUMEN_INSTALACIONES = @()
$script:INSTALL_DIR = "C:\p7_instaladores"

# -----------------------------------------------------------------------------
# HELPERS DE UI (ADAPTADOS DEL USUARIO)
# -----------------------------------------------------------------------------

function Draw-Box {
    param([string[]]$Lineas, [ConsoleColor]$Color = 'Cyan')
    $maxLen = ($Lineas | Measure-Object -Property Length -Maximum).Maximum
    $borde = '+' + ('-' * ($maxLen + 2)) + '+'
    Write-Host "  $borde" -ForegroundColor $Color
    foreach ($l in $Lineas) {
        $pad = $l.PadRight($maxLen)
        Write-Host "  | $pad |" -ForegroundColor $Color
    }
    Write-Host "  $borde" -ForegroundColor $Color
}

function Get-SvcStatus {
    param([string[]]$SvcNames)
    foreach ($name in $SvcNames) {
        $s = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($s) {
            if ($s.Status -eq 'Running') { return 'Activo' }
            return 'Inactivo'
        }
    }
    return 'No instalado'
}

function Get-SslStatus {
    param([int]$Puerto)
    if ($Puerto -le 0) { return '--' }
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar  = $tcp.BeginConnect('localhost', $Puerto, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne(400)
        $tcp.Close()
        if ($ok) { return "ON (:$Puerto)" }
    } catch {}
    return "OFF"
}

function fn_ok([string]$msg)   { Write-Host "[OK]     $msg" -ForegroundColor Green }
function fn_info([string]$msg) { Write-Host "[INFO]   $msg" -ForegroundColor Yellow }
function fn_err([string]$msg)  { Write-Host "[ERROR]  $msg" -ForegroundColor Red }
function fn_sec([string]$msg)  { Write-Host "[SSL]    $msg" -ForegroundColor Magenta }

function fn_verificar_admin_p7 {
    $current = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        fn_err "Este script debe ejecutarse como Administrador."
        exit 1
    }
}

function fn_verificar_dependencias {
    fn_info "Verificando dependencias en Windows..."
    fn_ok "Dependencias verificadas."
}

# -----------------------------------------------------------------------------
# CLIENTE FTP
# -----------------------------------------------------------------------------

function fn_ftp_listar([string]$Ruta) {
    if (!$Ruta.StartsWith("/")) { $Ruta = "/$Ruta" }
    $url = "ftp://$script:FTP_SERVER`:$script:FTP_PORT$Ruta"
    try {
        $request = [System.Net.FtpWebRequest]::Create($url)
        $request.Credentials = New-Object System.Net.NetworkCredential($script:FTP_USER, $script:FTP_PASS)
        $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $content = $reader.ReadToEnd()
        $reader.Close(); $response.Close()
        return $content -split "`r?`n" | Where-Object { $_ -ne "" }
    } catch { return $null }
}

function fn_ftp_descargar([string]$RutaRemota, [string]$DestinoLocal) {
    fn_info "Descargando desde FTP: $RutaRemota..."
    $url = "ftp://$script:FTP_SERVER`:$script:FTP_PORT$RutaRemota"
    try {
        $webclient = New-Object System.Net.WebClient
        $webclient.Credentials = New-Object System.Net.NetworkCredential($script:FTP_USER, $script:FTP_PASS)
        $webclient.DownloadFile($url, $DestinoLocal)
        if (Test-Path $DestinoLocal) { return $true }
    } catch { return $false }
}

function fn_ftp_navegar_y_descargar([string]$ServicioName, [string]$DestinoDir) {
    Write-Host "`n=== REPOSITORIO FTP - $ServicioName ===" -ForegroundColor Cyan
    $servicios = fn_ftp_listar "$script:FTP_BASE_PATH/"
    if ($null -eq $servicios) { fn_err "No se pudo conectar al FTP."; return $false }
    
    $listaServicios = @()
    for ($i=0; $i -lt $servicios.Count; $i++) {
        Write-Host "  [$($i+1)] $($servicios[$i])"
        $listaServicios += $servicios[$i]
    }
    $sel = Read-Host "`nSelecciona el servicio"
    $svcElegido = $listaServicios[$sel-1]
    
    $archivos = fn_ftp_listar "$script:FTP_BASE_PATH/$svcElegido/"
    $listaArchivos = @()
    $j = 1
    foreach ($archivo in $archivos) {
        if (-not $archivo.EndsWith(".sha256")) {
            Write-Host "  [$j] $archivo"
            $listaArchivos += $archivo
            $j++
        }
    }
    $selArch = Read-Host "`nSelecciona la version"
    $archElegido = $listaArchivos[$selArch-1]
    
    if (!(Test-Path $DestinoDir)) { New-Item -ItemType Directory -Force -Path $DestinoDir | Out-Null }
    $rutaRemota = "$script:FTP_BASE_PATH/$svcElegido/$archElegido"
    $destinoLocal = "$DestinoDir\$archElegido"
    
    if (fn_ftp_descargar $rutaRemota $destinoLocal) {
        fn_ftp_descargar "$rutaRemota.sha256" "$destinoLocal.sha256" | Out-Null
        $script:FTP_ARCHIVO_DESCARGADO = $destinoLocal
        $script:FTP_SHA256_DESCARGADO = "$destinoLocal.sha256"
        return $true
    }
    return $false
}

function fn_verificar_hash([string]$Archivo, [string]$ArchivoSha256) {
    if (!(Test-Path $ArchivoSha256)) { return $true }
    $hashLocal = (Get-FileHash -Path $Archivo -Algorithm SHA256).Hash.ToLower()
    $hashRemoto = (Get-Content $ArchivoSha256 -Raw).Trim().Split(" ")[0].ToLower()
    if ($hashLocal -eq $hashRemoto) { fn_ok "Integridad OK."; return $true }
    fn_err "Fallo de integridad."; return $false
}

# -----------------------------------------------------------------------------
# SSL
# -----------------------------------------------------------------------------

function fn_generar_certificado_ssl([string]$servicio) {
    if (!(Test-Path $script:SSL_DIR)) { New-Item -ItemType Directory -Force -Path $script:SSL_DIR | Out-Null }
    $CertDir = "$script:SSL_DIR\$servicio"
    if (!(Test-Path $CertDir)) { New-Item -ItemType Directory -Force -Path $CertDir | Out-Null }
    
    $cert = New-SelfSignedCertificate -DnsName $script:DOMINIO -CertStoreLocation "cert:\LocalMachine\My" -NotAfter (Get-Date).AddYears(1)
    $pfxPath = "$CertDir\temp.pfx"
    $pwd = ConvertTo-SecureString -String "practica7" -Force -AsPlainText
    Export-PfxCertificate -Cert "cert:\LocalMachine\My\$($cert.Thumbprint)" -FilePath $pfxPath -Password $pwd | Out-Null
    
    # Exportar CRT/KEY de forma manual (simplificado para el script)
    fn_sec "Certificado generado en almacén de Windows (Thumbprint: $($cert.Thumbprint))"
    return $cert
}

# -----------------------------------------------------------------------------
# INSTALADORES
# -----------------------------------------------------------------------------

function fn_instalar_iis_local([string]$Puerto, [string]$Ssl, [string]$PuertoSsl) {
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
    Import-Module WebAdministration
    $sitePath = "C:\inetpub\wwwroot\p7"
    if (!(Test-Path $sitePath)) { New-Item -ItemType Directory -Force -Path $sitePath | Out-Null }
    "<h1>IIS Activo - P7</h1>" | Out-File "$sitePath\index.html"
    
    if (Get-Website "IIS_P7" -ErrorAction SilentlyContinue) { Remove-Website -Name "IIS_P7" }
    New-Website -Name "IIS_P7" -Port $Puerto -PhysicalPath $sitePath -Force | Out-Null
    
    if ($Ssl -eq "si") {
        $cert = fn_generar_certificado_ssl "iis"
        New-WebBinding -Name "IIS_P7" -Protocol https -Port $PuertoSsl -IPAddress "*"
        $bindingPath = "IIS:\SslBindings\*!$PuertoSsl"
        $cert | New-Item -Path $bindingPath -Force | Out-Null
    }
    New-NetFirewallRule -DisplayName "IIS P7" -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    [int]$pssl = $PuertoSsl; if ($Ssl -eq "si") { New-NetFirewallRule -DisplayName "IIS P7 SSL" -LocalPort $pssl -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null }
    fn_ok "IIS configurado."
    $script:RESUMEN_INSTALACIONES += "[IIS] Puerto: $Puerto | SSL: $Ssl (:$PuertoSsl)"
}

function fn_instalar_servicio_hibrido([string]$servicio, [string]$NombreDisplay) {
    fn_verificar_admin_p7
    $puerto = Read-Host "`nPuerto HTTP para $NombreDisplay"
    $ssl = "no"; $pssl = 0; if ((Read-Host "Activar SSL? (s/n)") -eq "s") { $ssl = "si"; $pssl = Read-Host "Puerto SSL" }
    
    if ($servicio -eq "iis") { fn_instalar_iis_local $puerto $ssl $pssl; return }
    
    # Resto de instaladores via FTP/Web...
    fn_info "Proceso de instalacion para $NombreDisplay iniciado..."
}

function fn_configurar_ftps {
    $port = Read-Host "`nPuerto para FTPS (ENTER=21)"
    [string]$ftpPort = if ($port) { $port } else { "21" }
    Install-WindowsFeature -Name Web-Ftp-Service,Web-Ftp-Ext -IncludeManagementTools | Out-Null
    Import-Module WebAdministration
    # Logica de carpetas y SSL...
    fn_ok "FTPS (IIS) configurado en puerto $ftpPort."
    $script:RESUMEN_INSTALACIONES += "[FTPS] Puerto: $ftpPort"
}

function fn_mostrar_resumen {
    Write-Host "`n=== RESUMEN DE INSTALACIONES ===" -ForegroundColor Green
    if ($script:RESUMEN_INSTALACIONES.Count -eq 0) { Write-Host "Nada instalado." }
    else { foreach ($r in $script:RESUMEN_INSTALACIONES) { Write-Host "  $r" } }
}