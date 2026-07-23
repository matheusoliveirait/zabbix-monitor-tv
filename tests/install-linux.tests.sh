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
