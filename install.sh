#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY="matheusoliveirait/zabbix-monitor-tv"
INSTALL_DIR="${CENTRAL_INCIDENTES_DIR:-/var/www/central-incidentes}"
VERSION="${CENTRAL_INCIDENTES_VERSION:-latest}"
WEB_SERVER="${CENTRAL_INCIDENTES_WEB_SERVER:-}"
SERVER_NAME="${CENTRAL_INCIDENTES_SERVER_NAME:-_}"
PORT="${CENTRAL_INCIDENTES_PORT:-}"
PORT_EXPLICIT=0
SOURCE_DIR=""
NON_INTERACTIVE="${CENTRAL_INCIDENTES_NON_INTERACTIVE:-0}"
MAKE_DEFAULT="${CENTRAL_INCIDENTES_DEFAULT_SITE:-1}"
CONFIGURE_LOCAL_DB="${CENTRAL_INCIDENTES_LOCAL_DB:-1}"
DB_NAME="${CENTRAL_INCIDENTES_DB_NAME:-central_incidentes}"
DB_USER="${CENTRAL_INCIDENTES_DB_USER:-central_incidentes}"
WORK_DIR=""
POLICY_RC_CREATED=0

[[ -n "$PORT" ]] && PORT_EXPLICIT=1

cleanup() {
    if [[ "$POLICY_RC_CREATED" == "1" ]]; then
        rm -f /usr/sbin/policy-rc.d
    fi
    if [[ -n "${WORK_DIR:-}" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
}

trap cleanup EXIT

info() {
    printf '\033[1;36m%s\033[0m\n' "$1"
}

success() {
    printf '\033[1;32m%s\033[0m\n' "$1"
}

warn() {
    printf '\033[1;33mAviso: %s\033[0m\n' "$1" >&2
}

fail() {
    printf '\033[1;31mErro: %s\033[0m\n' "$1" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Uso: sudo ./install.sh [opções]

Instalação em um comando:
  wget -qO /tmp/central-incidentes-install.sh https://github.com/matheusoliveirait/zabbix-monitor-tv/releases/latest/download/install.sh && sudo bash /tmp/central-incidentes-install.sh

  --apache             usar Apache
  --port PORTA         porta HTTP; detectada automaticamente quando omitida
  --nginx              usar Nginx
  --server-name NOME   domínio ou IP do painel
  --install-dir PASTA  diretório de instalação
  --version TAG        release específica, por exemplo v1.0.0
  --source PASTA       instalar arquivos locais em vez de baixar uma release
  --non-interactive    aceitar opções fornecidas por parâmetros/ambiente
  --no-local-db        não criar banco MariaDB local
  --no-default-site    não substituir o site padrão da porta 80
  --help               mostrar esta ajuda
EOF
}

while (($#)); do
    case "$1" in
        --apache) WEB_SERVER="apache" ;;
        --nginx) WEB_SERVER="nginx" ;;
        --server-name)
            shift
            SERVER_NAME="${1:-}"
            ;;
        --port)
            shift
            PORT="${1:-}"
            PORT_EXPLICIT=1
            ;;
        --install-dir)
            shift
            INSTALL_DIR="${1:-}"
            ;;
        --version)
            shift
            VERSION="${1:-}"
            ;;
        --source)
            shift
            SOURCE_DIR="${1:-}"
            ;;
        --non-interactive) NON_INTERACTIVE=1 ;;
        --no-local-db) CONFIGURE_LOCAL_DB=0 ;;
        --no-default-site) MAKE_DEFAULT=0 ;;
        --help)
            usage
            exit 0
            ;;
        *) fail "Opção desconhecida: $1" ;;
    esac
    shift
done

