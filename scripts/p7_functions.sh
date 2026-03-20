#!/bin/bash
# =============================================================================
# p7_functions.sh - Libreria de funciones Practica 7
# Sistema Operativo: Mageia Linux
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
FTP_SERVER="192.168.107.128"
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
    echo "║       SISTEMA DE APROVISIONAMIENTO WEB - MAGEIA          ║"
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
    if [ "$SSL" = "si" ]; then
        fn_generar_certificado_ssl "apache"
        local CERT_DIR="${SSL_DIR}/apache"
        SSL_LABEL="Si (puerto 443)"

        sed -i 's/#LoadModule ssl_module/LoadModule ssl_module/' "$CONF"
        sed -i 's/#LoadModule headers_module/LoadModule headers_module/' "$CONF"
        sed -i 's/#LoadModule socache_shmcb_module/LoadModule socache_shmcb_module/' "$CONF"

        cat >> "$CONF" <<SSLEOF

# SSL - Practica 7
Listen 443

<VirtualHost *:443>
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
    Redirect permanent / https://${DOMINIO}/
</VirtualHost>
SSLEOF
        fn_sec "SSL configurado en Apache (puerto 443 + redireccion desde ${PUERTO})"
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
        <h1>Apache - Mageia Linux</h1>
        <div>
            <span class="badge">Servidor: Apache</span>
            <span class="badge">Puerto: ${PUERTO}</span>
            <span class="badge">SSL: ${SSL_LABEL}</span>
        </div>
        <div>OS: Mageia Linux</div>
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
    if [ "$SSL" = "si" ]; then
        fn_generar_certificado_ssl "nginx"
        local CERT_DIR="${SSL_DIR}/nginx"
        SSL_LABEL="Si (puerto 443)"
        SSL_BLOCK="
    server {
        listen 443 ssl;
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
        return 301 https://\$host\$request_uri;
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
        <h1>Nginx - Mageia Linux</h1>
        <div>
            <span class="badge">Servidor: Nginx</span>
            <span class="badge">Version: ${VERSION}</span>
            <span class="badge">Puerto: ${PUERTO}</span>
            <span class="badge">SSL: ${SSL_LABEL}</span>
        </div>
        <div>OS: Mageia Linux</div>
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
    if [ "$SSL" = "si" ]; then
        fn_generar_certificado_ssl "tomcat"
        local CERT_DIR="${SSL_DIR}/tomcat"
        SSL_LABEL="Si (puerto 443)"

        sed -i "s|</Service>|    <Connector port=\"443\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\"\n               SSLEnabled=\"true\" scheme=\"https\" secure=\"true\"\n               keystoreFile=\"${CERT_DIR}/server.crt\"\n               keystorePass=\"practica7\"\n               clientAuth=\"false\" sslProtocol=\"TLS\" />\n</Service>|" \
            "${TOMCAT_BASE}/conf/server.xml"

        fn_sec "SSL configurado en Tomcat puerto 443"
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
    <title>Tomcat - Activo</title>
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
        <h1>Tomcat - Mageia Linux</h1>
        <div>
            <span class="badge">Servidor: Tomcat</span>
            <span class="badge">Version: ${VERSION}</span>
            <span class="badge">Puerto: ${PUERTO}</span>
            <span class="badge">SSL: ${SSL_LABEL}</span>
        </div>
        <div>OS: Mageia Linux</div>
        <div>Dominio: ${DOMINIO}</div>
        <div class="status">Servidor activo y funcionando</div>
        <p style="font-size:0.8em;color:#888">Practica 7 - FTP + SSL</p>
    </div>
</body>
</html>
HTMLEOF

    # Detectar JAVA_HOME dinamicamente
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
# BLOQUE 7: SSL PARA VSFTPD (FTPS)
# -----------------------------------------------------------------------------

fn_configurar_ftps() {
    echo ""
    echo -e "${CYAN}=== CONFIGURACION FTPS (SSL en vsftpd) ===${NC}"

    if ! command -v vsftpd &>/dev/null; then
        fn_info "Instalando vsftpd en Mageia..."
        urpmi --auto --quiet vsftpd 2>/dev/null
    fi

    mkdir -p "${SSL_DIR}/vsftpd"
    fn_sec "Generando certificado SSL para vsftpd..."

    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "${SSL_DIR}/vsftpd/vsftpd.key" \
        -out "${SSL_DIR}/vsftpd/vsftpd.crt" \
        -subj "/C=MX/ST=Sinaloa/L=Culiacan/O=Reprobados/OU=FTP/CN=${DOMINIO}" \
        2>/dev/null

    chmod 600 "${SSL_DIR}/vsftpd/vsftpd.key"
    fn_sec "Certificado FTPS generado."

    # En Mageia el vsftpd.conf esta en /etc/vsftpd/vsftpd.conf
    local VSFTPD_CONF="/etc/vsftpd/vsftpd.conf"
    if [ ! -f "$VSFTPD_CONF" ]; then
        # Fallback a /etc/vsftpd.conf si no existe el anterior
        [ -f "/etc/vsftpd.conf" ] && VSFTPD_CONF="/etc/vsftpd.conf"
    fi

    if [ ! -f "$VSFTPD_CONF" ]; then
        fn_err "No se encontro vsftpd.conf. Verifica la instalacion de vsftpd."
        return 1
    fi

    fn_info "Usando configuracion en: $VSFTPD_CONF"

    # Limpiar configuraciones SSL previas
    sed -i '/^ssl_enable/d' "$VSFTPD_CONF"
    sed -i '/^rsa_cert_file/d' "$VSFTPD_CONF"
    sed -i '/^rsa_private_key_file/d' "$VSFTPD_CONF"
    sed -i '/^ssl_tlsv1/d' "$VSFTPD_CONF"
    sed -i '/^ssl_sslv2/d' "$VSFTPD_CONF"
    sed -i '/^ssl_sslv3/d' "$VSFTPD_CONF"
    sed -i '/^force_local_data_ssl/d' "$VSFTPD_CONF"
    sed -i '/^force_local_logins_ssl/d' "$VSFTPD_CONF"
    sed -i '/^require_ssl_reuse/d' "$VSFTPD_CONF"
    sed -i '/^ssl_ciphers/d' "$VSFTPD_CONF"

    cat >> "$VSFTPD_CONF" <<FTPSEOF

# FTPS - SSL/TLS - Practica 7
ssl_enable=YES
rsa_cert_file=${SSL_DIR}/vsftpd/vsftpd.crt
rsa_private_key_file=${SSL_DIR}/vsftpd/vsftpd.key
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
require_ssl_reuse=NO
ssl_ciphers=HIGH
FTPSEOF

    systemctl restart vsftpd 2>/dev/null
    if [ $? -eq 0 ]; then
        fn_sec "vsftpd reiniciado con FTPS activado."
        fn_ok "FTPS configurado correctamente en ${DOMINIO}"
    else
        fn_err "No se pudo reiniciar vsftpd. Revisa: systemctl status vsftpd"
    fi

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
            # En Mageia: paquete=apache, servicio=httpd, conf=/etc/httpd/conf/httpd.conf
            urpmi --auto --quiet apache apache-mod_ssl apache-mod_headers 2>/dev/null

            local APACHE_CONF="/etc/httpd/conf/httpd.conf"
            local APACHE_CONFD="/etc/httpd/conf/conf.d"
            local WEBROOT="/var/www/html"
            mkdir -p "$APACHE_CONFD" "$WEBROOT"

            # Limpiar configuracion previa de practica7
            rm -f "${APACHE_CONFD}/practica7-ssl.conf" 2>/dev/null

            # Ajustar puerto de escucha (reemplaza cualquier puerto Listen existente)
            sed -i "s/^Listen.*$/Listen ${PUERTO}/" "$APACHE_CONF" 2>/dev/null

            # Asegurar que mod_ssl y mod_headers esten cargados
            grep -q 'LoadModule ssl_module' "$APACHE_CONF" || \
                echo "LoadModule ssl_module modules/mod_ssl.so" >> "$APACHE_CONF"
            grep -q 'LoadModule headers_module' "$APACHE_CONF" || \
                echo "LoadModule headers_module modules/mod_headers.so" >> "$APACHE_CONF"
            grep -q 'LoadModule socache_shmcb_module' "$APACHE_CONF" || \
                echo "LoadModule socache_shmcb_module modules/mod_socache_shmcb.so" >> "$APACHE_CONF"

            local SSL_LABEL="No"
            if [ "$SSL" = "si" ]; then
                fn_generar_certificado_ssl "apache"
                local CERT_DIR="${SSL_DIR}/apache"
                SSL_LABEL="Si (puerto 443)"

                cat > "${APACHE_CONFD}/practica7-ssl.conf" <<APACHESSLCONF
<VirtualHost *:443>
    ServerName ${DOMINIO}
    DocumentRoot ${WEBROOT}
    SSLEngine on
    SSLCertificateFile    ${CERT_DIR}/server.crt
    SSLCertificateKeyFile ${CERT_DIR}/server.key
    SSLProtocol TLSv1.2 TLSv1.3
    Header always set Strict-Transport-Security "max-age=31536000"
</VirtualHost>

<VirtualHost *:${PUERTO}>
    ServerName ${DOMINIO}
    Redirect permanent / https://${DOMINIO}/
</VirtualHost>
APACHESSLCONF
                fn_sec "VirtualHost SSL creado."
            fi

            # Crear pagina HTML con datos correctos
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
        <h1>Apache - Mageia Linux</h1>
        <div>
            <span class="badge">Servidor: Apache</span>
            <span class="badge">Puerto HTTP: ${PUERTO}</span>
            <span class="badge">SSL: ${SSL_LABEL}</span>
        </div>
        <div>OS: Mageia Linux</div>
        <div>Dominio: ${DOMINIO}</div>
        <div class="status">Servidor activo y funcionando</div>
        <p style="font-size:0.8em;color:#888">Practica 7 - FTP + SSL</p>
    </div>
</body>
</html>
HTMLEOF

            systemctl enable httpd 2>/dev/null
            systemctl restart httpd 2>/dev/null
            fn_ok "Apache instalado via urpmi (servicio: httpd) - puerto ${PUERTO}"
            RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n[Apache] Puerto: ${PUERTO} | SSL: ${SSL_LABEL} | Origen: WEB"
            ;;

        nginx)
            urpmi --auto --quiet nginx 2>/dev/null

            local NGINX_CONFD="/etc/nginx/conf.d"
            local NGINX_WEBROOT="/usr/share/nginx/html"
            mkdir -p "$NGINX_CONFD" "$NGINX_WEBROOT"
            rm -f "${NGINX_CONFD}/default.conf" 2>/dev/null

            local SSL_LABEL="No"
            local PUERTO_SSL=""

            if [ "$SSL" = "si" ]; then
                fn_generar_certificado_ssl "nginx"
                local CERT_DIR="${SSL_DIR}/nginx"
                SSL_LABEL="Si"

                # Pedir puerto HTTPS separado para no chocar con Apache (443)
                echo ""
                echo -e "${YELLOW}Ingresa el puerto HTTPS para Nginx (ej: 8443, 9443):${NC}"
                while true; do
                    read -r PUERTO_SSL
                    if [[ "$PUERTO_SSL" =~ ^[0-9]+$ ]] && [ "$PUERTO_SSL" -ge 1 ] && [ "$PUERTO_SSL" -le 65535 ]; then
                        if ss -tlnp 2>/dev/null | grep -q ":${PUERTO_SSL} "; then
                            fn_err "Puerto ${PUERTO_SSL} ya esta en uso. Elige otro."
                        else
                            fn_ok "Puerto HTTPS ${PUERTO_SSL} disponible."
                            break
                        fi
                    else
                        fn_err "Puerto invalido."
                    fi
                done
                SSL_LABEL="Si (puerto ${PUERTO_SSL})"
                PUERTO_SSL_USADO="$PUERTO_SSL"

                cat > "${NGINX_CONFD}/practica7.conf" <<NGINXCONF
server {
    listen ${PUERTO};
    server_name ${DOMINIO};
    server_tokens off;
    return 301 https://\$host:${PUERTO_SSL}\$request_uri;
}

server {
    listen ${PUERTO_SSL} ssl;
    server_name ${DOMINIO};
    ssl_certificate     ${CERT_DIR}/server.crt;
    ssl_certificate_key ${CERT_DIR}/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    root ${NGINX_WEBROOT};
    index index.html;
    server_tokens off;
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
}
NGINXCONF

                # Abrir puerto SSL en firewall
                iptables -I INPUT -p tcp --dport "$PUERTO_SSL" -j ACCEPT 2>/dev/null

            else
                cat > "${NGINX_CONFD}/practica7.conf" <<NGINXCONF
server {
    listen ${PUERTO};
    server_name ${DOMINIO};
    root ${NGINX_WEBROOT};
    index index.html;
    server_tokens off;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
}
NGINXCONF
            fi

            # Crear pagina HTML
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
        <h1>Nginx - Mageia Linux</h1>
        <div>
            <span class="badge">Servidor: Nginx</span>
            <span class="badge">Puerto HTTP: ${PUERTO}</span>
            <span class="badge">SSL: ${SSL_LABEL}</span>
        </div>
        <div>OS: Mageia Linux</div>
        <div>Dominio: ${DOMINIO}</div>
        <div class="status">Servidor activo y funcionando</div>
        <p style="font-size:0.8em;color:#888">Practica 7 - FTP + SSL</p>
    </div>
</body>
</html>
HTMLEOF

            systemctl enable nginx 2>/dev/null
            systemctl restart nginx 2>/dev/null
            fn_ok "Nginx instalado via urpmi - puerto ${PUERTO} | SSL: ${SSL_LABEL}"
            RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n[Nginx] Puerto: ${PUERTO} | SSL: ${SSL_LABEL} | Origen: WEB"
            ;;

        tomcat)
            urpmi --auto --quiet tomcat 2>/dev/null || \
            urpmi --auto --quiet tomcat9 2>/dev/null

            if ! command -v java &>/dev/null; then
                urpmi --auto --quiet java-11-openjdk 2>/dev/null
            fi

            # Detectar nombre del servicio tomcat
            local TOMCAT_SVC="tomcat"
            systemctl list-units --type=service 2>/dev/null | grep -q "tomcat9" && TOMCAT_SVC="tomcat9"

            # Detectar directorio de configuracion de tomcat
            local TOMCAT_CONF=""
            for DIR in /etc/tomcat /etc/tomcat9 /usr/share/tomcat/conf /usr/share/tomcat9/conf; do
                [ -f "${DIR}/server.xml" ] && TOMCAT_CONF="$DIR" && break
            done

            local SSL_LABEL="No"

            if [ -n "$TOMCAT_CONF" ]; then
                # Detener tomcat antes de modificar configuracion
                systemctl stop "$TOMCAT_SVC" 2>/dev/null

                # Cambiar puerto HTTP - reemplaza cualquier puerto en el conector HTTP principal
                # Busca el Connector con protocol HTTP/1.1 y cambia su puerto
                sed -i "s|<Connector port=\"[0-9]*\" protocol=\"HTTP/1.1\"|<Connector port=\"${PUERTO}\" protocol=\"HTTP/1.1\"|" \
                    "${TOMCAT_CONF}/server.xml" 2>/dev/null

                # Fallback: si no encontro el patron anterior, reemplaza 8080 o cualquier puerto comun
                grep -q "port=\"${PUERTO}\"" "${TOMCAT_CONF}/server.xml" || \
                    sed -i "s/port=\"[0-9]*\" protocol=\"HTTP/port=\"${PUERTO}\" protocol=\"HTTP/" \
                    "${TOMCAT_CONF}/server.xml" 2>/dev/null

                fn_ok "Puerto Tomcat configurado a ${PUERTO}"

                if [ "$SSL" = "si" ]; then
                    fn_generar_certificado_ssl "tomcat"
                    local CERT_DIR="${SSL_DIR}/tomcat"

                    # Pedir puerto HTTPS separado
                    echo ""
                    echo -e "${YELLOW}Ingresa el puerto HTTPS para Tomcat (ej: 8444, 9444):${NC}"
                    local PUERTO_SSL_TC=""
                    while true; do
                        read -r PUERTO_SSL_TC
                        if [[ "$PUERTO_SSL_TC" =~ ^[0-9]+$ ]] && [ "$PUERTO_SSL_TC" -ge 1 ] && [ "$PUERTO_SSL_TC" -le 65535 ]; then
                            if ss -tlnp 2>/dev/null | grep -q ":${PUERTO_SSL_TC} "; then
                                fn_err "Puerto ${PUERTO_SSL_TC} ya esta en uso. Elige otro."
                            else
                                fn_ok "Puerto HTTPS ${PUERTO_SSL_TC} disponible."
                                break
                            fi
                        else
                            fn_err "Puerto invalido."
                        fi
                    done
                    SSL_LABEL="Si (puerto ${PUERTO_SSL_TC})"
                    PUERTO_SSL_USADO="$PUERTO_SSL_TC"

                    sed -i "s|</Service>|    <Connector port=\"${PUERTO_SSL_TC}\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\"\n               SSLEnabled=\"true\" scheme=\"https\" secure=\"true\"\n               keystoreFile=\"${CERT_DIR}/server.crt\"\n               keystorePass=\"practica7\"\n               clientAuth=\"false\" sslProtocol=\"TLS\" />\n</Service>|" \
                        "${TOMCAT_CONF}/server.xml" 2>/dev/null

                    iptables -I INPUT -p tcp --dport "$PUERTO_SSL_TC" -j ACCEPT 2>/dev/null
                    fn_sec "SSL configurado en Tomcat puerto ${PUERTO_SSL_TC}"
                fi

                # Crear pagina HTML en el webroot de Tomcat
                local TOMCAT_WEBROOT=""
                for DIR in /var/lib/tomcat/webapps/ROOT /var/lib/tomcat9/webapps/ROOT \
                           /usr/share/tomcat/webapps/ROOT /usr/share/tomcat9/webapps/ROOT; do
                    [ -d "$DIR" ] && TOMCAT_WEBROOT="$DIR" && break
                done

                if [ -n "$TOMCAT_WEBROOT" ]; then
                    cat > "${TOMCAT_WEBROOT}/index.html" <<HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Tomcat - Activo</title>
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
        <h1>Tomcat - Mageia Linux</h1>
        <div>
            <span class="badge">Servidor: Tomcat</span>
            <span class="badge">Puerto HTTP: ${PUERTO}</span>
            <span class="badge">SSL: ${SSL_LABEL}</span>
        </div>
        <div>OS: Mageia Linux</div>
        <div>Dominio: ${DOMINIO}</div>
        <div class="status">Servidor activo y funcionando</div>
        <p style="font-size:0.8em;color:#888">Practica 7 - FTP + SSL</p>
    </div>
