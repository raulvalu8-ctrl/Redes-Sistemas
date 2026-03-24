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
$script:INSTALL_DIR = "C:\p7_instaladores"
$script:RESUMEN_INSTALACIONES = @()

# -----------------------------------------------------------------------------
# COMPATIBILIDAD CON p7_main.ps1
# -----------------------------------------------------------------------------
function fn_instalar_servicio_hibrido { fn_menu_instalar_p7 @args }
function fn_configurar_ftps { fn_configurar_ftps_p7 @args }

# -----------------------------------------------------------------------------
# HELPERS DE UI Y SISTEMA
# -----------------------------------------------------------------------------
function Draw-Box {
    param([string[]]$Lineas, [ConsoleColor]$Color = 'Cyan')
    $maxLen = 0
    foreach ($l in $Lineas) { if ($l.Length -gt $maxLen) { $maxLen = $l.Length } }
    $borde = '+' + ('-' * ($maxLen + 2)) + '+'
    Write-Host "`n  $borde" -ForegroundColor $Color
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
        if ($s) { if ($s.Status -eq 'Running') { return 'Activo' } else { return 'Inactivo' } }
    }
    if (Get-Process "nginx" -ErrorAction SilentlyContinue) { return 'Activo' }
    return 'No instalado'
}

function Get-SslStatus {
    param([int]$Puerto)
    if ($Puerto -le 0) { return '--' }
    $t = New-Object System.Net.Sockets.TcpClient
    try {
        $a = $t.BeginConnect("127.0.0.1", $Puerto, $null, $null)
        if ($a.AsyncWaitHandle.WaitOne(400)) { $t.Close(); return "ON (:$Puerto)" }
    } catch {}
    return "OFF"
}

function fn_ok([string]$msg)   { Write-Host "[OK]     $msg" -ForegroundColor Green }
function fn_info([string]$msg) { Write-Host "[INFO]   $msg" -ForegroundColor Yellow }
function fn_err([string]$msg)  { Write-Host "[ERROR]  $msg" -ForegroundColor Red }
function fn_sec([string]$msg)  { Write-Host "[SSL]    $msg" -ForegroundColor Magenta }

function fn_verificar_admin_p7 {
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        fn_err "Ejecuta como Administrador."; exit 1
    }
}

function fn_limpiar_procesos([string]$nombre) {
    fn_info "Limpiando procesos de $nombre..."
    taskkill /F /IM "$nombre*" /T 2>$null | Out-Null
    Start-Sleep -Seconds 1
}

function fn_abrir_firewall([int]$p1, [int]$p2) {
    fn_info "Configurando Firewall (Puertos $p1, $p2)..."
    netsh advfirewall firewall delete rule name="P7_WEB" 2>$null | Out-Null
    netsh advfirewall firewall add rule name="P7_WEB" dir=in action=allow protocol=TCP localport="$p1,$p2" 2>$null | Out-Null
}

