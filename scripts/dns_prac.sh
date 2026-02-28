#!/bin/bash
# REQUISITO: Ejecutar con sudo (root)

# 1. Colores y Configuración Inicial
VERDE='\033[0;32m'
CYAN='\033[0;36m'
AMARILLO='\033[1;33m'
ROJO='\033[0;31m'
RESET='\033[0m'

# 2. Detectar la ruta de zonas correcta en Mageia
if [ -d "/var/lib/named/var/named" ]; then
    ZONEDIR="/var/lib/named/var/named"
elif [ -d "/var/lib/named" ]; then
    ZONEDIR="/var/lib/named"
else
    ZONEDIR="/var/named"
fi

# 3. Temporalmente usar DNS de Google para no perder conexión
echo "nameserver 8.8.8.8" > /etc/resolv.conf

mostrar_menu() {
    clear
    echo -e "${CYAN}===============================================${RESET}"
    echo -e "${CYAN}       GESTOR DNS MAGEIA - FINAL 2026          ${RESET}"
    echo -e "${CYAN}===============================================${RESET}"
    echo "1. Crear Dominio (Habilitar Ping Local)"
    echo "2. Ver Dominios e IPs Registradas"
    echo "3. Eliminar Dominio (Limpieza Total)"
    echo "4. Probar con HOST / NSLOOKUP"
    echo "5. Salir"
    echo -e "${CYAN}===============================================${RESET}"
}

while true; do
    mostrar_menu
    read -p "Seleccione una opcion: " opc

    case $opc in
        1)
            read -p "Nombre del dominio (ej. reprobados.com): " dominio
            read -p "IP a la que apunta (ej. 192.168.10.1): " ip
            
            if [ -z "$dominio" ] || [ -z "$ip" ]; then
                echo -e "${ROJO}[!] No puedes dejar campos vacios.${RESET}"
                sleep 2; continue
            fi

            echo -e "${AMARILLO}Creando archivo de zona en $ZONEDIR...${RESET}"
            
            # Crear archivo de zona con EOF
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
            
            # Agregar al named.conf con RUTA ABSOLUTA (Esto es lo que fallaba)
            if ! grep -q "zone \"$dominio\"" /etc/named.conf; then
                echo "zone \"$dominio\" IN { type master; file \"$ZONEDIR/$dominio.zone\"; };" >> /etc/named.conf
            fi

            # Permisos críticos para que Mageia lo lea
            chown named:named "$ZONEDIR/$dominio.zone"
            chmod 664 "$ZONEDIR/$dominio.zone"

            # Reiniciar Servicio
            systemctl restart named
            
            if [ $? -eq 0 ]; then
                # Configurar DNS local para que el PING responda
                echo "nameserver 127.0.0.1" > /etc/resolv.conf
                echo -e "${VERDE}[OK] Dominio '$dominio' listo. Prueba 'ping $dominio'${RESET}"
            else
                echo -e "${ROJO}[!] Error: Revisa el archivo /etc/named.conf manual.${RESET}"
                echo "nameserver 8.8.8.8" > /etc/resolv.conf # Regresar internet si falla
            fi
            read -p "Presione Enter..."
            ;;

        2)
            echo -e "\n${AMARILLO}--- REGISTROS EN EL SERVIDOR ---${RESET}"
            grep "zone" /etc/named.conf | grep -v "localhost" | cut -d'"' -f2 | while read -r dom; do
                if [ -f "$ZONEDIR/$dom.zone" ]; then
                    ip_reg=$(grep -P "\tA\t| IN A " "$ZONEDIR/$dom.zone" | grep "@" | awk '{print $NF}')
                    echo -e "Dominio: $dom  --> IP: $ip_reg"
                fi
            done
            read -p "Presione Enter..."
            ;;

        3)
            read -p "Dominio a eliminar: " dominio
            if grep -q "zone \"$dominio\"" /etc/named.conf; then
                sed -i "/zone \"$dominio\"/d" /etc/named.conf
                rm -f "$ZONEDIR/$dominio.zone"
                systemctl restart named
                echo -e "${VERDE}[OK] Eliminado.${RESET}"
            else
                echo -e "${ROJO}[!] No existe.${RESET}"
            fi
            read -p "Presione Enter..."
            ;;

        4)
            read -p "Dominio a consultar: " test
            host "$test"
            read -p "Presione Enter..."
            ;;

        5)
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
            echo "Saliendo..."
            break
            ;;

        *)
            echo -e "${ROJO}Opcion invalida.${RESET}"
            sleep 1
            ;;
    esac
done