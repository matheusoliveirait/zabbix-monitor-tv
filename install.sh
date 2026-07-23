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
INSTALL_ACTION="${CENTRAL_INCIDENTES_INSTALL_ACTION:-}"
RESET_DATABASE="${CENTRAL_INCIDENTES_RESET_DATABASE:-0}"
OPEN_FIREWALL="${CENTRAL_INCIDENTES_OPEN_FIREWALL:-0}"
TEST_MODE="${CENTRAL_INCIDENTES_TEST_MODE:-0}"
TEST_APT_UPDATE_OUTPUT="${CENTRAL_INCIDENTES_TEST_APT_UPDATE_OUTPUT:-}"
TEST_VALIDATE_OS="${CENTRAL_INCIDENTES_TEST_VALIDATE_OS:-0}"
OS_RELEASE_FILE="${CENTRAL_INCIDENTES_OS_RELEASE_FILE:-/etc/os-release}"
WORK_DIR=""
APT_WORK_DIR=""
POLICY_RC_CREATED=0
EXISTING_BACKUP=""
FILES_REPLACED=0
INSTALL_COMPLETED=0
PORT_REUSE=0
DB_NOTICE=""
WEB_CONFIG_PATH=""
WEB_CONFIG_BACKUP=""
WEB_CONFIG_CREATED=0
PORT_CONFIG_PATH=""
PORT_CONFIG_BACKUP=""
PORT_CONFIG_CREATED=0
APACHE_DEFAULT_DISABLED=0
NGINX_DEFAULT_TARGET=""
APACHE_SITE_ENABLED_BY_INSTALLER=0
NGINX_SITE_LINK_CREATED=0
APACHE_PORT_CONF_ENABLED_BY_INSTALLER=0

[[ -n "$PORT" ]] && PORT_EXPLICIT=1

