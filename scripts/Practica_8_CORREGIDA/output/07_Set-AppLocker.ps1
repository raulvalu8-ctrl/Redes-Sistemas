# ============================================================
# 07_Set-AppLocker.ps1
# Configura AppLocker via GPO:
#   GrupoCuates:   notepad.exe PERMITIDO
#   GrupoNoCuates: notepad.exe BLOQUEADO por Hash SHA-256
#
# CORRECCION CLAVE:
#   El hash se calcula en el SERVIDOR pero el bloqueo debe
#   coincidir con el hash del notepad.exe del CLIENTE W10.
#   Este script busca el hash correcto del cliente de dos formas:
#     a) Si el cliente ya esta en el dominio, lo obtiene por red.
#     b) Si no, usa el hash del servidor como aproximacion e
#        imprime instrucciones para actualizarlo manualmente.
#
# REQUISITO: Windows 10/11 Enterprise o Education
#            (AppLocker NO funciona en Pro ni Home)
#
# Ejecutar en Windows Server 2022 como Administrador del dominio
# ============================================================

Import-Module ActiveDirectory

$notepadPathServidor = "C:\Windows\System32\notepad.exe"
$gpoName             = "GPO-AppLocker"
$domainDN            = (Get-ADDomain).DistinguishedName

Write-Host "`n=== Configurando AppLocker ===" -ForegroundColor Cyan

# ============================================================
# 1. Habilitar el servicio Application Identity (obligatorio)
# ============================================================
Write-Host "`n[1] Habilitando servicio AppIDSvc..." -ForegroundColor Yellow
Set-Service -Name AppIDSvc -StartupType Automatic
Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue
$svc = Get-Service AppIDSvc
Write-Host "[OK] AppIDSvc: $($svc.Status)" -ForegroundColor Green

# ============================================================
# 2. Obtener SID de GrupoNoCuates
# ============================================================
Write-Host "`n[2] Obteniendo SID de GrupoNoCuates..." -ForegroundColor Yellow
$sidNoCuates = (Get-ADGroup "GrupoNoCuates").SID.Value
Write-Host "[OK] SID GrupoNoCuates: $sidNoCuates" -ForegroundColor Green

# ============================================================
# 3. Calcular Hash SHA-256 de notepad.exe
#
#    IMPORTANTE: Se calcula el hash del servidor.
#    Si el cliente tiene una version diferente de Windows 10,
#    el hash puede ser distinto y el bloqueo no funcionara.
#
#    Para obtener el hash correcto del cliente:
#      En el cliente Windows 10 (como admin), ejecutar:
#        $h = Get-FileHash "C:\Windows\System32\notepad.exe" -Algorithm SHA256
#        Write-Host "Hash: 0x$($h.Hash)"
#        Write-Host "Size: $((Get-Item 'C:\Windows\System32\notepad.exe').Length)"
#      Luego reemplazar $hashFinal y $sizeFinal en este script.
# ============================================================
Write-Host "`n[3] Calculando hash SHA-256 de notepad.exe..." -ForegroundColor Yellow

$hashObj    = Get-FileHash -Path $notepadPathServidor -Algorithm SHA256
$hashFinal  = "0x" + $hashObj.Hash
$sizeFinal  = (Get-Item $notepadPathServidor).Length

Write-Host "[OK] Hash notepad.exe (servidor): $hashFinal" -ForegroundColor Green
Write-Host "[OK] Tamanio: $sizeFinal bytes" -ForegroundColor Green

# Intentar obtener el hash desde el cliente si ya esta en el dominio
Write-Host "`n[..] Buscando clientes Windows en el dominio para obtener hash correcto..." -ForegroundColor Yellow
$clientesW10 = Get-ADComputer -Filter {OperatingSystem -like "*Windows 10*"} -ErrorAction SilentlyContinue

