#!/bin/bash
# ============================================================
# 04_union-mageia-dominio.sh
# Une Mageia Linux al dominio lab.local
# Usa realmd + sssd + adcli (disponibles en Mageia via DNF)
# Ejecutar como root
# ============================================================

DOMAIN_UP="LAB.LOCAL"
DOMAIN_LO="lab.local"
DC_IP="192.168.56.10"
ADMIN_USER="Administrator"

echo ""
echo "=== Union de Mageia Linux al dominio $DOMAIN_LO ==="
echo ""

# ============================================================
# 1. Configurar DNS apuntando al DC
# ============================================================
echo "[1] Configurando DNS hacia el DC ($DC_IP)..."
cat > /etc/resolv.conf << EOF
nameserver $DC_IP
nameserver 8.8.8.8
search $DOMAIN_LO
EOF
echo "[OK] /etc/resolv.conf configurado"

# ============================================================
# 2. Instalar paquetes necesarios
# ============================================================
echo ""
echo "[2] Instalando paquetes (realmd, sssd, adcli, krb5)..."
dnf install -y \
    realmd \
    sssd \
    sssd-ad \
    sssd-tools \
    adcli \
    krb5-workstation \
    oddjob \
    oddjob-mkhomedir \
    samba-common-tools \
    sudo \
    chrony

if [ $? -ne 0 ]; then
    echo "[ERROR] Fallo la instalacion de paquetes."
    exit 1
fi
echo "[OK] Paquetes instalados"

# ============================================================
# 3. Sincronizar tiempo con el DC (Kerberos lo requiere)
# ============================================================
echo ""
echo "[3] Sincronizando tiempo con el DC..."
systemctl enable chronyd --now > /dev/null 2>&1

# Agregar el DC como fuente NTP
if ! grep -q "$DC_IP" /etc/chrony.conf; then
    sed -i "1s/^/server $DC_IP iburst\n/" /etc/chrony.conf
    systemctl restart chronyd
fi

chronyc makestep > /dev/null 2>&1
echo "[OK] Tiempo sincronizado"

# ============================================================
# 4. Habilitar y arrancar servicios necesarios
# ============================================================
echo ""
echo "[4] Habilitando servicios dbus y oddjobd..."
systemctl enable dbus --now   > /dev/null 2>&1
systemctl enable oddjobd --now > /dev/null 2>&1
echo "[OK] Servicios activos"

# ============================================================
# 5. Descubrir el dominio con realmd
# ============================================================
echo ""
echo "[5] Descubriendo el dominio $DOMAIN_LO con realmd..."
realm discover $DOMAIN_LO
if [ $? -ne 0 ]; then
    echo "[ERROR] No se pudo descubrir el dominio. Verifica DNS y conectividad."
    exit 1
fi
echo "[OK] Dominio descubierto"

# ============================================================
# 6. Unirse al dominio
# ============================================================
echo ""
echo "[6] Uniendose al dominio $DOMAIN_LO..."
echo "    Se pedira la contrasena del Administrador del dominio"
realm join --user="$ADMIN_USER" "$DOMAIN_LO"
if [ $? -ne 0 ]; then
    echo "[ERROR] Fallo la union al dominio."
    exit 1
fi
echo "[OK] Equipo unido a $DOMAIN_LO"

# ============================================================
# 7. Configurar sssd.conf
#    - fallback_homedir = /home/%u@%d  (requerido por la practica)
#    - use_fully_qualified_names = False (para login sin @dominio)
# ============================================================
echo ""
echo "[7] Configurando /etc/sssd/sssd.conf..."
cat > /etc/sssd/sssd.conf << EOF
[sssd]
domains = $DOMAIN_LO
config_file_version = 2
services = nss, pam

[domain/$DOMAIN_LO]
ad_domain = $DOMAIN_LO
krb5_realm = $DOMAIN_UP
realmd_tags = manages-system joined-with-adcli
cache_credentials = True
id_provider = ad
krb5_store_password_if_offline = True
default_shell = /bin/bash
ldap_id_mapping = True
use_fully_qualified_names = False
fallback_homedir = /home/%u@%d
access_provider = ad
EOF

chmod 600 /etc/sssd/sssd.conf
echo "[OK] /etc/sssd/sssd.conf configurado"

# ============================================================
# 8. Habilitar creacion automatica del home al iniciar sesion
# ============================================================
echo ""
echo "[8] Habilitando mkhomedir (PAM)..."
authselect select sssd with-mkhomedir --force > /dev/null 2>&1
if [ $? -ne 0 ]; then
    # Fallback manual si authselect no esta disponible
    if ! grep -q "pam_mkhomedir" /etc/pam.d/system-auth; then
        echo "session optional pam_mkhomedir.so skel=/etc/skel/ umask=0077" \
            >> /etc/pam.d/system-auth
    fi
fi
echo "[OK] mkhomedir habilitado"

# ============================================================
# 9. Reiniciar y habilitar sssd
# ============================================================
echo ""
echo "[9] Iniciando sssd..."
systemctl enable sssd --now
systemctl restart sssd
sleep 3

if ! systemctl is-active --quiet sssd; then
    echo "[ERROR] sssd no pudo iniciarse. Revisa: journalctl -u sssd"
    exit 1
fi
echo "[OK] sssd corriendo"

# ============================================================
# 10. Configurar sudo para GrupoCuates del dominio
#     Requerido por la practica: /etc/sudoers.d/ad-admins
# ============================================================
echo ""
echo "[10] Configurando sudo para GrupoCuates..."
mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/ad-admins << EOF
# Permite sudo a todos los miembros de GrupoCuates en el dominio lab.local
%GrupoCuates@$DOMAIN_LO ALL=(ALL) ALL
EOF
chmod 440 /etc/sudoers.d/ad-admins
echo "[OK] /etc/sudoers.d/ad-admins configurado"

# ============================================================
# 11. Verificacion final
# ============================================================
echo ""
echo "=== Verificacion ==="

echo "Estado del dominio:"
realm list

echo ""
echo "Usuarios AD visibles (prueba con id):"
for user in jgarcia mlopez rperez psanchez; do
    result=$(id "$user" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "  [OK] $user -> $result"
    else
        echo "  [--] $user no encontrado aun (sssd puede tardar unos segundos)"
    fi
done

echo ""
echo "Grupos AD visibles:"
getent group GrupoCuates 2>/dev/null   && echo "  [OK] GrupoCuates visible" || echo "  [--] GrupoCuates no visible aun"
getent group GrupoNoCuates 2>/dev/null && echo "  [OK] GrupoNoCuates visible" || echo "  [--] GrupoNoCuates no visible aun"

echo ""
echo "[DONE] Mageia unida a $DOMAIN_LO"
echo ""
echo "Para iniciar sesion con un usuario del dominio:"
echo "  ssh jgarcia@localhost"
echo "  O en la pantalla de login usa: jgarcia (sin @dominio)"
echo ""
echo "El home se creara automaticamente en: /home/jgarcia@$DOMAIN_LO"