cleanup() {
    if [[ "$INSTALL_COMPLETED" != "1" && "$FILES_REPLACED" == "1" ]]; then
        rm -rf -- "$INSTALL_DIR"
        if [[ -n "$EXISTING_BACKUP" && -d "$EXISTING_BACKUP" ]]; then
            warn "Restaurando os arquivos anteriores..."
            cp -a "$EXISTING_BACKUP" "$INSTALL_DIR"
        fi
    fi
    if [[ "$INSTALL_COMPLETED" != "1" ]]; then
        if [[ -n "$WEB_CONFIG_BACKUP" && -f "$WEB_CONFIG_BACKUP" ]]; then
            cp -a "$WEB_CONFIG_BACKUP" "$WEB_CONFIG_PATH"
        elif [[ "$WEB_CONFIG_CREATED" == "1" && -n "$WEB_CONFIG_PATH" ]]; then
            rm -f -- "$WEB_CONFIG_PATH"
        fi
        if [[ -n "$PORT_CONFIG_BACKUP" && -f "$PORT_CONFIG_BACKUP" ]]; then
            cp -a "$PORT_CONFIG_BACKUP" "$PORT_CONFIG_PATH"
        elif [[ "$PORT_CONFIG_CREATED" == "1" && -n "$PORT_CONFIG_PATH" ]]; then
            rm -f -- "$PORT_CONFIG_PATH"
        fi
        if [[ "$APACHE_DEFAULT_DISABLED" == "1" ]] && command -v a2ensite >/dev/null 2>&1; then
            a2ensite 000-default.conf >/dev/null 2>&1 || true
        fi
        if [[ "$APACHE_SITE_ENABLED_BY_INSTALLER" == "1" ]] && command -v a2dissite >/dev/null 2>&1; then
            a2dissite central-incidentes.conf >/dev/null 2>&1 || true
        fi
        if [[ "$APACHE_PORT_CONF_ENABLED_BY_INSTALLER" == "1" ]] && command -v a2disconf >/dev/null 2>&1; then
            a2disconf central-incidentes-port.conf >/dev/null 2>&1 || true
        fi
        if [[ "$NGINX_SITE_LINK_CREATED" == "1" ]]; then
            rm -f /etc/nginx/sites-enabled/central-incidentes
        fi
        if [[ -n "$NGINX_DEFAULT_TARGET" ]]; then
            ln -sfn "$NGINX_DEFAULT_TARGET" /etc/nginx/sites-enabled/default
        fi
        if [[ "$TEST_MODE" != "1" ]]; then
            systemctl reload apache2 >/dev/null 2>&1 || true
            systemctl reload nginx >/dev/null 2>&1 || true
        fi
    fi
    if [[ "$POLICY_RC_CREATED" == "1" ]]; then
        rm -f /usr/sbin/policy-rc.d
    fi
    if [[ -n "${WORK_DIR:-}" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
    if [[ -n "${APT_WORK_DIR:-}" ]]; then
        rm -rf -- "$APT_WORK_DIR"
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

apt_log_has_signature_error() {
    local log_file="$1"
    grep -Eqi \
        'NO_PUBKEY|EXPKEYSIG|BADSIG|GPG error:|signature verification|assinaturas?.*(não|nao).*verific|repository .* (is not signed|não está assinado|nao esta assinado)' \
        "$log_file"
}

show_apt_recovery() {
    printf '\n'
    warn "O APT precisa estar consistente antes que o painel possa instalar dependências."
    printf 'O instalador não desativa repositórios, importa chaves nem remove pacotes automaticamente.\n'
    printf 'Revise o diagnóstico acima e execute, nesta ordem:\n\n'
    printf '  sudo dpkg --configure -a\n'
    printf '  apt-mark showhold\n'
    printf '  sudo apt-get --fix-broken install\n'
    printf '  sudo apt-get update\n\n'
    printf 'Se houver erro de assinatura, corrija ou desative somente o repositório indicado,\n'
    printf 'seguindo a documentação oficial do fornecedor, e execute o instalador novamente.\n'
}

show_apt_state() {
    printf '\nEstado informado pelo dpkg:\n'
    dpkg --audit || true
    printf '\nPacotes marcados como retidos (hold):\n'
    local held_packages
    held_packages=$(apt-mark showhold 2>/dev/null || true)
    if [[ -n "$held_packages" ]]; then
        printf '%s\n' "$held_packages"
    else
        printf '  Nenhum pacote retido foi encontrado.\n'
    fi
}

validate_supported_linux() {
    [[ -r "$OS_RELEASE_FILE" ]] || fail "Não foi possível identificar a distribuição Linux."

    local distro_info
    distro_info=$(
        # O subshell impede que VERSION e outras variáveis do sistema
        # sobrescrevam as opções já carregadas pelo instalador.
        source "$OS_RELEASE_FILE"
        printf '%s\t%s\t%s' "${ID:-}" "${VERSION_ID:-}" "${PRETTY_NAME:-Linux}"
    )

    local distro_id=""
    local distro_version=""
    local distro_name=""
    IFS=$'\t' read -r distro_id distro_version distro_name <<< "$distro_info"
    distro_id=$(printf '%s' "$distro_id" | tr '[:upper:]' '[:lower:]')

    local minimum_major
    case "$distro_id" in
        linuxmint) minimum_major=21 ;;
        ubuntu) minimum_major=22 ;;
        debian) minimum_major=12 ;;
        *)
            fail "Use Linux Mint 21+, Ubuntu 22.04+ ou Debian 12+."
            ;;
    esac

    local distro_major="${distro_version%%.*}"
    [[ "$distro_major" =~ ^[0-9]+$ ]] ||
        fail "Não foi possível validar a versão de ${distro_name:-$distro_id}."

    if ((10#$distro_major < minimum_major)); then
        fail "${distro_name:-$distro_id} não é compatível: o painel exige PHP 8.1 ou superior. Use Linux Mint 21+, Ubuntu 22.04+ ou Debian 12+."
    fi
}

run_apt_preflight() {
    APT_WORK_DIR=$(mktemp -d)
    local update_log="$APT_WORK_DIR/update.log"
    local simulation_log="$APT_WORK_DIR/simulation.log"

    info "Validando os repositórios do sistema..."
    if [[ "$TEST_MODE" == "1" ]]; then
        printf '%s\n' "$TEST_APT_UPDATE_OUTPUT" > "$update_log"
    elif ! apt-get update 2>&1 | tee "$update_log"; then
        show_apt_recovery
        fail "Não foi possível atualizar a lista de pacotes."
    fi

    if apt_log_has_signature_error "$update_log"; then
        show_apt_recovery
        fail "Um ou mais repositórios possuem assinatura inválida ou chave pública ausente."
    fi

    [[ "$TEST_MODE" == "1" ]] && return

    info "Simulando a instalação das dependências..."
    if ! apt-get install --simulate "${COMMON_PACKAGES[@]}" 2>&1 | tee "$simulation_log"; then
        show_apt_state
        show_apt_recovery
        fail "O APT não conseguiu resolver as dependências. Nenhum pacote do painel foi instalado."
    fi
}

backup_config_file() {
    local path="$1"
    local kind="$2"
    local backup="$WORK_DIR/${kind}.backup"

    if [[ -f "$path" ]]; then
        cp -a "$path" "$backup"
        if [[ "$kind" == "web-config" ]]; then
            WEB_CONFIG_BACKUP="$backup"
        else
            PORT_CONFIG_BACKUP="$backup"
        fi
    elif [[ "$kind" == "web-config" ]]; then
        WEB_CONFIG_CREATED=1
    else
        PORT_CONFIG_CREATED=1
    fi
}

usage() {
    cat <<'EOF'
Uso: sudo ./install.sh [opções]

Instalação em um comando:
  (arquivo=$(mktemp) && trap 'rm -f "$arquivo"' EXIT && wget -qO "$arquivo" https://github.com/matheusoliveirait/zabbix-monitor-tv/releases/latest/download/install.sh && sudo bash "$arquivo")

  --apache             usar Apache
  --port PORTA         porta HTTP; detectada automaticamente quando omitida
  --nginx              usar Nginx
  --server-name NOME   domínio ou IP do painel
  --install-dir PASTA  diretório de instalação
  --version TAG        release específica, por exemplo v1.0.0
  --source PASTA       instalar arquivos locais em vez de baixar uma release
  --update              atualizar arquivos e preservar configuração e banco
  --replace             reinstalar os arquivos da pasta existente
  --reset-database      excluir o banco/usuário configurado e criar novos
  --open-firewall       liberar a porta no firewall da rede local
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
        --update) INSTALL_ACTION="update" ;;
        --replace) INSTALL_ACTION="replace" ;;
        --reset-database) RESET_DATABASE=1 ;;
        --open-firewall) OPEN_FIREWALL=1 ;;
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

