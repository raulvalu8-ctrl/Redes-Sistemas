#!/bin/bash
# Requisito: Ejecutar con sudo

# --- COLORES ---
VERDE='\033[0;32m'
CYAN='\033[0;36m'
AMARILLO='\033[1;33m'
ROJO='\033[0;31m'
RESET='\033[0m'

# --- RUTAS BASE ---
FTP_RAIZ="/var/ftp_data"
DIR_GENERAL="$FTP_RAIZ/general"
DIR_GRUPOS="$FTP_RAIZ/grupos"

# --- 1. INSTALACIÓN E IDEMPOTENCIA ---
instalar_vsftpd() {
    echo -e "${CYAN}Verificando vsftpd...${RESET}"
    if ! rpm -q vsftpd &>/dev/null; then
        echo "Instalando vsftpd..."
        urpmi vsftpd --auto
    else
        echo -e "${VERDE}vsftpd ya está instalado.${RESET}"
    fi

    # Crear estructura base
    mkdir -p "$DIR_GENERAL"
    mkdir -p "$DIR_GRUPOS/reprobados"
    mkdir -p "$DIR_GRUPOS/recursadores"
    
    # Configuración de vsftpd.conf
    cat <<EOF > /etc/vsftpd.conf
listen=YES
local_enable=YES
write_enable=YES
local_umask=022
anonymous_enable=YES
no_anon_password=YES
anon_root=$DIR_GENERAL
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
# Forzar que la raiz sea la carpeta ftp del home del usuario
local_root=/home/\$USER/ftp
EOF
    systemctl restart vsftpd
    echo -e "${VERDE}Servicio configurado y reiniciado.${RESET}"
}

# --- 2. GESTIÓN DE USUARIOS ---
crear_usuarios() {
    # Asegurar grupos
    groupadd reprobados 2>/dev/null
    groupadd recursadores 2>/dev/null

    read -p "¿Cuántos usuarios desea crear?: " n
    for (( i=1; i<=n; i++ )); do
        echo -e "\n${AMARILLO}Usuario $i de $n:${RESET}"
        read -p "Nombre: " username
        read -s -p "Contraseña: " password
        echo ""
        read -p "Grupo (1. reprobados / 2. recursadores): " g_opt
        
        group="reprobados"
        [ "$g_opt" == "2" ] && group="recursadores"

        # Crear usuario con home y grupo
        useradd -m -g "$group" -s /sbin/nologin "$username"
        echo "$username:$password" | chpasswd

        # ESTRUCTURA DE CARPETAS DEL USUARIO
        U_HOME="/home/$username/ftp"
        mkdir -p "$U_HOME/general"
        mkdir -p "$U_HOME/$group"
        mkdir -p "$U_HOME/$username"

        # DAR PERMISOS NTFS-LIKE (ACLs/Chmod)
        chown -R "$username:$group" "/home/$username"
        chmod 755 "$U_HOME"
        
        # EL TRUCO DEL MONTAJE (Para que vea la carpeta general y de grupo)
        # Esto hace que lo que pase en /var/ftp_data se vea en el home del usuario
        mount --bind "$DIR_GENERAL" "$U_HOME/general"
        mount --bind "$DIR_GRUPOS/$group" "$U_HOME/$group"
        
        echo -e "${VERDE}Usuario $username creado y vinculado a $group.${RESET}"
    done
}

# --- 3. CAMBIO DE GRUPO ---
cambiar_grupo() {
    read -p "Nombre de usuario: " username
    if id "$username" &>/dev/null; then
        read -p "Nuevo Grupo (1. reprobados / 2. recursadores): " g_opt
        new_group="reprobados"
        [ "$g_opt" == "2" ] && new_group="recursadores"

        # Desmontar carpeta vieja de grupo
        old_group=$(id -gn "$username")
        umount "/home/$username/ftp/$old_group" 2>/dev/null
        rmdir "/home/$username/ftp/$old_group"

        # Cambiar grupo en sistema
        usermod -g "$new_group" "$username"
        
        # Crear y montar nueva carpeta
        mkdir -p "/home/$username/ftp/$new_group"
        mount --bind "$DIR_GRUPOS/$new_group" "/home/$username/ftp/$new_group"
        chown "$username:$new_group" "/home/$username/ftp/$new_group"
        
        echo -e "${VERDE}Usuario movido a $new_group.${RESET}"
    else
        echo -e "${ROJO}Usuario no existe.${RESET}"
    fi
}

# --- 4. ELIMINAR USUARIO ---
eliminar_usuario() {
    read -p "Usuario a eliminar: " username
    if id "$username" &>/dev/null; then
        # Desmontar todo antes de borrar
        umount -l "/home/$username/ftp/"* 2>/dev/null
        userdel -r "$username"
        echo -e "${VERDE}Usuario eliminado.${RESET}"
    else
        echo -e "${ROJO}No existe.${RESET}"
    fi
}

# --- MENU PRINCIPAL ---
while true; do
    echo -e "\n${CYAN}==== GESTOR FTP ROBUSTO ====${RESET}"
    echo "1. Instalar/Verificar Servicio"
    echo "2. Crear Usuarios (Masivo)"
    echo "3. Cambiar Usuario de Grupo"
    echo "4. Eliminar Usuario"
    echo "5. Reiniciar vsftpd"
    echo "6. Salir"
    read -p "Opción: " opt

    case $opt in
        1) instalar_vsftpd ;;
        2) crear_usuarios ;;
        3) cambiar_grupo ;;
        4) eliminar_usuario ;;
        5) systemctl restart vsftpd && echo "Reiniciado." ;;
        6) exit 0 ;;
        *) echo "Invalido." ;;
    esac
done