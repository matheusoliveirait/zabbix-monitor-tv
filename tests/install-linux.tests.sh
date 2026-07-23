#!/usr/bin/env bash
set -Eeuo pipefail

assert_file() {
    [[ -f "$1" ]] || {
        printf 'Falha: arquivo ausente: %s\n' "$1" >&2
        exit 1
    }
}

assert_missing() {
    [[ ! -e "$1" ]] || {
        printf 'Falha: caminho deveria estar ausente: %s\n' "$1" >&2
        exit 1
    }
}

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMP_ROOT=$(mktemp -d)
INSTALL_DIR="$TEMP_ROOT/central-incidentes"
PORT=$(php -r '
$socket = stream_socket_server("tcp://127.0.0.1:0", $code, $message);
$address = stream_socket_get_name($socket, false);
echo substr(strrchr($address, ":"), 1);
fclose($socket);
')

cleanup() {
    rm -rf -- "$TEMP_ROOT"
}
trap cleanup EXIT

run_installer() {
    CENTRAL_INCIDENTES_TEST_MODE=1 bash "$ROOT/install.sh" \
        --apache \
        --source "$ROOT" \
        --install-dir "$INSTALL_DIR" \
        --server-name localhost \
        --port "$PORT" \
        --non-interactive \
        "$@"
}

if CENTRAL_INCIDENTES_TEST_APT_UPDATE_OUTPUT='W: GPG error: https://example.invalid stable InRelease: NO_PUBKEY 0123456789ABCDEF' \
    run_installer 2>/dev/null; then
    printf 'Falha: repositório sem chave pública deveria interromper a instalação.\n' >&2
    exit 1
fi
assert_missing "$INSTALL_DIR"

if CENTRAL_INCIDENTES_TEST_APT_UPDATE_OUTPUT='Hit: repositories available' \
    CENTRAL_INCIDENTES_TEST_APT_SIMULATION_OUTPUT=$'The following packages will be REMOVED:\n  mysql-server\nRemv mysql-server [8.0]' \
    run_installer >"$TEMP_ROOT/package-removal.log" 2>&1; then
    printf 'Falha: uma simulação com remoção de pacotes deveria ser recusada.\n' >&2
    exit 1
fi
grep -q 'exigiria remover pacotes existentes' "$TEMP_ROOT/package-removal.log"
assert_missing "$INSTALL_DIR"

if grep -Fq '`$DB_NAME`' "$ROOT/install.sh"; then
    printf 'Falha: o identificador do banco não pode executar substituição de comando no shell.\n' >&2
    exit 1
fi
grep -q 'Senha do usuário root do %s (não será armazenada)' "$ROOT/install.sh"
grep -q 'Excluir e recriar somente o banco e o usuário do painel' "$ROOT/install.sh"
grep -Fq 'MYSQL_PWD="$MYSQL_ADMIN_PASSWORD" timeout' "$ROOT/install.sh"
grep -q 'Foi encontrada uma pasta residual não registrada pelo banco' "$ROOT/install.sh"
grep -Fq '/var/backups/central-incidentes' "$ROOT/install.sh"
grep -q 'archive_orphan_database_dir' "$ROOT/install.sh"
grep -Fq '[[ "$ORPHAN_DB_DIR" == "1" ]] || return 0' "$ROOT/install.sh"
grep -q 'Corrigir somente a pasta principal' "$ROOT/install.sh"
grep -q 'Permissão da pasta principal do banco corrigida sem alterar seu conteúdo' "$ROOT/install.sh"
if grep -Eq 'chown .*(-R|--recursive).*DB_DATA_DIR' "$ROOT/install.sh"; then
    printf 'Falha: o instalador não pode alterar recursivamente o diretório do banco.\n' >&2
    exit 1
fi
grep -q 'Continuar sem banco preparado e informar credenciais no wizard' "$ROOT/install.sh"
grep -q 'Servidor .* existente detectado; o banco do painel será verificado separadamente' "$ROOT/install.sh"
grep -q "Escolha como tratar o banco.*nesta reinstalação" "$ROOT/install.sh"
grep -q 'Excluir qualquer banco e usuário do painel e criar uma instalação limpa' "$ROOT/install.sh"
grep -q 'Limpar somente os recursos do painel, corrigir o acesso e tentar novamente' "$ROOT/install.sh"
grep -q 'repair_database_security_controls' "$ROOT/install.sh"
grep -q 'find_apparmor_profile_file' "$ROOT/install.sh"
grep -q 'acesso completo ao diretório de dados' "$ROOT/install.sh"
grep -q 'Perfil correto do AppArmor aplicado e serviço do banco reiniciado' "$ROOT/install.sh"
grep -q 'show_database_access_diagnostics' "$ROOT/install.sh"
grep -q 'show_database_service_diagnostics' "$ROOT/install.sh"
grep -q 'run_database_systemctl enable --now' "$ROOT/install.sh"
grep -q 'Testando o acesso administrativo' "$ROOT/install.sh"
grep -q 'CENTRAL_INCIDENTES_DB_SERVICE_TIMEOUT' "$ROOT/install.sh"
grep -q 'CENTRAL_INCIDENTES_DB_COMMAND_TIMEOUT' "$ROOT/install.sh"
grep -q 'journalctl -u.*LOCAL_DB_SERVICE' "$ROOT/install.sh"
grep -q 'central-incidentes-write-test' "$ROOT/install.sh"
if grep -Eq 'chmod +0?777' "$ROOT/install.sh"; then
    printf 'Falha: o instalador não pode liberar permissões globais no sistema.\n' >&2
    exit 1
fi

MINT_20_OS_RELEASE="$TEMP_ROOT/mint-20-os-release"
printf 'ID=linuxmint\nVERSION_ID="20.3"\nPRETTY_NAME="Linux Mint 20.3"\n' > "$MINT_20_OS_RELEASE"
if CENTRAL_INCIDENTES_TEST_VALIDATE_OS=1 \
    CENTRAL_INCIDENTES_OS_RELEASE_FILE="$MINT_20_OS_RELEASE" \
    run_installer >"$TEMP_ROOT/mint-20.log" 2>&1; then
    printf 'Falha: Linux Mint 20.3 deveria ser recusado.\n' >&2
    exit 1
fi
grep -q 'Linux Mint 20.3 não é compatível' "$TEMP_ROOT/mint-20.log"
assert_missing "$INSTALL_DIR"

MINT_21_OS_RELEASE="$TEMP_ROOT/mint-21-os-release"
printf 'ID=linuxmint\nVERSION_ID="21.3"\nPRETTY_NAME="Linux Mint 21.3"\n' > "$MINT_21_OS_RELEASE"
CENTRAL_INCIDENTES_TEST_VALIDATE_OS=1 \
    CENTRAL_INCIDENTES_OS_RELEASE_FILE="$MINT_21_OS_RELEASE" \
    run_installer
assert_file "$INSTALL_DIR/index.php"
assert_file "$INSTALL_DIR/setup/index.php"
assert_file "$INSTALL_DIR/config/setup.php"
grep -q "'database_notice' =>" "$INSTALL_DIR/config/setup.php"

if run_installer 2>/dev/null; then
    printf 'Falha: pasta preenchida sem ação explícita deveria ser recusada.\n' >&2
    exit 1
fi
assert_file "$INSTALL_DIR/index.php"

printf "<?php return ['marker' => 'preserved'];\n" > "$INSTALL_DIR/config/app.php"
printf 'installed\n' > "$INSTALL_DIR/config/installed.lock"
printf 'obsolete\n' > "$INSTALL_DIR/obsolete.txt"
rm -f "$INSTALL_DIR/config/setup.php"

if CENTRAL_INCIDENTES_TEST_FAIL_AFTER_COPY=1 run_installer --replace 2>/dev/null; then
    printf 'Falha: substituição simulada deveria falhar.\n' >&2
    exit 1
fi
grep -q "preserved" "$INSTALL_DIR/config/app.php"
assert_file "$INSTALL_DIR/config/installed.lock"

run_installer --update
grep -q "preserved" "$INSTALL_DIR/config/app.php"
assert_file "$INSTALL_DIR/config/installed.lock"
assert_missing "$INSTALL_DIR/obsolete.txt"
assert_missing "$INSTALL_DIR/config/setup.php"

run_installer --replace
assert_missing "$INSTALL_DIR/config/app.php"
assert_missing "$INSTALL_DIR/config/installed.lock"
assert_file "$INSTALL_DIR/config/setup.php"

printf 'Linux installer tests: OK\n'
