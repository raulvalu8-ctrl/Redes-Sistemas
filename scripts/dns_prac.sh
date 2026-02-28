#!/bin/bash
# REQUISITO: Ejecutar con sudo

# Colores para que se vea bien
VERDE='\033[0;32m'
CYAN='\033[0;36m'
AMARILLO='\033[1;33m'
RESET='\033[0m'

mostrar_menu() {
    clear
    echo -e "${CYAN}===============================================${RESET}"
    echo -e "${CYAN}       GESTOR DNS MAGEIA - SOLUCION PING       ${RESET}"
    echo -e "${CYAN}===============================================${RESET}"
    echo "1. Crear Dominio (EOF + Registro A)"
    echo "2. Ver Dominios e IPs registradas"
    echo "3. Eliminar Dominio y Limpiar"
    echo "4. Probar con NSLOOKUP / HOST"
    echo "5. Salir"
    echo -e "${CYAN}===============================================${RESET}"
}

# Configurar el sistema para que se consulte a si mismo
# Esto arregla el error de "Nombre o servicio desconocido"
echo "nameserver 127.0.0.1" > /etc/resolv.conf

while true; do
    mostrar_menu
    read -p "Seleccione una opcion: " opc

    case $opc in
        1)
            read -p "Nombre del dominio (ej. reprobados.com): " dominio
            read -p "IP a la que apunta: " ip
            
            # Crear archivo de zona usando EOF (Here Document)
            cat <<EOF > /var/lib/named/var/named/$dominio.zone
\$TTL 86400
@   IN  SOA     ns1.$dominio. admin.$dominio. (
                2026022701 ; Serial
                3600       ; Refresh
                1800       ; Retry
                604800     ; Expire
                86400 )    ; Minimum
    IN  NS      ns1.$dominio.
ns1 IN  A       $ip
@   IN  A       $ip
www IN  A       $ip
EOF
            
            # Agregar al archivo de configuracion (Include)
            # Solo lo agrega si no existe ya en el archivo
            if ! grep -q "$dominio" /etc/named.conf; then
                echo "zone \"$dominio\" IN { type master; file \"$dominio.zone\"; };" >> /etc/named.conf
            fi

            # Permisos y Reinicio
            chown named:named /var/lib/named/var/named/$dominio.zone
            systemctl restart named
            echo -e "${VERDE}[OK] Dominio $dominio creado y apuntando a $ip${RESET}"
            read -p "Presione Enter..."
            ;;

        2)
            echo -e "\n${AMARILLO}--- DOMINIOS EN /etc/named.conf ---${RESET}"
            grep "zone" /etc/named.conf | grep -v "localhost" | cut -d'"' -f2
            read -p "Presione Enter..."
            ;;

        3)
            read -p "Dominio a eliminar: " dominio
            # Borrar la zona del archivo de config (sed borra la linea que coincida)
            sed -i "/zone \"$dominio\"/d" /etc/named.conf
            # Borrar el archivo de zona físicamente
            rm -f /var/lib/named/var/named/$dominio.zone
            systemctl restart named
            echo -e "${VERDE}[OK] Dominio eliminado.${RESET}"
            read -p "Presione Enter..."
            ;;

        4)
            read -p "Dominio a consultar: " test
            host $test
            read -p "Presione Enter..."
            ;;

        5)
            echo "Saliendo..."
            break
            ;;

        *)
            echo "Opcion no valida"
            sleep 1
            ;;
    esac
done