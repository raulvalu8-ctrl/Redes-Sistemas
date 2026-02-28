#!/bin/bash
# REQUISITO: sudo

# 1. Detectar rutas de Mageia
ZONEDIR="/var/lib/named"
[ -d "/var/lib/named/var/named" ] && ZONEDIR="/var/lib/named/var/named"
CONF_D="/etc/named.d"
mkdir -p $CONF_D

# 2. Asegurar DNS para tener internet (GitHub)
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# 3. Vincular el archivo de zonas pro al principal (solo una vez)
if ! grep -q "pro-zones.conf" /etc/named.conf; then
    touch $CONF_D/pro-zones.conf
    echo "include \"$CONF_D/pro-zones.conf\";" >> /etc/named.conf
fi

mostrar_menu() {
    clear
    echo "==============================================="
    echo "       GESTOR DNS MAGEIA - SOLUCION FINAL      "
    echo "==============================================="
    echo "1. Crear Dominio (Ping OK)"
    echo "2. Limpiar Errores y Reiniciar Servicio"
    echo "3. Salir"
}

while true; do
    mostrar_menu
    read -p "Opcion: " opc
    case $opc in
        1)
            read -p "Dominio: " dom
            read -p "IP: " ip
            [ -z "$dom" ] && continue

            # Crear archivo de zona con RUTA ABSOLUTA
            cat <<EOF > "$ZONEDIR/$dom.zone"
\$TTL 86400
@ IN SOA ns1.$dom. admin.$dom. ( 2026022701 3600 1800 604800 86400 )
  IN NS ns1.$dom.
ns1 IN A $ip
@ IN A $ip
www IN A $ip
EOF
            # Agregar al archivo secundario para no ensuciar el principal
            if ! grep -q "$dom" $CONF_D/pro-zones.conf; then
                echo "zone \"$dom\" IN { type master; file \"$ZONEDIR/$dom.zone\"; };" >> $CONF_D/pro-zones.conf
            fi

            chown named:named "$ZONEDIR/$dom.zone"
            systemctl restart named
            
            if [ $? -eq 0 ]; then
                echo "nameserver 127.0.0.1" > /etc/resolv.conf
                echo -e "\e[32m[OK] Dominio listo. Prueba ping $dom\e[0m"
            else
                echo -e "\e[31m[!] Falló. Revisa que no haya basura en /etc/named.conf\e[0m"
                echo "nameserver 8.8.8.8" > /etc/resolv.conf
            fi
            read -p "Enter..."
            ;;
        2)
            > $CONF_D/pro-zones.conf # Vacía las zonas personalizadas
            systemctl restart named
            echo "Servicio limpio."
            read -p "Enter..."
            ;;
        3) exit 0 ;;
    esac
done