if [[ "$TEST_MODE" == "1" ]]; then
    NON_INTERACTIVE=1
    CONFIGURE_LOCAL_DB=0
    OPEN_FIREWALL=0
    MAKE_DEFAULT=0
    [[ -n "$SOURCE_DIR" ]] || fail "O modo de teste exige --source."
else
    [[ "${EUID}" -eq 0 ]] || fail "Execute o instalador com sudo."
fi
if [[ "$TEST_MODE" != "1" || "$TEST_VALIDATE_OS" == "1" ]]; then
    validate_supported_linux
fi
if [[ "$TEST_MODE" != "1" ]]; then
    command -v apt-get >/dev/null 2>&1 || fail "O gerenciador de pacotes APT não foi encontrado."
fi
[[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || fail "Nome de banco inválido."
[[ "$DB_USER" =~ ^[A-Za-z0-9_]+$ ]] || fail "Usuário de banco inválido."
[[ "$SERVER_NAME" =~ ^[_A-Za-z0-9.-]+$ ]] || fail "Nome de servidor inválido."
[[ "$INSTALL_DIR" = /* && "$INSTALL_DIR" != "/" ]] || fail "Use um diretório absoluto de instalação."
[[ "$(dirname "$INSTALL_DIR")" != "/" ]] || fail "Use uma subpasta dedicada, não um diretório principal do sistema."
[[ "$INSTALL_ACTION" =~ ^(update|replace)?$ ]] || fail "Ação de instalação inválida."
if [[ "$INSTALL_ACTION" == "update" && "$RESET_DATABASE" == "1" ]]; then
    fail "--update preserva o banco e não pode ser combinado com --reset-database."
fi

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535))
}

port_in_use() {
    ss -H -ltn "sport = :$1" 2>/dev/null | grep -q .
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-no}"
    local suffix="[s/N]"
    [[ "$default" == "yes" ]] && suffix="[S/n]"
    printf '%s %s: ' "$prompt" "$suffix"
    read -r answer
    if [[ -z "${answer:-}" ]]; then
        [[ "$default" == "yes" ]]
    else
        [[ "$answer" =~ ^[SsYy]$ ]]
    fi
}

resolve_install_action() {
    local installed=0
    local populated=0

    if [[ -d "$INSTALL_DIR" ]]; then
        find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q . && populated=1
        if [[ -f "$INSTALL_DIR/config/app.php" || -f "$INSTALL_DIR/config/installed.lock" ]]; then
            installed=1
        fi
    fi

    if [[ "$populated" == "0" ]]; then
        INSTALL_ACTION="fresh"
        return
    fi
    if [[ "$INSTALL_ACTION" == "update" ]]; then
        [[ "$installed" == "1" ]] \
            || fail "A pasta existe, mas não contém uma instalação concluída para atualizar."
        return
    fi
    if [[ "$INSTALL_ACTION" == "replace" ]]; then
        return
    fi
    if [[ "$NON_INTERACTIVE" == "1" ]]; then
        fail "A pasta $INSTALL_DIR não está vazia. Use --update para preservar configuração e banco ou --replace para reinstalar os arquivos."
    fi

    printf '\n'
    warn "A pasta $INSTALL_DIR já contém arquivos."
    if [[ "$installed" == "1" ]]; then
        printf '  [1] Atualizar arquivos e preservar configuração e banco (recomendado)\n'
        printf '  [2] Reinstalar arquivos e abrir um novo wizard\n'
        printf '  [3] Cancelar\n'
        printf 'Escolha uma opção [1]: '
        read -r choice
        case "${choice:-1}" in
            1) INSTALL_ACTION="update" ;;
            2)
                ask_yes_no "Reinstalar os arquivos desta pasta?" "no" \
                    || fail "Reinstalação cancelada."
                INSTALL_ACTION="replace"
                ;;
            *) fail "Instalação cancelada; nenhum arquivo foi alterado." ;;
        esac
    else
        printf '  [1] Substituir o conteúdo da pasta\n'
        printf '  [2] Cancelar\n'
        printf 'Escolha uma opção [2]: '
        read -r choice
        if [[ "${choice:-2}" == "1" ]] \
            && ask_yes_no "Confirmar a substituição dos arquivos?" "no"; then
            INSTALL_ACTION="replace"
        else
            fail "Instalação cancelada; nenhum arquivo foi alterado."
        fi
    fi
}

detect_existing_port() {
    local config=""
    local detected=""
    if [[ "$PORT_EXPLICIT" != "0" ]]; then
        return 0
    fi
    if [[ "$INSTALL_ACTION" != "update" && "$INSTALL_ACTION" != "replace" ]]; then
        return 0
    fi

    if [[ "$WEB_SERVER" == "apache" ]]; then
        config="/etc/apache2/sites-available/central-incidentes.conf"
        [[ -f "$config" ]] && detected=$(sed -nE 's/.*<VirtualHost[^:]*:([0-9]+)>.*/\1/p' "$config" | head -n 1)
    else
        config="/etc/nginx/sites-available/central-incidentes"
        [[ -f "$config" ]] && detected=$(sed -nE 's/^[[:space:]]*listen[[:space:]]+([0-9]+).*/\1/p' "$config" | head -n 1)
    fi

    if [[ -n "$detected" ]]; then
        PORT="$detected"
        PORT_REUSE=1
    elif [[ "$INSTALL_ACTION" == "update" ]]; then
        fail "Não foi possível detectar a porta da instalação existente. Execute novamente com --port PORTA."
    fi
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
[[ ! -L "$INSTALL_DIR" ]] || fail "A pasta de instalação não pode ser um link simbólico."
resolve_install_action

if [[ "$NON_INTERACTIVE" != "1" ]]; then
    printf 'Usar o painel como site padrao da porta escolhida? [S/n]: '
    read -r answer
    [[ "${answer:-S}" =~ ^[Nn]$ ]] && MAKE_DEFAULT=0

    if [[ "$INSTALL_ACTION" != "update" ]]; then
        printf 'Preparar um banco MariaDB local automaticamente? [S/n]: '
        read -r answer
        [[ "${answer:-S}" =~ ^[Nn]$ ]] && CONFIGURE_LOCAL_DB=0
    fi
fi
[[ "$INSTALL_ACTION" == "update" ]] && CONFIGURE_LOCAL_DB=0

COMMON_PACKAGES=(iproute2 ca-certificates curl unzip wget openssl php-cli php-common php-mysql php-curl php-mbstring)
if [[ "$CONFIGURE_LOCAL_DB" == "1" ]]; then
    COMMON_PACKAGES+=(mariadb-server)
fi
if [[ "$WEB_SERVER" == "apache" ]]; then
    COMMON_PACKAGES+=(apache2 libapache2-mod-php)
else
    COMMON_PACKAGES+=(nginx php-fpm)
fi

if [[ "$TEST_MODE" != "1" || -n "$TEST_APT_UPDATE_OUTPUT" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    run_apt_preflight
fi

if [[ "$TEST_MODE" != "1" ]]; then
    info "Instalando a ferramenta de detecção de portas..."
    if ! apt-get install -y iproute2; then
        show_apt_state
        show_apt_recovery
        fail "Não foi possível instalar iproute2."
    fi
fi
detect_existing_port

if [[ -n "$PORT" ]]; then
    validate_port "$PORT" || fail "Porta invalida: $PORT. Use um numero entre 1 e 65535."
    [[ "$PORT" != "443" ]] || fail "A porta 443 exige HTTPS. Use outra porta HTTP e configure TLS em um proxy reverso."
    if [[ "$PORT_REUSE" != "1" ]] && port_in_use "$PORT"; then
        fail "A porta $PORT ja esta em uso. Execute novamente com --port PORTA."
    fi
else
    for candidate in 80 8080 8081 8888; do
        if ! port_in_use "$candidate"; then
            PORT="$candidate"
            break
        fi
    done
    [[ -n "$PORT" ]] || fail "As portas 80, 8080, 8081 e 8888 estao ocupadas. Escolha outra com --port PORTA."
fi

if [[ "$NON_INTERACTIVE" != "1" && "$PORT_EXPLICIT" == "0" ]]; then
    if ! ask_yes_no "Usar a porta HTTP $PORT?" "yes"; then
        while true; do
            printf 'Informe outra porta HTTP: '
            read -r candidate
            if ! validate_port "${candidate:-}" || [[ "$candidate" == "443" ]]; then
                warn "Informe uma porta HTTP entre 1 e 65535, exceto 443."
                continue
            fi
            if port_in_use "$candidate"; then
                warn "A porta $candidate ja esta em uso."
                continue
            fi
            PORT="$candidate"
            PORT_REUSE=0
            break
        done
    fi
fi

if [[ "$PORT_EXPLICIT" != "1" && "$PORT" != "80" ]]; then
    warn "O painel usará a porta $PORT."
fi

if [[ "$NON_INTERACTIVE" != "1" && "$OPEN_FIREWALL" != "1" ]]; then
    printf '\n'
    printf 'O painel ja funcionara neste servidor pela porta %s.\n' "$PORT"
    printf 'A liberacao abaixo permite acesso por outros dispositivos da rede local.\n'
    ask_yes_no "Liberar esta porta no firewall?" "no" && OPEN_FIREWALL=1
fi

if [[ "$TEST_MODE" != "1" ]]; then
    info "Instalando dependências..."

    # Evita que um servidor recém-instalado tente ocupar a porta 80 antes
    # de receber a configuração com a porta livre selecionada acima.
    if [[ ! -e /usr/sbin/policy-rc.d ]]; then
        printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
        chmod 0755 /usr/sbin/policy-rc.d
        POLICY_RC_CREATED=1
    fi

    if ! apt-get install -y "${COMMON_PACKAGES[@]}"; then
        show_apt_state
        show_apt_recovery
        fail "A instalação das dependências falhou."
    fi

    if [[ "$POLICY_RC_CREATED" == "1" ]]; then
        rm -f /usr/sbin/policy-rc.d
        POLICY_RC_CREATED=0
    fi
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

if [[ "$INSTALL_ACTION" == "update" ]]; then
    info "Atualizando arquivos em $INSTALL_DIR sem alterar o banco..."
else
    info "Instalando arquivos em $INSTALL_DIR..."
fi

if [[ -d "$INSTALL_DIR" ]] \
    && find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    EXISTING_BACKUP="$WORK_DIR/previous-install"
    cp -a "$INSTALL_DIR" "$EXISTING_BACKUP"
    rm -rf -- "$INSTALL_DIR"
    FILES_REPLACED=1
elif [[ -e "$INSTALL_DIR" ]]; then
    rm -rf -- "$INSTALL_DIR"
fi

FILES_REPLACED=1
install -d -m 0755 "$INSTALL_DIR"
cp -a "$STAGING"/. "$INSTALL_DIR"/
rm -f "$INSTALL_DIR/config/app.php" "$INSTALL_DIR/config/setup.php" "$INSTALL_DIR/config/installed.lock"

if [[ "$TEST_MODE" == "1" && "${CENTRAL_INCIDENTES_TEST_FAIL_AFTER_COPY:-0}" == "1" ]]; then
    fail "Falha simulada após a cópia dos arquivos."
fi

if [[ "$INSTALL_ACTION" == "update" ]]; then
    for local_config in config/app.php config/installed.lock; do
        if [[ -f "$EXISTING_BACKUP/$local_config" ]]; then
            install -D -m 0640 "$EXISTING_BACKUP/$local_config" "$INSTALL_DIR/$local_config"
        fi
    done
fi

if [[ "$TEST_MODE" == "1" ]]; then
    mkdir -p "$INSTALL_DIR/config"
else
    install -d -o www-data -g www-data -m 0750 "$INSTALL_DIR/config"
fi

DB_PASSWORD=""
DB_PREPARED=0
if [[ "$INSTALL_ACTION" != "update" && "$CONFIGURE_LOCAL_DB" == "1" ]]; then
    systemctl enable --now mariadb >/dev/null
    if EXISTING_STATE=$(mysql --protocol=socket -uroot --batch --skip-column-names \
        --execute="SELECT CONCAT(
            (SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$DB_NAME'),
            ':',
            (SELECT COUNT(*) FROM mysql.user WHERE User = '$DB_USER' AND Host IN ('localhost', '127.0.0.1'))
        );" 2>/dev/null); then
        SHOULD_CREATE=1
        if [[ "$EXISTING_STATE" != "0:0" && "$RESET_DATABASE" == "1" \
            && "$NON_INTERACTIVE" != "1" ]]; then
            printf '\nEsta ação apaga permanentemente todas as tabelas de %s.\n' "$DB_NAME"
            printf 'Digite EXCLUIR para confirmar: '
            read -r confirmation
            [[ "$confirmation" == "EXCLUIR" ]] \
                || fail "Exclusão do banco cancelada; nenhum dado foi removido."
        fi

        if [[ "$EXISTING_STATE" != "0:0" && "$RESET_DATABASE" != "1" ]]; then
            if [[ "$NON_INTERACTIVE" == "1" ]]; then
                SHOULD_CREATE=0
                DB_NOTICE="O banco ou usuário $DB_NAME já existe. Use Banco existente ou execute novamente com --reset-database para apagar esses dados."
                warn "$DB_NOTICE"
            else
                printf '\n'
                warn "O banco ou usuário '$DB_NAME' já existe."
                printf '  [1] Manter os dados e informar as credenciais no wizard (recomendado)\n'
                printf '  [2] Excluir o banco e o usuário para criar uma instalação limpa\n'
                printf '  [3] Cancelar\n'
                printf 'Escolha uma opção [1]: '
                read -r choice
                case "${choice:-1}" in
                    2)
                        printf '\nEsta ação apaga permanentemente todas as tabelas de %s.\n' "$DB_NAME"
                        printf 'Digite EXCLUIR para confirmar: '
                        read -r confirmation
                        [[ "$confirmation" == "EXCLUIR" ]] \
                            || fail "Exclusão do banco cancelada; nenhum dado foi removido."
                        RESET_DATABASE=1
                        ;;
                    3) fail "Instalação cancelada; nenhum dado foi removido." ;;
                    *)
                        SHOULD_CREATE=0
                        DB_NOTICE="O banco existente foi preservado. Use Banco existente e informe um usuário do MySQL ou MariaDB; não use o login do Zabbix ou do painel."
                        warn "$DB_NOTICE"
                        ;;
                esac
            fi
        fi

        if [[ "$SHOULD_CREATE" == "1" ]]; then
            if [[ "$RESET_DATABASE" == "1" ]]; then
                info "Excluindo somente o banco e o usuário confirmados..."
                mysql --protocol=socket -uroot <<SQL
DROP DATABASE IF EXISTS `$DB_NAME`;
DROP USER IF EXISTS '$DB_USER'@'localhost';
DROP USER IF EXISTS '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
            fi

            DB_PASSWORD=$(openssl rand -hex 24)
            info "Criando banco e usuário exclusivos..."
            if mysql --protocol=socket -uroot <<SQL
CREATE DATABASE `$DB_NAME` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON `$DB_NAME`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON `$DB_NAME`.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
            then
                DB_PREPARED=1
            else
                DB_PASSWORD=""
                DB_NOTICE="A criação automática do banco falhou. Use Banco existente e informe as credenciais do MySQL ou MariaDB."
                warn "$DB_NOTICE"
            fi
        fi
    else
        DB_NOTICE="O MariaDB usa credenciais administrativas próprias. Use Banco existente e informe um usuário do MySQL ou MariaDB."
        warn "$DB_NOTICE"
    fi
elif [[ "$INSTALL_ACTION" != "update" ]]; then
    DB_NOTICE="O banco automático não foi solicitado. Use Banco existente e informe uma conexão MySQL ou MariaDB."
fi

SETUP_TOKEN=""
if [[ "$INSTALL_ACTION" != "update" ]]; then
    SETUP_TOKEN=$(openssl rand -hex 8 | tr '[:lower:]' '[:upper:]' | sed 's/\(....\)/\1-/g')
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
    export CI_DB_NOTICE="$DB_NOTICE"

    php -r '
$config = [
    "token_hash" => getenv("CI_SETUP_HASH"),
    "expires_at" => (int)getenv("CI_SETUP_EXPIRES"),
    "version" => getenv("CI_SETUP_VERSION"),
];
if (getenv("CI_DB_NOTICE") !== "") {
    $config["database_notice"] = getenv("CI_DB_NOTICE");
}
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
fi

if [[ "$TEST_MODE" != "1" ]]; then
    find "$INSTALL_DIR" -type d -exec chmod 0755 {} +
    find "$INSTALL_DIR" -type f -exec chmod 0644 {} +
    chown -R root:www-data "$INSTALL_DIR"
    chown -R www-data:www-data "$INSTALL_DIR/config"
    chmod 0750 "$INSTALL_DIR/config"
    if [[ "$INSTALL_ACTION" == "update" ]]; then
        [[ -f "$INSTALL_DIR/config/app.php" ]] && chmod 0640 "$INSTALL_DIR/config/app.php"
        [[ -f "$INSTALL_DIR/config/installed.lock" ]] && chmod 0640 "$INSTALL_DIR/config/installed.lock"
    else
        chmod 0640 "$INSTALL_DIR/config/setup.php"
    fi
fi

configure_firewall() {
    if [[ "$TEST_MODE" == "1" ]]; then
        return
    fi
    if [[ "$OPEN_FIREWALL" != "1" ]]; then
        info "Firewall mantido sem alterações. O acesso local continua disponível."
        return
    fi

    local network
    network=$(ip -o -4 route show scope link 2>/dev/null \
        | awk '$1 ~ /\// && $1 !~ /^169\.254\./ {print $1; exit}')
    if [[ -z "$network" ]]; then
        warn "Não foi possível identificar a rede local. A porta não foi liberada automaticamente."
        return
    fi

    if command -v ufw >/dev/null 2>&1 \
        && LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active'; then
        if ufw allow from "$network" to any port "$PORT" proto tcp \
            comment 'Central de Incidentes' >/dev/null; then
            success "Porta $PORT liberada no UFW somente para $network."
        else
            warn "O UFW recusou a nova regra. O painel continua disponível localmente."
        fi
        return
    fi

    if command -v firewall-cmd >/dev/null 2>&1 \
        && systemctl is-active --quiet firewalld; then
        local zone
        zone=$(firewall-cmd --get-active-zones | awk 'NR == 1 {print $1}')
        [[ -n "$zone" ]] || zone="public"
        if firewall-cmd --permanent --zone="$zone" --add-port="$PORT/tcp" >/dev/null \
            && firewall-cmd --reload >/dev/null; then
            success "Porta $PORT liberada na zona $zone do firewalld."
        else
            warn "O firewalld recusou a nova regra. O painel continua disponível localmente."
        fi
        return
    fi

    warn "UFW e firewalld não estão ativos. Nenhuma regra de firewall foi alterada."
}

if [[ "$TEST_MODE" == "1" ]]; then
    info "Modo de teste: configuração do servidor web preservada."
elif [[ "$INSTALL_ACTION" == "update" ]]; then
    info "Configuração existente de $WEB_SERVER preservada."
elif [[ "$WEB_SERVER" == "apache" ]]; then
    CONFIG_PATH="/etc/apache2/sites-available/central-incidentes.conf"
    WEB_CONFIG_PATH="$CONFIG_PATH"
    backup_config_file "$CONFIG_PATH" "web-config"
    sed \
        -e "s|{{SERVER_NAME}}|$SERVER_NAME|g" \
        -e "s|{{PORT}}|$PORT|g" \
        -e "s|{{INSTALL_DIR}}|$INSTALL_DIR|g" \
        "$INSTALL_DIR/deploy/apache-vhost.conf" > "$CONFIG_PATH"

    if ! grep -RqsE "^[[:space:]]*Listen[[:space:]]+$PORT([[:space:]]|$)" \
        /etc/apache2/ports.conf /etc/apache2/conf-enabled 2>/dev/null; then
        PORT_CONFIG_PATH="/etc/apache2/conf-available/central-incidentes-port.conf"
        backup_config_file "$PORT_CONFIG_PATH" "port-config"
        printf 'Listen %s\n' "$PORT" > "$PORT_CONFIG_PATH"
        if ! a2query -c central-incidentes-port >/dev/null 2>&1; then
            APACHE_PORT_CONF_ENABLED_BY_INSTALLER=1
        fi
        a2enconf central-incidentes-port.conf >/dev/null
    fi

    a2enmod rewrite >/dev/null
    if ! a2query -s central-incidentes >/dev/null 2>&1; then
        APACHE_SITE_ENABLED_BY_INSTALLER=1
    fi
    a2ensite central-incidentes.conf >/dev/null
    if [[ "$MAKE_DEFAULT" == "1" && "$PORT" == "80" ]]; then
        if a2query -s 000-default >/dev/null 2>&1; then
            APACHE_DEFAULT_DISABLED=1
        fi
        a2dissite 000-default.conf >/dev/null 2>&1 || true
    fi
    apache2ctl configtest
    systemctl enable --now apache2 >/dev/null
    systemctl reload apache2
else
    PHP_FPM_SOCKET=$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' | sort -V | tail -n 1)
    [[ -n "$PHP_FPM_SOCKET" ]] || fail "O socket do PHP-FPM não foi encontrado."

    CONFIG_PATH="/etc/nginx/sites-available/central-incidentes"
    WEB_CONFIG_PATH="$CONFIG_PATH"
    backup_config_file "$CONFIG_PATH" "web-config"
    sed \
        -e "s|{{SERVER_NAME}}|$SERVER_NAME|g" \
        -e "s|{{PORT}}|$PORT|g" \
        -e "s|{{INSTALL_DIR}}|$INSTALL_DIR|g" \
        -e "s|{{PHP_FPM_SOCKET}}|$PHP_FPM_SOCKET|g" \
        "$INSTALL_DIR/deploy/nginx-server.conf" > "$CONFIG_PATH"

    if [[ "$MAKE_DEFAULT" != "1" ]]; then
        sed -i 's/ default_server//g' "$CONFIG_PATH"
    elif [[ "$PORT" == "80" ]]; then
        if [[ -L /etc/nginx/sites-enabled/default ]]; then
            NGINX_DEFAULT_TARGET=$(readlink /etc/nginx/sites-enabled/default)
        fi
        rm -f /etc/nginx/sites-enabled/default
    fi
    if [[ ! -e /etc/nginx/sites-enabled/central-incidentes ]]; then
        NGINX_SITE_LINK_CREATED=1
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

configure_firewall
INSTALL_COMPLETED=1

if [[ "$INSTALL_ACTION" == "update" ]]; then
    success "Atualização concluída com sucesso."
    printf '\n'
    if [[ "$PORT" == "80" ]]; then
        printf '  Acesse:  http://%s/\n' "$DISPLAY_HOST"
    else
        printf '  Acesse:  http://%s:%s/\n' "$DISPLAY_HOST" "$PORT"
    fi
    printf '\nA configuração e o banco foram preservados.\n'
    exit 0
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
