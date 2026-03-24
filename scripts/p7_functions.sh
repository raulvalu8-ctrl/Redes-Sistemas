#!/bin/bash
# =============================================================================
# p7_functions.sh - Libreria de funciones Practica 7
# Sistema Operativo: Windows Server (Visual Mod)
# Integra: Cliente FTP dinamico + SSL/TLS + Verificacion Hash
# Gestor de paquetes: urpmi
# =============================================================================

# -----------------------------------------------------------------------------
# COLORES
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# VARIABLES GLOBALES
# -----------------------------------------------------------------------------
FTP_SERVER="192.168.5.129"
FTP_PORT="21"
FTP_USER="u1"
FTP_PASS="alumno1"
FTP_BASE_PATH="/http/Linux"
DOMINIO="reprobados.com"
SSL_DIR="/etc/ssl/practica7"
RESUMEN_INSTALACIONES=""
INSTALL_DIR="/opt/p7_instaladores"

# -----------------------------------------------------------------------------
# FUNCIONES DE UTILIDAD
# -----------------------------------------------------------------------------
fn_header_p7() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║       SISTEMA DE APROVISIONAMIENTO WEB - WINDOWS         ║"
    echo "║          Practica 7 - FTP + SSL/TLS + Hash               ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

fn_ok()   { echo -e "${GREEN}[OK] $1${NC}"; }
fn_info() { echo -e "${YELLOW}[INFO] $1${NC}"; }
fn_err()  { echo -e "${RED}[ERROR] $1${NC}"; }
fn_sec()  { echo -e "${MAGENTA}[SSL] $1${NC}"; }

fn_verificar_root_p7() {
    if [ "$(id -u)" -ne 0 ]; then
        fn_err "Este script debe ejecutarse como root."
        exit 1
    fi
}

fn_verificar_dependencias() {
    fn_info "Verificando dependencias..."
    urpmi.update -a -q 2>/dev/null

    local DEPS="curl wget openssl"
    for DEP in $DEPS; do
        if ! command -v "$DEP" &>/dev/null; then
            fn_info "Instalando $DEP..."
            urpmi --auto --quiet "$DEP" 2>/dev/null
        fi
    done

    if ! command -v sha256sum &>/dev/null; then
        urpmi --auto --quiet coreutils 2>/dev/null
    fi

    fn_ok "Dependencias verificadas."
}

# -----------------------------------------------------------------------------
# BLOQUE 1: CLIENTE FTP DINAMICO
# -----------------------------------------------------------------------------

fn_ftp_listar() {
    local RUTA="$1"
    curl -s --connect-timeout 10 \
        "ftp://${FTP_SERVER}:${FTP_PORT}${RUTA}" \
        --user "${FTP_USER}:${FTP_PASS}" \
        -l 2>/dev/null
}

fn_ftp_descargar() {
    local RUTA_REMOTA="$1"
    local DESTINO="$2"

    fn_info "Descargando desde FTP: ${RUTA_REMOTA}..."
    curl -s --connect-timeout 30 --progress-bar \
        "ftp://${FTP_SERVER}:${FTP_PORT}${RUTA_REMOTA}" \
        --user "${FTP_USER}:${FTP_PASS}" \
        -o "$DESTINO" 2>/dev/null

    if [ $? -eq 0 ] && [ -s "$DESTINO" ]; then
        fn_ok "Archivo descargado: $DESTINO"
        return 0
    else
        fn_err "No se pudo descargar el archivo."
        return 1
    fi
}

fn_ftp_navegar_y_descargar() {
    local SERVICIO="$1"
    local DESTINO_DIR="$2"

    echo ""
    echo -e "${CYAN}=== REPOSITORIO FTP - ${SERVICIO} ===${NC}"

    fn_info "Conectando al servidor FTP ${FTP_SERVER}..."
    local SERVICIOS
    SERVICIOS=$(fn_ftp_listar "${FTP_BASE_PATH}/")

    if [ -z "$SERVICIOS" ]; then
        fn_err "No se pudo conectar al servidor FTP o el repositorio esta vacio."
        return 1
    fi

    fn_ok "Conexion FTP exitosa."
    echo ""
    echo -e "${CYAN}Servicios disponibles en el repositorio:${NC}"
    local i=1
    local LISTA_SERVICIOS=""
    while IFS= read -r linea; do
        if [ -n "$linea" ]; then
            echo "  [$i] $linea"
            LISTA_SERVICIOS="$LISTA_SERVICIOS $linea"
            i=$((i+1))
        fi
    done <<< "$SERVICIOS"

    local TOTAL=$((i-1))
    local SEL_SVC=0
    while true; do
        echo ""
        echo -e "${YELLOW}Selecciona el servicio a instalar (1-${TOTAL}):${NC}"
        read -r SEL_SVC
        if [[ "$SEL_SVC" =~ ^[0-9]+$ ]] && [ "$SEL_SVC" -ge 1 ] && [ "$SEL_SVC" -le "$TOTAL" ]; then
            break
        fi
        fn_err "Seleccion invalida."
    done

    local SVC_ELEGIDO
    SVC_ELEGIDO=$(echo "$LISTA_SERVICIOS" | awk -v n="$SEL_SVC" '{print $n}')
    fn_ok "Servicio seleccionado: $SVC_ELEGIDO"

    echo ""
    fn_info "Listando versiones disponibles para ${SVC_ELEGIDO}..."
    local ARCHIVOS
    ARCHIVOS=$(fn_ftp_listar "${FTP_BASE_PATH}/${SVC_ELEGIDO}/")

    if [ -z "$ARCHIVOS" ]; then
        fn_err "No hay archivos en el repositorio para ${SVC_ELEGIDO}."
        return 1
    fi

    echo ""
    echo -e "${CYAN}Versiones disponibles:${NC}"
    local j=1
    local LISTA_ARCHIVOS=""
    while IFS= read -r archivo; do
        if [ -n "$archivo" ] && ! echo "$archivo" | grep -q "\.sha256$"; then
            echo "  [$j] $archivo"
            LISTA_ARCHIVOS="$LISTA_ARCHIVOS $archivo"
            j=$((j+1))
        fi
    done <<< "$ARCHIVOS"

    local TOTAL_ARCH=$((j-1))
    if [ "$TOTAL_ARCH" -eq 0 ]; then
        fn_err "No hay instaladores disponibles."
        return 1
    fi

    local SEL_ARCH=0
    while true; do
        echo ""
        echo -e "${YELLOW}Selecciona la version a descargar (1-${TOTAL_ARCH}):${NC}"
        read -r SEL_ARCH
        if [[ "$SEL_ARCH" =~ ^[0-9]+$ ]] && [ "$SEL_ARCH" -ge 1 ] && [ "$SEL_ARCH" -le "$TOTAL_ARCH" ]; then
            break
        fi
        fn_err "Seleccion invalida."
    done

    local ARCH_ELEGIDO
    ARCH_ELEGIDO=$(echo "$LISTA_ARCHIVOS" | awk -v n="$SEL_ARCH" '{print $n}')
    fn_ok "Version seleccionada: $ARCH_ELEGIDO"

    mkdir -p "$DESTINO_DIR"
    local RUTA_REMOTA="${FTP_BASE_PATH}/${SVC_ELEGIDO}/${ARCH_ELEGIDO}"
    local RUTA_SHA256="${RUTA_REMOTA}.sha256"
    local DESTINO_LOCAL="${DESTINO_DIR}/${ARCH_ELEGIDO}"
    local DESTINO_SHA256="${DESTINO_DIR}/${ARCH_ELEGIDO}.sha256"

    fn_ftp_descargar "$RUTA_REMOTA" "$DESTINO_LOCAL" || return 1
    fn_ftp_descargar "$RUTA_SHA256" "$DESTINO_SHA256" || {
        fn_info "No se encontro archivo SHA256, omitiendo verificacion."
    }

    FTP_ARCHIVO_DESCARGADO="$DESTINO_LOCAL"
    FTP_SHA256_DESCARGADO="$DESTINO_SHA256"
    FTP_SERVICIO_ELEGIDO="$SVC_ELEGIDO"
    FTP_ARCHIVO_NOMBRE="$ARCH_ELEGIDO"

    return 0
}