</body>
</html>
HTMLEOF
                fi
            fi

            systemctl enable "$TOMCAT_SVC" 2>/dev/null
            systemctl restart "$TOMCAT_SVC" 2>/dev/null
            fn_ok "Tomcat instalado via urpmi - puerto ${PUERTO} | SSL: ${SSL_LABEL}"
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
    local PUERTO_SSL="${4:-443}"   # Puerto HTTPS, por defecto 443

    echo -e "\n${CYAN}Verificando ${NOMBRE}...${NC}"

    if ss -tlnp 2>/dev/null | grep -q ":${PUERTO} "; then
        fn_ok "${NOMBRE} escuchando en puerto ${PUERTO}"
    elif netstat -tlnp 2>/dev/null | grep -q ":${PUERTO} "; then
        fn_ok "${NOMBRE} escuchando en puerto ${PUERTO}"
    else
        fn_err "${NOMBRE} NO esta escuchando en puerto ${PUERTO}"
        return 1
    fi

    local RESP
    RESP=$(curl -sk --connect-timeout 5 "http://127.0.0.1:${PUERTO}" -o /dev/null -w "%{http_code}" 2>/dev/null)
    if [ "$RESP" = "200" ] || [ "$RESP" = "302" ] || [ "$RESP" = "301" ]; then
        fn_ok "${NOMBRE} responde HTTP correctamente (codigo: ${RESP})"
    else
        fn_info "${NOMBRE} responde con codigo: ${RESP}"
    fi

    if [ "$SSL" = "si" ]; then
        local RESP_SSL
        RESP_SSL=$(curl -sk --connect-timeout 5 "https://127.0.0.1:${PUERTO_SSL}" -o /dev/null -w "%{http_code}" 2>/dev/null)
        if [ "$RESP_SSL" = "200" ] || [ "$RESP_SSL" = "302" ]; then
            fn_sec "${NOMBRE} responde HTTPS correctamente en puerto ${PUERTO_SSL} (codigo: ${RESP_SSL})"
        else
            fn_info "${NOMBRE} HTTPS responde con codigo: ${RESP_SSL}"
        fi

        local CERT_INFO
        CERT_INFO=$(echo | openssl s_client -connect "127.0.0.1:${PUERTO_SSL}" \
            -servername "${DOMINIO}" 2>/dev/null | \
            openssl x509 -noout -subject -dates 2>/dev/null)
        if [ -n "$CERT_INFO" ]; then
            fn_sec "Certificado SSL verificado:"
            echo "$CERT_INFO" | while read -r linea; do
                echo "    $linea"
            done
        fi
    fi
}

