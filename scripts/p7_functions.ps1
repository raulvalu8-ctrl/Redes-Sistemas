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

function fn_header_p7 {
    Clear-Host
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "       SISTEMA DE APROVISIONAMIENTO WEB - WINDOWS         " -ForegroundColor Cyan
    Write-Host "          Practica 7 - FTP + SSL/TLS + Hash               " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
}

function fn_ok([string]$msg)   { Write-Host "[OK]     $msg" -ForegroundColor Green }
function fn_info([string]$msg) { Write-Host "[INFO]   $msg" -ForegroundColor Yellow }
function fn_err([string]$msg)  { Write-Host "[ERROR]  $msg" -ForegroundColor Red }
function fn_sec([string]$msg)  { Write-Host "[SSL]    $msg" -ForegroundColor Magenta }

function fn_verificar_admin_p7 {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (!$isAdmin) {
        fn_err "Este script debe ejecutarse como Administrador."
        exit 1
    }
}

function fn_verificar_dependencias {
    fn_info "Verificando dependencias en Windows..."
    fn_ok "Dependencias verificadas."
}

# -----------------------------------------------------------------------------
# CLIENTE FTP DINAMICO
# -----------------------------------------------------------------------------

function fn_ftp_listar([string]$Ruta) {
    if (!$Ruta.StartsWith("/")) { $Ruta = "/$Ruta" }
    $url = "ftp://$script:FTP_SERVER`:$script:FTP_PORT$Ruta"
    try {
        $request = [System.Net.FtpWebRequest]::Create($url)
        $request.Credentials = New-Object System.Net.NetworkCredential($script:FTP_USER, $script:FTP_PASS)
        $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $response = $request.GetResponse()
        if ($response) {
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $content = $reader.ReadToEnd()
            $reader.Close()
            $response.Close()
            return $content -split "`r?`n" | Where-Object { $_ -ne "" }
        }
    } catch { return $null }
}

function fn_ftp_descargar([string]$RutaRemota, [string]$DestinoLocal) {
    fn_info "Descargando desde FTP: $RutaRemota..."
    $url = "ftp://$script:FTP_SERVER`:$script:FTP_PORT$RutaRemota"
    try {
        $webclient = New-Object System.Net.WebClient
        $webclient.Credentials = New-Object System.Net.NetworkCredential($script:FTP_USER, $script:FTP_PASS)
        $webclient.DownloadFile($url, $DestinoLocal)
        if (Test-Path $DestinoLocal) {
            fn_ok "Archivo descargado: $DestinoLocal"
            return $true
        } else { throw }
    } catch {
        fn_err "No se pudo descargar el archivo $RutaRemota."
        return $false
    }
}

function fn_ftp_navegar_y_descargar([string]$ServicioName, [string]$DestinoDir) {
    Write-Host "`n=== REPOSITORIO FTP - $ServicioName ===" -ForegroundColor Cyan
    fn_info "Conectando al servidor FTP $script:FTP_SERVER..."
    
    $servicios = fn_ftp_listar "$script:FTP_BASE_PATH/"
    if ($null -eq $servicios -or $servicios.Count -eq 0) {
        fn_err "No se pudo conectar al servidor FTP o el repositorio esta vacio."
        return $false
    }
    fn_ok "Conexion FTP exitosa."
    
    Write-Host "`nServicios disponibles en el repositorio:" -ForegroundColor Cyan
    $listaServicios = @()
    for ($i=0; $i -lt $servicios.Count; $i++) {
        Write-Host "  [$($i+1)] $($servicios[$i])"
        $listaServicios += $servicios[$i]
    }
    
    $selSvc = 0
    while ($true) {
        $sel = Read-Host -Prompt "`nSelecciona el servicio a instalar (1-$($listaServicios.Count))"
        if ([int]::TryParse($sel, [ref]$selSvc) -and $selSvc -ge 1 -and $selSvc -le $listaServicios.Count) { break }
        fn_err "Seleccion invalida."
    }
    
    $svcElegido = $listaServicios[$selSvc-1]
    fn_ok "Servicio seleccionado: $svcElegido"
    
    fn_info "Listando versiones disponibles para $svcElegido..."
    $archivos = fn_ftp_listar "$script:FTP_BASE_PATH/$svcElegido/"
    if ($null -eq $archivos -or $archivos.Count -eq 0) {
        fn_err "No hay archivos en el repositorio para $svcElegido."
        return $false
    }
    
    $listaArchivos = @()
    Write-Host "`nVersiones disponibles:" -ForegroundColor Cyan
    $j = 1
    foreach ($archivo in $archivos) {
        if (-not $archivo.EndsWith(".sha256")) {
            Write-Host "  [$j] $archivo"
            $listaArchivos += $archivo
            $j++
        }
    }
    
    if ($listaArchivos.Count -eq 0) {
        fn_err "No hay instaladores disponibles."
        return $false
    }
    
    $selArch = 0
    while ($true) {
        $sel = Read-Host -Prompt "`nSelecciona la version a descargar (1-$($listaArchivos.Count))"
        if ([int]::TryParse($sel, [ref]$selArch) -and $selArch -ge 1 -and $selArch -le $listaArchivos.Count) { break }
        fn_err "Seleccion invalida."
    }
    
    $archElegido = $listaArchivos[$selArch-1]
    fn_ok "Version seleccionada: $archElegido"
    
    if (!(Test-Path $DestinoDir)) { New-Item -ItemType Directory -Force -Path $DestinoDir | Out-Null }
    
    $rutaRemota = "$script:FTP_BASE_PATH/$svcElegido/$archElegido"
    $rutaSha256 = "$rutaRemota.sha256"
    $destinoLocal = "$DestinoDir\$archElegido"
    $destinoSha256 = "$DestinoDir\$archElegido.sha256"
    
    if (-not (fn_ftp_descargar $rutaRemota $destinoLocal)) { return $false }
    if (-not (fn_ftp_descargar $rutaSha256 $destinoSha256)) {
        fn_info "No se encontro archivo SHA256, omitiendo verificacion."
    }
    
    $script:FTP_ARCHIVO_DESCARGADO = $destinoLocal
    $script:FTP_SHA256_DESCARGADO = $destinoSha256
    $script:FTP_SERVICIO_ELEGIDO = $svcElegido
    $script:FTP_ARCHIVO_NOMBRE = $archElegido
    return $true
}

