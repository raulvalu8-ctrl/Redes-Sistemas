#!/bin/bash

# ==============================================================================
# Practica-06: http_functions.sh
# Libreria de funciones para aprovisionamiento web automatizado en Linux
# ==============================================================================

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

fn_info()    { echo -e "${CYAN}  [INFO]  $1${NC}"; }
fn_ok()      { echo -e "${GREEN}  [OK]    $1${NC}"; }
fn_warn()    { echo -e "${YELLOW}  [WARN]  $1${NC}"; }
fn_err()     { echo -e "${RED}  [ERROR] $1${NC}"; }
fn_section() {
    echo ""
    echo -e "${BLUE}  ==================================================${NC}"
    echo -e "${BLUE}    $1${NC}"
    echo -e "${BLUE}  ==================================================${NC}"
    echo ""
}

# Funcion para validar entrada (evitar caracteres especiales y nulos)
validate_input() {
    local input="$1"
    if [[ -z "$input" || "$input" =~ [^a-zA-Z0-9._-] ]]; then
        return 1
    fi
    return 0
}

# Funcion para verificar si un puerto esta ocupado
check_port() {
    local port=$1
    # FIX: usar ss en lugar de lsof (no siempre disponible en Mageia)
    if ss -tlnp | grep -q ":${port}\b"; then
        return 1 # Puerto ocupado
    else
        return 0 # Puerto libre
    fi
}

# Funcion para validar que el puerto este en el rango valido
is_reserved_port() {
    local port=$1
    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        return 0 # Fuera de rango (invalido)
    fi
    return 1 # En rango (valido)
}

# Listar versiones dinamicamente (Adaptado para Mageia/DNF o URPMI)
get_versions() {
    local service=$1
    fn_info "Consultando versiones en repositorios de Mageia para $service..."

    # FIX: en Mageia el paquete apache se llama "apache" no "apache2"
    local pkg="$service"
    [[ "$service" == "apache2" ]] && pkg="apache"

    if command -v dnf &>/dev/null; then
        # FIX: usar --showduplicates correctamente para Mageia
        local versions
        versions=$(dnf --showduplicates list "$pkg" 2>/dev/null | \
            awk 'NR>1 && /^[a-zA-Z]/ {print $2}' | grep -E '^[0-9]' | head -n 10)
        if [[ -z "$versions" ]]; then
            # Fallback: mostrar la version disponible sin duplicados
            versions=$(dnf info "$pkg" 2>/dev/null | grep "^Version" | awk '{print $3}' | head -n 5)
        fi
        if [[ -z "$versions" ]]; then
            fn_warn "No se encontraron versiones. Se instalara la version disponible en repositorio."
            echo "latest (version del repositorio)"
        else
            echo "$versions"
        fi
    elif command -v urpmq &>/dev/null; then
        urpmq --list-media 2>/dev/null | head -n 5
        urpmq -m "$pkg" 2>/dev/null | head -n 5
    else
        fn_warn "No se detecto dnf ni urpmi. Escriba 'latest'."
        echo "latest"
    fi
}

# Configuracion de Seguridad General (Mageia/RedHat Paths)
apply_security_config() {
    local service=$1
    local web_root=$2

    fn_section "Hardening de seguridad: $service"

    case $service in
        apache2|httpd)
            # FIX: detectar ruta correcta del httpd.conf en Mageia
            local CONF=""
            for f in /etc/httpd/conf/httpd.conf /etc/apache2/httpd.conf /etc/httpd/httpd.conf; do
                [[ -f "$f" ]] && CONF="$f" && break
            done

            if [[ -z "$CONF" ]]; then
                fn_warn "No se encontro httpd.conf. Seguridad omitida."
                return
            fi

            sed -i "s/^ServerTokens .*/ServerTokens Prod/" "$CONF" 2>/dev/null
            grep -q "^ServerTokens Prod" "$CONF" || echo "ServerTokens Prod" >> "$CONF"
            sed -i "s/^ServerSignature .*/ServerSignature Off/" "$CONF" 2>/dev/null
            grep -q "^ServerSignature Off" "$CONF" || echo "ServerSignature Off" >> "$CONF"
            grep -q "^TraceEnable Off" "$CONF" || echo "TraceEnable Off" >> "$CONF"

            # Agregar headers de seguridad
            if ! grep -q "X-Frame-Options" "$CONF"; then
                cat >> "$CONF" << 'SECEOF'