fn_mostrar_resumen() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║            RESUMEN DE INSTALACIONES - PRACTICA 7         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if [ -z "$RESUMEN_INSTALACIONES" ]; then
        echo -e "${YELLOW}No hay instalaciones registradas en esta sesion.${NC}"
    else
        echo -e "${GREEN}Servicios instalados/configurados:${NC}"
        echo -e "$RESUMEN_INSTALACIONES"
    fi

    echo ""
    echo -e "${CYAN}Estado actual de puertos:${NC}"
    ss -tlnp 2>/dev/null | grep -E ":(80|443|8080|8000|9090|8083|21) " | \
    while read -r linea; do echo "  $linea"; done

    echo ""
    echo -e "${CYAN}Estado de servicios (systemctl):${NC}"
    for SVC in httpd apache nginx tomcat tomcat9 vsftpd; do
        if systemctl list-units --type=service 2>/dev/null | grep -q "${SVC}.service"; then
            local ESTADO
            ESTADO=$(systemctl is-active "$SVC" 2>/dev/null)
            if [ "$ESTADO" = "active" ]; then
                echo -e "  ${GREEN}[ACTIVO]${NC}   $SVC"
            else
                echo -e "  ${RED}[INACTIVO]${NC} $SVC"
            fi
        fi
    done

    echo ""
    echo -e "${CYAN}Certificados SSL generados:${NC}"
    if [ -d "$SSL_DIR" ]; then
        find "$SSL_DIR" -name "*.crt" 2>/dev/null | while read -r cert; do
            local INFO
            INFO=$(openssl x509 -noout -subject -enddate -in "$cert" 2>/dev/null)
            echo "  Archivo: $cert"
            echo "$INFO" | while read -r l; do echo "    $l"; done
        done
    else
        echo "  (ninguno generado aun)"
    fi
    echo ""
}

