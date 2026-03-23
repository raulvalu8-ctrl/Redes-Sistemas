#!/bin/bash
# =============================================================================
# p7_main.sh - Script Principal Practica 7
# Sistema Operativo: Mageia Linux
# Uso: sudo bash p7_main.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCTIONS_FILE="${SCRIPT_DIR}/p7_functions.sh"

if [ ! -f "$FUNCTIONS_FILE" ]; then
    echo "[ERROR] No se encontro p7_functions.sh en: $FUNCTIONS_FILE"
    exit 1
fi

source "$FUNCTIONS_FILE"

fn_menu_principal_p7() {
    while true; do
        fn_header_p7
        echo -e "${BOLD}  Selecciona una opcion:${NC}\n"
        echo -e "  ${CYAN}[1]${NC} Instalar Apache  (WEB o FTP + SSL opcional)"
        echo -e "  ${CYAN}[2]${NC} Instalar Nginx   (WEB o FTP + SSL opcional)"
        echo -e "  ${CYAN}[3]${NC} Instalar Tomcat  (WEB o FTP + SSL opcional)"
        echo -e "  ${CYAN}[4]${NC} Configurar FTPS  (SSL en vsftpd)"
        echo -e "  ${CYAN}[5]${NC} Ver estado de servicios"
        echo -e "  ${CYAN}[6]${NC} Resumen de instalaciones"
        echo -e "  ${RED}[0]${NC} Salir\n"
        echo -ne "${YELLOW}Opcion: ${NC}"
        read -r OPCION

        case "$OPCION" in
            1)
                fn_verificar_root_p7
                fn_verificar_dependencias
                fn_instalar_servicio_hibrido "apache" "Apache"
                echo -e "\n${YELLOW}Presiona ENTER para continuar...${NC}"
                read -r
                ;;
            2)
                fn_verificar_root_p7
                fn_verificar_dependencias
                fn_instalar_servicio_hibrido "nginx" "Nginx"
                echo -e "\n${YELLOW}Presiona ENTER para continuar...${NC}"
                read -r
                ;;
            3)
                fn_verificar_root_p7
                fn_verificar_dependencias
                fn_instalar_servicio_hibrido "tomcat" "Tomcat"
                echo -e "\n${YELLOW}Presiona ENTER para continuar...${NC}"
                read -r
                ;;
            4)
                fn_verificar_root_p7
                fn_configurar_ftps
                echo -e "\n${YELLOW}Presiona ENTER para continuar...${NC}"
                read -r
                ;;
            5)
                echo ""
                echo -e "${CYAN}====== ESTADO DE SERVICIOS ======${NC}"
                echo -e "${CYAN}Puertos en escucha:${NC}"
                ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null
                echo ""
                echo -e "${CYAN}Servicios activos (systemctl):${NC}"
                for SVC in httpd apache nginx tomcat tomcat9 vsftpd; do
                    if systemctl list-units --type=service 2>/dev/null | grep -q "${SVC}.service"; then
                        STATUS=$(systemctl is-active "$SVC" 2>/dev/null)
                        if [ "$STATUS" = "active" ]; then
                            echo -e "  ${GREEN}[ACTIVO]${NC}   $SVC"
                        else
                            echo -e "  ${RED}[INACTIVO]${NC} $SVC"
                        fi
                    fi
                done
                echo ""
                ps aux 2>/dev/null | grep -E "httpd|nginx|tomcat|java|vsftpd" | grep -v grep \
                    || echo "  (ninguno)"
                echo ""
                read -r
                ;;
            6)
                fn_mostrar_resumen
                echo -e "\n${YELLOW}Presiona ENTER para continuar...${NC}"
                read -r
                ;;
            0)
                echo -e "\n${GREEN}Saliendo. Hasta luego!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${RED}[ERROR] Opcion invalida.${NC}"
                sleep 1
                ;;
        esac
    done
}

fn_verificar_root_p7
fn_menu_principal_p7