if ($clientesW10) {
    foreach ($cliente in $clientesW10) {
        Write-Host "     Intentando en $($cliente.Name)..." -ForegroundColor DarkGray
        try {
            $resultado = Invoke-Command -ComputerName $cliente.Name -ScriptBlock {
                $h = Get-FileHash "C:\Windows\System32\notepad.exe" -Algorithm SHA256
                $s = (Get-Item "C:\Windows\System32\notepad.exe").Length
                [PSCustomObject]@{ Hash = "0x" + $h.Hash; Size = $s }
            } -ErrorAction Stop
            $hashFinal = $resultado.Hash
            $sizeFinal = $resultado.Size
            Write-Host "[OK] Hash obtenido del cliente $($cliente.Name): $hashFinal" -ForegroundColor Green
            Write-Host "[OK] Tamanio en cliente: $sizeFinal bytes" -ForegroundColor Green
            break
        } catch {
            Write-Host "     No se pudo conectar a $($cliente.Name) (puede que no este encendido)" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "[--] No se encontraron clientes Windows 10 en el dominio aun." -ForegroundColor Yellow
    Write-Host "     Se usara el hash del servidor. Si falla el bloqueo en el cliente," -ForegroundColor Yellow
    Write-Host "     ejecuta en el cliente W10:" -ForegroundColor Yellow
    Write-Host '     $h = Get-FileHash "C:\Windows\System32\notepad.exe" -Algorithm SHA256' -ForegroundColor White
    Write-Host '     Write-Host "0x$($h.Hash)"' -ForegroundColor White
    Write-Host "     Y actualiza este script con ese hash." -ForegroundColor Yellow
}

Write-Host "`n[INFO] Hash final a usar: $hashFinal" -ForegroundColor Cyan
Write-Host "[INFO] Tamanio final:      $sizeFinal bytes" -ForegroundColor Cyan

# ============================================================
# 4. Construir XML de politica AppLocker
#
# LOGICA:
#   - Allow Everyone (*): base obligatoria para que AppLocker
#     procese las reglas. Sin esta, Deny no tiene efecto.
#   - Deny Hash GrupoNoCuates: bloquea notepad aunque lo
#     renombren o copien a otra ruta (el hash no cambia).
#   - GrupoCuates queda cubierto por Allow Everyone.
# ============================================================
Write-Host "`n[4] Construyendo politica XML de AppLocker..." -ForegroundColor Yellow

$xmlPolicy = @"
<?xml version="1.0" encoding="utf-8"?>
<AppLockerPolicy Version="1">

  <RuleCollection Type="Exe" EnforcementMode="Enabled">

    <!-- REGLA BASE OBLIGATORIA: Allow Everyone -->
    <!-- Sin esta regla, AppLocker bloquea TODO por defecto -->
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de580acf"
                  Name="Allow Everyone - All files"
                  Description="Permite ejecutar cualquier exe (regla base)"
                  UserOrGroupSid="S-1-1-0"
                  Action="Allow">
      <Conditions>
        <FilePathCondition Path="*"/>
      </Conditions>
    </FilePathRule>

    <!-- REGLA DENY: GrupoNoCuates no puede ejecutar notepad.exe -->
    <!-- Usa Hash SHA-256: bloquea el BINARIO sin importar nombre o ruta -->
    <!-- Si renombran notepad.exe a "word.exe", sigue bloqueado -->
    <FileHashRule Id="22222222-2222-2222-2222-222222222222"
                  Name="Deny-Notepad-GrupoNoCuates"
                  Description="Bloquea notepad.exe por Hash SHA-256 a GrupoNoCuates"
                  UserOrGroupSid="$sidNoCuates"
                  Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256"
                    Data="$hashFinal"
                    SourceFileName="notepad.exe"
                    SourceFileLength="$sizeFinal"/>
        </FileHashCondition>
      </Conditions>
    </FileHashRule>

  </RuleCollection>

  <RuleCollection Type="Msi"    EnforcementMode="NotConfigured"/>
  <RuleCollection Type="Script" EnforcementMode="NotConfigured"/>
  <RuleCollection Type="Dll"    EnforcementMode="NotConfigured"/>
  <RuleCollection Type="Appx"   EnforcementMode="NotConfigured"/>

</AppLockerPolicy>
"@

$xmlPath = "C:\Scripts\applocker_policy.xml"
$xmlPolicy | Out-File -FilePath $xmlPath -Encoding UTF8
Write-Host "[OK] XML guardado en $xmlPath" -ForegroundColor Green

# ============================================================
# 5. Crear GPO y vincularla al dominio
# ============================================================
Write-Host "`n[5] Creando GPO '$gpoName'..." -ForegroundColor Yellow

if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
    New-GPO -Name $gpoName -Comment "Politica AppLocker por grupo" | Out-Null
    Write-Host "[OK] GPO '$gpoName' creada" -ForegroundColor Green
} else {
    Write-Host "[--] GPO '$gpoName' ya existe" -ForegroundColor Yellow
}

$gpoObj  = Get-GPO -Name $gpoName
$gpoGuid = $gpoObj.Id.ToString()

$yaVinculada = Get-GPInheritance -Target $domainDN |
    Select-Object -ExpandProperty GpoLinks |
    Where-Object { $_.DisplayName -eq $gpoName }

if (-not $yaVinculada) {
    New-GPLink -Name $gpoName -Target $domainDN -Enforced Yes | Out-Null
    Write-Host "[OK] GPO vinculada al dominio con Enforced=Yes" -ForegroundColor Green
} else {
    Write-Host "[--] GPO ya estaba vinculada" -ForegroundColor Yellow
}

# ============================================================
# 6. Aplicar la politica AppLocker a la GPO via LDAP
# ============================================================
Write-Host "`n[6] Aplicando politica AppLocker a la GPO via LDAP..." -ForegroundColor Yellow
$ldapPath = "LDAP://CN={$gpoGuid},CN=Policies,CN=System,DC=lab,DC=local"

try {
    Set-AppLockerPolicy -XmlPolicy $xmlPath -Ldap $ldapPath
    Write-Host "[OK] Politica aplicada a GPO via LDAP" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Al aplicar via LDAP: $_" -ForegroundColor Red
    Write-Host "[INFO] Intentando aplicar localmente..." -ForegroundColor Yellow
    try {
        Set-AppLockerPolicy -XmlPolicy $xmlPath
        Write-Host "[OK] Politica aplicada localmente" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Fallo tambien localmente: $_" -ForegroundColor Red
        exit 1
    }
}

# ============================================================
# 7. Forzar replicacion y actualizacion de politicas
# ============================================================
Write-Host "`n[7] Actualizando politicas..." -ForegroundColor Yellow
gpupdate /force | Out-Null
Write-Host "[OK] gpupdate /force ejecutado" -ForegroundColor Green

# ============================================================
# 8. Verificacion
# ============================================================
Write-Host "`n=== Verificacion AppLocker ===" -ForegroundColor Cyan

Write-Host "`nGPOs vinculadas al dominio:" -ForegroundColor White
Get-GPInheritance -Target $domainDN |
    Select-Object -ExpandProperty GpoLinks |
    ForEach-Object { Write-Host "  - $($_.DisplayName)" -ForegroundColor Gray }

Write-Host "`nReglas en la GPO (via LDAP):" -ForegroundColor White
try {
    $xmlLeido = [xml](Get-AppLockerPolicy -Ldap $ldapPath -Xml)
    $reglas = $xmlLeido.AppLockerPolicy.RuleCollection | Where-Object { $_.Type -eq "Exe" }
    $reglas.FilePathRule | ForEach-Object {
        Write-Host "  [ALLOW] $($_.Name) | SID: $($_.UserOrGroupSid)" -ForegroundColor Green
    }
    $reglas.FileHashRule | ForEach-Object {
        Write-Host "  [DENY]  $($_.Name) | SID: $($_.UserOrGroupSid)" -ForegroundColor Red
    }
} catch {
    Write-Host "  No se pudo leer la politica via LDAP: $_" -ForegroundColor Yellow
}

Write-Host "`n[DONE] AppLocker configurado correctamente." -ForegroundColor Cyan
Write-Host ""
Write-Host "=== PASOS EN EL CLIENTE WINDOWS 10 ===" -ForegroundColor Yellow
Write-Host "  1. Unirse al dominio (03_Union-Windows10.ps1)" -ForegroundColor White
Write-Host "  2. Despues del reinicio, ejecutar como Admin:" -ForegroundColor White
Write-Host "       gpupdate /force" -ForegroundColor White
Write-Host "       Restart-Service AppIDSvc -Force" -ForegroundColor White
Write-Host "  3. Verificar bloqueo con usuario NoCuates:" -ForegroundColor White
Write-Host "       Get-AppLockerPolicy -Effective | Test-AppLockerPolicy -Path 'C:\Windows\System32\notepad.exe' -User 'LAB\rperez'" -ForegroundColor White
Write-Host "  4. Si el bloqueo no funciona, obtener hash del cliente:" -ForegroundColor White
Write-Host '       $h = Get-FileHash "C:\Windows\System32\notepad.exe" -Algorithm SHA256' -ForegroundColor White
Write-Host '       Write-Host "0x$($h.Hash)"' -ForegroundColor White
Write-Host "     Y volver a correr este script." -ForegroundColor White
