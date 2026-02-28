#!/bin/bash
# REQUISITO: Ejecutar con sudo (root)

# 1. Colores
VERDE='\033[0;32m'
CYAN='\033[0;36m'
AMARILLO='\033[1;33m'
ROJO='\033[0;31m'
RESET='\033[0m'

# 2. Detectar la ruta de zonas de Mageia
if [ -d "/var/lib/named/var/named" ]; then
    ZONEDIR="/var/lib/named/var/named"
elif [ -d "/var/lib/named" ]; then
    ZONEDIR="/var/lib/named"
else
    ZONEDIR="/var/named"
fi

# 3. Función de Limpieza (Borra intentos fallidos previos en named.conf)
limpiar_config() {
    echo -e "${AMARILLO}[!] Limpiando configuraciones previas para evitar errores...${RESET}"
    # Crea un respaldo por si acaso
    cp /etc/named.conf /etc/named.conf.bak
    # Borra todas las líneas que agregamos nosotros (las que contienen '.zone')
    sed -i '/.zone/d' /etc/named.conf
    # Reinicia DNS para verificar que el motor está limpio
    systemctl restart named
}

mostrar_menu() {
    clear
    echo -e "${CYAN}===============================================${RESET}"
    echo -e "${CYAN}       GESTOR DNS MAGEIA - 100% FUNCIONAL      ${RESET}"
    echo -e "${CYAN}===============================================${RESET}"
    echo "1. Crear Dominio (Habilita Ping Local)"
    echo "2. Ver Dominios e IPs"
    echo "3. Limpiar Todo y Reiniciar (Fix Errores)"
    echo "4. Probar con HOST"
    echo "5. Salir"
    echo -e "${CYAN}===============================================${RESET}"
}

# Ejecutar limpieza al iniciar para asegurar que el servicio corra
limpiar_config

while true; do
    mostrar_menu
    read -p "Seleccione una opcion: " opc

    case $opc in
        1)
            read -p "Dominio (ej. reprobados.com): " dominio
            read -p "IP de destino: " ip
            
            if [ -z "$dominio" ] || [ -z "$ip" ]; then
                echo -e "${ROJO}Error: Faltan datos.${RESET}"; sleep 1; continue
            fi

            # Crear archivo de zona con la ruta absoluta detectada
            cat <<EOF > "$ZONEDIR/$dominio.zone"
\$TTL 86400
@   IN  SOA     ns1.$dominio. admin.$dominio. (
                2026022701 ; Serial
                3600 1800 604800 86400 )
    IN  NS      ns1.$dominio.
ns1 IN  A       $ip
@   IN  A       $ip
www IN  A       $ip
EOF
            
            # Agregar al named.conf con RUTA COMPLETA para que Bind no se pierda
            if ! grep -q "$dominio" /etc/named.conf; then
                echo "zone \"$dominio\" IN { type master; file \"$ZONEDIR/$dominio.zone\"; };" >> /etc/named.conf
            fi

            # Permisos de sistema para Mageia
            chown named:named "$ZONEDIR/$dominio.zone"
            chmod 664 "$ZONEDIR/$dominio.zone"

            # Reiniciar y forzar DNS local para el PING
            systemctl restart named
            if [ $? -eq 0 ]; then
                echo "nameserver 127.0.0.1" > /etc/resolv.conf
                echo -e "${VERDE}[OK] Dominio '$dominio' listo. Prueba 'ping $dominio'${RESET}"
            else
                echo -e "${ROJO}[!] Error crítico: Revisa /etc/named.conf${RESET}"
            fi
            read -p "Enter para continuar..."
            ;;

        2)
            echo -e "\n${AMARILLO}--- REGISTROS ---${RESET}"
            grep "zone" /etc/named.conf | grep -v "localhost" | cut -d'"' -f2 | while read -r d; do
                echo "Dominio activo: $d"
            done
            read -p "Enter..."
            ;;

        3)
            limpiar_config
            echo -e "${VERDE}[OK] Sistema limpio y servicio reiniciado.${RESET}"
            read -p "Enter..."
            ;;

        4)
            read -p "Dominio a consultar: " test
            host "$test"
            read -p "Enter..."
            ;;

        5) exit 0 ;;
    esac
done