#!/bin/bash

# Función para pausar
pause(){
  read -p "Presione [Enter] para continuar..." fackEnterKey
}

while true; do
    clear
    echo "================================================"
    echo "       MENU PRINCIPAL DE PRACTICAS (LINUX)      "
    echo "================================================"
    echo " 1. SSH (Verificar/Instalar OpenSSH)"
    echo " 2. DHCP (Llamar a tu script dhcp.sh)"
    echo " 3. DNS (Llamar a tu script dns.sh)"
    echo " 4. Salir"
    echo "================================================"
    read -p "Selecciona una opción [1-4]: " opcion

    case $opcion in
        1)
            # --- MODULO SSH ---
            echo "Revisando estado de SSH..."
            if rpm -qa | grep -q openssh-server; then
                echo "Estado: Instalado"
                systemctl status sshd | grep "Active:"
            else
                echo "Estado: No instalado. Instalando..."
                sudo urpmi openssh-server
                sudo systemctl enable --now sshd
            fi
            pause
            ;;

        2)
            # --- LLAMAR A TU DHCP ---
            if [ -f "./dhcp.sh" ]; then
                bash ./dhcp.sh
            else
                echo "Error: No se encuentra el archivo dhcp.sh"
                pause
            fi
            ;;

        3)
            # --- LLAMAR A TU DNS ---
            if [ -f "./dns.sh" ]; then
                bash ./dns.sh
            else
                echo "Error: No se encuentra el archivo dns.sh"
                pause
            fi
            ;;

        4)
            echo "Saliendo..."
            exit 0
            ;;

        *)
            echo "Opción no válida."
            sleep 1
            ;;
    esac
done