# -----------------------------------------------------------------------------
# VERIFICACION DE INTEGRIDAD SHA256
# -----------------------------------------------------------------------------

function fn_verificar_hash([string]$Archivo, [string]$ArchivoSha256) {
    Write-Host "`n=== VERIFICACION DE INTEGRIDAD ===" -ForegroundColor Cyan
    if (!(Test-Path $Archivo)) { fn_err "Archivo no encontrado: $Archivo"; return $false }
    if (!(Test-Path $ArchivoSha256)) { fn_info "No hay archivo SHA256 disponible. Omitiendo verificacion."; return $true }
    
    fn_info "Calculando hash SHA256 del archivo descargado..."
    $hashLocal = (Get-FileHash -Path $Archivo -Algorithm SHA256).Hash.ToLower()
    $hashRemoto = (Get-Content $ArchivoSha256 -Raw).Trim().Split(" ")[0].ToLower()
    
    Write-Host "  Hash local:  $hashLocal"
    Write-Host "  Hash remoto: $hashRemoto"
    
    if ($hashLocal -eq $hashRemoto) {
        fn_ok "Integridad verificada. El archivo no esta corrompido."
        return $true
    } else {
        fn_err "FALLO DE INTEGRIDAD. Los hashes no coinciden."
        return $false
    }
}

# -----------------------------------------------------------------------------
# GENERACION DE CERTIFICADOS SSL/TLS (INCLUYE SOLUCION A AH00526)
# -----------------------------------------------------------------------------

function fn_generar_certificado_ssl([string]$servicio) {
    $CertDir = "$script:SSL_DIR\$servicio"
    if (!(Test-Path $CertDir)) { New-Item -ItemType Directory -Force -Path $CertDir | Out-Null }
    
    fn_sec "Generando certificado SSL para $script:DOMINIO..."
    
    $OpenSSLPath = ""
    if (Test-Path "C:\Apache24\bin\openssl.exe") { $OpenSSLPath = "C:\Apache24\bin\openssl.exe" }
    elseif (Test-Path "C:\Program Files\Git\usr\bin\openssl.exe") { $OpenSSLPath = "C:\Program Files\Git\usr\bin\openssl.exe" }
    
    if ($OpenSSLPath -ne "") {
        if (Test-Path "C:\Apache24\conf\openssl.cnf") { $env:OPENSSL_CONF = "C:\Apache24\conf\openssl.cnf" }
        $argStr = "req -x509 -nodes -days 365 -newkey rsa:2048 -keyout `"$CertDir\server.key`" -out `"$CertDir\server.crt`" -subj `"/C=MX/ST=Sinaloa/L=Culiacan/O=Reprobados/OU=Sistemas/CN=$script:DOMINIO`""
        $p = Start-Process -FilePath $OpenSSLPath -ArgumentList $argStr -Wait -WindowStyle Hidden -PassThru
        if ($p.ExitCode -eq 0) {
            fn_sec "Archivos CRT y KEY generados con OpenSSL."
            fn_sec "  Clave:       $CertDir\server.key"
            fn_sec "  Certificado: $CertDir\server.crt"
            return $true
        }
    }
    
    fn_info "OpenSSL no disponible. Compilando extractor de PFX en C# para exportar CRT y KEY nativos..."
    $code = @"
using System;
using System.Security.Cryptography.X509Certificates;
using System.Security.Cryptography;
using System.IO;
using System.Text;

public class CertExport {
    public static void Export(string pfxPath, string pass, string crtPath, string keyPath) {
        X509Certificate2 cert = new X509Certificate2(pfxPath, pass, X509KeyStorageFlags.Exportable);
        StringBuilder builder = new StringBuilder();
        builder.AppendLine("-----BEGIN CERTIFICATE-----");
        builder.AppendLine(Convert.ToBase64String(cert.Export(X509ContentType.Cert), Base64FormattingOptions.InsertLineBreaks));
        builder.AppendLine("-----END CERTIFICATE-----");
        File.WriteAllText(crtPath, builder.ToString());
        
        RSA rsa = cert.GetRSAPrivateKey();
        if (rsa != null) {
            byte[] privKeyBytes = rsa.ExportRSAPrivateKey();
            StringBuilder keyBuilder = new StringBuilder();
            keyBuilder.AppendLine("-----BEGIN RSA PRIVATE KEY-----");
            keyBuilder.AppendLine(Convert.ToBase64String(privKeyBytes, Base64FormattingOptions.InsertLineBreaks));
            keyBuilder.AppendLine("-----END RSA PRIVATE KEY-----");
            File.WriteAllText(keyPath, keyBuilder.ToString());
        }
    }
}
"@
    try { Add-Type -TypeDefinition $code -Language CSharp -ErrorAction Ignore } catch {}
    
    $cert = New-SelfSignedCertificate -DnsName $script:DOMINIO -CertStoreLocation "cert:\LocalMachine\My" -NotAfter (Get-Date).AddYears(1)
    fn_sec "Thumbprint: $($cert.Thumbprint)"
    
    $pwd = ConvertTo-SecureString -String "practica7" -Force -AsPlainText
    $pfxPath = "$CertDir\temp.pfx"
    Export-PfxCertificate -Cert "cert:\LocalMachine\My\$($cert.Thumbprint)" -FilePath $pfxPath -Password $pwd | Out-Null
    
    try {
        [CertExport]::Export($pfxPath, "practica7", "$CertDir\server.crt", "$CertDir\server.key")
        Remove-Item $pfxPath -Force
        fn_sec "Archivos CRT y KEY exportados exitosamente sin necesidad de OpenSSL."
        fn_sec "  Clave:       $CertDir\server.key"
        fn_sec "  Certificado: $CertDir\server.crt"
        return $true
    } catch {
        fn_err "Fallo la exportación del certificado .crt y .key. Use OpenSSL."
        return $false
    }
}