# -----------------------------------------------------------------------------
# BLOQUE 10: FUNCION PRINCIPAL DE INSTALACION HIBRIDA
# -----------------------------------------------------------------------------

fn_instalar_servicio_hibrido() {
    local SERVICIO="$1"
    local NOMBRE_DISPLAY="$2"

    echo ""
    echo -e "${CYAN}====== INSTALACION DE ${NOMBRE_DISPLAY} ======${NC}"

    echo ""
    echo -e "${YELLOW}¿Desde donde deseas instalar ${NOMBRE_DISPLAY}?${NC}"
    echo "  [1] WEB - Repositorio urpmi (Mageia)"
    echo "  [2] FTP - Repositorio privado (${FTP_SERVER})"
    echo ""
    local ORIGEN=""
    while true; do
        read -r ORIGEN
        case "$ORIGEN" in
            1|2) break ;;
            *) fn_err "Elige 1 (WEB) o 2 (FTP)" ;;
        esac
    done

    echo ""
    echo -e "${YELLOW}Ingresa el puerto HTTP para ${NOMBRE_DISPLAY} (ej: 8080, 9090, 8083):${NC}"
    local PUERTO=""
    while true; do
        read -r PUERTO
        if [[ "$PUERTO" =~ ^[0-9]+$ ]] && [ "$PUERTO" -ge 1 ] && [ "$PUERTO" -le 65535 ]; then
            if ss -tlnp 2>/dev/null | grep -q ":${PUERTO} "; then
                fn_err "Puerto ${PUERTO} ya esta en uso. Elige otro."
            else
                fn_ok "Puerto ${PUERTO} disponible."
                break
            fi
        else
            fn_err "Puerto invalido. Debe ser entre 1 y 65535."
        fi
    done

    local SSL="no"
    fn_preguntar_ssl && SSL="si"

    # Variable global para el puerto SSL (se asigna dentro de fn_instalar_web_con_ssl)
    PUERTO_SSL_USADO="443"

    if [ "$ORIGEN" = "1" ]; then
        fn_instalar_web_con_ssl "$SERVICIO" "$PUERTO" "$SSL"
    else
        fn_ftp_navegar_y_descargar "$NOMBRE_DISPLAY" "$INSTALL_DIR" || return 1
        fn_verificar_hash "$FTP_ARCHIVO_DESCARGADO" "$FTP_SHA256_DESCARGADO" || return 1

        case "$SERVICIO" in
            apache) fn_instalar_apache_ftp "$FTP_ARCHIVO_DESCARGADO" "$PUERTO" "$SSL" ;;
            nginx)  fn_instalar_nginx_ftp  "$FTP_ARCHIVO_DESCARGADO" "$PUERTO" "$SSL" ;;
            tomcat) fn_instalar_tomcat_ftp "$FTP_ARCHIVO_DESCARGADO" "$PUERTO" "$SSL" ;;
        esac
    fi

    # Firewall
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="${PUERTO}/tcp" 2>/dev/null
        firewall-cmd --reload 2>/dev/null
        fn_ok "Firewall (firewalld) configurado para puerto ${PUERTO}"
    elif command -v iptables &>/dev/null; then
        iptables -I INPUT -p tcp --dport "$PUERTO" -j ACCEPT 2>/dev/null
        fn_ok "Firewall (iptables) configurado para puerto ${PUERTO}"
    fi

    sleep 2
    fn_verificar_servicio_http "$NOMBRE_DISPLAY" "$PUERTO" "$SSL" "$PUERTO_SSL_USADO"
}