# -----------------------------------------------------------------------------
# PAGINA WEB PREMIUM COMPACTA (STYLE MAGEIA)
# -----------------------------------------------------------------------------
function fn_generar_index_premium([string]$Path, [string]$Svc, [int]$P, [int]$PS) {
    $sslTxt = if ($PS -gt 0) { "Si (puerto $PS)" } else { "No" }
    $title = "$Svc - Windows Server"
    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Servidor Activo - P7</title>
    <style>
        body { background-color: #1a2a44; color: white; font-family: 'Segoe UI', sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background-color: #24344d; padding: 30px; border-radius: 20px; text-align: center; width: 500px; box-shadow: 0 10px 30px rgba(0,0,0,0.6); border-left: 8px solid #3498db; }
        h1 { color: #ff4d4d; font-size: 2em; margin-bottom: 20px; text-transform: uppercase; letter-spacing: 1px; }
        .badges { display: flex; justify-content: center; gap: 10px; margin-bottom: 15px; flex-wrap: wrap; }
        .badge { background-color: #2c3e50; padding: 6px 15px; border-radius: 30px; font-weight: bold; font-size: 0.9em; border: 1px solid #34495e; box-shadow: 1px 1px 5px rgba(0,0,0,0.3); }
        .status { color: #2ecc71; font-size: 1.4em; font-weight: bold; margin: 20px 0; text-shadow: 1px 1px 4px rgba(0,0,0,0.4); }
        .footer { color: #7f8c8d; font-size: 0.85em; margin-top: 15px; border-top: 1px solid #34495e; padding-top: 10px; }
    </style>
</head>
<body>
    <div class="card">
        <h1>$title</h1>
        <div class="badges">
            <div class="badge">Servidor: $Svc</div>
            <div class="badge">Puerto: $P</div>
            <div class="badge">SSL: $sslTxt</div>
        </div>
        <div class="status">Servidor activo y funcionando</div>
        <div class="footer">Practica 7 - Redes y Sistemas (Windows)</div>
    </div>
</body>
</html>
"@
    $html | Set-Content "$Path\index.html" -Force
}

# -----------------------------------------------------------------------------
# DESCARGAS (INTELLIGENT BITS TRANSFER)
# -----------------------------------------------------------------------------
function fn_descargar_internet_estable([string]$Svc, [string]$DestDir) {
    if (!(Test-Path $DestDir)) { New-Item -ItemType Directory $DestDir -Force | Out-Null }
    $url = if ($Svc -eq "Nginx") { "https://nginx.org/download/nginx-1.26.2.zip" } 
           else { "https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.62-240718-win64-VS17.zip" }
    $loc = "$DestDir\$Svc`_internet.zip"
    fn_info "Iniciando descarga estable de $Svc..."
    try { 
        Import-Module BitsTransfer
        Start-BitsTransfer -Source $url -Destination $loc -DisplayName "Descarga $Svc P7" -ErrorAction Stop
        if (Test-Path $loc) { return $loc }
    } catch { 
        fn_err "Fallo BITS. Usando WebClient (Ultimo recurso)..."
        try { (New-Object System.Net.WebClient).DownloadFile($url, $loc); return $loc } catch { return $null }
    }
    return $null
}

function fn_ftp_navegar_y_descargar([string]$Svc, [string]$Dest) {
    fn_err "PROBLEMA DE REPOSITORIO (ZIP Corrupto o FTP fallido)"
    Write-Host " [1] Descarga ESTABLE de internet (RECOMENDADO) " -ForegroundColor Cyan
    Write-Host " [2] Seleccionar archivo local (C:\p7_instaladores) " -ForegroundColor Yellow
    $e = Read-Host "Elige opcion de rescate"
    
    if ($e -eq "1") {
        $res = fn_descargar_internet_estable $Svc $Dest
        if ($res) { $script:FTP_ARCHIVO_DESCARGADO = $res; return $true }
        fn_err "No se pudo obtener el instalador de internet."
    }
    # Modo manual local
    if (!(Test-Path $Dest)) { New-Item -ItemType Directory $Dest -Force | Out-Null }
    $files = Get-ChildItem "$Dest\*.zip", "$Dest\*.tar.gz" | Select-Object -ExpandProperty Name
    if (!$files) { fn_err "No hay zips en $Dest."; return $false }
    for ($i=0; $i -lt $files.Count; $i++) { Write-Host "  [$($i+1)] $($files[$i])" }
    $s = Read-Host "Elige archivo"; $script:FTP_ARCHIVO_DESCARGADO = "$Dest\$($files[[int]$s-1])"; return $true
}

function fn_generar_ssl_p7([string]$svc) {
    $d = "$script:SSL_DIR\$svc"; if (!(Test-Path $d)) { New-Item -ItemType Directory $d -Force | Out-Null }
    $c = New-SelfSignedCertificate -DnsName $script:DOMINIO -CertStoreLocation "cert:\LocalMachine\My" -KeyExportPolicy Exportable -NotAfter (Get-Date).AddYears(1)
    $b64 = [System.Convert]::ToBase64String($c.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert), "InsertLineBreaks")
    "-----BEGIN CERTIFICATE-----`r`n$b64`r`n-----END CERTIFICATE-----" | Set-Content "$d\cert.crt"
    if (Get-Command openssl -ErrorAction SilentlyContinue) {
        $pfx = "$d\cert.pfx"; $pw = ConvertTo-SecureString "practica7" -AsPlainText -Force
        Export-PfxCertificate -Cert $c -FilePath $pfx -Password $pw | Out-Null
        & openssl pkcs12 -in $pfx -nocerts -nodes -out "$d\cert.key" -passin pass:practica7 -quiet 2>$null
    }
    return $c
}

# -----------------------------------------------------------------------------
# INSTALADORES (APACHE, NGINX, IIS)
# -----------------------------------------------------------------------------
function fn_instalar_iis_p7([int]$p, [int]$ps) {
    Install-WindowsFeature Web-Server | Out-Null
    $root = "C:\inetpub\wwwroot\p7"; if(!(Test-Path $root)){New-Item -ItemType Directory $root | Out-Null}
    fn_generar_index_premium $root "IIS" $p $ps
    Import-Module WebAdministration; if(Get-Website "P7" -ErrorAction SilentlyContinue){Remove-Website "P7"}
    New-Website -Name "P7" -Port $p -PhysicalPath $root -Force | Out-Null
    if($ps -gt 0){ $c=fn_generar_ssl_p7 "iis"; New-WebBinding -Name "P7" -Protocol https -Port $ps -IPAddress "*"; $c | New-Item "IIS:\SslBindings\*!$ps" -Force | Out-Null }
    fn_abrir_firewall $p $ps; fn_ok "IIS instalado y premium."
}

function fn_instalar_apache_p7([int]$p, [int]$ps) {
    $dir = "C:\Apache24"
    if (fn_ftp_navegar_y_descargar "Apache" $script:INSTALL_DIR) {
        fn_limpiar_procesos "httpd"; if(Test-Path $dir){Remove-Item $dir -Recurse -Force | Out-Null}
        fn_info "Extrayendo Apache..."; try { Expand-Archive $script:FTP_ARCHIVO_DESCARGADO "C:\" -Force -ErrorAction Stop }
        catch { fn_err "ZIP Corrupto. Borra 'Apache_internet.zip' e intenta de nuevo con la Opcion 1."; return }
        if(!(Test-Path $dir)){$f=Get-ChildItem "C:\httpd-*"|Select-Object -First 1; if($f){Rename-Item $f.FullName "Apache24"}}
        fn_generar_index_premium "$dir\htdocs" "Apache" $p $ps
        $conf = "$dir\conf\httpd.conf"; $crt="C:/ssl_practica7/apache/cert.crt"; $key="C:/ssl_practica7/apache/cert.key"
        $txt = (Get-Content $conf) -replace 'Listen 80', "Listen $p" -replace 'Define SRVROOT "/Apache24"', "Define SRVROOT `"$dir`""
        if($ps -gt 0){ fn_generar_ssl_p7 "apache" | Out-Null; $txt += "`nListen $ps`nLoadModule ssl_module modules/mod_ssl.so`nLoadModule socache_shmcb_module modules/mod_socache_shmcb.so`n<VirtualHost *:$ps>`n  SSLEngine on`n  SSLCertificateFile `"$crt`"`n  SSLCertificateKeyFile `"$key`"`n</VirtualHost>" }
        $txt | Set-Content $conf; & "$dir\bin\httpd.exe" -k install -n "Apache24" 2>$null; Start-Service Apache24
        fn_abrir_firewall $p $ps; fn_ok "Apache premium listo."
    }
}

function fn_instalar_nginx_p7([int]$p, [int]$ps) {
    $dir = "C:\nginx"
    if (fn_ftp_navegar_y_descargar "Nginx" $script:INSTALL_DIR) {
        fn_limpiar_procesos "nginx"; if(Test-Path $dir){Remove-Item $dir -Recurse -Force | Out-Null}
        fn_info "Extrayendo Nginx..."; try { Expand-Archive $script:FTP_ARCHIVO_DESCARGADO "C:\" -Force -ErrorAction Stop }
        catch { fn_err "ZIP Corrupto. Intenta de nuevo."; return }
        $f=Get-ChildItem "C:\nginx-*"|Select-Object -First 1; if($f){Rename-Item $f.FullName "nginx"}
        fn_generar_index_premium "$dir\html" "Nginx" $p $ps
        $conf = "$dir\conf\nginx.conf"; $crt="C:/ssl_practica7/nginx/cert.crt"; $key="C:/ssl_practica7/nginx/cert.key"
        $sslB = if($ps -gt 0){ fn_generar_ssl_p7 "nginx" | Out-Null; "`n    server { listen $ps ssl; server_name localhost; ssl_certificate `"$crt`"; ssl_certificate_key `"$key`"; location / { root html; index index.html; } }" } else { "" }
        (Get-Content $conf) -replace "listen\s+80;", "listen $p;" -replace "}\s+#\s+another", "$sslB `n    # another" | Set-Content $conf
        Start-Process "$dir\nginx.exe" -WorkingDirectory $dir; Start-Sleep -Seconds 2; fn_abrir_firewall $p $ps; fn_ok "Nginx premium."
    }
}

function fn_menu_instalar_p7([string]$s, [string]$n) {
    fn_verificar_admin_p7
    $p = Read-Host "Puerto HTTP ($n)"
    $unsafe = @(1, 7, 9, 11, 13, 15, 17, 19, 20, 21, 22, 23, 25, 37, 42, 43, 53, 69, 77, 79, 87, 95, 101, 102, 103, 104, 109, 110, 111, 113, 115, 117, 119, 123, 135, 137, 138, 139, 143, 161, 179, 389, 427, 465, 512, 513, 514, 515, 526, 530, 531, 532, 540, 548, 554, 556, 563, 587, 601, 636, 989, 990, 993, 995, 1719, 1720, 1723, 2049, 3659, 4045, 5060, 5061, 6000, 6566, 6665, 6666, 6667, 6668, 6669, 6697, 10080)
    if ($unsafe -contains [int]$p) { fn_err "Navegadores bloquean puerto $p. Usa puertos como 8080 o 7000." }
    $ps = Read-Host "Puerto SSL (ENTER=No)"; if(!$ps){$ps=0}
    if($s -eq 'iis'){fn_instalar_iis_p7 $p $ps} elseif($s -eq 'apache'){fn_instalar_apache_p7 $p $ps} elseif($s -eq 'nginx'){fn_instalar_nginx_p7 $p $ps}
    $script:RESUMEN_INSTALACIONES += "[$n] P:$p SSL:$ps"
}

function fn_configurar_ftps_p7 {
    $p = Read-Host "Puerto FTP (21)"; if(!$p){$p=21}
    Install-WindowsFeature Web-Ftp-Service | Out-Null
    $root = "C:\inetpub\ftproot_p7"; if(!(Test-Path $root)){New-Item -ItemType Directory $root -Force | Out-Null}
    $u = "alumno_p7"; $pw = ConvertTo-SecureString "Practica7!" -AsPlainText -Force
    if(!(Get-LocalUser $u -ErrorAction SilentlyContinue)){ New-LocalUser $u -Password $pw | Out-Null }
    Import-Module WebAdministration; if(Get-Website "FTP_P7" -ErrorAction SilentlyContinue){Remove-Website "FTP_P7"}
    New-WebFtpSite "FTP_P7" -Port $p -PhysicalPath $root -Force | Out-Null; Restart-Service ftpsvc; fn_ok "FTP listo."
}

function fn_configurar_repo_ftp {
    $ip = Read-Host "IP Repo ($script:FTP_SERVER)"; if($ip){$script:FTP_SERVER=$ip}
    fn_ok "Repositorio actualizado."
}

function fn_mostrar_resumen {
    Write-Host "`n=== RESUMEN ===" -ForegroundColor Green
    if($script:RESUMEN_INSTALACIONES.Count -eq 0){ Write-Host "Nada instalado." } else { foreach($r in $script:RESUMEN_INSTALACIONES){ Write-Host " $r" } }
}