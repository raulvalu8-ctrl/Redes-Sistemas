# ============================================================
# 02_Importar-Usuarios.ps1
# Lee usuarios.csv y los crea en la OU correspondiente
# segun el campo Departamento (Cuates o NoCuates)
# Ejecutar DESPUES de 01_Crear-OUs.ps1
# ============================================================

Import-Module ActiveDirectory

$csvPath  = "C:\Scripts\usuarios.csv"
$domainDN = (Get-ADDomain).DistinguishedName

if (-not (Test-Path $csvPath)) {
    Write-Host "[ERROR] No se encontro el archivo: $csvPath" -ForegroundColor Red
    exit 1
}

$usuarios = Import-Csv -Path $csvPath
Write-Host "`n=== Importando $($usuarios.Count) usuarios desde CSV ===" -ForegroundColor Cyan

foreach ($u in $usuarios) {

    # Determinar OU y grupo segun Departamento
    switch ($u.Departamento) {
        "Cuates"   {
            $ouPath = "OU=Cuates,$domainDN"
            $grupo  = "GrupoCuates"
        }
        "NoCuates" {
            $ouPath = "OU=NoCuates,$domainDN"
            $grupo  = "GrupoNoCuates"
        }
        default {
            Write-Warning "Departamento desconocido '$($u.Departamento)' para $($u.Usuario). Omitiendo."
            continue
        }
    }

    $secPwd = ConvertTo-SecureString $u.Password -AsPlainText -Force

    try {
        # Crear usuario en AD
        New-ADUser `
            -Name                 "$($u.Nombre) $($u.Apellido)" `
            -GivenName            $u.Nombre `
            -Surname              $u.Apellido `
            -SamAccountName       $u.Usuario `
            -UserPrincipalName    $u.Email `
            -EmailAddress         $u.Email `
            -Department           $u.Departamento `
            -Path                 $ouPath `
            -AccountPassword      $secPwd `
            -Enabled              $true `
            -PasswordNeverExpires $true

        # Agregar al grupo de seguridad correspondiente
        Add-ADGroupMember -Identity $grupo -Members $u.Usuario

        # Crear carpeta personal del usuario
        $homeDir = "C:\Perfiles\$($u.Usuario)"
        if (-not (Test-Path $homeDir)) {
            New-Item -ItemType Directory -Path $homeDir | Out-Null
        }

        # Asignar permisos: solo el usuario tiene acceso a su carpeta
        $acl      = Get-Acl $homeDir
        $identity = "lab\$($u.Usuario)"
        $rule     = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $identity, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.SetAccessRule($rule)
        Set-Acl -Path $homeDir -AclObject $acl

        Write-Host "[OK] $($u.Usuario) -> OU: $($u.Departamento) | Carpeta: $homeDir" -ForegroundColor Green

    } catch {
        Write-Warning "Error al crear $($u.Usuario): $_"
    }
}

Write-Host "`n[DONE] Importacion completada.`n" -ForegroundColor Cyan