# Seguridad Practica 6
<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
</IfModule>
SECEOF
            fi

            fn_info "Validando configuracion de Apache..."
            if apachectl configtest &>/dev/null || httpd -t &>/dev/null; then
                systemctl restart httpd 2>/dev/null || systemctl restart apache2 2>/dev/null
                fn_ok "Apache reiniciado correctamente."
            else
                fn_err "Error de sintaxis en httpd.conf:"
                apachectl configtest 2>&1 || httpd -t 2>&1
            fi
            ;;
        nginx)
            # FIX: verificar ruta correcta de nginx.conf en Mageia
            local NGINX_CONF="/etc/nginx/nginx.conf"
            [[ ! -f "$NGINX_CONF" ]] && NGINX_CONF="/etc/nginx/conf/nginx.conf"

            if [[ ! -f "$NGINX_CONF" ]]; then
                fn_warn "No se encontro nginx.conf. Seguridad omitida."
                return
            fi

            sed -i "s/server_tokens on;/server_tokens off;/" "$NGINX_CONF"
            grep -q "server_tokens off;" "$NGINX_CONF" || \
                sed -i '/http {/a \    server_tokens off;' "$NGINX_CONF"

            # Agregar headers de seguridad si no existen
            if ! grep -q "X-Frame-Options" "$NGINX_CONF"; then
                sed -i '/server {/a \        add_header X-Frame-Options "SAMEORIGIN" always;\n        add_header X-Content-Type-Options "nosniff" always;\n        add_header X-XSS-Protection "1; mode=block" always;' "$NGINX_CONF"
            fi

            if nginx -t &>/dev/null; then
                systemctl restart nginx
                fn_ok "Nginx reiniciado correctamente."
            else
                fn_err "Error de sintaxis en nginx.conf:"
                nginx -t
            fi
            ;;
    esac
}

