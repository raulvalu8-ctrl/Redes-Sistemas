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
    
    # Asegurar que los shells sean válidos para que vsftpd no rechace el login
    for shell in "/sbin/nologin" "/bin/false"; do
        if ! grep -q "$shell" /etc/shells; then
            echo "$shell" | sudo tee -a /etc/shells > /dev/null
        fi
    done

    # Crear directorio para chroot seguro si no existe
    sudo mkdir -p /var/run/vsftpd/empty
    sudo chmod 755 /var/run/vsftpd/empty
    
    # Asegurar que el usuario ftp exista, tenga el shell correcto y esté en su zona aislada
    if ! id "ftp" &>/dev/null; then
        sudo useradd -r -d /var/ftp_anon -s /bin/false ftp > /dev/null 2>&1
    else
        # Forzar el home aislado para que vsftpd no se confunda
        sudo usermod -d /var/ftp_anon -s /bin/false ftp > /dev/null 2>&1
    fi
    sudo usermod -U ftp > /dev/null 2>&1

    # vsftpd es extremadamente estricto con el chroot: la raíz NO puede tener escritura.
    sudo mkdir -p /var/ftp/publica
    sudo mkdir -p /var/ftp/grupos
    
    sudo chown root:root /var/ftp
    sudo chmod 755 /var/ftp
    
    # --- AISLAMIENTO ANÓNIMO (Solo carpeta 'general') ---
    # Limpiamos CUALQUIER rastro previo para que no haya fugas
    sudo umount -l /var/ftp_anon/general 2>/dev/null
    sudo rm -rf /var/ftp_anon
    sudo mkdir -p /var/ftp_anon/general
    sudo chown root:root /var/ftp_anon
    sudo chmod 755 /var/ftp_anon
    
    # Montar la carpeta compartida como 'general'
    sudo mount --bind /var/ftp/publica /var/ftp_anon/general
    
    # Eliminar carpeta 'pub' por defecto si existe en /var/ftp para evitar confusiones
    sudo rm -rf /var/ftp/pub 2>/dev/null
    
    # Permisos totales para que puedan crear carpetas y archivos dentro
    sudo chmod 777 /var/ftp/publica
    sudo chmod 777 /var/ftp/grupos
    sudo chmod 777 /var/ftp/grupos/reprobados

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
listen_ipv6=NO
ssl_enable=NO
check_shell=NO

