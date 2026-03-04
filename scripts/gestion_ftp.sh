#!/bin/bash
# =================================================
# SCRIPT FTP ROBUSTO PARA MAGEIA (LINUX)
# =================================================

# 1. VERIFICACIÓN E INSTALACIÓN (Idempotencia)
echo "--- Verificando vsftpd ---"
if ! rpm -q vsftpd &>/dev/null; then
    echo "Instalando vsftpd..."
    urpmi vsftpd --auto
else
    echo "vsftpd ya está instalado. Continuando..."
fi

# 2. CREAR ESTRUCTURA RAIZ DEL SERVIDOR
# Estas son las carpetas reales en el disco duro
mkdir -p /var/ftp/general
mkdir -p /var/ftp/grupos/reprobados
mkdir -p /var/ftp/grupos/recursadores

# Asegurar que existan los grupos en el sistema
groupadd reprobados 2>/dev/null
groupadd recursadores 2>/dev/null

# Permisos para la carpeta publica (Anonimos)
chmod 755 /var/ftp/general
chown ftp:ftp /var/ftp/general

# 3. CONFIGURACIÓN DEL SERVICIO VSFTPD
echo "--- Configurando archivo /etc/vsftpd.conf ---"
cat <<EOF > /etc/vsftpd.conf
# Configuracion General
listen=YES
local_enable=YES
write_enable=YES
local_umask=022

# Acceso Anonimo (Solo lectura a /general)
anonymous_enable=YES
no_anon_password=YES
anon_root=/var/ftp/general

# Enjaular usuarios en su home
chroot_local_user=YES
allow_writeable_chroot=YES

# Definir la raiz del usuario (su carpeta ftp personal)
user_sub_token=\$USER
local_root=/home/\$USER/ftp
EOF

# 4. CREACIÓN DE USUARIOS
echo "--- Gestion de Usuarios ---"
read -p "¿Cuántos usuarios quieres dar de alta?: " n

for (( i=1; i<=n; i++ )); do
    echo -e "\n[Usuario $i de $n]"
    read -p "Nombre de usuario: " usuario
    
    # Aquí verás la contraseña mientras la escribes
    read -p "Escribe la contraseña para $usuario: " pass 
    
    echo "Selecciona el grupo:"
    echo "1) reprobados"
    echo "2) recursadores"
    read -p "Opción: " g_opt

    if [ "$g_opt" == "2" ]; then
        grupo="recursadores"
    else
        grupo="reprobados"
    fi

    # Crear usuario, asignar grupo y denegar acceso a la terminal (solo FTP)
    useradd -m -g "$grupo" -s /sbin/nologin "$usuario"
    echo "$usuario:$pass" | chpasswd

    # Crear la estructura de carpetas dentro del HOME del usuario
    U_FTP="/home/$usuario/ftp"
    mkdir -p "$U_FTP/general"
    mkdir -p "$U_FTP/$grupo"
    mkdir -p "$U_FTP/$usuario"

    # EL TRUCO DEL PROFE: Vincular carpetas externas a la raiz del usuario
    # Esto permite que vea las carpetas compartidas aunque esté "enjaulado"
    mount --bind /var/ftp/general "$U_FTP/general"
    mount --bind /var/ftp/grupos/$grupo "$U_FTP/$grupo"

    # Asignar permisos: El usuario es dueño de su estructura
    chown -R "$usuario:$grupo" "/home/$usuario"
    chmod 755 "$U_FTP"
    
    echo ">> Usuario $usuario configurado exitosamente en $grupo."
done

# 5. REINICIAR SERVICIO Y LIMPIAR FIREWALL
systemctl restart vsftpd
shorewall clear &>/dev/null # Desactiva firewall de Mageia temporalmente para pruebas

echo -e "\n=========================================="
echo "   CONFIGURACIÓN FINALIZADA CON ÉXITO"
echo "=========================================="
echo "Acceso Anónimo: Raiz es /general"
echo "Acceso Usuarios: Ven /general, /$grupo y /$usuario"