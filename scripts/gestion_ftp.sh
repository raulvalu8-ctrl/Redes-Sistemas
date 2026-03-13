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
    
    # Asegurar que el usuario ftp exista (visto como sistema) pero sin uso FTP
    if ! id "ftp" &>/dev/null; then
        sudo useradd -r -d /var/ftp -s /bin/false ftp > /dev/null 2>&1
    fi
    sudo usermod -U ftp > /dev/null 2>&1

    # --- LIMPIEZA DE RASTROS ANONIMOS ---
    sudo umount -l /var/ftp_anon/general 2>/dev/null
    sudo rm -rf /var/ftp_anon 2>/dev/null
    
    # Asegurar carpetas base para usuarios reales
    sudo mkdir -p /var/ftp/publica
    sudo mkdir -p /var/ftp/grupos
    sudo chown root:root /var/ftp
    sudo chmod 755 /var/ftp
    
    # Eliminar carpeta 'pub' por defecto si existe en /var/ftp para evitar confusiones
    sudo rm -rf /var/ftp/pub 2>/dev/null
    
    # Permisos totales para que puedan crear carpetas y archivos dentro
    sudo chmod 777 /var/ftp/publica
    sudo chmod 777 /var/ftp/grupos
    sudo chmod 777 /var/ftp/grupos/reprobados

    # --- CONFIGURACION ANONIMA ESTRICTA (SOLO LECTURA) ---
    sudo mkdir -p /var/ftp_anon/publica
    sudo umount -l /var/ftp_anon/publica 2>/dev/null || true
    sudo mount --bind /var/ftp/publica /var/ftp_anon/publica
    
    # Asegurar que la raíz sea de root y no escribible para anonimo
    sudo chown root:root /var/ftp_anon
    sudo chmod 555 /var/ftp_anon
    sudo chown root:root /var/ftp_anon/publica
    sudo chmod 555 /var/ftp_anon/publica

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
check_shell=NO