[[ "${EUID}" -eq 0 ]] || fail "Execute o instalador com sudo."
command -v apt-get >/dev/null 2>&1 || fail "Esta versão oferece suporte a Ubuntu e Debian."
[[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || fail "Nome de banco inválido."
[[ "$DB_USER" =~ ^[A-Za-z0-9_]+$ ]] || fail "Usuário de banco inválido."
[[ "$SERVER_NAME" =~ ^[_A-Za-z0-9.-]+$ ]] || fail "Nome de servidor inválido."
[[ "$INSTALL_DIR" = /* && "$INSTALL_DIR" != "/" ]] || fail "Use um diretório absoluto de instalação."

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535))
}

port_in_use() {
    ss -H -ltn "sport = :$1" 2>/dev/null | grep -q .
}

if [[ -z "$WEB_SERVER" ]]; then
    if [[ "$NON_INTERACTIVE" == "1" ]]; then
        WEB_SERVER="apache"
    else
        printf 'Servidor web [1=Apache, 2=Nginx] (1): '
        read -r choice
        WEB_SERVER=$([[ "${choice:-1}" == "2" ]] && echo nginx || echo apache)
    fi
fi
[[ "$WEB_SERVER" == "apache" || "$WEB_SERVER" == "nginx" ]] || fail "Escolha apache ou nginx."

if [[ -f "$INSTALL_DIR/config/installed.lock" || -f "$INSTALL_DIR/config/app.php" ]]; then
    fail "Já existe uma instalação em $INSTALL_DIR. O instalador inicial não faz atualizações."
fi

if [[ "$NON_INTERACTIVE" != "1" ]]; then
    printf 'Usar o painel como site padrao da porta escolhida? [S/n]: '
    read -r answer
    [[ "${answer:-S}" =~ ^[Nn]$ ]] && MAKE_DEFAULT=0

    printf 'Preparar um banco MariaDB local automaticamente? [S/n]: '
    read -r answer
    [[ "${answer:-S}" =~ ^[Nn]$ ]] && CONFIGURE_LOCAL_DB=0
fi

export DEBIAN_FRONTEND=noninteractive
info "Atualizando a lista de pacotes..."
apt-get update -qq

apt-get install -y -qq iproute2

if [[ -n "$PORT" ]]; then
    validate_port "$PORT" || fail "Porta invalida: $PORT. Use um numero entre 1 e 65535."
    [[ "$PORT" != "443" ]] || fail "A porta 443 exige HTTPS. Use outra porta HTTP e configure TLS em um proxy reverso."
    port_in_use "$PORT" && fail "A porta $PORT ja esta em uso. Execute novamente com --port PORTA."
else
    for candidate in 80 8080 8081 8888; do
        if ! port_in_use "$candidate"; then
            PORT="$candidate"
            break
        fi
    done
    [[ -n "$PORT" ]] || fail "As portas 80, 8080, 8081 e 8888 estao ocupadas. Escolha outra com --port PORTA."
fi

if [[ "$PORT_EXPLICIT" != "1" && "$PORT" != "80" ]]; then
    warn "A porta 80 esta ocupada; o painel usara automaticamente a porta $PORT."
fi

COMMON_PACKAGES=(ca-certificates curl unzip wget openssl php-cli php-common php-mysql php-curl php-mbstring)
if [[ "$CONFIGURE_LOCAL_DB" == "1" ]]; then
    COMMON_PACKAGES+=(mariadb-server)
fi
if [[ "$WEB_SERVER" == "apache" ]]; then
    COMMON_PACKAGES+=(apache2 libapache2-mod-php)
else
    COMMON_PACKAGES+=(nginx php-fpm)
fi

info "Instalando dependências..."

# Evita que um servidor recém-instalado tente ocupar a porta 80 antes
# de receber a configuração com a porta livre selecionada acima.
if [[ ! -e /usr/sbin/policy-rc.d ]]; then
    printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
    chmod 0755 /usr/sbin/policy-rc.d
    POLICY_RC_CREATED=1
fi

apt-get install -y -qq "${COMMON_PACKAGES[@]}"

if [[ "$POLICY_RC_CREATED" == "1" ]]; then
    rm -f /usr/sbin/policy-rc.d
    POLICY_RC_CREATED=0
fi

PHP_VERSION_ID=$(php -r 'echo PHP_VERSION_ID;')
((PHP_VERSION_ID >= 80100)) || fail "PHP 8.1 ou superior é obrigatório."

WORK_DIR=$(mktemp -d)
STAGING="$WORK_DIR/app"
mkdir -p "$STAGING"

if [[ -n "$SOURCE_DIR" ]]; then
    SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd)
    [[ -f "$SOURCE_DIR/index.php" && -d "$SOURCE_DIR/setup" ]] || fail "A origem local não contém o projeto completo."
    info "Copiando arquivos da origem local..."
    tar -C "$SOURCE_DIR" \
        --exclude=.git \
        --exclude=work \
        --exclude=outputs \
        --exclude=backups \
        --exclude=config/app.php \
        --exclude=config/setup.php \
        --exclude=config/installed.lock \
        -cf - . | tar -C "$STAGING" -xf -
else
    if [[ "$VERSION" == "latest" ]]; then
        BASE_URL="https://github.com/$REPOSITORY/releases/latest/download"
    else
        BASE_URL="https://github.com/$REPOSITORY/releases/download/$VERSION"
    fi
    ARCHIVE_URL="${CENTRAL_INCIDENTES_DOWNLOAD_URL:-$BASE_URL/central-incidentes.zip}"
    CHECKSUM_URL="${CENTRAL_INCIDENTES_CHECKSUM_URL:-$BASE_URL/central-incidentes.zip.sha256}"

    info "Baixando a versão $VERSION pelo GitHub Releases..."
    wget -q --show-progress -O "$WORK_DIR/central-incidentes.zip" "$ARCHIVE_URL"
    wget -q -O "$WORK_DIR/central-incidentes.zip.sha256" "$CHECKSUM_URL" \
        || fail "Não foi possível baixar o checksum da release."

    (
        cd "$WORK_DIR"
        sha256sum --check central-incidentes.zip.sha256
    ) || fail "O pacote baixado não passou na verificação SHA-256."

    unzip -q "$WORK_DIR/central-incidentes.zip" -d "$STAGING"
fi

[[ -f "$STAGING/index.php" && -f "$STAGING/setup/index.php" ]] \
    || fail "O pacote baixado não possui a estrutura esperada."

info "Instalando arquivos em $INSTALL_DIR..."
install -d -m 0755 "$INSTALL_DIR"
cp -a "$STAGING"/. "$INSTALL_DIR"/
rm -f "$INSTALL_DIR/config/app.php" "$INSTALL_DIR/config/setup.php" "$INSTALL_DIR/config/installed.lock"
install -d -o www-data -g www-data -m 0750 "$INSTALL_DIR/config"

DB_PASSWORD=""
DB_PREPARED=0
if [[ "$CONFIGURE_LOCAL_DB" == "1" ]]; then
    systemctl enable --now mariadb >/dev/null
    DB_PASSWORD=$(openssl rand -hex 24)

    info "Criando banco e usuário exclusivos..."
    if mysql --protocol=socket -uroot <<SQL
CREATE DATABASE IF NOT EXISTS `$DB_NAME` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON `$DB_NAME`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL
    then
        DB_PREPARED=1
    else
        DB_PASSWORD=""
        warn "O MariaDB está protegido por credenciais próprias. O banco será informado no wizard."
    fi
fi

SETUP_TOKEN=$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]' | sed 's/\(....\)/\1-/')
SETUP_TOKEN="${SETUP_TOKEN%-}"
SETUP_HASH=$(printf '%s' "$SETUP_TOKEN" | sha256sum | awk '{print $1}')
EXPIRES_AT=$(( $(date +%s) + 7200 ))
export CI_SETUP_HASH="$SETUP_HASH"
export CI_SETUP_EXPIRES="$EXPIRES_AT"
export CI_SETUP_VERSION="$VERSION"
export CI_DB_PREPARED="$DB_PREPARED"
export CI_DB_NAME="$DB_NAME"
export CI_DB_USER="$DB_USER"
export CI_DB_PASSWORD="$DB_PASSWORD"

php -r '
$config = [
    "token_hash" => getenv("CI_SETUP_HASH"),
    "expires_at" => (int)getenv("CI_SETUP_EXPIRES"),
    "version" => getenv("CI_SETUP_VERSION"),
];
if (getenv("CI_DB_PREPARED") === "1") {
    $config["prepared_db"] = [
        "host" => "127.0.0.1",
        "port" => 3306,
        "database" => getenv("CI_DB_NAME"),
        "username" => getenv("CI_DB_USER"),
        "password" => getenv("CI_DB_PASSWORD"),
        "charset" => "utf8mb4",
    ];
}
$content = "<?php\n\ndeclare(strict_types=1);\n\nreturn " . var_export($config, true) . ";\n";
if (file_put_contents($argv[1], $content, LOCK_EX) === false) {
    fwrite(STDERR, "Falha ao criar config/setup.php\n");
    exit(1);
}
' "$INSTALL_DIR/config/setup.php"

chown -R root:www-data "$INSTALL_DIR"
find "$INSTALL_DIR" -type d -exec chmod 0755 {} +
find "$INSTALL_DIR" -type f -exec chmod 0644 {} +
chown -R www-data:www-data "$INSTALL_DIR/config"
chmod 0750 "$INSTALL_DIR/config"
chmod 0640 "$INSTALL_DIR/config/setup.php"

if [[ "$WEB_SERVER" == "apache" ]]; then
    CONFIG_PATH="/etc/apache2/sites-available/central-incidentes.conf"
    sed \
        -e "s|{{SERVER_NAME}}|$SERVER_NAME|g" \
        -e "s|{{PORT}}|$PORT|g" \
        -e "s|{{INSTALL_DIR}}|$INSTALL_DIR|g" \
        "$INSTALL_DIR/deploy/apache-vhost.conf" > "$CONFIG_PATH"

    if ! grep -RqsE "^[[:space:]]*Listen[[:space:]]+$PORT([[:space:]]|$)" \
        /etc/apache2/ports.conf /etc/apache2/conf-enabled 2>/dev/null; then
        printf 'Listen %s\n' "$PORT" > /etc/apache2/conf-available/central-incidentes-port.conf
        a2enconf central-incidentes-port.conf >/dev/null
    fi

    a2enmod rewrite >/dev/null
    a2ensite central-incidentes.conf >/dev/null
    if [[ "$MAKE_DEFAULT" == "1" && "$PORT" == "80" ]]; then
        a2dissite 000-default.conf >/dev/null 2>&1 || true
    fi
    apache2ctl configtest
    systemctl enable --now apache2 >/dev/null
    systemctl reload apache2
else
    PHP_FPM_SOCKET=$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' | sort -V | tail -n 1)
    [[ -n "$PHP_FPM_SOCKET" ]] || fail "O socket do PHP-FPM não foi encontrado."

    CONFIG_PATH="/etc/nginx/sites-available/central-incidentes"
    sed \
        -e "s|{{SERVER_NAME}}|$SERVER_NAME|g" \
        -e "s|{{PORT}}|$PORT|g" \
        -e "s|{{INSTALL_DIR}}|$INSTALL_DIR|g" \
        -e "s|{{PHP_FPM_SOCKET}}|$PHP_FPM_SOCKET|g" \
        "$INSTALL_DIR/deploy/nginx-server.conf" > "$CONFIG_PATH"

    if [[ "$MAKE_DEFAULT" != "1" ]]; then
        sed -i 's/ default_server//g' "$CONFIG_PATH"
    elif [[ "$PORT" == "80" ]]; then
        rm -f /etc/nginx/sites-enabled/default
    fi
    ln -sfn "$CONFIG_PATH" /etc/nginx/sites-enabled/central-incidentes
    nginx -t
    systemctl enable --now nginx >/dev/null
    systemctl reload nginx
fi

if [[ "$SERVER_NAME" == "_" ]]; then
    DISPLAY_HOST=$(hostname -I 2>/dev/null | awk '{print $1}')
    DISPLAY_HOST="${DISPLAY_HOST:-localhost}"
else
    DISPLAY_HOST="$SERVER_NAME"
fi

success "Servidor preparado com sucesso."
printf '\n'
if [[ "$PORT" == "80" ]]; then
    printf '  Acesse:  http://%s/setup/\n' "$DISPLAY_HOST"
else
    printf '  Acesse:  http://%s:%s/setup/\n' "$DISPLAY_HOST" "$PORT"
fi
printf '  Código:  %s\n' "$SETUP_TOKEN"
printf '\n'
printf 'O código expira em 2 horas e será removido quando a instalação terminar.\n'
