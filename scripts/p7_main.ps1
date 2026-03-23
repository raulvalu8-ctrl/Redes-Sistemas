# =============================================================================
# p7_main.ps1 - Script Principal Practica 7 (Windows Server)
# =============================================================================

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$FunctionsFile = Join-Path $ScriptDir "p7_functions.ps1"

if (!(Test-Path $FunctionsFile)) {
    Write-Host "[ERROR] No se encontro p7_functions.ps1 en: $FunctionsFile" -ForegroundColor Red
    exit 1
}

. $FunctionsFile

function fn_menu_principal_p7 {
    while ($true) {
        fn_header_p7
        Write-Host "  Selecciona una opcion:`n" -ForegroundColor White
        Write-Host "  [1]" -ForegroundColor Cyan -NoNewline; Write-Host " Instalar IIS     (Rol nativo + SSL opcional)"
        Write-Host "  [2]" -ForegroundColor Cyan -NoNewline; Write-Host " Instalar Apache  (WEB o FTP + SSL opcional)"
        Write-Host "  [3]" -ForegroundColor Cyan -NoNewline; Write-Host " Instalar Nginx   (WEB o FTP + SSL opcional)"
        Write-Host "  [4]" -ForegroundColor Cyan -NoNewline; Write-Host " Configurar FTPS  (SSL en IIS FTP)"
        Write-Host "  [5]" -ForegroundColor Cyan -NoNewline; Write-Host " Ver estado de servicios"
        Write-Host "  [6]" -ForegroundColor Cyan -NoNewline; Write-Host " Resumen de instalaciones"
        Write-Host "  [0]" -ForegroundColor Red -NoNewline;  Write-Host " Salir`n"
        
        $opcion = Read-Host -Prompt "Opcion"
        switch ($opcion) {
            "1" { fn_verificar_admin_p7; fn_verificar_dependencias; fn_instalar_servicio_hibrido "iis" "IIS"; Read-Host "`nPresiona ENTER para continuar..." }
            "2" { fn_verificar_admin_p7; fn_verificar_dependencias; fn_instalar_servicio_hibrido "apache" "Apache"; Read-Host "`nPresiona ENTER para continuar..." }
            "3" { fn_verificar_admin_p7; fn_verificar_dependencias; fn_instalar_servicio_hibrido "nginx" "Nginx"; Read-Host "`nPresiona ENTER para continuar..." }
            "4" { fn_verificar_admin_p7; fn_configurar_ftps; Read-Host "`nPresiona ENTER para continuar..." }
            "5" { 
                Write-Host "`n====== ESTADO DE SERVICIOS ======" -ForegroundColor Cyan
                Write-Host "Puertos en escucha:" -ForegroundColor Cyan
                Get-NetTCPConnection -State Listen | Select-Object LocalAddress, LocalPort | Sort-Object LocalPort -Unique | Format-Table -AutoSize
                Write-Host "`nServicios activos:" -ForegroundColor Cyan
                Get-Service -Name "Apache*","nginx*","tomcat*","ftpsvc*" -ErrorAction SilentlyContinue | Format-Table Status, Name, DisplayName
                Read-Host "`nPresiona ENTER para continuar..."
            }
            "6" { fn_mostrar_resumen; Read-Host "`nPresiona ENTER para continuar..." }
            "0" { Write-Host "`nSaliendo. Hasta luego!`n" -ForegroundColor Green; exit 0 }
            default { Write-Host "[ERROR] Opcion invalida." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

fn_verificar_admin_p7
fn_menu_principal_p7
