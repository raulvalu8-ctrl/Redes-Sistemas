#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

validar_ip() {
    local ip=$1
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo -e "${RED}IP invalido${NC}"
        return 1
    fi

    if echo "$ip" | grep -qE "^0\.|^127\.|^169\.254\.|^22[4-9]\.|^23[0-9]\.|^255\.255\.255\.255\."; then
        echo -e "${RED}La IP pertenece a un rango reservado${NC}"
        return 1
    fi
    return 0
}

verificar_instalacion() {
    echo "Verificando"
    if rpm -q dhcp-server >/dev/null 2>&1; then
        echo -e "${GREEN}Ya esta instalado${NC}"
    else
        echo -e "${RED}No esta instalado${NC}"
    fi
}

instalar_silencioso() {
    echo "Instalacion silenciosa"
    urpmi --auto dhcp-server
    echo -e "${GREEN}Instalacion completada${NC}"
}

configurar_ambito() {
    read -p "Ingrese la Ip inicial para el rango del cliente: " IP_INI
    validar_ip "$IP_INI" || return 1

    read -p "Ingresar la IP donde termina el rango: " IP_FIN
    validar_ip "$IP_FIN" || return 1

    SRV_IP=$IP_INI
    PREFIX=$(echo $IP_INI | cut -d. -f1-3)
    ULTIMO=$(echo $IP_INI | cut -d. -f4)
    IP_CLIENTE_START="$PREFIX.$((ULTIMO + 1))"

    read -p "Ingresa la mascara de subred: " MASK
    validar_ip "$MASK" || return 1

    read -p "Tiempo (segundos): " TIEMPO_MANUAL

    read -p "Introducir puerta de enlace (enter si no): " GW
    Extra=""
    [[ -n $GW ]] && EXTRA=" option routers $GW;"

    read -p "Introducir DNS principal (enter si no): " DNS1
    read -p "Introducir DNS secundario (enter si no): " DNS2
    DNS_LINE=""
    if [[ -n "$DNS1" && -n "$DNS2" ]]; then
        DNS_LINE="option domain-name-servers $DNS1, $DNS2;"
    elif [[ -n "$DNS1" ]]; then
        DNS_LINE="option domain-name-servers $DNS1;"
    fi

    echo -e "${GREEN}Se tomo la IP $SRV_IP como IP estatica para el servidor${NC}"
    echo -e "El rango para el cliente sera: $IP_CLIENTE_START hasta $IP_FIN"

    ip addr flush dev ens34
    ip addr add $SRV_IP/24 dev ens34
    ip link set ens34 up

    cat <<EOF > /etc/dhcpd.conf
subnet $PREFIX.0 netmask $MASK {
    range $IP_CLIENTE_START $IP_FIN;
    $EXTRA
    $DNS_LINE
    default-lease-time $TIEMPO_MANUAL;
    max-lease-time $TIEMPO_MANUAL;
}
EOF

    mkdir -p /var/lib/dhcp && touch /var/lib/dhcp/dhcpd.leases
    echo -e "${GREEN}Configuracion guardada y sincronizada${NC}"
}

monitoreo() {
    echo -e "${GREEN}--Estado--${NC}"
    if pgrep dhcpd > /dev/null; then
        echo -e "Servicio: ${GREEN}Activo${NC}"
    else
        echo -e "Servicio: ${RED}insactivo${NC}"
    fi

    echo -e "Configuracion actual"
    cat /etc/dhcpd.conf
}

# --- Bucle y Menu con los comandos de tus capturas ---
while true; do
    echo -e "\n--- ADMINISTRACION DHCP ---"
    echo "1. Verificar instalacion"
    echo "2. Instalar DHCP"
    echo "2.1 Configuracion y Activacion"
    echo "3. Monitoreo de Clientes"
    echo "3.1 Reiniciar servicio"
    echo "4. Desinstalar DHCP"
    echo "5. Salir"
    read -p "Opcion: " OPC

    case $OPC in
        1) clear; verificar_instalacion; read -p "Presione enter..." ;;
        2) clear; instalar_silencioso; read -p "Presione enter..." ;;
        2.1) clear; configurar_ambito; read -p "Presione enter..." ;;
        3) clear; monitoreo; read -p "Presione enter..." ;;
        3.1) systemctl restart dhcpd && echo -e "${GREEN}Servicio reseteado${NC}" ;;
        4) urpme dhcp-server && echo -e "${RED}Desinstalado${NC}" ;;
        5) exit 0 ;;
        *) echo "Opcion no valida" ;;
    esac
done