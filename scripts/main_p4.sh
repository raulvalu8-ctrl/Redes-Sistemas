#!/bin/bash

# --- Función para verificar si el archivo existe y ejecutarlo ---
lanzar_script() {
    local archivo=$1
    if [ -f "$archivo" ]; then
        echo -e "\n[!] Ejecutando $archivo...\n"
        chmod +x "$archivo"
        ./"$archivo"
    else
        echo -e "\n[ERROR] No se encontró el archivo '$archivo' en esta carpeta."
        echo "Asegúrate de que el nombre sea exacto."
    fi
    echo -e "\n------------------------------------------------"
    read -p "Presiona ENTER para volver al menú principal..."
}

while true; do
    clear
    echo "================================================"
    echo "      ADMINISTRADOR DE PRÁCTICAS LINUX          "
    echo "================================================"
    echo " 1. SSH (Instalación y Verificación)"
    echo " 2. DHCP (Gestión de Red y Rangos)"
    echo " 3. DNS (Gestión de Dominios BIND)"
    echo " 4. Salir"
    echo "================================================"
    read -p "Selecciona una práctica [1-4]: " OPCION

    case $OPCION in
        1)
            # Llama a tu script de SSH
            lanzar_script "ssh.sh"
            ;;
        2)
            # Llama a tu script de DHCP (el que ya tienes validado)
            lanzar_script "dhcp.sh"
            ;;
        3)
            # Llama a tu script de DNS
            lanzar_script "dns.sh"
            ;;
        4)
            echo "Saliendo del administrador..."
            exit 0
            ;;
        *)
            echo "Opción no válida."
            sleep 1
            ;;
    esac
done