# Crear pagina index.html personalizada
create_custom_index() {
    local service=$1
    local version=$2
    local port=$3
    local path=$4

    mkdir -p "$path"

    cat > "$path/index.html" << HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>$service - Practica 6</title>
    <style>
        body { font-family: sans-serif; background: #1a1a2e; color: #eee;
               display: flex; justify-content: center; align-items: center;
               height: 100vh; margin: 0; }
        .card { background: #16213e; border-radius: 12px; padding: 40px 60px;
                box-shadow: 0 8px 32px rgba(0,0,0,.5); text-align: center; }
        h1 { color: #4fc3f7; font-size: 2.2em; margin-bottom: .3em; }
        .badge { display: inline-block; background: #e94560; color: #fff;
                 border-radius: 6px; padding: 4px 14px; font-size: .9em; margin: 6px 4px; }
        .info { color: #a8b2d8; margin-top: 1em; font-size: .95em; }
    </style>
</head>
<body>
    <div class="card">
        <h1>$service</h1>
        <div>
            <span class="badge">Servidor: $service</span>
            <span class="badge">Version: $version</span>
            <span class="badge">Puerto: $port</span>
        </div>
        <p class="info">Aprovisionado automaticamente - Practica 6 - Mageia 9</p>
    </div>
</body>
</html>
HTMLEOF

    # FIX: intentar chown con el usuario correcto segun el servicio
    if id apache &>/dev/null; then
        chown -R apache:apache "$path" 2>/dev/null
    elif id www-data &>/dev/null; then
        chown -R www-data:www-data "$path" 2>/dev/null
    elif id nginx &>/dev/null; then
        chown -R nginx:nginx "$path" 2>/dev/null
    fi
    chmod -R 755 "$path"
    fn_ok "index.html creado en $path"
}

# Instalacion de Apache (Mageia: paquete se llama "apache")
install_apache() {
    local version=$1
    local port=$2

    fn_section "Instalando Apache en Mageia"

    # FIX: en Mageia el paquete es "apache" no "apache2"
    fn_info "Instalando apache via dnf/urpmi..."
    if command -v dnf &>/dev/null; then
        dnf install -y apache apache-mod_headers 2>/dev/null
    else
        urpmi --auto apache 2>/dev/null
    fi

    # FIX: verificar que se instalo
    if ! command -v httpd &>/dev/null && ! command -v apachectl &>/dev/null; then
        fn_err "No se pudo instalar Apache. Verifica los repositorios."
        return 1
    fi

    fn_info "Forzando cambio de puerto en todos los archivos de Apache..."
    # Deshabilitar ssl.conf para evitar conflicto de puertos duplicados
    for sslf in /etc/httpd/conf/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf; do
        [[ -f "$sslf" ]] && mv "$sslf" "${sslf}.bak" && fn_info "ssl.conf deshabilitado."
    done

    # FIX: buscar y modificar el archivo correcto de puertos
    for conf in /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/*.conf /etc/apache2/httpd.conf; do
        [[ -f "$conf" ]] && sed -i "s/^Listen\s\+[0-9]\+/Listen $port/g" "$conf"
    done

    local apache_root="/var/www/html/apache"
    mkdir -p "$apache_root"

    # FIX: detectar y modificar el httpd.conf correcto
    local MAIN_CONF=""
    for f in /etc/httpd/conf/httpd.conf /etc/apache2/httpd.conf; do
        [[ -f "$f" ]] && MAIN_CONF="$f" && break
    done

    if [[ -n "$MAIN_CONF" ]]; then
        sed -i "s|DocumentRoot \"/var/www/html\"|DocumentRoot \"$apache_root\"|g" "$MAIN_CONF"
        sed -i "s|DocumentRoot '/var/www/html'|DocumentRoot '$apache_root'|g" "$MAIN_CONF"
        sed -i "s|<Directory \"/var/www/html\">|<Directory \"$apache_root\">|g" "$MAIN_CONF"
        sed -i "s|<Directory '/var/www/html'>|<Directory '$apache_root'>|g" "$MAIN_CONF"
    fi

    apply_security_config "httpd" "$apache_root"
    create_custom_index "Apache" "$version" "$port" "$apache_root"

    # FIX: usar solo iptables (firewalld no disponible en Mageia)
    iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
    fn_ok "Puerto $port abierto en iptables."

    systemctl enable httpd 2>/dev/null || systemctl enable apache2 2>/dev/null
    systemctl restart httpd 2>/dev/null || systemctl restart apache2 2>/dev/null

    sleep 2
    if systemctl is-active httpd &>/dev/null || systemctl is-active apache2 &>/dev/null; then
        fn_ok "Apache configurado en el puerto $port."
    else
        fn_err "Apache no pudo iniciarse. Revisa: journalctl -xe"
        journalctl -u httpd -n 10 --no-pager 2>/dev/null
    fi

    echo -e "  ${GREEN}URL     : http://localhost:$port${NC}"
    echo -e "  ${GREEN}Webroot : $apache_root${NC}"
}

# Instalacion de Nginx (Mageia)
install_nginx() {
    local version=$1
    local port=$2

    fn_section "Instalando Nginx en Mageia"

    fn_info "Instalando nginx via dnf/urpmi..."
    if command -v dnf &>/dev/null; then
        dnf install -y nginx 2>/dev/null
    else
        urpmi --auto nginx 2>/dev/null
    fi

    if ! command -v nginx &>/dev/null; then
        fn_err "No se pudo instalar Nginx."
        return 1
    fi

    fn_info "Forzando cambio de puerto en todos los archivos de Nginx..."
    # FIX: buscar nginx.conf en rutas de Mageia
    local NGINX_CONF="/etc/nginx/nginx.conf"
    [[ ! -f "$NGINX_CONF" ]] && NGINX_CONF="/etc/nginx/conf/nginx.conf"

    find /etc/nginx -name "*.conf" -exec sed -i "s/listen\s\+[0-9]\+;/listen $port;/g" {} + 2>/dev/null
    find /etc/nginx -name "*.conf" -exec sed -i "s/listen\s\+\[::\]:[0-9]\+;/listen [::]:$port;/g" {} + 2>/dev/null

    local nginx_root="/var/www/html/nginx"
    mkdir -p "$nginx_root"

    # FIX: cambiar el root en nginx.conf
    if [[ -f "$NGINX_CONF" ]]; then
        sed -i "s|root\s\+/usr/share/nginx/html;|root $nginx_root;|g" "$NGINX_CONF"
        sed -i "s|root\s\+/var/www/html;|root $nginx_root;|g" "$NGINX_CONF"
        sed -i "s|root\s\+/usr/share/nginx/html/;|root $nginx_root;|g" "$NGINX_CONF"
    fi

    apply_security_config "nginx" "$nginx_root"
    create_custom_index "Nginx" "$version" "$port" "$nginx_root"

    # FIX: usar solo iptables
    iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
    fn_ok "Puerto $port abierto en iptables."

    systemctl enable nginx
    systemctl restart nginx

    sleep 2
    if systemctl is-active nginx &>/dev/null; then
        fn_ok "Nginx configurado en el puerto $port."
    else
        fn_err "Nginx no pudo iniciarse. Revisa: journalctl -xe"
        journalctl -u nginx -n 10 --no-pager 2>/dev/null
    fi

    echo -e "  ${GREEN}URL     : http://localhost:$port${NC}"
    echo -e "  ${GREEN}Webroot : $nginx_root${NC}"
}

# Instalacion y configuracion de Tomcat (repositorio Mageia)
install_tomcat() {
    local port=$1

    fn_section "Instalando Tomcat en Mageia"

    if ! command -v java &>/dev/null; then
        fn_info "Instalando Java (OpenJDK)..."
        if command -v dnf &>/dev/null; then
            dnf install -y java-11-openjdk-devel 2>/dev/null || \
            dnf install -y java-1.8.0-openjdk-devel 2>/dev/null
        else
            urpmi --auto java-11-openjdk-devel 2>/dev/null || \
            urpmi --auto java-1.8.0-openjdk-devel 2>/dev/null
        fi
    fi

    fn_info "Instalando Tomcat desde repositorio..."
    if command -v dnf &>/dev/null; then
        dnf install -y tomcat 2>/dev/null
    else
        urpmi --auto tomcat 2>/dev/null
    fi

    # Obtener version instalada
    local version
    version=$(rpm -q tomcat 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [[ -z "$version" ]] && version="desconocida"
    fn_ok "Tomcat $version instalado."

    # FIX: configurar puerto en server.xml
    for serverxml in "/etc/tomcat/server.xml" "/usr/share/tomcat/conf/server.xml"; do
        if [[ -f "$serverxml" ]]; then
            sed -i "s|Connector port=\"[0-9]*\" address=\"[^\"]*\" protocol=\"HTTP/1.1\"|Connector port=\"$port\" address=\"0.0.0.0\" protocol=\"HTTP/1.1\"|g" "$serverxml"
            sed -i "s|Connector port=\"[0-9]*\" protocol=\"HTTP/1.1\"|Connector port=\"$port\" address=\"0.0.0.0\" protocol=\"HTTP/1.1\"|g" "$serverxml"
            fn_ok "Puerto $port configurado en $serverxml."
        fi
    done

    # FIX: configurar usuario del servicio
    local svc_file=""
    for f in /usr/lib/systemd/system/tomcat.service /lib/systemd/system/tomcat.service; do
        [[ -f "$f" ]] && svc_file="$f" && break
    done

    if [[ -n "$svc_file" ]]; then
        sed -i 's/^User=tomcat/User=root/' "$svc_file"
        fn_ok "Servicio tomcat configurado para correr como root."
    fi
    systemctl daemon-reload

    # FIX: detectar webroot correcto de Tomcat en Mageia
    local webroot=""
    for wr in "/var/lib/tomcat/webapps/ROOT" "/usr/share/tomcat/webapps/ROOT"; do
        if [[ -d "$(dirname $wr)" ]]; then
            webroot="$wr"
            mkdir -p "$webroot"
            break
        fi
    done
    [[ -z "$webroot" ]] && webroot="/var/lib/tomcat/webapps/ROOT" && mkdir -p "$webroot"

    create_custom_index "Tomcat" "$version" "$port" "$webroot"

    iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null

    systemctl enable tomcat 2>/dev/null
    systemctl restart tomcat
    sleep 3

    if systemctl is-active tomcat &>/dev/null; then
        fn_ok "Tomcat $version configurado en el puerto $port."
    else
        fn_err "Tomcat no pudo iniciarse. Revisa: journalctl -u tomcat -n 20"
        journalctl -u tomcat -n 10 --no-pager 2>/dev/null
    fi

    echo -e "  ${GREEN}URL     : http://localhost:$port${NC}"
    echo -e "  ${GREEN}Webroot : $webroot${NC}"
}

# Funcion para bajar servicios
stop_linux_service() {
    local service=$1
    fn_info "Deteniendo servicio $service..."
    case $service in
        apache2|httpd)
            systemctl stop httpd 2>/dev/null || systemctl stop apache2 2>/dev/null ;;
        nginx)
            systemctl stop nginx 2>/dev/null ;;
        tomcat)
            systemctl stop tomcat 2>/dev/null ;;
    esac
    fn_ok "Servicio $service detenido."
}

# Funcion para verificar estado y puertos de los servicios
check_services_status() {
    fn_section "Estado de los servicios web"
    printf "  ${CYAN}%-15s | %-12s | %-10s${NC}\n" "SERVICIO" "ESTADO" "PUERTO(S)"
    echo "  ------------------------------------------"

    local services=("httpd" "nginx" "tomcat")

    for srv in "${services[@]}"; do
        local status
        status=$(systemctl is-active "$srv" 2>/dev/null)
        if [[ "$status" == "active" ]]; then
            local search_pattern="$srv"
            [[ "$srv" == "tomcat" ]] && search_pattern="java"
            local ports
            ports=$(ss -tulpn 2>/dev/null | grep -i "$search_pattern" | \
                awk '{print $5}' | rev | cut -d':' -f1 | rev | sort -u | tr '\n' ',' | sed 's/,$//')
            [[ -z "$ports" ]] && ports="Iniciando..."
            printf "  %-15s | " "$srv"
            echo -ne "${GREEN}Corriendo   ${NC}"
            printf "| %-10s\n" "$ports"
        else
            printf "  %-15s | " "$srv"
            echo -ne "${RED}Detenido    ${NC}"
            printf "| %-10s\n" "-"
        fi
    done
    echo "  ------------------------------------------"
}

# Funcion para eliminacion total de servicios (Purge)
purge_services() {
    local service=$1
    fn_warn "Eliminando por completo $service (registros, configs y binarios)..."

    case $service in
        apache2|httpd)
            systemctl stop httpd 2>/dev/null || systemctl stop apache2 2>/dev/null
            if command -v dnf &>/dev/null; then
                dnf remove -y apache 2>/dev/null
            else
                urpme apache 2>/dev/null
            fi
            rm -rf /etc/httpd /var/www/html/apache /var/log/httpd
            ;;
        nginx)
            systemctl stop nginx 2>/dev/null
            if command -v dnf &>/dev/null; then
                dnf remove -y nginx 2>/dev/null
            else
                urpme nginx 2>/dev/null
            fi
            rm -rf /etc/nginx /var/www/html/nginx /var/log/nginx /usr/share/nginx
            ;;
        tomcat)
            systemctl stop tomcat 2>/dev/null
            if command -v dnf &>/dev/null; then
                dnf remove -y tomcat 2>/dev/null
            else
                urpme tomcat 2>/dev/null
            fi
            rm -rf /var/lib/tomcat /etc/tomcat /var/log/tomcat
            ;;
    esac
    fn_ok "Limpieza de $service completada."
}