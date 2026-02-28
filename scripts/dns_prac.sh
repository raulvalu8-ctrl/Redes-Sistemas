#!/bin/bash
# REQUISITO: Ejecutar con sudo (root)

# Colores para la interfaz
VERDE='\033[0;32m'
CYAN='\033[0;36m'
AMARILLO='\033[1;33m'
ROJO='\033[0;31m'
RESET='\033[0m'

# Intentar detectar la ruta de zonas de Mageia
if [ -d "/var/lib/named/var/named" ]; then
    ZONEDIR="/var/lib/named/var/named"
elif [ -d "/var/lib/named" ]; then
    ZONEDIR="/var/lib/named"
else
    ZONEDIR="/var/named"
fi

mostrar_menu() {
    clear
    echo -e "${CYAN}===============================================${RESET}"
    echo -e "${CYAN}       GESTOR DNS MAGEIA - CORREGIDO           ${RESET}"
    echo -e "${CYAN}===============================================${RESET}"
    echo "1. Crear Dominio (Habilita Ping local)"
    echo "2. Ver Dominios e IPs registradas"
    echo "3. Eliminar Dominio (Limpieza de archivos)"
    echo "4. Probar Resolucion (host/nslookup)"
    echo "5. Salir"
    echo -e "${CYAN}===============================================${RESET}"
}

# Forzar que el sistema se consulte a si mismo para que el PING funcione
echo "nameserver 127.0.0.1" > /etc/resolv.conf

while true; do
    mostrar_menu
    read -p "Seleccione una opcion: " opc

    case $opc in
        1)
            read -p "Nombre del dominio (ej. reprobados.com): " dominio
            read -p "IP a la que apunta: " ip
            
            if [ -z "$dominio" ] || [ -z "$ip" ]; then
                echo -e "${ROJO}[!] No puedes dejar campos vacios.${RESET}"
                sleep 2
                continue
            fi

            echo -e "${AMARILLO}Creando zona en $ZONEDIR...${RESET}"
            
            # Crear archivo de zona usando EOF
            cat <<EOF > "$ZONEDIR/$dominio.zone"
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
            
            # Agregar al named.conf si no existe
            if ! grep -q "zone \"$dominio\"" /etc/named.conf; then
                echo "zone \"$dominio\" IN { type master; file \"$dominio.zone\"; };" >> /etc/named.conf
            fi

            # Permisos correctos para Bind
            chown named:named "$ZONEDIR/$dominio.zone"
            chmod 664 "$ZONEDIR/$dominio.zone"

            # Reiniciar y verificar
            systemctl restart named
            if [ $? -eq 0 ]; then
                echo -e "${VERDE}[OK] Dominio $dominio listo. Prueba 'ping $dominio'${RESET}"
            else
                echo -e "${ROJO}[!] Error al reiniciar el servicio DNS.${RESET}"
            fi
            read -p "Presione Enter para continuar..."
            ;;

        2)
            echo -e "\n${AMARILLO}--- REGISTROS ACTUALES ---${RESET}"
            grep "zone" /etc/named.conf | grep -v "localhost" | cut -d'"' -f2 | while read -r dom; do
                if [ -f "$ZONEDIR/$dom.zone" ]; then
                    ip_reg=$(grep -P "\tA\t| IN A " "$ZONEDIR/$dom.zone" | grep "@" | awk '{print $NF}')
                    echo -e "Dominio: $dom  --> IP: $ip_reg"
                fi
            done
            read -p "Presione Enter..."
            ;;

        3)
            read -p "Nombre del dominio a eliminar: " dominio
            if [ -f "$ZONEDIR/$dominio.zone" ]; then
                # Borrar del config
                sed -i "/zone \"$dominio\"/d" /etc/named.conf
                # Borrar archivo fisico
                rm -f "$ZONEDIR/$dominio.zone"
                systemctl restart named
                echo -e "${VERDE}[OK] Eliminado correctamente.${RESET}"
            else
                echo -e "${ROJO}[!] El dominio no existe.${RESET}"
            fi
            read -p "Presione Enter..."
            ;;

        4)
            read -p "Dominio a consultar: " test
            host "$test"
            read -p "Presione Enter..."
            ;;

        5)
            echo "Saliendo..."
            break
            ;;

        *)
            echo -e "${ROJO}Opcion invalida.${RESET}"
            sleep 1
            ;;
    esac
done