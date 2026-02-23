# =========================
#    DNS PRO (WINDOWS SERVER)
# =========================

$ZONES_DIR = "C:\DNS_Pro_Zones"
if (!(Test-Path $ZONES_DIR)) { New-Item -ItemType Directory -Path $ZONES_DIR | Out-Null }

function Pause {
    Write-Host ""
    Read-Host "Presiona ENTER para continuar..."
}

function Require-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[ERROR] Ejecuta PowerShell como Administrador." -ForegroundColor Red
        exit
    }
}

function Install-DNS-If-Needed {
    if (!(Get-WindowsFeature -Name DNS).Installed) {
        Write-Host "[i] Instalando Rol DNS..." -ForegroundColor Cyan
        Install-WindowsFeature -Name DNS -IncludeManagementTools | Out-Null
    }
}

function Obtener-Datos-Red {
    Write-Host "`n--- Interfaces disponibles ---" -ForegroundColor Cyan
    Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object Name, Status | Format-Table
    
    $script:INTERFAZ = Read-Host "Introduce el nombre de la interfaz (ej. Ethernet 1)"
    
    $ipInfo = Get-NetIPAddress -InterfaceAlias $script:INTERFAZ -AddressFamily IPv4 -ErrorAction SilentlyContinue
    
    if ($null -eq $ipInfo) {
        Write-Host "[!] La interfaz no tiene IP asignada aun. Deberas usar la opcion manual." -ForegroundColor Yellow
        $script:IP_SUGERIDA = "0.0.0.0" 
        return $true
    }
    
    $script:IP_SUGERIDA = $ipInfo.IPAddress
    Write-Host "[+] IP detectada en $script:INTERFAZ : $script:IP_SUGERIDA" -ForegroundColor Green
    return $true
}

function Crear-Zona {
    if (-not (Obtener-Datos-Red)) { return }

    Write-Host "`n¿Que IP deseas usar para el dominio?"
    Write-Host "  1) Usar IP detectada: $script:IP_SUGERIDA"
    Write-Host "  2) Ingresar IP manualmente"
    $opcionIp = Read-Host "Opcion (1/2)"

    if ($opcionIp -eq "2") {
        $manual = Read-Host "Introduce la IP"
        if ([string]::IsNullOrWhiteSpace($manual)) { Write-Host "IP vacia"; return }
        $script:IP_SUGERIDA = $manual.Trim()
    }

    $dominio = Read-Host "Nombre del dominio (ej. quieromiavion.com)"
    $dominio = $dominio.Trim()
    if ([string]::IsNullOrWhiteSpace($dominio)) { Write-Host "Dominio vacio"; return }

    try {
        # Crear la zona si no existe
        if (!(Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns"
            Write-Host "[+] Zona $dominio creada." -ForegroundColor Cyan
        }

        # Se elimino el parametro -Force para evitar errores de compatibilidad
        Add-DnsServerResourceRecordA -Name "@" -IPv4Address $script:IP_SUGERIDA -ZoneName $dominio
        Add-DnsServerResourceRecordA -Name "ns1" -IPv4Address $script:IP_SUGERIDA -ZoneName $dominio
        Add-DnsServerResourceRecordA -Name "www" -IPv4Address $script:IP_SUGERIDA -ZoneName $dominio

        Write-Host "[OK] Dominio $dominio creado apuntando a $script:IP_SUGERIDA" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] No se pudo crear la zona: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Eliminar-Zona {
    $domDel = Read-Host "Dominio a eliminar"
    if (Get-DnsServerZone -Name $domDel -ErrorAction SilentlyContinue) {
        Remove-DnsServerZone -Name $domDel -Force
        Write-Host "[OK] Dominio eliminado: $domDel" -ForegroundColor Green
    } else {
        Write-Host "[!] El dominio no existe." -ForegroundColor Yellow
    }
}

function Enlistar-Dominios {
    Write-Host "--- Dominios activos (DNS Windows) ---" -ForegroundColor Cyan
    Get-DnsServerZone | Where-Object { $_.ZoneType -eq "Primary" -and $_.ZoneName -ne "TrustAnchors" } | Select-Object ZoneName | Format-List
}

function Probar-Resolucion {
    $domCon = Read-Host "Dominio a consultar"
    Write-Host "`n[Resolve-DnsName] Consultando localmente..." -ForegroundColor Cyan
    Resolve-DnsName -Name $domCon -Server 127.0.0.1 -ErrorAction SilentlyContinue | Format-Table
    Resolve-DnsName -Name "www.$domCon" -Server 127.0.0.1 -ErrorAction SilentlyContinue | Format-Table
}

function Monitoreo {
    Write-Host "=== MONITOREO ===" -ForegroundColor Yellow
    Write-Host "[Servicio]"
    Get-Service DNS | Select-Object Status, Name, DisplayName
    Write-Host "`n[Puertos escuchando 53]"
    Get-NetTCPConnection -LocalPort 53 -ErrorAction SilentlyContinue | Select-Object LocalAddress, LocalPort, State
    Write-Host "`n[Resumen de Zonas]"
    Get-DnsServerZone | Group-Object ZoneType | Select-Object Count, Name
}

# --- Bucle Principal ---
Require-Admin
Install-DNS-If-Needed

while ($true) {
    Clear-Host
    Write-Host "Administracion dns"
    Write-Host "1. Enlistar Dominios"
    Write-Host "2. Agregar Dominio (incluye fijar IP)"
    Write-Host "3. Eliminar Dominio"
    Write-Host "4. Probar Resolucion Local"
    Write-Host "5. Monitoreo"
    Write-Host "6. Salir"
    $opcion = Read-Host "Selecciona una opcion"

    switch ($opcion) {
        "1" { Enlistar-Dominios; Pause }
        "2" { Crear-Zona; Pause }
        "3" { Eliminar-Zona; Pause }
        "4" { Probar-Resolucion; Pause }
        "5" { Monitoreo; Pause }
        "6" { Write-Host "Saliendo..."; exit }
        default { Write-Host "Opcion no valida."; Start-Sleep -Seconds 1 }
    }
}