# -----------------------------------------------------------------------------
# BLOQUE 2: VERIFICACION DE INTEGRIDAD SHA256
# -----------------------------------------------------------------------------

fn_verificar_hash() {
    local ARCHIVO="$1"
    local ARCHIVO_SHA256="$2"

    echo ""
    echo -e "${CYAN}=== VERIFICACION DE INTEGRIDAD ===${NC}"

    if [ ! -f "$ARCHIVO" ]; then
        fn_err "Archivo no encontrado: $ARCHIVO"
        return 1
    fi

    if [ ! -f "$ARCHIVO_SHA256" ]; then
        fn_info "No hay archivo SHA256 disponible. Omitiendo verificacion."
        return 0
    fi

    fn_info "Calculando hash SHA256 del archivo descargado..."
    local HASH_LOCAL
    HASH_LOCAL=$(sha256sum "$ARCHIVO" | awk '{print $1}')

    local HASH_REMOTO
    HASH_REMOTO=$(awk '{print $1}' "$ARCHIVO_SHA256")

    echo "  Hash local:  $HASH_LOCAL"
    echo "  Hash remoto: $HASH_REMOTO"

    if [ "$HASH_LOCAL" = "$HASH_REMOTO" ]; then
        fn_ok "Integridad verificada. El archivo no esta corrompido."
        return 0
    else
        fn_err "FALLO DE INTEGRIDAD. Los hashes no coinciden."
        fn_err "El archivo puede estar corrompido. Abortando instalacion."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# BLOQUE 3: GENERACION DE CERTIFICADOS SSL/TLS
# -----------------------------------------------------------------------------

fn_generar_certificado_ssl() {
    local SERVICIO="$1"
    local CERT_DIR="${SSL_DIR}/${SERVICIO}"

    mkdir -p "$CERT_DIR"

    fn_sec "Generando certificado SSL autofirmado para ${DOMINIO}..."

    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "${CERT_DIR}/server.key" \
        -out "${CERT_DIR}/server.crt" \
        -subj "/C=MX/ST=Sinaloa/L=Culiacan/O=Reprobados/OU=Sistemas/CN=${DOMINIO}" \
        2>/dev/null

    if [ $? -eq 0 ]; then
        chmod 600 "${CERT_DIR}/server.key"
        chmod 644 "${CERT_DIR}/server.crt"
        fn_sec "Certificado generado:"
        fn_sec "  Clave:       ${CERT_DIR}/server.key"
        fn_sec "  Certificado: ${CERT_DIR}/server.crt"
        fn_sec "  Dominio:     ${DOMINIO}"
        fn_sec "  Validez:     365 dias"
        return 0
    else
        fn_err "No se pudo generar el certificado SSL."
        return 1
    fi
}

fn_preguntar_ssl() {
    echo ""
    echo -e "${CYAN}¿Desea activar SSL/TLS en este servicio? [s/n]:${NC}"
    read -r RESP_SSL
    if echo "$RESP_SSL" | grep -qi "^s"; then
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# BLOQUE 4: INSTALACION APACHE DESDE FTP
# -----------------------------------------------------------------------------

fn_instalar_apache_ftp() {
    local ARCHIVO="$1"
    local PUERTO="$2"
    local SSL="$3"

    echo ""
    echo -e "${BLUE}====== INSTALACION APACHE DESDE FTP ======${NC}"

    fn_info "Instalando dependencias para compilar Apache en Mageia..."
    # Nombres de paquetes de desarrollo en Mageia (RPM-based)
    urpmi --auto --quiet gcc make libapr-devel libaprutil-devel \
        libpcre-devel libopenssl-devel zlib-devel libxml2-devel \
        libcurl-devel 2>/dev/null

    local EXTRACT_DIR="${INSTALL_DIR}/apache_src"
    mkdir -p "$EXTRACT_DIR"
    fn_info "Extrayendo ${ARCHIVO}..."
    tar -xzf "$ARCHIVO" -C "$EXTRACT_DIR" 2>/dev/null
    local SRC_DIR
    SRC_DIR=$(find "$EXTRACT_DIR" -maxdepth 1 -type d -name "httpd-*" | head -1)

    if [ -z "$SRC_DIR" ]; then
        fn_err "No se pudo extraer el archivo de Apache."
        return 1
    fi

    fn_info "Compilando Apache (esto puede tardar varios minutos)..."
    cd "$SRC_DIR" || return 1

    ./configure --prefix=/usr/local/apache2 \
        --enable-so \
        --enable-ssl \
        --enable-rewrite \
        --enable-headers \
        --enable-deflate \
        --with-mpm=event \
        >/tmp/apache_configure.log 2>&1

    make -j2 >/tmp/apache_make.log 2>&1
    make install >/tmp/apache_install.log 2>&1

    if [ ! -f "/usr/local/apache2/bin/httpd" ]; then
        fn_err "La compilacion de Apache fallo. Revisa /tmp/apache_make.log"
        return 1
    fi

    fn_ok "Apache compilado e instalado en /usr/local/apache2"

    local CONF="/usr/local/apache2/conf/httpd.conf"
    sed -i "s/^Listen .*/Listen ${PUERTO}/" "$CONF"
    sed -i "s/^#ServerName .*/ServerName ${DOMINIO}:${PUERTO}/" "$CONF"
    sed -i "s/^ServerName .*/ServerName ${DOMINIO}:${PUERTO}/" "$CONF"

    cat >> "$CONF" <<APACHEEOF

# Seguridad - Practica 7
ServerTokens Prod
ServerSignature Off
TraceEnable Off
APACHEEOF

    local SSL_LABEL="No"
    local PUERTO_SSL="443"
    if [ "$SSL" = "si" ]; then
        fn_generar_certificado_ssl "apache"
        local CERT_DIR="${SSL_DIR}/apache"
        
        echo -ne "${YELLOW}Puerto SSL para Apache (ENTER=443): ${NC}"
        read -r PUERTO_SSL
        [ -z "$PUERTO_SSL" ] && PUERTO_SSL="443"
        SSL_LABEL="Si (puerto $PUERTO_SSL)"

        sed -i 's/#LoadModule ssl_module/LoadModule ssl_module/' "$CONF"
        sed -i 's/#LoadModule headers_module/LoadModule headers_module/' "$CONF"
        sed -i 's/#LoadModule socache_shmcb_module/LoadModule socache_shmcb_module/' "$CONF"

        cat >> "$CONF" <<SSLEOF

# SSL - Practica 7
Listen $PUERTO_SSL

<VirtualHost *:$PUERTO_SSL>
    ServerName ${DOMINIO}
    DocumentRoot "/usr/local/apache2/htdocs"
    SSLEngine on
    SSLCertificateFile    ${CERT_DIR}/server.crt
    SSLCertificateKeyFile ${CERT_DIR}/server.key
    SSLProtocol TLSv1.2 TLSv1.3
    Header always set Strict-Transport-Security "max-age=31536000"
</VirtualHost>

<VirtualHost *:${PUERTO}>
    ServerName ${DOMINIO}
    Redirect permanent / https://${DOMINIO}:$PUERTO_SSL/
</VirtualHost>
SSLEOF
        fn_sec "SSL configurado en Apache (puerto $PUERTO_SSL + redireccion desde ${PUERTO})"
        iptables -I INPUT -p tcp --dport "$PUERTO_SSL" -j ACCEPT 2>/dev/null
    fi

    mkdir -p /usr/local/apache2/htdocs
    cat > /usr/local/apache2/htdocs/index.html <<HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Apache - Activo</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee;
               display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: #16213e; padding: 40px 60px; border-radius: 12px;
                border-left: 6px solid #0f3460; text-align: center; }
        h1 { color: #e94560; }
        .badge { display: inline-block; background: #0f3460; padding: 4px 14px;
                 border-radius: 20px; margin: 4px; font-size: 0.9em; }
        .status { color: #4ade80; font-weight: bold; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Apache - Windows Server</h1>
        <div>
            <span class="badge">Servidor: Apache</span>
            <span class="badge">Puerto: ${PUERTO}</span>
            <span class="badge">SSL: ${SSL_LABEL}</span>
        </div>
        <div>OS: Windows Server</div>
        <div>Dominio: ${DOMINIO}</div>
        <div class="status">Servidor activo y funcionando</div>
        <p style="font-size:0.8em;color:#888">Practica 7 - FTP + SSL</p>
    </div>
</body>
</html>
HTMLEOF

    /usr/local/apache2/bin/apachectl start 2>/dev/null
    fn_ok "Apache iniciado."

    RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n[Apache] Puerto: ${PUERTO} | SSL: ${SSL_LABEL} | Origen: FTP"
    return 0
}

# -----------------------------------------------------------------------------
# BLOQUE 5: INSTALACION NGINX DESDE FTP
# -----------------------------------------------------------------------------

fn_instalar_nginx_ftp() {
    local ARCHIVO="$1"
    local PUERTO="$2"
    local SSL="$3"

    echo ""
    echo -e "${BLUE}====== INSTALACION NGINX DESDE FTP ======${NC}"

    fn_info "Instalando dependencias para compilar Nginx en Mageia..."
    urpmi --auto --quiet gcc make libpcre-devel libopenssl-devel zlib-devel 2>/dev/null

    local EXTRACT_DIR="${INSTALL_DIR}/nginx_src"
    mkdir -p "$EXTRACT_DIR"
    fn_info "Extrayendo ${ARCHIVO}..."
    tar -xzf "$ARCHIVO" -C "$EXTRACT_DIR" 2>/dev/null
    local SRC_DIR
    SRC_DIR=$(find "$EXTRACT_DIR" -maxdepth 1 -type d -name "nginx-*" | head -1)

    if [ -z "$SRC_DIR" ]; then
        fn_err "No se pudo extraer el archivo de Nginx."
        return 1
    fi

    fn_info "Compilando Nginx..."
    cd "$SRC_DIR" || return 1

    ./configure \
        --prefix=/usr/local/nginx \
        --with-http_ssl_module \
        --with-http_rewrite_module \
        --with-http_v2_module \
        >/tmp/nginx_configure.log 2>&1

    make -j2 >/tmp/nginx_make.log 2>&1
    make install >/tmp/nginx_install.log 2>&1

    if [ ! -f "/usr/local/nginx/sbin/nginx" ]; then
        fn_err "La compilacion de Nginx fallo. Revisa /tmp/nginx_make.log"
        return 1
    fi

    fn_ok "Nginx compilado e instalado en /usr/local/nginx"

    local SSL_BLOCK=""
    local SSL_LABEL="No"
    local PUERTO_SSL="443"
    if [ "$SSL" = "si" ]; then
        fn_generar_certificado_ssl "nginx"
        local CERT_DIR="${SSL_DIR}/nginx"
        
        echo -ne "${YELLOW}Puerto SSL para Nginx (ENTER=443): ${NC}"
        read -r PUERTO_SSL
        [ -z "$PUERTO_SSL" ] && PUERTO_SSL="443"
        SSL_LABEL="Si (puerto $PUERTO_SSL)"
        
        SSL_BLOCK="
    server {
        listen $PUERTO_SSL ssl;
        server_name ${DOMINIO};
        ssl_certificate     ${CERT_DIR}/server.crt;
        ssl_certificate_key ${CERT_DIR}/server.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        add_header Strict-Transport-Security \"max-age=31536000\" always;
        add_header X-Frame-Options SAMEORIGIN always;
        add_header X-Content-Type-Options nosniff always;
        root /usr/local/nginx/html;
        index index.html;
        server_tokens off;
    }"
        iptables -I INPUT -p tcp --dport "$PUERTO_SSL" -j ACCEPT 2>/dev/null
    fi

    cat > /usr/local/nginx/conf/nginx.conf <<NGINXEOF
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    server_tokens off;

    server {
        listen ${PUERTO};
        server_name ${DOMINIO};
        root /usr/local/nginx/html;
        index index.html;

        add_header X-Frame-Options SAMEORIGIN always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-XSS-Protection "1; mode=block" always;

        if (\$request_method !~ ^(GET|POST|HEAD)$) {
            return 405;
        }
NGINXEOF

    if [ "$SSL" = "si" ]; then
        cat >> /usr/local/nginx/conf/nginx.conf <<REDIREOF
        return 301 https://\$host:$PUERTO_SSL\$request_uri;
REDIREOF
    fi

    cat >> /usr/local/nginx/conf/nginx.conf <<NGINXEOF2
    }
${SSL_BLOCK}
}
NGINXEOF2

    local VERSION
    VERSION=$(find "$EXTRACT_DIR" -maxdepth 1 -type d -name "nginx-*" | head -1 | xargs basename | sed 's/nginx-//')

    mkdir -p /usr/local/nginx/html
    cat > /usr/local/nginx/html/index.html <<HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Nginx - Activo</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee;
               display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: #16213e; padding: 40px 60px; border-radius: 12px;
                border-left: 6px solid #0f3460; text-align: center; }
        h1 { color: #e94560; }
        .badge { display: inline-block; background: #0f3460; padding: 4px 14px;
                 border-radius: 20px; margin: 4px; font-size: 0.9em; }
        .status { color: #4ade80; font-weight: bold; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Nginx - Windows Server</h1>
        <div>
            <span class="badge">Servidor: Nginx</span>
            <span class="badge">Version: ${VERSION}</span>
            <span class="badge">Puerto: ${PUERTO}</span>
            <span class="badge">SSL: ${SSL_LABEL}</span>
        </div>
        <div>OS: Windows Server</div>
        <div>Dominio: ${DOMINIO}</div>
        <div class="status">Servidor activo y funcionando</div>
        <p style="font-size:0.8em;color:#888">Practica 7 - FTP + SSL</p>
    </div>
</body>
</html>
HTMLEOF

    /usr/local/nginx/sbin/nginx 2>/dev/null
    fn_ok "Nginx iniciado."

    RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n[Nginx] Puerto: ${PUERTO} | SSL: ${SSL_LABEL} | Origen: FTP"
    return 0
}

# -----------------------------------------------------------------------------
# BLOQUE 6: INSTALACION TOMCAT DESDE FTP
# -----------------------------------------------------------------------------

fn_instalar_tomcat_ftp() {
    local ARCHIVO="$1"
    local PUERTO="$2"
    local SSL="$3"

    echo ""
    echo -e "${BLUE}====== INSTALACION TOMCAT DESDE FTP ======${NC}"

    if ! command -v java &>/dev/null; then
        fn_info "Instalando Java OpenJDK en Mageia..."
        urpmi --auto --quiet java-11-openjdk 2>/dev/null || \
        urpmi --auto --quiet java-17-openjdk 2>/dev/null || \
        urpmi --auto --quiet jre-current 2>/dev/null
    fi
    fn_ok "Java disponible: $(java -version 2>&1 | head -1)"

    local TOMCAT_BASE="/opt/tomcat9"
    mkdir -p "$TOMCAT_BASE"
    fn_info "Extrayendo ${ARCHIVO}..."
    tar -xzf "$ARCHIVO" -C "$TOMCAT_BASE" --strip-components=1 2>/dev/null

    if [ ! -f "${TOMCAT_BASE}/bin/catalina.sh" ]; then
        fn_err "No se pudo extraer Tomcat correctamente."
        return 1
    fi

    fn_ok "Tomcat extraido en ${TOMCAT_BASE}"

    sed -i "s/port=\"8080\"/port=\"${PUERTO}\"/" "${TOMCAT_BASE}/conf/server.xml"
    fn_ok "Puerto Tomcat configurado a ${PUERTO}"

    local SSL_LABEL="No"
    local PUERTO_SSL="443"
    if [ "$SSL" = "si" ]; then
        fn_generar_certificado_ssl "tomcat"
        local CERT_DIR="${SSL_DIR}/tomcat"
        
        echo -ne "${YELLOW}Puerto SSL para Tomcat (ENTER=443): ${NC}"
        read -r PUERTO_SSL
        [ -z "$PUERTO_SSL" ] && PUERTO_SSL="443"
        SSL_LABEL="Si (puerto $PUERTO_SSL)"

        sed -i "s|</Service>|    <Connector port=\"$PUERTO_SSL\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\"\n               SSLEnabled=\"true\" scheme=\"https\" secure=\"true\"\n               keystoreFile=\"${CERT_DIR}/server.crt\"\n               keystorePass=\"practica7\"\n               clientAuth=\"false\" sslProtocol=\"TLS\" />\n</Service>|" \
            "${TOMCAT_BASE}/conf/server.xml"

        fn_sec "SSL configurado en Tomcat puerto $PUERTO_SSL"
        iptables -I INPUT -p tcp --dport "$PUERTO_SSL" -j ACCEPT 2>/dev/null
    fi

    if ! id tomcat &>/dev/null; then
        useradd -r -M -d "$TOMCAT_BASE" -s /sbin/nologin tomcat 2>/dev/null
    fi
    chown -R tomcat:tomcat "$TOMCAT_BASE"
    chmod +x "${TOMCAT_BASE}/bin/"*.sh

    local VERSION
    VERSION=$(basename "$ARCHIVO" | sed 's/apache-tomcat-//' | sed 's/.tar.gz//')

    mkdir -p "${TOMCAT_BASE}/webapps/ROOT"
    cat > "${TOMCAT_BASE}/webapps/ROOT/index.html" <<HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>IIS - Activo</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee;
               display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: #16213e; padding: 40px 60px; border-radius: 12px;
                border-left: 6px solid #0f3460; text-align: center; }
        h1 { color: #e94560; }
        .badge { display: inline-block; background: #0f3460; padding: 4px 14px;
                 border-radius: 20px; margin: 4px; font-size: 0.9em; }
        .status { color: #4ade80; font-weight: bold; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="card">
        <h1>IIS - Windows Server</h1>
        <div>
            <span class="badge">Servidor: IIS</span>
            <span class="badge">Version: ${VERSION}</span>
            <span class="badge">Puerto: ${PUERTO}</span>
            <span class="badge">SSL: ${SSL_LABEL}</span>
        </div>
        <div>OS: Windows Server</div>
        <div>Dominio: ${DOMINIO}</div>
        <div class="status">Servidor activo y funcionando</div>
        <p style="font-size:0.8em;color:#888">Practica 7 - FTP + SSL</p>
    </div>
</body>
</html>
HTMLEOF

    # Detectar JAVA_HOME dinamente
    local JAVA_HOME_DIR
    JAVA_HOME_DIR=$(dirname $(dirname $(readlink -f $(which java) 2>/dev/null) 2>/dev/null) 2>/dev/null)

    export JAVA_HOME="$JAVA_HOME_DIR"
    export CATALINA_HOME="$TOMCAT_BASE"

    su -s /bin/bash tomcat -c \
        "export JAVA_HOME=${JAVA_HOME_DIR}; export CATALINA_HOME=${TOMCAT_BASE}; ${TOMCAT_BASE}/bin/startup.sh" \
        2>/dev/null || bash "${TOMCAT_BASE}/bin/startup.sh" 2>/dev/null

    fn_ok "Tomcat iniciado."

    RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n[Tomcat] Puerto: ${PUERTO} | SSL: ${SSL_LABEL} | Origen: FTP"
    return 0
}

# -----------------------------------------------------------------------------
# BLOQUE 2: INSTALACION HIBRIDA (WEB / FTP)
# -----------------------------------------------------------------------------

fn_instalar_servicio_hibrido() {
    local TIPO="$1"    # apache, nginx, tomcat
    local NOMBRE="$2"  # Apache, Nginx, Tomcat
    
    echo -e "\n${CYAN}>>> CONFIGURACION DE $NOMBRE <<<${NC}"
    echo -e "  [1] Aprovisionamiento WEB (Instalacion Local)"
    echo -e "  [2] Descarga via FTP (Instaladores para Windows/Zip)"
    echo -ne "\n${YELLOW}Selecciona modo: ${NC}"
    read -r MODO
    
    local SSL="no"
    local PUERTO=""
    local PUERTO_SSL_USADO="443"

    if [ "$MODO" = "1" ]; then
        # Preguntar por los dos puertos (HTTP y HTTPS)
        echo -ne "${YELLOW}Ingresa el puerto HTTP deseado (ENTER para default): ${NC}"
        read -r PUERTO
        if [ -z "$PUERTO" ]; then
            [ "$TIPO" = "apache" ] && PUERTO="80"
            [ "$TIPO" = "nginx" ] && PUERTO="81"
            [ "$TIPO" = "tomcat" ] && PUERTO="8080"
        fi
        
        # Advertencia de puertos no seguros (Chrome/Edge bloquean ciertos puertos como 6000)
        if [[ "$PUERTO" =~ ^(6000|6665|6666|6667|6668|6669|6697|1719|1720|1723|2049|3659|4045)$ ]]; then
            fn_err "CUIDADO: El puerto $PUERTO suele ser bloqueado por navegadores (ERR_UNSAFE_PORT)."
            fn_info "Te recomiendo usar: 80, 81, 8080, 8443, 9000, 9090."
        fi

        echo -ne "${YELLOW}¿Deseas activar SSL/HTTPS en este servicio? (s/n): ${NC}"
        read -r ACTIVAR_SSL
        
        if [[ "$ACTIVAR_SSL" =~ ^[sS]$ ]]; then
            fn_instalar_web_con_ssl "$TIPO" "$PUERTO" "si"
            SSL="si"
            # PUERTO_SSL_USADO se actualiza dentro de fn_instalar_web_con_ssl o por ahi
        else
            fn_info "Iniciando aprovisionamiento WEB para $NOMBRE en puerto $PUERTO..."
            case "$TIPO" in
                "apache")
                    urpmi --auto httpd 2>/dev/null
                    sed -i "s/^Listen .*/Listen $PUERTO/" /etc/httpd/conf/httpd.conf 2>/dev/null
                    systemctl enable --now httpd 2>/dev/null
                    ;;
                "nginx")
                    urpmi --auto nginx 2>/dev/null
                    sed -i "s/listen .*[0-9];/listen $PUERTO;/" /etc/nginx/nginx.conf 2>/dev/null
                    systemctl enable --now nginx 2>/dev/null
                    ;;
                "tomcat")
                    urpmi --auto tomcat 2>/dev/null
                    local TC_CONF="/etc/tomcat/server.xml"
                    [ ! -f "$TC_CONF" ] && TC_CONF="/etc/tomcat9/server.xml"
                    [ -f "$TC_CONF" ] && sed -i "s/port=\"8080\"/port=\"$PUERTO\" address=\"0.0.0.0\"/g" "$TC_CONF" 2>/dev/null
                    systemctl enable --now tomcat 2>/dev/null
                    ;;
            esac
        fi
    elif [ "$MODO" = "2" ]; then
        fn_info "Iniciando descarga via FTP de $NOMBRE..."
        local REMOTO="${FTP_BASE_PATH}/${TIPO}/"
        FILES=$(fn_ftp_listar "$REMOTO")
        [ -z "$FILES" ] && { fn_err "No hay archivos."; return 1; }
        echo "$FILES"
        read -p "Archivo a descargar: " FILE_NAME
        mkdir -p "$INSTALL_DIR"
        fn_ftp_descargar "${REMOTO}${FILE_NAME}" "${INSTALL_DIR}/${FILE_NAME}"
        return
    fi

    # Firewall y Verificacion
    iptables -I INPUT -p tcp --dport "$PUERTO" -j ACCEPT 2>/dev/null
    
    fn_verificar_servicio_http "$NOMBRE" "$PUERTO" "$SSL"
}

# -----------------------------------------------------------------------------
# BLOQUE 7: SSL PARA VSFTPD (FTPS)
# -----------------------------------------------------------------------------

fn_configurar_ftps() {
    echo ""
    echo -e "${CYAN}=== CONFIGURACION FTPS (SSL en vsftpd) ===${NC}"

    if ! command -v vsftpd &>/dev/null; then
        fn_info "Instalando vsftpd en Mageia..."
        urpmi --auto --quiet vsftpd 2>/dev/null
    fi

    systemctl stop shorewall 2>/dev/null
    shorewall clear 2>/dev/null

    mkdir -p /var/run/vsftpd/empty
    chmod 755 /var/run/vsftpd/empty

    for shell in "/sbin/nologin" "/bin/false"; do
        grep -q "$shell" /etc/shells || echo "$shell" >> /etc/shells
    done

    local SERVER_IP
    SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    fn_info "IP del servidor: ${SERVER_IP}"

    fn_info "Asegurando usuario ${FTP_USER}..."
    if ! id "$FTP_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$FTP_USER" 2>/dev/null
    fi
    echo "${FTP_USER}:${FTP_PASS}" | chpasswd
    
    sed -i "/^${FTP_USER}$/d" /etc/ftpusers 2>/dev/null

    mkdir -p "${SSL_DIR}/vsftpd"
    fn_sec "Generando certificado SSL para vsftpd..."

    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "${SSL_DIR}/vsftpd/vsftpd.key" \
        -out "${SSL_DIR}/vsftpd/vsftpd.crt" \
        -subj "/C=MX/ST=Sinaloa/L=Culiacan/O=Reprobados/OU=FTP/CN=${SERVER_IP}" \
        -sha256 2>/dev/null

    cat "${SSL_DIR}/vsftpd/vsftpd.key" "${SSL_DIR}/vsftpd/vsftpd.crt" \
        > "${SSL_DIR}/vsftpd/vsftpd.pem"
    chmod 600 "${SSL_DIR}/vsftpd/vsftpd.key"
    
    VSFTPD_CONF="/etc/vsftpd/vsftpd.conf"
    [ -f "$VSFTPD_CONF" ] && cp "$VSFTPD_CONF" "${VSFTPD_CONF}.bak"

    cat <<VSFTPDEOF > "$VSFTPD_CONF"
# vsftpd.conf - Practica 7 Config Master
listen=YES
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=10000
pasv_max_port=10100

# Anonymous Config
anon_root=/var/ftp_p7
no_anon_password=YES
anon_upload_enable=YES
anon_mkdir_write_enable=YES
anon_other_write_enable=YES
anon_world_readable_only=YES

# FTPS - SSL/TLS - Maxima compatibilidad
ssl_enable=YES
allow_anon_ssl=YES
force_local_data_ssl=YES
force_local_logins_ssl=YES
force_anon_data_ssl=NO
force_anon_logins_ssl=NO
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
require_ssl_reuse=NO
ssl_ciphers=HIGH
rsa_cert_file=${SSL_DIR}/vsftpd/vsftpd.crt
rsa_private_key_file=${SSL_DIR}/vsftpd/vsftpd.key
debug_ssl=YES
implicit_ssl=NO
seccomp_sandbox=NO
check_shell=NO
VSFTPDEOF

    local FTP_ROOT="/var/ftp_p7"
    mkdir -p "${FTP_ROOT}/u1"
    mkdir -p "${FTP_ROOT}/general"
    mkdir -p "${FTP_ROOT}/http/Linux/apache"
    mkdir -p "${FTP_ROOT}/http/Linux/nginx"
    mkdir -p "${FTP_ROOT}/http/Linux/tomcat"
    
    chown root:root "$FTP_ROOT"
    chmod 555 "$FTP_ROOT"
    chown -R ${FTP_USER}:ftp "${FTP_ROOT}/u1"
    chmod 755 "${FTP_ROOT}/u1"
    chown -R ftp:ftp "${FTP_ROOT}/http"
    chmod 777 "${FTP_ROOT}/http"

    iptables -I INPUT -p tcp --dport 21 -j ACCEPT 2>/dev/null
    iptables -I INPUT -p tcp --dport 20 -j ACCEPT 2>/dev/null
    iptables -I INPUT -p tcp --dport 10000:10100 -j ACCEPT 2>/dev/null

    systemctl stop vsftpd 2>/dev/null
    systemctl start vsftpd 2>/dev/null

    RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n[vsftpd] FTPS activado | Cert: ${SSL_DIR}/vsftpd/vsftpd.crt"
}

# -----------------------------------------------------------------------------
# BLOQUE 8: INSTALACION WEB (URPMI) CON SSL OPCIONAL
# -----------------------------------------------------------------------------

fn_instalar_web_con_ssl() {
    local SERVICIO="$1"
    local PUERTO="$2"
    local SSL="$3"

    fn_info "Instalando ${SERVICIO} via repositorio urpmi (Mageia)..."

    case "$SERVICIO" in
        apache)
            urpmi --auto --quiet apache apache-mod_ssl 2>/dev/null
            local APACHE_CONF="/etc/httpd/conf/httpd.conf"
            local WEBROOT="/var/www/html"

            sed -i "s/^Listen.*$/Listen ${PUERTO}/" "$APACHE_CONF" 2>/dev/null

            local SSL_LABEL="No"
            local PUERTO_SSL="443"
            if [ "$SSL" = "si" ]; then
                fn_generar_certificado_ssl "apache"
                local CERT_DIR="${SSL_DIR}/apache"
                
                echo -ne "${YELLOW}Puerto SSL para Apache (ENTER=443): ${NC}"
                read -r PUERTO_SSL
                [ -z "$PUERTO_SSL" ] && PUERTO_SSL="443"
                SSL_LABEL="Si (puerto $PUERTO_SSL)"

                cat > /etc/httpd/conf/conf.d/ssl_p7.conf <<APACHESSLCONF
Listen $PUERTO_SSL
<VirtualHost *:$PUERTO_SSL>
    ServerName ${DOMINIO}
    DocumentRoot ${WEBROOT}
    SSLEngine on
    SSLCertificateFile    ${CERT_DIR}/server.crt
    SSLCertificateKeyFile ${CERT_DIR}/server.key
</VirtualHost>
APACHESSLCONF
                iptables -I INPUT -p tcp --dport "$PUERTO_SSL" -j ACCEPT 2>/dev/null
            fi

            cat > "${WEBROOT}/index.html" <<HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Apache - Activo</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee;
               display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: #16213e; padding: 40px 60px; border-radius: 12px;
                border-left: 6px solid #0f3460; text-align: center; }
        h1 { color: #e94560; }
        .badge { display: inline-block; background: #0f3460; padding: 4px 14px;
                 border-radius: 20px; margin: 4px; font-size: 0.9em; }
        .status { color: #4ade80; font-weight: bold; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Apache - Windows Server</h1>
        <div>
            <span class="badge">Servidor: Apache</span>
            <span class="badge">Puerto HTTP: ${PUERTO}</span>
            <span class="badge">SSL: ${SSL_LABEL}</span>
        </div>
        <div>OS: Windows Server</div>
        <div>Dominio: ${DOMINIO}</div>
        <div class="status">Servidor activo y funcionando</div>
        <p style="font-size:0.8em;color:#888">Practica 7 - FTP + SSL</p>
    </div>
</body>
</html>
HTMLEOF

            systemctl enable httpd 2>/dev/null
            systemctl restart httpd 2>/dev/null
            RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n[Apache] Puerto: ${PUERTO} | SSL: ${SSL_LABEL} | Origen: WEB"
            ;;
        nginx)
            urpmi --auto --quiet nginx 2>/dev/null
            local NGINX_WEBROOT="/usr/share/nginx/html"

            local SSL_LABEL="No"
            local SSL_BLOCK=""
            local PUERTO_SSL="443"
            if [ "$SSL" = "si" ]; then
                fn_generar_certificado_ssl "nginx"
                local CERT_DIR="${SSL_DIR}/nginx"
                
                echo -ne "${YELLOW}Puerto SSL para Nginx (ENTER=443): ${NC}"
                read -r PUERTO_SSL
                [ -z "$PUERTO_SSL" ] && PUERTO_SSL="443"
                SSL_LABEL="Si (puerto $PUERTO_SSL)"

                SSL_BLOCK="
    server {
        listen $PUERTO_SSL ssl;
        server_name ${DOMINIO};
        ssl_certificate     ${CERT_DIR}/server.crt;
        ssl_certificate_key ${CERT_DIR}/server.key;
        root ${NGINX_WEBROOT};
        index index.html;
    }"
                iptables -I INPUT -p tcp --dport "$PUERTO_SSL" -j ACCEPT 2>/dev/null
            fi

            cat > /etc/nginx/nginx.conf <<NGINXCONF
worker_processes auto;
events { worker_connections 1024; }
http {
    include mime.types;
    server {
        listen ${PUERTO};
        server_name ${DOMINIO};
        root ${NGINX_WEBROOT};
        index index.html;
    }
    ${SSL_BLOCK}
}
NGINXCONF

            cat > "${NGINX_WEBROOT}/index.html" <<HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Nginx - Activo</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee;
               display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: #16213e; padding: 40px 60px; border-radius: 12px;
                border-left: 6px solid #0f3460; text-align: center; }
        h1 { color: #e94560; }
        .badge { display: inline-block; background: #0f3460; padding: 4px 14px;
                 border-radius: 20px; margin: 4px; font-size: 0.9em; }
        .status { color: #4ade80; font-weight: bold; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Nginx - Windows Server</h1>
        <div>
            <span class="badge">Servidor: Nginx</span>
            <span class="badge">Puerto HTTP: ${PUERTO}</span>
            <span class="badge">SSL: ${SSL_LABEL}</span>
        </div>
        <div>OS: Windows Server</div>
        <div>Dominio: ${DOMINIO}</div>
        <div class="status">Servidor activo y funcionando</div>
        <p style="font-size:0.8em;color:#888">Practica 7 - FTP + SSL</p>
    </div>
</body>
</html>
HTMLEOF

            systemctl enable nginx 2>/dev/null
            systemctl restart nginx 2>/dev/null
            RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n[Nginx] Puerto: ${PUERTO} | SSL: ${SSL_LABEL} | Origen: WEB"
            ;;
        tomcat)
            urpmi --auto --quiet tomcat 2>/dev/null
            local TC_ROOT="/var/lib/tomcat/webapps/ROOT"
            mkdir -p "$TC_ROOT"

            local SSL_LABEL="No"
            local PUERTO_SSL="8443"
            if [ "$SSL" = "si" ]; then
                fn_generar_certificado_ssl "tomcat"
                local CERT_DIR="${SSL_DIR}/tomcat"
                
                echo -ne "${YELLOW}Puerto SSL para Tomcat (ENTER=8443): ${NC}"
                read -r PUERTO_SSL
                [ -z "$PUERTO_SSL" ] && PUERTO_SSL="8443"
                SSL_LABEL="Si (puerto $PUERTO_SSL)"
                
                local TC_CONF="/etc/tomcat/server.xml"
                [ ! -f "$TC_CONF" ] && TC_CONF="/etc/tomcat9/server.xml"
                
                if [ -f "$TC_CONF" ]; then
                    # Cambiar el primer "port=..." (que es el HTTP) sea cual sea el numero actual
                    sed -i "s/port=\"[0-9]*\"/port=\"$PUERTO\"/1" "$TC_CONF" 2>/dev/null
                    # Cambiar el primer "redirectPort=..." (que es el SSL)
                    sed -i "s/redirectPort=\"[0-9]*\"/redirectPort=\"$PUERTO_SSL\"/1" "$TC_CONF" 2>/dev/null
                    # Añadir el conector SSL al final del bloque <Service>
                    # (Esto lo hacemos solo la primera vez, pero sed no tiene facildad de "si no existe")
                    # Para evitar duplicados brutales, buscamos si ya existe el puerto SSL en el archivo
                    if ! grep -q "port=\"$PUERTO_SSL\"" "$TC_CONF"; then
                        sed -i "s|</Service>|    <Connector port=\"$PUERTO_SSL\" address=\"0.0.0.0\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\"\n               SSLEnabled=\"true\" scheme=\"https\" secure=\"true\"\n               keystoreFile=\"${CERT_DIR}/server.crt\"\n               keystorePass=\"practica7\"\n               clientAuth=\"false\" sslProtocol=\"TLS\" />\n</Service>|" "$TC_CONF"
                    fi
                fi
                iptables -I INPUT -p tcp --dport "$PUERTO" -j ACCEPT 2>/dev/null
                iptables -I INPUT -p tcp --dport "$PUERTO_SSL" -j ACCEPT 2>/dev/null
            fi

            cat > "${TC_ROOT}/index.html" <<HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>IIS - Activo</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee;
               display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: #16213e; padding: 40px 60px; border-radius: 12px;
                border-left: 6px solid #0f3460; text-align: center; }
        h1 { color: #e94560; }
        .badge { display: inline-block; background: #0f3460; padding: 4px 14px;
                 border-radius: 20px; margin: 4px; font-size: 0.9em; }
        .status { color: #4ade80; font-weight: bold; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="card">
        <h1>IIS - Windows Server</h1>
        <div>
            <span class="badge">Servidor: IIS</span>
            <span class="badge">Puerto HTTP: ${PUERTO}</span>
            <span class="badge">SSL: ${SSL_LABEL}</span>
        </div>
        <div>OS: Windows Server</div>
        <div>Dominio: ${DOMINIO}</div>
        <div class="status">Servidor activo y funcionando</div>
        <p style="font-size:0.8em;color:#888">Practica 7 - FTP + SSL</p>
    </div>
</body>
</html>
HTMLEOF

            systemctl enable tomcat 2>/dev/null
            systemctl restart tomcat 2>/dev/null
            RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n[Tomcat] Puerto: ${PUERTO} | SSL: ${SSL_LABEL} | Origen: WEB"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# BLOQUE 9: VERIFICACION AUTOMATIZADA Y RESUMEN
# -----------------------------------------------------------------------------

fn_verificar_servicio_http() {
    local NOMBRE="$1"
    local PUERTO="$2"
    local SSL="$3"
    echo -e "\n${CYAN}Verificando ${NOMBRE}...${NC}"
    sleep 3
    if curl -sk --connect-timeout 5 "http://127.0.0.1:${PUERTO}" -o /dev/null; then
        fn_ok "${NOMBRE} responde HTTP en puerto ${PUERTO}"
    else
        fn_err "${NOMBRE} no responde en puerto ${PUERTO}"
    fi
}

fn_mostrar_resumen() {
    echo -e "\n${CYAN}====== RESUMEN FINAL ======${NC}"
    echo -e "$RESUMEN_INSTALACIONES"
    echo ""
}
