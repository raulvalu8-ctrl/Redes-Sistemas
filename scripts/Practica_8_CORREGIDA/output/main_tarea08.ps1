# ============================================================
# main_tarea08.ps1
# Menu principal para la Tarea 08:
# Gobernanza, Cuotas y Control de Aplicaciones en AD
#
# CORRECCION: ruta cambiada de Z:\scripts a C:\Scripts
# ============================================================

Set-ExecutionPolicy Unrestricted -Scope Process -Force

$scriptsPath = "C:\Scripts"

function Show-Menu {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "       TAREA 08 - GOBERNANZA AD           " -ForegroundColor Cyan
    Write-Host "       Windows Server 2022 - lab.local    " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. Crear OUs y Grupos (Cuates / NoCuates)" -ForegroundColor White
    Write-Host "  2. Importar Usuarios desde CSV"            -ForegroundColor White
    Write-Host "  3. Configurar Logon Hours + GPO"           -ForegroundColor White
    Write-Host "  4. Instalar FSRM + Cuotas + Screening"     -ForegroundColor White
    Write-Host "  5. Configurar AppLocker"                   -ForegroundColor White
    Write-Host ""
    Write-Host "  6. Ejecutar TODO en orden"                 -ForegroundColor Yellow
    Write-Host "  7. Verificar configuracion"                -ForegroundColor Green
    Write-Host ""
    Write-Host "  0. Salir"                                  -ForegroundColor Red
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
}

function Run-Script {
    param(
        [string]$nombre,
        [string]$archivo
    )
    $ruta = "$scriptsPath\$archivo"
    Write-Host ""
    Write-Host ">>> Ejecutando: $nombre" -ForegroundColor Yellow
    Write-Host "    $ruta" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-Path $ruta)) {
        Write-Host "[ERROR] No se encontro el archivo: $ruta" -ForegroundColor Red
    } else {
        & $ruta
    }

    Write-Host ""
    Write-Host "Presiona cualquier tecla para volver al menu..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ============================================================
# LOOP PRINCIPAL
# ============================================================
do {
    Show-Menu
    $opcion = Read-Host "Selecciona una opcion"

    switch ($opcion) {
        "1" { Run-Script "Crear OUs y Grupos"               "01_Crear-OUs.ps1"          }
        "2" { Run-Script "Importar Usuarios desde CSV"      "02_Importar-Usuarios.ps1"  }
        "3" { Run-Script "Logon Hours + GPO"                "05_Set-LogonHours-GPO.ps1" }
        "4" { Run-Script "FSRM + Cuotas + Screening"        "06_Setup-FSRM.ps1"         }
        "5" { Run-Script "AppLocker"                        "07_Set-AppLocker.ps1"      }

        "6" {
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Yellow
            Write-Host "   Ejecutando TODOS los scripts en orden  " -ForegroundColor Yellow
            Write-Host "==========================================" -ForegroundColor Yellow

            $pasos = @(
                @{ nombre = "Crear OUs y Grupos"        ; archivo = "01_Crear-OUs.ps1"          },
                @{ nombre = "Importar Usuarios"         ; archivo = "02_Importar-Usuarios.ps1"  },
                @{ nombre = "Logon Hours + GPO"         ; archivo = "05_Set-LogonHours-GPO.ps1" },
                @{ nombre = "FSRM + Cuotas + Screening" ; archivo = "06_Setup-FSRM.ps1"         },
                @{ nombre = "AppLocker"                 ; archivo = "07_Set-AppLocker.ps1"      }
            )

            $i = 1
            foreach ($paso in $pasos) {
                Write-Host ""
                Write-Host "[$i/$($pasos.Count)] $($paso.nombre)" -ForegroundColor Cyan
                $ruta = "$scriptsPath\$($paso.archivo)"
                if (Test-Path $ruta) {
                    & $ruta
                } else {
                    Write-Host "[ERROR] No encontrado: $ruta" -ForegroundColor Red
                }
                $i++
            }

            Write-Host ""
            Write-Host "==========================================" -ForegroundColor Green
            Write-Host "   TODOS LOS SCRIPTS EJECUTADOS"           -ForegroundColor Green
            Write-Host "==========================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "Presiona cualquier tecla para volver al menu..." -ForegroundColor DarkGray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }

        "7" { Run-Script "Verificacion General" "08_Verificar-Todo.ps1" }

        "0" {
            Clear-Host
            Write-Host ""
            Write-Host "  Saliendo..." -ForegroundColor Red
            Write-Host ""
        }

        default {
            Write-Host ""
            Write-Host "  Opcion no valida. Intenta de nuevo." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }

} while ($opcion -ne "0")