# Acceso Anónimo (Aislado con carpeta 'general')
anonymous_enable=YES
no_anon_password=YES
anon_root=/var/ftp_anon
ftp_username=ftp
anon_world_readable_only=NO
anon_upload_enable=YES
anon_mkdir_write_enable=YES
anon_other_write_enable=YES
EOF'
    
    # Limpiar posibles bloqueos de usuario ftp en listas de seguridad
    [ -f /etc/vsftpd/user_list ] && sudo sed -i '/^ftp$/d' /etc/vsftpd/user_list
    [ -f /etc/vsftpd/ftpusers ] && sudo sed -i '/^ftp$/d' /etc/vsftpd/ftpusers

    sudo rm -rf /home/*/tmp 2>/dev/null
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
        sudo urpmi vsftpd --auto
    fi
    
    if systemctl is-active --quiet vsftpd; then
        echo -e "${VERDE}[ESTADO]: El servicio vsftpd está ACTIVO.${RESET}"
    else
        echo -e "${ROJO}[ESTADO]: El servicio está INACTIVO. Iniciando...${RESET}"
        sudo systemctl start vsftpd
    fi
    read -p "Presiona Enter para volver..."
}

# --- 2. GESTIÓN DE USUARIOS ---
crear_usuario() {
    read -p "Nombre del usuario: " user
    read -p "Escribe la contraseña (VISIBLE): " pass
    grupo="reprobados"
    
    # Crear la carpeta base si no existe para evitar el error de "dispositivo especial"
    sudo mkdir -p "/var/ftp/publica"
    sudo mkdir -p "/var/ftp/grupos/$grupo"
    
    sudo groupadd "$grupo" 2>/dev/null
    sudo useradd -m -g "$grupo" -s /sbin/nologin "$user"
    printf "%s:%s" "$user" "$pass" | sudo chpasswd
    
    U_FTP="/home/$user"
    sudo mkdir -p "$U_FTP/publica" "$U_FTP/grupo" "$U_FTP/user"
    
    # Montajes
    sudo mount --bind /var/ftp/publica "$U_FTP/publica"
    sudo mount --bind "/var/ftp/grupos/$grupo" "$U_FTP/grupo"
    
    # Carpeta personal y permisos de gestión
    sudo chown -R "$user:$grupo" "$U_FTP"
    sudo chmod 775 "$U_FTP"
    sudo chmod 775 "$U_FTP/user"
    
    # Limpiar archivos ocultos y carpetas extra para vista de 3 carpetas unicamente
    sudo find "$U_FTP" -maxdepth 1 -mindepth 1 -not -name "publica" -not -name "grupo" -not -name "user" -exec rm -rf {} + 2>/dev/null
    
    echo -e "${VERDE}Usuario $user listo con sus 3 carpetas.${RESET}"
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
    sudo umount -l "/home/$user/publica" 2>/dev/null
    sudo umount -l "/home/$user/"* 2>/dev/null
    sudo userdel -r "$user"
    echo -e "${ROJO}Usuario $user borrado.${RESET}"
    read -p "Presiona Enter..."
}

eliminar_grupo() {
    read -p "Nombre del grupo a eliminar: " grupo
    # Desmontar carpetas de usuarios que pertenezcan a este grupo (si existen)
    echo -e "${AMARILLO}Buscando usuarios del grupo $grupo para desmontar directorios...${RESET}"
    for user in $(grep ":$grupo$" /etc/group | cut -d: -f4 | tr ',' ' '); do
        sudo umount -l "/home/$user/$grupo" 2>/dev/null
    done
    
    sudo groupdel "$grupo" 2>/dev/null
    sudo rm -rf "/var/ftp/grupos/$grupo"
    echo -e "${ROJO}Grupo $grupo borrado.${RESET}"
    read -p "Presiona Enter..."
}

crear_grupo() {
    read -p "Nombre del nuevo grupo: " grupo
    if grep -q "^$grupo:" /etc/group; then
        echo -e "${ROJO}El grupo $grupo ya existe.${RESET}"
    else
        sudo groupadd "$grupo"
        sudo mkdir -p "/var/ftp/grupos/$grupo"
        sudo chmod 770 "/var/ftp/grupos/$grupo"
        echo -e "${VERDE}Grupo $grupo creado en /var/ftp/grupos/$grupo${RESET}"
    fi
    read -p "Presiona Enter..."
}

# --- 4. FUNCIÓN PERMITIR CAMBIO DE GRUPO ---
cambiar_grupo_usuario() {
    read -p "Usuario a modificar: " user
    if ! id "$user" &>/dev/null; then
        echo -e "${ROJO}El usuario $user no existe.${RESET}"
        read -p "Presiona Enter..."
        return
    fi

    # Obtener el grupo actual del usuario
    grupo_actual=$(id -gn "$user")
    echo -e "${AMARILLO}Usuario: $user | Grupo actual: $grupo_actual${RESET}"
    
    read -p "Nuevo grupo para $user: " nuevo_grupo
    
    # Verificar si el nuevo grupo existe
    if ! grep -q "^$nuevo_grupo:" /etc/group; then
        echo -e "${AMARILLO}El grupo $nuevo_grupo no existe. ¿Deseas crearlo? (s/n): ${RESET}"
        read -p "" crear
        if [[ "$crear" == "s" ]]; then
            groupadd "$nuevo_grupo"
            mkdir -p "/var/ftp/grupos/$nuevo_grupo"
            chmod 770 "/var/ftp/grupos/$nuevo_grupo"
        else
            return
        fi
    fi

    # 1. Desmontar grupo antiguo
    echo -e "${AMARILLO}Desmontando carpeta del grupo antiguo ($grupo_actual)...${RESET}"
    sudo umount -l "/home/$user/grupo" 2>/dev/null
    sudo rm -rf "/home/$user/grupo"

    # 2. Cambiar grupo principal en el sistema
    sudo usermod -g "$nuevo_grupo" "$user"

    # 3. Crear nueva carpeta y cargar montaje
    sudo mkdir -p "/home/$user/grupo"
    sudo mount --bind "/var/ftp/grupos/$nuevo_grupo" "/home/$user/grupo"

    # 4. Asegurar que las carpetas fija (publica, user) existen por si acaso
    sudo mkdir -p "/home/$user/publica" "/home/$user/user"
    sudo mount --bind /var/ftp/publica "/home/$user/publica" 2>/dev/null

    # 5. Ajustar permisos
    sudo chown -R "$user:$nuevo_grupo" "/home/$user"
    sudo chmod 755 "/home/$user/user"
    
    # 6. Limpiar carpetas no deseadas (publica, grupo, user)
    sudo find "/home/$user" -maxdepth 1 -mindepth 1 -not -name "publica" -not -name "grupo" -not -name "user" -exec rm -rf {} + 2>/dev/null
    
    echo -e "${VERDE}El usuario $user ha sido movido al grupo $nuevo_grupo exitosamente.${RESET}"
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
    echo "6) Cambiar Usuario de Grupo"
    echo -e "7) ${VERDE}VER USUARIOS Y GRUPOS${RESET}"
    echo "8) Reiniciar Servicio (vsftpd)"
    echo "9) Salir"
    echo -e "${CYAN}==========================================${RESET}"
    read -p "Selecciona una opción: " opt

    case $opt in
        1) verificar_y_instalar ;;
        2) crear_usuario ;;
        3) eliminar_usuario ;;
        4) crear_grupo ;;
        5) eliminar_grupo ;;
        6) cambiar_grupo_usuario ;;
        7) ver_usuarios_grupos ;;
        8) systemctl restart vsftpd && echo "Servicio Reiniciado" && sleep 2 ;;
        9) exit 0 ;;
        *) echo "Opción no válida" && sleep 1 ;;
    esac
done