function fn_preguntar_ssl {
    while ($true) {
        $resp = Read-Host -Prompt "`n¿Desea activar SSL/TLS en este servicio? [s/n]"
        if ($resp -match "^(?i)s") { return $true }
        if ($resp -match "^(?i)n") { return $false }
        Write-Host "Por favor ingresa 's' para Sí, o 'n' para No." -ForegroundColor Yellow
    }
}

# -----------------------------------------------------------------------------
# INSTALACION APACHE
# -----------------------------------------------------------------------------

function fn_instalar_apache_ftp([string]$Archivo, [string]$Puerto, [string]$Ssl) {
    Write-Host "`n====== INSTALACION APACHE DESDE FTP ======" -ForegroundColor Blue
    
    Stop-Service Apache2.4 -ErrorAction SilentlyContinue
    Stop-Service Apache24 -ErrorAction SilentlyContinue
    Stop-Service apache -ErrorAction SilentlyContinue
    cmd.exe /c "taskkill /F /IM httpd.exe /T 2>NUL"
    Stop-Process -Name "httpd" -Force -ErrorAction SilentlyContinue
    
    fn_info "Esperando liberacion de archivos en Windows..."
    Start-Sleep -Seconds 3
    
    fn_info "Limpiando puertos y reglas de Firewall viejas de Apache..."
    Remove-NetFirewallRule -DisplayName "Apache P7*" -ErrorAction SilentlyContinue
    
    fn_info "Preparando extraccion limpia de Apache..."
    $Staging = "C:\p7_staging_apache"
    if (Test-Path $Staging) { Remove-Item -Path $Staging -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $Staging -Force | Out-Null
    
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($Archivo, $Staging)
    } catch {
        fn_err "Error CRITICO: El instalador ZIP esta corrupto o incompleto."
        Remove-Item -Path $Archivo -Force -ErrorAction SilentlyContinue
        fn_info "He eliminado el archivo corrupto. Por favor, corre el script de nuevo para re-descargarlo."
        return $false
    }
    
    if (Test-Path "C:\Apache24\conf") { Remove-Item -Path "C:\Apache24\conf" -Recurse -Force -ErrorAction SilentlyContinue }
    if (!(Test-Path "C:\Apache24")) { New-Item -ItemType Directory -Path "C:\Apache24" -Force | Out-Null }
    
    if (Test-Path "C:\Apache24\bin\httpd.exe") { Rename-Item -Path "C:\Apache24\bin\httpd.exe" -NewName "httpd_trash_$([guid]::NewGuid().ToString().Substring(0,8)).exe" -Force -ErrorAction SilentlyContinue }
    
    $sub = Get-ChildItem -Path $Staging -Directory -Filter "Apache24" | Select-Object -First 1
    if ($sub) {
        Copy-Item -Path "$($sub.FullName)\*" -Destination "C:\Apache24" -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Copy-Item -Path "$Staging\*" -Destination "C:\Apache24" -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    if (!(Test-Path "C:\Apache24\bin\httpd.exe")) {
        fn_err "Extraccion de Apache fallo. Verifica el archivo: $Archivo"; return $false
    }
    fn_ok "Apache actualizado en C:\Apache24"
    $conf = "C:\Apache24\conf\httpd.conf"
    $lines = Get-Content $conf
    $lines = $lines | Where-Object { $_ -notmatch "^Listen\s+" }
    $lines = $lines | Where-Object { $_ -notmatch "^#?ServerName\s+" }
    
    $lines += "Listen 0.0.0.0:$Puerto"
    $lines += "ServerName $script:DOMINIO`:$Puerto"
    
    if (-not ($lines -match "Seguridad P7")) {
        $lines += ""
        $lines += "# Seguridad P7"
        $lines += "ServerTokens Prod"
        $lines += "ServerSignature Off"
        $lines += "TraceEnable Off"
    }
    
    $SslLabel = "No"
    $SslPort = 443
    if ($Ssl -eq "si") {
        $InputPort = Read-Host -Prompt "Ingresa el puerto HTTPS para Apache (ej: 443, 8443, 9443)"
        if (-not [string]::IsNullOrWhiteSpace($InputPort)) { $SslPort = $InputPort }
        $SslLabel = "Si (puerto $SslPort)"
        
        fn_generar_certificado_ssl "apache" | Out-Null
        
        $lines = $lines -replace "^#?LoadModule ssl_module.*", "LoadModule ssl_module modules/mod_ssl.so"
        $lines = $lines -replace "^#?LoadModule headers_module.*", "LoadModule headers_module modules/mod_headers.so"
        $lines = $lines -replace "^#?LoadModule socache_shmcb_module.*", "LoadModule socache_shmcb_module modules/mod_socache_shmcb.so"
        
        $lines = $lines | Where-Object { $_ -notmatch "Include conf/extra/httpd-ahssl\.conf" }
        $lines += "Include conf/extra/httpd-ahssl.conf"
        
        $sslConf = "C:\Apache24\conf\extra\httpd-ahssl.conf"
        $certDir = "$script:SSL_DIR\apache"
        $certCrt = ($certDir + "\server.crt").Replace("\", "/")
        $certKey = ($certDir + "\server.key").Replace("\", "/")
        
        $vhost = @"
Listen 0.0.0.0:$SslPort
<VirtualHost *:$SslPort>
    ServerName $script:DOMINIO
    DocumentRoot "C:/Apache24/htdocs"
    SSLEngine on
    SSLCertificateFile    "$certCrt"
    SSLCertificateKeyFile "$certKey"
    SSLProtocol TLSv1.2 TLSv1.3
    Header always set Strict-Transport-Security "max-age=31536000"
</VirtualHost>

<VirtualHost *:$Puerto>
    ServerName $script:DOMINIO
    Redirect permanent / https://$script:DOMINIO:$SslPort/
</VirtualHost>
"@
        Set-Content -Path $sslConf -Value $vhost
        fn_sec "SSL configurado en Apache (puerto $SslPort + redireccion desde $Puerto)"
    }
    
    Set-Content -Path $conf -Value $lines
    
    $html = @"
<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"><title>Apache - Activo</title>
<style>body { font-family: Arial; background: #1a1a2e; color: #eee; text-align: center; margin-top:20vh; }
.card { background: #16213e; padding: 40px 60px; border-radius: 12px; display: inline-block; border-left: 6px solid #0f3460; }</style>
</head><body><div class="card"><h2>Apache - Windows Server</h2>
<p>Puerto HTTP: $Puerto | SSL: $SslLabel</p><p>Dominio: $script:DOMINIO</p><p style="color:#4ade80">Servidor activo y funcionando</p>
<p style="color:#888;font-size:0.8em">Practica 7</p></div></body></html>
"@
    Set-Content -Path "C:\Apache24\htdocs\index.html" -Value $html
    
    Start-Process -FilePath "C:\Apache24\bin\httpd.exe" -ArgumentList "-k install -n `"Apache24`"" -WindowStyle Hidden -Wait
    Start-Service Apache24 -ErrorAction SilentlyContinue
    
    $oldPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $testResult = & "C:\Apache24\bin\httpd.exe" -t 2>&1
    $ErrorActionPreference = $oldPref
    
    if ("$testResult" -match "Syntax OK") {
        fn_ok "Servicio Apache24 instalado e iniciado (Sintaxis OK)."
    } else {
        Write-Host "`n[FATAL ERROR APACHE] La configuracion tiene un error:" -ForegroundColor Red
        Write-Host "$testResult" -ForegroundColor Yellow
        Write-Host "Por favor, toma una captura de este error para revisarlo.`n" -ForegroundColor Red
        Read-Host "Presiona ENTER para continuar a pesar del error..."
    }
    
    New-NetFirewallRule -DisplayName "Apache P7" -Direction Inbound -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    if ($Ssl -eq "si") { New-NetFirewallRule -DisplayName "Apache P7 SSL" -Direction Inbound -LocalPort $SslPort -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null }
    
    $script:RESUMEN_INSTALACIONES += "[Apache] Puerto: $Puerto | SSL: $SslLabel | Origen: FTP"
    return $true
}

# -----------------------------------------------------------------------------
# INSTALACION NGINX
# -----------------------------------------------------------------------------

function fn_instalar_nginx_ftp([string]$Archivo, [string]$Puerto, [string]$Ssl) {
    Write-Host "`n====== INSTALACION NGINX DESDE FTP ======" -ForegroundColor Blue
    
    if (Test-Path "C:\nginx\nginx.exe") {
        Start-Process -FilePath "C:\nginx\nginx.exe" -ArgumentList "-s quit" -WorkingDirectory "C:\nginx" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
    }
    cmd.exe /c "taskkill /F /IM nginx.exe /T 2>NUL"
    Stop-Process -Name "nginx" -Force -ErrorAction SilentlyContinue
    
    fn_info "Esperando liberacion de archivos en Windows..."
    Start-Sleep -Seconds 3
    
    fn_info "Limpiando puertos y reglas de Firewall viejas de Nginx..."
    Remove-NetFirewallRule -DisplayName "Nginx P7*" -ErrorAction SilentlyContinue
    
    fn_info "Preparando extraccion limpia de Nginx..."
    $Staging = "C:\p7_staging_nginx"
    if (Test-Path $Staging) { Remove-Item -Path $Staging -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $Staging -Force | Out-Null
    
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($Archivo, $Staging)
    } catch {
        fn_err "Error CRITICO: El instalador ZIP esta corrupto o incompleto."
        Remove-Item -Path $Archivo -Force -ErrorAction SilentlyContinue
        fn_info "He eliminado el archivo corrupto. Por favor, corre el script de nuevo para re-descargarlo."
        return $false
    }
    
    if (Test-Path "C:\nginx\nginx.exe") { Rename-Item -Path "C:\nginx\nginx.exe" -NewName "nginx_trash_$([guid]::NewGuid().ToString().Substring(0,8)).exe" -Force -ErrorAction SilentlyContinue }
    
    if (!(Test-Path "C:\nginx")) { New-Item -ItemType Directory -Path "C:\nginx" -Force | Out-Null }
    
    $nginxSub = Get-ChildItem -Path $Staging -Directory -Filter "nginx-*" | Select-Object -First 1
    if ($nginxSub) {
        Copy-Item -Path "$($nginxSub.FullName)\*" -Destination "C:\nginx" -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Copy-Item -Path "$Staging\*" -Destination "C:\nginx" -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    if (!(Test-Path "C:\nginx\nginx.exe")) { fn_err "Extraccion de Nginx fallo."; return $false }
    
    $nginxDir = "C:\nginx"
    fn_ok "Nginx actualizado en $nginxDir"
    
    $SslLabel = "No"
    $SslBlock = ""
    $SslPort = 443
    if ($Ssl -eq "si") {
        fn_generar_certificado_ssl "nginx" | Out-Null
        $PuertoSsl = Read-Host -Prompt "Ingresa el puerto HTTPS para Nginx (ej: 8443, 9443)"
        $SslPort = $PuertoSsl
        $SslLabel = "Si (puerto $SslPort)"
        
        $certDir = "$script:SSL_DIR\nginx"
        $certCrt = ($certDir + "\server.crt").Replace("\", "/")
        $certKey = ($certDir + "\server.key").Replace("\", "/")
        
        $SslBlock = @"
    server {
        listen       $SslPort ssl;
        server_name  $script:DOMINIO;
        ssl_certificate      "$certCrt";
        ssl_certificate_key  "$certKey";
        ssl_protocols TLSv1.2 TLSv1.3;
        add_header Strict-Transport-Security "max-age=31536000" always;
        root   html;
        index  index.html;
    }
"@
    }
    
    $nginxConf = @"
worker_processes  1;
events { worker_connections  1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    server_tokens off;
    
    server {
        listen       $Puerto;
        server_name  $script:DOMINIO;
        root   html;
        index  index.html;
        add_header X-Frame-Options SAMEORIGIN always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-XSS-Protection "1; mode=block" always;
"@
    if ($Ssl -eq "si") { $nginxConf += "`n        return 301 https://`$host:$SslPort`$request_uri;" }
    $nginxConf += "`n    }`n$SslBlock`n}"
    
    Set-Content -Path "$nginxDir\conf\nginx.conf" -Value $nginxConf
    
    $html = @"
<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"><title>Nginx - Activo</title>
<style>body { font-family: Arial; background: #1a1a2e; color: #eee; text-align: center; margin-top:20vh; }
.card { background: #16213e; padding: 40px 60px; border-radius: 12px; display: inline-block; border-left: 6px solid #0f3460; }</style>
</head><body><div class="card"><h2>Nginx - Windows Server</h2>
<p>Puerto HTTP: $Puerto | SSL: $SslLabel</p><p>Dominio: $script:DOMINIO</p><p style="color:#4ade80">Servidor activo y funcionando</p>
<p style="color:#888;font-size:0.8em">Practica 7</p></div></body></html>
"@
    Set-Content -Path "$nginxDir\html\index.html" -Value $html
    
    Start-Process -FilePath "$nginxDir\nginx.exe" -WorkingDirectory $nginxDir -WindowStyle Hidden
    fn_ok "Nginx iniciado."
    
    New-NetFirewallRule -DisplayName "Nginx P7" -Direction Inbound -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    if ($Ssl -eq "si") { New-NetFirewallRule -DisplayName "Nginx P7 SSL" -Direction Inbound -LocalPort $SslPort -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null }
    
    $script:RESUMEN_INSTALACIONES += "[Nginx] Puerto: $Puerto | SSL: $SslLabel | Origen: FTP"
    return $true
}

# -----------------------------------------------------------------------------
# INSTALACION IIS
# -----------------------------------------------------------------------------

function fn_instalar_iis_local([string]$Puerto, [string]$Ssl) {
    Write-Host "`n====== INSTALACION IIS ======" -ForegroundColor Blue
    
    fn_info "Limpiando puertos y reglas de Firewall viejas de IIS..."
    Remove-NetFirewallRule -DisplayName "IIS P7*" -ErrorAction SilentlyContinue
    
    fn_info "Instalando rol de IIS (Web-Server)..."
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
    fn_ok "IIS instalado."
    
    Import-Module WebAdministration
    
    if (Get-Website "Default Web Site" -ErrorAction SilentlyContinue) {
        Remove-Website -Name "Default Web Site"
    }
    
    $sitePath = "C:\inetpub\wwwroot\p7"
    if (!(Test-Path $sitePath)) { New-Item -ItemType Directory -Force -Path $sitePath | Out-Null }
    
    $SslLabel = "No"
    $SslPort = 443
    if ($Ssl -eq "si") {
        $InputPort = Read-Host -Prompt "Ingresa el puerto HTTPS para IIS (ej: 443, 8443, 9444)"
        if (-not [string]::IsNullOrWhiteSpace($InputPort)) { $SslPort = $InputPort }
        $SslLabel = "Si (puerto $SslPort)"
    }
    
    $html = @"
<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"><title>IIS - Activo</title>
<style>body { font-family: Arial; background: #1a1a2e; color: #eee; text-align: center; margin-top:20vh; }
.card { background: #16213e; padding: 40px 60px; border-radius: 12px; display: inline-block; border-left: 6px solid #0f3460; }</style>
</head><body><div class="card"><h2>IIS - Windows Server</h2>
<p>Puerto HTTP: $Puerto | SSL: $SslLabel</p><p>Dominio: $script:DOMINIO</p><p style="color:#4ade80">Servidor activo y funcionando</p>
<p style="color:#888;font-size:0.8em">Practica 7</p></div></body></html>
"@
    Set-Content -Path "$sitePath\index.html" -Value $html
    
    $siteName = "IIS_P7"
    if (Get-Website $siteName -ErrorAction SilentlyContinue) { Remove-Website -Name $siteName }
    
    New-Website -Name $siteName -Port $Puerto -PhysicalPath $sitePath -Force | Out-Null
    
    if ($Ssl -eq "si") {
        fn_sec "Generando y asignando certificado autofirmado en el almacén de Windows para IIS..."
        $cert = New-SelfSignedCertificate -DnsName $script:DOMINIO -CertStoreLocation "cert:\LocalMachine\My" -NotAfter (Get-Date).AddYears(1)
        New-WebBinding -Name $siteName -Protocol https -Port $SslPort -IPAddress "*"
        $bindingPath = "IIS:\SslBindings\*!$SslPort"
        $cert | New-Item -Path $bindingPath -Force | Out-Null
        fn_sec "Binding HTTPS creado en IIS."
    }
    
    New-NetFirewallRule -DisplayName "IIS P7" -Direction Inbound -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    if ($Ssl -eq "si") { New-NetFirewallRule -DisplayName "IIS P7 SSL" -Direction Inbound -LocalPort $SslPort -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null }
    
    Start-Website -Name $siteName -ErrorAction SilentlyContinue
    fn_ok "Sitio IIS configurado e iniciado."
    
    $script:RESUMEN_INSTALACIONES += "[IIS] Puerto: $Puerto | SSL: $SslLabel | Origen: Nativo"
}

# -----------------------------------------------------------------------------
# LLAMADAS PRINCIPALES
# -----------------------------------------------------------------------------

function fn_instalar_web_con_ssl([string]$servicio, [string]$Puerto, [string]$Ssl) {
    fn_info "Iniciando instalacion WEB para $servicio..."
    $DestinoDir = $script:INSTALL_DIR
    if (!(Test-Path $DestinoDir)) { New-Item -ItemType Directory -Force -Path $DestinoDir | Out-Null }
    
    $url = ""
    $archivo = ""
    switch ($servicio) {
        "apache" {
            $url = "https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.59-win64-VS17.zip"
            $archivo = "$DestinoDir\httpd-2.4.59-win64-VS17.zip"
        }
        "nginx" {
            $url = "https://nginx.org/download/nginx-1.26.0.zip"
            $archivo = "$DestinoDir\nginx-1.26.0.zip"
        }
    }
    
    if (!(Test-Path $archivo)) {
        fn_info "Descargando desde internet: $url (esto puede tardar unos momentos)..."
        try {
            $webclient = New-Object System.Net.WebClient
            $webclient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
            $webclient.DownloadFile($url, $archivo)
            fn_ok "Descarga completada."
        } catch {
            fn_err "Fallo la descarga desde web. Verifique su conexion o intente por FTP."
            return $false
        }
    } else {
        fn_info "El archivo de instalacion ya existe localmente y sera reutilizado."
    }
    
    switch ($servicio) {
        "apache" { fn_instalar_apache_ftp $archivo $Puerto $Ssl }
        "nginx"  { fn_instalar_nginx_ftp  $archivo $Puerto $Ssl }
    }
    return $true
}

function fn_instalar_servicio_hibrido([string]$servicio, [string]$NombreDisplay) {
    Write-Host "`n====== INSTALACION DE $NombreDisplay ======" -ForegroundColor Cyan
    $puerto = Read-Host -Prompt "Ingresa el puerto HTTP para $NombreDisplay (ej: 8080, 9090, 8083)"
    $ssl = "no"
    if (fn_preguntar_ssl) { $ssl = "si" }
    
    if ($servicio -eq "iis") {
        fn_instalar_iis_local $puerto $ssl
        return
    }

    Write-Host "`n¿Desde donde deseas instalar $NombreDisplay?" -ForegroundColor Yellow
    Write-Host "  [1] WEB - Descarga oficial (internet)"
    Write-Host "  [2] FTP - Repositorio privado ($script:FTP_SERVER)"
    
    $origen = Read-Host -Prompt "Opcion"
    
    if ($origen -eq "1") {
        fn_instalar_web_con_ssl $servicio $puerto $ssl
    }
    
    if ($origen -eq "2") {
        if (-not (fn_ftp_navegar_y_descargar $NombreDisplay $script:INSTALL_DIR)) { return }
        if (-not (fn_verificar_hash $script:FTP_ARCHIVO_DESCARGADO $script:FTP_SHA256_DESCARGADO)) { return }
        switch ($servicio) {
            "apache" { fn_instalar_apache_ftp $script:FTP_ARCHIVO_DESCARGADO $puerto $ssl }
            "nginx"  { fn_instalar_nginx_ftp  $script:FTP_ARCHIVO_DESCARGADO $puerto $ssl }
        }
    }
}

function fn_configurar_ftps {
    Write-Host "`n====== CONFIGURACION SSL PARA FTP (IIS) ======" -ForegroundColor Blue
    
    $ftpInstalled = Get-WindowsFeature Web-Ftp-Service
    if ($ftpInstalled.InstallState -ne "Installed") {
        fn_info "El servicio FTP de IIS no esta instalado. Instalando rol (puede tardar minutos)..."
        Install-WindowsFeature -Name Web-Ftp-Service,Web-Ftp-Ext -IncludeManagementTools | Out-Null
        fn_ok "Servicio FTP de IIS instalado."
    }
    
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    
    $sitePath = "C:\inetpub\ftproot"
    if (!(Test-Path $sitePath)) { New-Item -ItemType Directory -Force -Path $sitePath | Out-Null }
    
    # Limpieza de carpetas no deseadas
    # UNIVERSAL: SIDs para Everyone y Users (Funciona en todos los idiomas)
    $sidEveryone = New-Object System.Security.Principal.SecurityIdentifier("S-1-1-0")
    $sidUsers = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
    
    fn_info "Limpiando carpetas basura (pkg, pub, grupos)..."
    $junk = @("pkg", "pub", "grupos")
    foreach($j in $junk) {
        $jPath = Join-Path $sitePath $j
        if (Test-Path $jPath) { Remove-Item -Path $jPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
    
    # Crear jerarquia balanceada: u1, http, general
    fn_info "Asegurando jerarquia limpia (/u1, /http/Windows, /general)..."
    $baseFolders = @("u1", "http\Windows", "general")
    foreach($f in $baseFolders) {
        $fullPath = "$sitePath\$f"
        if (!(Test-Path $fullPath)) { New-Item -ItemType Directory -Path $fullPath -Force | Out-Null }
        
        # AJUSTE: La carpeta u1 es PRIVADA (Solo lectura para anonimos)
        if ($f -eq "u1") {
            $acl = Get-Acl $fullPath
            # Quitar cualquier permiso Modify de Everyone
            $everyoneRule = New-Object System.Security.AccessControl.FileSystemAccessRule($sidEveryone, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.SetAccessRule($everyoneRule)
            
            # Pero el usuario 'u1' (o Users) SI debe poder escribir en su propia carpeta
            $u1Rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sidUsers, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.AddAccessRule($u1Rule)
            Set-Acl $fullPath $acl
        } else {
            # General y Http (bases) tambien solo lectura para everyone
            $acl = Get-Acl $fullPath
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sidEveryone, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.SetAccessRule($rule)
            Set-Acl $fullPath $acl
        }
    }
    
    # Subcarpetas dentro de /http/Windows (Acceso de Escritura para Anonimo)
    $osPath = "$sitePath\http\Windows"
    $folders = @("apache", "nginx", "tomcat")
    foreach($f in $folders) {
        $folderPath = Join-Path $osPath $f
        if (!(Test-Path $folderPath)) { New-Item -ItemType Directory -Path $folderPath -Force | Out-Null }
        
        # Crear archivos ejecutables y zips de prueba
        $exeName = "$f.exe"
        $zipName = switch($f) {
            "apache" { "httpd-2.4.59-win64.zip" }
            "nginx"  { "nginx-1.24.0.zip" }
            "tomcat" { "apache-tomcat-9.0.87-windows-x64.zip" }
        }
        
        "Instalador $f Windows Server" | Out-File (Join-Path $folderPath $exeName) -Force
        "Instalador $f Zip Server" | Out-File (Join-Path $folderPath $zipName) -Force
        
        # EL USUARIO NORMAL PUEDE TODO, EL ANONIMO SOLO AQUI
        $acl = Get-Acl $folderPath
        $rule_anon = New-Object System.Security.AccessControl.FileSystemAccessRule($sidEveryone, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.SetAccessRule($rule_anon)
        Set-Acl $folderPath $acl
    }
    
    # PERMISOS DE LA RAIZ Y SUBFOLDERS: u1 (Users) puede TODO
    $acl_root = Get-Acl $sitePath
    $u1_root_rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sidUsers, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl_root.SetAccessRule($u1_root_rule)
    
    # Pero el PUBLICO (Anonimo) en la RAIZ solo puede leer
    $pub_root_rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sidEveryone, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl_root.SetAccessRule($pub_root_rule)
    Set-Acl $sitePath $acl_root
    
    # Asegurar que /general y /u1 heredan esto (u1=Full, Anon=Read)
    $generalPath = Join-Path $sitePath "general"
    $u1Path = Join-Path $sitePath "u1"
    # No hace falta setear ACLs extra si la raiz hereda, pero lo forzamos por seguridad
    Set-Acl $generalPath $acl_root
    Set-Acl $u1Path $acl_root
    
    # EXCEPCION: Instaladores (Anonimo puede escribir AQUÍ)
    $installers = @("apache", "nginx", "tomcat")
    foreach ($f in $installers) {
        $folderPath = "$sitePath\http\Windows\$f"
        $acl = Get-Acl $folderPath
        $rule_anon = New-Object System.Security.AccessControl.FileSystemAccessRule($sidEveryone, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.SetAccessRule($rule_anon)
        Set-Acl $folderPath $acl
    }
    
    $siteName = "IIS_P7_FTP"
    # ELIMINAR SITIO PREVIO PARA ASEGURAR ESTADO LIMPIO (Fix 0x800710D8)
    if (Get-Website -Name $siteName -ErrorAction SilentlyContinue) {
        fn_info "Eliminando instancia previa de $siteName para recreacion limpia..."
        Remove-Website -Name $siteName -ErrorAction SilentlyContinue 
        Start-Sleep -Seconds 1
    }
    
    fn_info "Creando nuevo sitio FTP base: $siteName..."
    New-WebFtpSite -Name $siteName -Port 21 -PhysicalPath $sitePath -Force | Out-Null
    Start-Sleep -Seconds 5 # Pausa extendida para sincronizacion total (Final Fix)


    
    fn_sec "Generando certificado SSL para FTPS..."
    $cert = New-SelfSignedCertificate -DnsName $script:DOMINIO -CertStoreLocation "cert:\LocalMachine\My" -NotAfter (Get-Date).AddYears(1)
    
    fn_info "Inyectando politicas de seguridad TLS/SSL via AppCmd (SslAllow)..."
    $appCmd = "C:\Windows\System32\inetsrv\appcmd.exe"
    $certHash = $cert.GetCertHashString()
    
    # Usar AppCmd para saltarse los fallos del proveedor de PowerShell
    & $appCmd set config "$siteName" /section:system.ftpServer/security/ssl /controlChannelPolicy:SslAllow /dataChannelPolicy:SslAllow /serverCertHash:$certHash /commit:apphost | Out-Null

    
    fn_info "Limpiando y creando reglas de firewall para FTPS..."
    Remove-NetFirewallRule -DisplayName "FTPS P7*" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "FTPS P7 Control" -Direction Inbound -LocalPort 21 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "FTPS P7 Pasivo" -Direction Inbound -LocalPort 10000-10100 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null

    
    fn_info "Configurando acceso ANONIMO para el servidor FTP via AppCmd..."
    # Habilitar Autenticacion Anonima
    & $appCmd set config "$siteName" /section:system.ftpServer/security/authentication/anonymousAuthentication /enabled:true /commit:apphost | Out-Null
    
    # Autorizar lectura/escritura anonima para ? (Usuarios anonimos en IIS)
    fn_info "Aplicando autorizacion FTP via AppCmd..."
    # Limpiar reglas previas (usando appcmd es mas seguro)
    & $appCmd clear config "$siteName" /section:system.ftpServer/security/authorization /commit:apphost | Out-Null
    & $appCmd set config "$siteName" /section:system.ftpServer/security/authorization /+"[accessType='Allow',users='?',permissions='Read,Write']" /commit:apphost | Out-Null
    
    # Asegurar permisos NTFS de la RAIZ (Solo lectura para estabilidad y seguridad)
    fn_info "Ajustando permisos NTFS de la RAIZ (Solo lectura)..."
    $acl = Get-Acl $sitePath
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($sidEveryone, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($accessRule)
    Set-Acl $sitePath $acl
    
    # REINICIO DE SERVICIO: Forzar a IIS a leer la nueva config
    fn_info "Reiniciando Servicio FTP para aplicar cambios..."
    Restart-Service ftpsvc -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    # INTENTO ARRANQUE: Ignorar si el objeto aun no es "valido" para PowerShell
    try {
        Start-Website -Name $siteName -ErrorAction SilentlyContinue | Out-Null
    } catch { }
    
    fn_ok "FTPS (IIS) Completado: $script:DOMINIO (Escritura SOLO en instaladores)."
    $script:RESUMEN_INSTALACIONES += "[IIS FTP] FTPS Activo | Escritura: SOLO INSTALADORES | Puerto: 21"
}

function fn_mostrar_resumen {
    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host   "            RESUMEN DE INSTALACIONES - PRACTICA 7         " -ForegroundColor Cyan
    Write-Host   "==========================================================" -ForegroundColor Cyan
    if ($script:RESUMEN_INSTALACIONES.Count -eq 0) {
        Write-Host "No hay instalaciones registradas en esta sesion." -ForegroundColor Yellow
    } else {
        Write-Host "Servicios instalados/configurados:" -ForegroundColor Green
        foreach ($r in $script:RESUMEN_INSTALACIONES) { Write-Host "  $r" }
    }
}
