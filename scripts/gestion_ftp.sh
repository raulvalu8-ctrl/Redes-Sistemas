#!/bin/bash

# --- COLORES ---
VERDE='\033[0;32m'
CYAN='\033[0;36m'
AMARILLO='\033[1;33m'
ROJO='\033[0;31m'
RESET='\033[0m'

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
    
    # Verificar si el servicio está corriendo
    if systemctl is-active --quiet vsftpd; then
        echo -e "${VERDE}[ESTADO]: El servicio vsftpd está ACTIVO y funcionando.${RESET}"
    else
        echo -e "${ROJO}[ESTADO]: El servicio está INACTIVO. Iniciando...${RESET}"
        systemctl start vsftpd
    fi
    read -p "Presiona Enter para volver al menú..."
}

# --- 2. GESTIÓN DE USUARIOS (PASS VISIBLE) ---
crear_usuario() {
    read -p "Nombre del usuario: " user
    read -p "Escribe la contraseña (VISIBLE): " pass
    read -p "Grupo: " grupo
    
    groupadd "$grupo" 2>/dev/null
    useradd -m -g "$grupo" -s /sbin/nologin "$user"
    echo "$user:$pass" | chpasswd
    
    # Crear carpetas espejo
    U_FTP="/home/$user/ftp"
    mkdir -p "/var/ftp/grupos/$grupo"
    mkdir -p "$U_FTP/general" "$U_FTP/$grupo" "$U_FTP/$user"
    
    mount --bind /var/ftp/general "$U_FTP/general"
    mount --bind "/var/ftp/grupos/$grupo" "$U_FTP/$grupo"
    
    chown -R "$user:$grupo" "/home/$user"
    echo -e "${VERDE}Usuario $user creado.${RESET}"
    read -p "Presiona Enter..."
}

# --- 3. GESTIÓN DE GRUPOS ---
crear_grupo() {
    read -p "Nombre del nuevo grupo: " grupo
    groupadd "$grupo"
    mkdir -p "/var/ftp/grupos/$grupo"
    echo -e "${VERDE}Grupo $grupo listo.${RESET}"
    read -p "Presiona Enter..."
}

eliminar_usuario() {
    read -p "Usuario a eliminar: " user
    umount -l "/home/$user/ftp/"* 2>/dev/null
    userdel -r "$user"
    echo -e "${ROJO}Usuario borrado.${RESET}"
    read -p "Presiona Enter..."
}

eliminar_grupo() {
    read -p "Grupo a eliminar: " grupo
    groupdel "$grupo"
    rm -rf "/var/ftp/grupos/$grupo"
    echo -e "${ROJO}Grupo borrado.${RESET}"
    read -p "Presiona Enter..."
}

# --- MENÚ PRINCIPAL ---
while true; do
    clear
    echo -e "${CYAN}==========================================${RESET}"
    echo -e "${CYAN}     SISTEMA DE GESTIÓN FTP (MAGEIA)      ${RESET}"
    echo -e "${CYAN}==========================================${RESET}"
    echo -e "1) ${AMARILLO}VERIFICAR E INSTALAR VSFTPD${RESET}"
    echo "2) Crear Usuario (Contraseña Visible)"
    echo "3) Eliminar Usuario"
    echo "4) Crear Grupo"
    echo "5) Eliminar Grupo"
    echo "6) Reiniciar Servicio"
    echo "7) Salir"
    echo -e "${CYAN}==========================================${RESET}"
    read -p "Selecciona una opción: " opt

    case $opt in
        1) verificar_y_instalar ;;
        2) crear_usuario ;;
        3) eliminar_usuario ;;
        4) crear_grupo ;;
        5) eliminar_grupo ;;
        6) systemctl restart vsftpd && echo "Servicio Reiniciado" && sleep 2 ;;
        7) exit 0 ;;
        *) echo "Opción no válida" && sleep 1 ;;
    esac
done