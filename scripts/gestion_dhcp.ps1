# Script de Gestion DHCP - Version Final Validada
Set-StrictMode -Version Latest
$ConfirmPreference = "None"
$ErrorActionPreference = "SilentlyContinue"

# Validacion para IPs (Servidor, Rango, DNS, GW)
function Validar-IP-Host ($ip) {
    $obj = $null
    if (-not [ipaddress]::TryParse($ip, [ref]$obj)) { return $false }
    $b = $obj.GetAddressBytes()
    # Bloquea 0.x, 127.x y Multicast/Broadcast (224+)
    if (($b[0] -eq 0) -or ($b[0] -eq 127) -or ($b[0] -ge 224)) { return $false }
    return $true
}

# Validacion simple solo para el formato de la Mascara
function Validar-Formato-IP ($ip) {
    return [ipaddress]::TryParse($ip, [ref]$null)
}

function Get-Prefix ($m) {
    try {
        $bits = ""
        [ipaddress]::Parse($m).GetAddressBytes() | ForEach-Object { $bits += [System.Convert]::ToString($_, 2).PadLeft(8, '0') }
        return ($bits.ToCharArray() | Where-Object { $_ -eq '1' }).Count
    } catch { return 24 }
}

function Menu-Principal {
    Write-Host "`n--- ADMINISTRACION DHCP ---"
    Write-Host "1. Verificar instalacion"
    Write-Host "2. Instalar DHCP"
    Write-Host "2.1 Configuracion y Activacion"
    Write-Host "3. Monitoreo de Clientes"
    Write-Host "4. Desinstalar DHCP"
    Write-Host "5. Salir"
}

do {
    Menu-Principal
    $OPC = (Read-Host "Opcion").Trim()

    switch ($OPC) {
        "1" {
            if (Test-Path "C:\Windows\System32\dhcpssvc.dll") {
                Write-Host "Estado: Instalado"
                $serv = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
                Write-Host "Servicio: $($serv.Status)"
            } else { Write-Host "Estado: No instalado" }
        }

        "2" {
            Write-Host "Instalando componentes..."
            dism /online /enable-feature /featurename:DHCPServer /all /norestart
            Install-WindowsFeature DHCP -IncludeManagementTools > $null
            Set-Service -Name DHCPServer -StartupType Automatic
            Start-Service DHCPServer
            Write-Host "Proceso finalizado."
        }

        "2.1" {
            $Adapter = Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1
            if (-not $Adapter) { Write-Host "Error: No hay red."; break }

            # --- ENTRADAS CON VALIDACION CORRECTA ---
            do { $IP_SRV = Read-Host "IP Servidor" } until (Validar-IP-Host $IP_SRV)
            do { $IP_FIN = Read-Host "IP Final Rango" } until (Validar-IP-Host $IP_FIN)
            # Aqui solo validamos que sea una IP escrita correctamente
            do { $MASK = Read-Host "Mascara" } until (Validar-Formato-IP $MASK)
            
            $GW = Read-Host "Puerta de Enlace (Vacio para saltar)"
            $DNS1 = Read-Host "DNS 1 (Vacio para saltar)"
            $DNS2 = Read-Host "DNS 2 (Vacio para saltar)"
            $TIEMPO = Read-Host "Segundos de concesion"

            $ObjIP = [ipaddress]$IP_SRV
            $Bytes = $ObjIP.GetAddressBytes()
            $IP_START = "$($Bytes[0]).$($Bytes[1]).$($Bytes[2]).$($Bytes[3] + 1)"
            $ScopeID = "$($Bytes[0]).$($Bytes[1]).$($Bytes[2]).0"
            $Prefix = Get-Prefix $MASK

            # Red Servidor
            $Adapter | Get-NetIPAddress -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false
            New-NetIPAddress -InterfaceAlias $Adapter.Name -IPAddress $IP_SRV -PrefixLength $Prefix -Confirm:$false > $null

            # DHCP Ambito
            Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force > $null
            $TS = New-TimeSpan -Seconds ([int]$TIEMPO)
            Add-DhcpServerv4Scope -Name "DHCP_Scope" -StartRange $IP_START -EndRange $IP_FIN -SubnetMask $MASK -LeaseDuration $TS -State Active
            
            # Opciones
            if ($GW -and (Validar-IP-Host $GW)) { Set-DhcpServerv4OptionValue -ScopeId $ScopeID -Router $GW -Force }
            $listaDNS = @()
            if ($DNS1 -and (Validar-IP-Host $DNS1)) { $listaDNS += $DNS1 }
            if ($DNS2 -and (Validar-IP-Host $DNS2)) { $listaDNS += $DNS2 }
            if ($listaDNS.Count -gt 0) { Set-DhcpServerv4OptionValue -ScopeId $ScopeID -DnsServer $listaDNS -Force }

            # Registro y Firewall
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\DHCPServer\Parameters" -Name "DisableRogueDetection" -Value 1 -Type DWord
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name "ConfigurationState" -Value 2 -Type DWord
            Set-DhcpServerv4Binding -InterfaceAlias $Adapter.Name -BindingState $true
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
            Restart-Service DHCPServer
            Write-Host "Configuracion aplicada."
        }

        "3" {
            Write-Host "--- Concesiones ---"
            Get-DhcpServerv4Scope | Get-DhcpServerv4Lease | Select-Object IPAddress, HostName | Format-Table
        }

        "4" {
            Write-Host "Desinstalando..."
            dism /online /disable-feature /featurename:DHCPServer /norestart
            Uninstall-WindowsFeature DHCP -IncludeManagementTools -Confirm:$false > $null
            Write-Host "Hecho."
        }

        "5" { break }
    }
} while ($true)