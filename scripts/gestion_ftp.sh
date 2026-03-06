#!/bin/bash

# --- COLORES ---
VERDE='\033[0;32m'
CYAN='\033[0;36m'
AMARILLO='\033[1;33m'
ROJO='\033[0;31m'
RESET='\033[0m'

# --- CONFIGURACIÓN AUTOMÁTICA AL INICIAR ---
# Esto asegura que el Firewall no estorbe y que el .conf esté bien
preparar_entorno() {
    echo -e "${AMARILLO}Configurando entorno para vsftpd...${RESET}"
    sudo shorewall clear > /dev/null 2>&1
    sudo systemctl stop shorewall > /dev/null 2>&1
    
    # Asegurar que /sbin/nologin sea un shell válido para que vsftpd no lo rechace
    if ! grep -q "/sbin/nologin" /etc/shells; then
        echo "/sbin/nologin" | sudo tee -a /etc/shells > /dev/null
    fi

    # Crear directorio para chroot seguro si no existe
    sudo mkdir -p /var/run/vsftpd/empty
    sudo chmod 755 /var/run/vsftpd/empty
    
    # Configuración maestra optimizada para FileZilla y Mageia
    sudo bash -c 'cat <<EOF > /etc/vsftpd/vsftpd.conf
listen=YES
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=10000
pasv_max_port=10100
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
ssl_enable=NO
anonymous_enable=NO
# Evita errores de shell si el usuario usa /sbin/nologin
check_shell=NO
# Desactivamos listen_ipv6 si listen=YES para evitar conflictos
listen_ipv6=NO
EOF'
    sudo systemctl restart vsftpd
}

# --- 1. FUNCIÓN: INSTALAR Y VERIFICAR ---
verificar_y_instalar() {
    echo -e "\n${CYAN}--- PROCESO DE VERIFICACIÓN ---${RESET}"
    if rpm -q vsftpd &>/dev/null; then
        echo -e "${VERDE}[INSTALADO]: El paquete vsftpd ya se encuentra en el sistema.${RESET}"
    else
        echo -e "${AMARILLO}[NO ENCONTRADO]: vsftpd no está instalado.${RESET}"
        echo "Instalando vsftpd ahora..."
        urpmi vsftpd --auto
    fi
    
    if systemctl is-active --quiet vsftpd; then
        echo -e "${VERDE}[ESTADO]: El servicio vsftpd está ACTIVO.${RESET}"
    else
        echo -e "${ROJO}[ESTADO]: El servicio está INACTIVO. Iniciando...${RESET}"
        systemctl start vsftpd
    fi
    read -p "Presiona Enter para volver..."
}

# --- 2. GESTIÓN DE USUARIOS ---
crear_usuario() {
    read -p "Nombre del usuario: " user
    read -p "Escribe la contraseña (VISIBLE): " pass
    read -p "Grupo: " grupo
    
    # Crear la carpeta base si no existe para evitar el error de "dispositivo especial"
    mkdir -p "/var/ftp/general"
    mkdir -p "/var/ftp/grupos/$grupo"
    
    groupadd "$grupo" 2>/dev/null
    useradd -m -g "$grupo" -s /sbin/nologin "$user"
    echo "$user:$pass" | chpasswd
    
    U_FTP="/home/$user/ftp"
    mkdir -p "$U_FTP/general" "$U_FTP/$grupo"
    
    # Montajes
    mount --bind /var/ftp/general "$U_FTP/general"
    mount --bind "/var/ftp/grupos/$grupo" "$U_FTP/$grupo"
    
    chown -R "$user:$grupo" "/home/$user"
    echo -e "${VERDE}Usuario $user creado y carpetas vinculadas.${RESET}"
    read -p "Presiona Enter..."
}

# --- 3. CONSULTA DE USUARIOS Y GRUPOS (NUEVA) ---
ver_usuarios_grupos() {
    echo -e "\n${CYAN}--- USUARIOS CREADOS ---${RESET}"
    # Filtramos usuarios que tienen carpeta en /home (los que creamos nosotros)
    grep "/home" /etc/passwd | cut -d: -f1,3
    
    echo -e "\n${CYAN}--- GRUPOS FTP ---${RESET}"
    # Mostramos grupos con ID mayor a 1000 (creados por el usuario)
    awk -F: '$3 >= 1000 {print $1}' /etc/group
    
    echo -e "\n${AMARILLO}--- MONTAJES ACTIVOS ---${RESET}"
    mount | grep "ftp" | awk '{print $3}'
    read -p "Presiona Enter..."
}

eliminar_usuario() {
    read -p "Usuario a eliminar: " user
    umount -l "/home/$user/ftp/"* 2>/dev/null
    userdel -r "$user"
    echo -e "${ROJO}Usuario $user borrado.${RESET}"
    read -p "Presiona Enter..."
}

eliminar_grupo() {
    read -p "Nombre del grupo a eliminar: " grupo
    # Desmontar carpetas de usuarios que pertenezcan a este grupo (si existen)
    echo -e "${AMARILLO}Buscando usuarios del grupo $grupo para desmontar directorios...${RESET}"
    for user in $(grep ":$grupo$" /etc/group | cut -d: -f4 | tr ',' ' '); do
        umount -l "/home/$user/ftp/$grupo" 2>/dev/null
    done
    
    groupdel "$grupo" 2>/dev/null
    rm -rf "/var/ftp/grupos/$grupo"
    echo -e "${ROJO}Grupo $grupo borrado.${RESET}"
    read -p "Presiona Enter..."
}

crear_grupo() {
    read -p "Nombre del nuevo grupo: " grupo
    if grep -q "^$grupo:" /etc/group; then
        echo -e "${ROJO}El grupo $grupo ya existe.${RESET}"
    else
        groupadd "$grupo"
        mkdir -p "/var/ftp/grupos/$grupo"
        chmod 770 "/var/ftp/grupos/$grupo"
        echo -e "${VERDE}Grupo $grupo creado en /var/ftp/grupos/$grupo${RESET}"
    fi
    read -p "Presiona Enter..."
}

# --- EJECUCIÓN INICIAL ---
preparar_entorno

# --- MENÚ PRINCIPAL ---
while true; do
    clear
    echo -e "${CYAN}==========================================${RESET}"
    echo -e "${CYAN}     SISTEMA DE GESTIÓN FTP (MAGEIA)      ${RESET}"
    echo -e "${CYAN}==========================================${RESET}"
    echo -e "1) ${AMARILLO}VERIFICAR E INSTALAR VSFTPD${RESET}"
    echo "2) Crear Usuario (Carpeta y Montaje)"
    echo "3) Eliminar Usuario"
    echo "4) Crear Grupo"
    echo "5) Eliminar Grupo"
    echo -e "6) ${VERDE}VER USUARIOS Y GRUPOS${RESET}"
    echo "7) Reiniciar Servicio (vsftpd)"
    echo "8) Salir"
    echo -e "${CYAN}==========================================${RESET}"
    read -p "Selecciona una opción: " opt

    case $opt in
        1) verificar_y_instalar ;;
        2) crear_usuario ;;
        3) eliminar_usuario ;;
        4) crear_grupo ;;
        5) eliminar_grupo ;;
        6) ver_usuarios_grupos ;;
        7) systemctl restart vsftpd && echo "Servicio Reiniciado" && sleep 2 ;;
        8) exit 0 ;;
        *) echo "Opción no válida" && sleep 1 ;;
    esac
done