# Acceso Anónimo (ESTRICTO: Solo Lectura, Solo Publica)
anonymous_enable=YES
no_anon_password=YES
anon_root=/var/ftp_anon
ftp_username=ftp
anon_world_readable_only=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO
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
    Log-Header "Registrar/Reparar Usuario"
    read -p "Nombre del usuario: " user
    read -p "Escribe la contraseña (VISIBLE): " pass
    
    # --- Selección de Grupo Interactiva ---
    echo -e "${CYAN}[+] Grupos de Clase disponibles:${NC}"
    # Listar carpetas en /var/ftp/grupos
    group_folders=$(ls /var/ftp/grupos 2>/dev/null)
    # Listar grupos que existen en el sistema y tienen carpeta o son el default
    groups=($(awk -F: -v folders="$group_folders" -v def="$GROUP_A" 'BEGIN{split(folders,f," ")} {for(i in f) if($1==f[i] || $1==def) {print $1; break}}' /etc/group | sort -u | head -n 10))
    
    if [ ${#groups[@]} -eq 0 ]; then
        cGroup=$GROUP_A
    else
        for i in "${!groups[@]}"; do
            echo -e "  [$((i+1))] ${groups[$i]}"
        done
        read -p "Seleccione el número o escriba el nombre del grupo (Enter para '$GROUP_A'): " in
        
        if [[ $in =~ ^[0-9]+$ ]] && [ "$in" -ge 1 ] && [ "$in" -le "${#groups[@]}" ]; then
            cGroup=${groups[$((in-1))]}
        elif [[ " ${groups[*]} " =~ " $in " ]]; then
            cGroup=$in
        else
            cGroup=$GROUP_A
        fi
    fi

    # Asegurar que el grupo exista en el sistema y carpeta física
    if ! getent group "$cGroup" > /dev/null; then
        sudo groupadd "$cGroup" 2>/dev/null
    fi
    sudo mkdir -p "/var/ftp/grupos/$cGroup"
    sudo chmod 777 "/var/ftp/grupos/$cGroup"

    if ! id "$user" &>/dev/null; then
        # Crear usuario con home en /var/ftp/usuario
        sudo useradd -m -d "/var/ftp/$user" -s /bin/false "$user"
        sudo usermod -aG "$GROUP_BASE" "$user"
    fi

    # Limpiar pertenencia a otros grupos (un usuario solo debe estar en su grupo asignado + base)
    # Obtenemos grupos actuales excluyendo el grupo primario del usuario
    current_groups=$(id -Gn "$user")
    for g in $current_groups; do
        if [[ "$g" != "$GROUP_BASE" && "$g" != "$user" && "$g" != "$cGroup" ]]; then
            sudo gpasswd -d "$user" "$g" 2>/dev/null
        fi
    done
    sudo usermod -aG "$cGroup" "$user"
    
    # Establecer/Actualizar contraseña
    echo "$user:$pass" | sudo chpasswd

    # --- Estructura de 3 Carpetas ---
    user_home="/var/ftp/$user"
    sudo mkdir -p "$user_home/user"
    sudo mkdir -p "$user_home/publica"
    sudo mkdir -p "$user_home/$cGroup"
    
    # Desmontar cualquier cosa previa para limpiar rastro de grupos antiguos
    # Buscamos montajes que pertenezcan a este usuario
    mounts=$(mount | grep "$user_home/" | awk '{print $3}')
    for m in $mounts; do
        sudo umount -l "$m" 2>/dev/null || true
    done
    
    # Borrar carpetas de grupos antiguos (solo dejamos user y publica)
    sudo find "$user_home" -maxdepth 1 -mindepth 1 -not -name "user" -not -name "publica" -not -name "$cGroup" -exec rm -rf {} + 2>/dev/null

    # Re-montar
    sudo mount --bind /var/ftp/publica "$user_home/publica"
    sudo mount --bind "/var/ftp/grupos/$cGroup" "$user_home/$cGroup"
    
    # Asegurar propiedad y permisos restrictivos para chroot
    sudo chown root:root "$user_home"
    sudo chmod 755 "$user_home"
    
    # La carpeta 'user' y el contenido de los mounts deben ser accesibles
    sudo chown "$user:$user" "$user_home/user"
    sudo chmod 700 "$user_home/user"

    echo -e "${VERDE}[+] Usuario '$user' configurado en grupo '$cGroup'.${NC}"
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
    echo -e "${AMARILLO}Desmontando carpeta del grupo antiguo...${RESET}"
    sudo umount -l "/home/$user/grupo" 2>/dev/null
    sudo rm -rf "/home/$user/grupo"
    sudo umount -l "/home/$user/$grupo_actual" 2>/dev/null
    sudo rm -rf "/home/$user/$grupo_actual"

    # 2. Cambiar grupo principal en el sistema
    sudo usermod -g "$nuevo_grupo" "$user"

    # 3. Crear nueva carpeta y cargar montaje
    sudo mkdir -p "/home/$user/$nuevo_grupo"
    sudo mount --bind "/var/ftp/grupos/$nuevo_grupo" "/home/$user/$nuevo_grupo"

    # 4. Asegurar que las carpetas fija (publica, user) existen por si acaso
    sudo mkdir -p "/home/$user/publica" "/home/$user/user"
    sudo mount --bind /var/ftp/publica "/home/$user/publica" 2>/dev/null

    # 5. Ajustar permisos
    sudo chown -R "$user:$nuevo_grupo" "/home/$user"
    sudo chmod 755 "/home/$user/user"
    
    # 6. Limpiar carpetas no deseadas para vista de 3 carpetas impecable
    # solo permitimos: publica, [nombre_nuevo_grupo] y user
    sudo find "/home/$user" -maxdepth 1 -mindepth 1 -not -name "publica" -not -name "$nuevo_grupo" -not -name "user" -exec rm -rf {} + 2>/dev/null
    
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