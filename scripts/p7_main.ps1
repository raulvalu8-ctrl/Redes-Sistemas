# =============================================================================
# p7_main.ps1 - Orquestador de Instalacion Windows (Premium Menu)
# =============================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\p7_functions.ps1"

fn_verificar_admin_p7

function Show-StatusHeader {
    Clear-Host
    Write-Host ""
    Draw-Box -Color Blue -Lineas @(
        '  ORQUESTADOR DE INSTALACION  ',
        '      reprobados.com          ',
        '  Windows Server 2022         '
    )

    $iisSvcS   = Get-SvcStatus -SvcNames @('W3SVC')
    $apacheS   = Get-SvcStatus -SvcNames @('Apache24','Apache2.4')
    $nginxS    = Get-SvcStatus -SvcNames @('Nginx')
    
    # Intentamos detectar puertos SSL comunes o configurados
    Draw-Box -Color Cyan -Lineas @(
        ' Servicio   Estado        SSL           ',
        ' ---------------------------------------',
        " IIS        $($iisSvcS.PadRight(13)) $(Get-SslStatus -Puerto 443)",
        " Apache     $($apacheS.PadRight(13)) $(Get-SslStatus -Puerto 8443)",
        " Nginx      $($nginxS.PadRight(13)) $(Get-SslStatus -Puerto 8444)"
    )
    Write-Host ""
}

while ($true) {
    Show-StatusHeader
    
    Draw-Box -Color Blue -Lineas @(
        ' 1) Instalar IIS    (Local + SSL)     ',
        ' 2) Instalar Apache (Hibrido FTP/Web) ',
        ' 3) Instalar Nginx  (Hibrido FTP/Web) ',
        ' 4) Configurar FTPS (IIS FTP + SSL)   ',
        ' 5) Ver resumen de instalaciones      ',
        ' 6) Configurar Repositorio FTP (Linux) ',
        ' 0) Salir                             '
    )
    
    Write-Host ""
    $opcion = Read-Host "  Selecciona una opcion"
    
    switch ($opcion) {
        "1" { fn_instalar_servicio_hibrido "iis" "IIS" }
        "2" { fn_instalar_servicio_hibrido "apache" "Apache" }
        "3" { fn_instalar_servicio_hibrido "nginx" "Nginx" }
        "4" { fn_configurar_ftps }
        "5" { fn_mostrar_resumen }
        "6" { fn_configurar_repo_ftp }
        "0" { 
            Write-Host "`nSaliendo..." -ForegroundColor Red
            Start-Sleep -Seconds 1
            break 
        }
        default { fn_err "Opcion no valida." }
    }
    
    if ($opcion -ne "0") {
        Write-Host "`nPresiona ENTER para volver al menu..." -ForegroundColor Gray
        Read-Host | Out-Null
    }
}
