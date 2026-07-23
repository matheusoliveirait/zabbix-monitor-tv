<?php

declare(strict_types=1);

error_reporting(E_ALL);
ini_set('display_errors', '0');

const SETUP_ROOT = __DIR__ . '/..';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'");

function setup_response(array $payload, int $status = 200): never
{
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function setup_error(string $message, int $status = 400): never
{
    setup_response(['ok' => false, 'error' => $message], $status);
}

function setup_input(): array
{
    $raw = file_get_contents('php://input') ?: '';
    $input = json_decode($raw, true);

    if (!is_array($input)) {
        setup_error('Requisição inválida.', 400);
    }

    return $input;
}

function setup_session(): void
{
    if (session_status() === PHP_SESSION_ACTIVE) {
        return;
    }

    $secure = (!empty($_SERVER['HTTPS']) && strtolower((string)$_SERVER['HTTPS']) !== 'off')
        || (int)($_SERVER['SERVER_PORT'] ?? 0) === 443;
    $script = str_replace('\\', '/', (string)($_SERVER['SCRIPT_NAME'] ?? '/setup/api.php'));
    $basePath = str_replace('\\', '/', dirname(dirname($script)));
    $basePath = $basePath === '.' ? '/' : rtrim($basePath, '/') . '/';

    ini_set('session.use_strict_mode', '1');
    session_name('central_incidentes_setup');
    session_set_cookie_params([
        'lifetime' => 0,
        'path' => $basePath,
        'secure' => $secure,
        'httponly' => true,
        'samesite' => 'Strict',
    ]);
    session_start();

    if (empty($_SESSION['setup_csrf'])) {
        $_SESSION['setup_csrf'] = bin2hex(random_bytes(24));
    }
}

function setup_file(): string
{
    return SETUP_ROOT . '/config/setup.php';
}

function app_file(): string
{
    return SETUP_ROOT . '/config/app.php';
}

function lock_file(): string
{
    return SETUP_ROOT . '/config/installed.lock';
}

function setup_definition(): ?array
{
    $path = setup_file();
    if (!is_file($path)) {
        return null;
    }

    $config = require $path;
    return is_array($config) ? $config : null;
}

function setup_is_installed(): bool
{
    return is_file(app_file()) && !is_file(setup_file());
}

function setup_requirements(): array
{
    $checks = [
        ['label' => 'PHP 8.1 ou superior', 'ok' => PHP_VERSION_ID >= 80100, 'value' => PHP_VERSION],
        ['label' => 'Extensão PDO', 'ok' => extension_loaded('pdo'), 'value' => extension_loaded('pdo') ? 'Disponível' : 'Ausente'],
        ['label' => 'Driver PDO MySQL', 'ok' => extension_loaded('pdo_mysql'), 'value' => extension_loaded('pdo_mysql') ? 'Disponível' : 'Ausente'],
        ['label' => 'Extensão cURL', 'ok' => extension_loaded('curl'), 'value' => extension_loaded('curl') ? 'Disponível' : 'Ausente'],
        ['label' => 'Extensão OpenSSL', 'ok' => extension_loaded('openssl'), 'value' => extension_loaded('openssl') ? 'Disponível' : 'Ausente'],
        ['label' => 'Pasta config gravável', 'ok' => is_writable(SETUP_ROOT . '/config'), 'value' => is_writable(SETUP_ROOT . '/config') ? 'Disponível' : 'Sem permissão'],
    ];

    return [
        'checks' => $checks,
        'ready' => count(array_filter($checks, static fn(array $check): bool => !$check['ok'])) === 0,
    ];
}

function setup_csrf(array $input): void
{
    $provided = (string)($input['csrf'] ?? '');
    $stored = (string)($_SESSION['setup_csrf'] ?? '');

    if ($stored === '' || !hash_equals($stored, $provided)) {
        setup_error('A sessão do instalador expirou. Recarregue a página.', 419);
    }
}

function setup_require_unlock(): array
{
    if (empty($_SESSION['setup_unlocked'])) {
        setup_error('Informe o código temporário gerado pelo instalador.', 401);
    }

    $config = setup_definition();
    if (!$config) {
        setup_error('A preparação do instalador não foi encontrada.', 409);
    }

    if ((int)($config['expires_at'] ?? 0) < time()) {
        setup_error('O código temporário expirou. Execute novamente o instalador.', 410);
    }

    return $config;
}

function setup_validate_db(array $db): array
{
    $host = trim((string)($db['host'] ?? ''));
    $database = trim((string)($db['database'] ?? ''));
    $username = trim((string)($db['username'] ?? ''));
    $password = (string)($db['password'] ?? '');
    $port = filter_var($db['port'] ?? 3306, FILTER_VALIDATE_INT, [
        'options' => ['min_range' => 1, 'max_range' => 65535],
    ]);

    if ($host === '' || strlen($host) > 255 || preg_match('/[\r\n]/', $host)) {
        setup_error('Informe um host de banco válido.', 422);
    }
    if (!preg_match('/^[A-Za-z0-9_]+$/', $database) || strlen($database) > 64) {
        setup_error('O nome do banco deve conter apenas letras, números e sublinhado.', 422);
    }
    if ($username === '' || strlen($username) > 80 || preg_match('/[\r\n]/', $username)) {
        setup_error('Informe um usuário de banco válido.', 422);
    }
    if ($port === false) {
        setup_error('Informe uma porta de banco válida.', 422);
    }

    return [
        'host' => $host,
        'port' => (int)$port,
        'database' => $database,
        'username' => $username,
        'password' => $password,
        'charset' => 'utf8mb4',
    ];
}

function setup_pdo(array $db): PDO
{
    $dsn = sprintf(
        'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
        $db['host'],
        $db['port'],
        $db['database']
    );

    return new PDO($dsn, $db['username'], $db['password'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
        PDO::ATTR_TIMEOUT => 4,
    ]);
}

function setup_write_php_config(string $path, array $config): void
{
    $temporary = $path . '.tmp-' . bin2hex(random_bytes(6));
    $content = "<?php\n\ndeclare(strict_types=1);\n\nreturn "
        . var_export($config, true)
        . ";\n";

    if (file_put_contents($temporary, $content, LOCK_EX) === false) {
        setup_error('Não foi possível gravar a configuração. Verifique as permissões da pasta config.', 500);
    }

    @chmod($temporary, 0640);
    if (!rename($temporary, $path)) {
        @unlink($temporary);
        setup_error('Não foi possível concluir a gravação da configuração.', 500);
    }
}

function setup_app_config(): array
{
    if (!is_file(app_file())) {
        setup_error('Configure o banco de dados antes de continuar.', 409);
    }

    $config = require app_file();
    if (!is_array($config)) {
        setup_error('O arquivo de configuração da aplicação é inválido.', 500);
    }

    return $config;
}

function setup_application_pdo(): PDO
{
    return setup_pdo(setup_validate_db(setup_app_config()['db'] ?? []));
}

function setup_encrypt_secret(string $plain, string $appKey): string
{
    $key = hash('sha256', $appKey, true);
    $iv = random_bytes(16);
    $cipher = openssl_encrypt($plain, 'AES-256-CBC', $key, OPENSSL_RAW_DATA, $iv);

    if ($cipher === false) {
        setup_error('Não foi possível proteger o token do Zabbix.', 500);
    }

    return base64_encode($iv . $cipher);
}

function setup_zabbix_request(string $url, string $token): void
{
    $payload = json_encode([
        'jsonrpc' => '2.0',
        'method' => 'host.get',
        'params' => ['countOutput' => true],
        'id' => 1,
    ], JSON_UNESCAPED_SLASHES);

    $curl = curl_init($url);
    curl_setopt_array($curl, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json-rpc',
            'Authorization: Bearer ' . $token,
        ],
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_TIMEOUT => 15,
        CURLOPT_FOLLOWLOCATION => false,
    ]);

    $body = curl_exec($curl);
    $status = (int)curl_getinfo($curl, CURLINFO_HTTP_CODE);
    $error = curl_error($curl);
    curl_close($curl);

    if ($body === false || $status >= 400 || $status === 0) {
        setup_error('Não foi possível acessar o Zabbix: ' . ($error ?: 'HTTP ' . $status), 422);
    }

    $response = json_decode((string)$body, true);
    if (!is_array($response)) {
        setup_error('O Zabbix retornou uma resposta inválida.', 422);
    }
    if (isset($response['error'])) {
        $message = $response['error']['data'] ?? $response['error']['message'] ?? 'Token ou URL inválidos.';
        setup_error('O Zabbix recusou a conexão: ' . (string)$message, 422);
    }
}

function setup_public_status(): array
{
    $definition = setup_definition();
    $requirements = setup_requirements();
    $status = [
        'ok' => true,
        'installed' => setup_is_installed(),
        'prepared' => $definition !== null,
        'unlocked' => !empty($_SESSION['setup_unlocked']),
        'csrf' => $_SESSION['setup_csrf'],
        'requirements' => $requirements,
        'loginUrl' => '../login.html',
    ];

    if (!$definition || empty($_SESSION['setup_unlocked'])) {
        return $status;
    }

    $status['expiresAt'] = (int)($definition['expires_at'] ?? 0);
    $preparedDb = is_array($definition['prepared_db'] ?? null) ? $definition['prepared_db'] : [];
    $databaseNotice = trim((string)($definition['database_notice'] ?? ''));
    $status['preparedDatabase'] = $preparedDb ? [
        'available' => true,
        'host' => (string)($preparedDb['host'] ?? '127.0.0.1'),
        'port' => (int)($preparedDb['port'] ?? 3306),
        'database' => (string)($preparedDb['database'] ?? ''),
        'username' => (string)($preparedDb['username'] ?? ''),
        'notice' => $databaseNotice,
    ] : [
        'available' => false,
        'notice' => $databaseNotice ?: 'O instalador não preparou uma conta de banco. Use Banco existente.',
    ];

    $status['appConfigured'] = is_file(app_file());
    $status['adminCreated'] = false;
    $status['zabbixConfigured'] = false;

    if ($status['appConfigured']) {
        try {
            $pdo = setup_application_pdo();
            $status['adminCreated'] = (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn() > 0;
            $settings = $pdo->query('SELECT zabbix_api_url, zabbix_token_encrypted FROM settings WHERE id = 1')->fetch();
            $status['zabbixConfigured'] = !empty($settings['zabbix_api_url']) && !empty($settings['zabbix_token_encrypted']);
        } catch (Throwable) {
            $status['databaseError'] = true;
        }
    }

    return $status;
}

setup_session();

try {
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

    if ($method === 'GET') {
        setup_response(setup_public_status());
    }

    if ($method !== 'POST') {
        setup_error('Método não permitido.', 405);
    }

    $input = setup_input();
    setup_csrf($input);
    $action = (string)($input['action'] ?? '');

    if ($action === 'unlock') {
        $blockedUntil = (int)($_SESSION['setup_blocked_until'] ?? 0);
        if ($blockedUntil > time()) {
            setup_error('Muitas tentativas inválidas. Aguarde alguns segundos e tente novamente.', 429);
        }

        $definition = setup_definition();
        if (!$definition) {
            setup_error('Execute o instalador no servidor antes de continuar.', 409);
        }
        if ((int)($definition['expires_at'] ?? 0) < time()) {
            setup_error('O código temporário expirou. Execute novamente o instalador.', 410);
        }

        $token = strtoupper(trim((string)($input['token'] ?? '')));
        $expected = (string)($definition['token_hash'] ?? '');
        if ($token === '' || $expected === '' || !hash_equals($expected, hash('sha256', $token))) {
            usleep(250000);
            $attempts = (int)($_SESSION['setup_attempts'] ?? 0) + 1;
            if ($attempts >= 5) {
                $_SESSION['setup_attempts'] = 0;
                $_SESSION['setup_blocked_until'] = time() + 30;
            } else {
                $_SESSION['setup_attempts'] = $attempts;
            }
            setup_error('Código temporário inválido.', 401);
        }

        session_regenerate_id(true);
        $_SESSION['setup_unlocked'] = true;
        unset($_SESSION['setup_attempts'], $_SESSION['setup_blocked_until']);
        $_SESSION['setup_csrf'] = bin2hex(random_bytes(24));
        setup_response(setup_public_status());
    }

    $definition = setup_require_unlock();

    if ($action === 'database') {
        if (!setup_requirements()['ready']) {
            setup_error('Corrija os requisitos do servidor antes de configurar o banco.', 409);
        }

        $mode = (string)($input['mode'] ?? 'prepared');
        if ($mode === 'prepared') {
            $prepared = $definition['prepared_db'] ?? null;
            if (!is_array($prepared)) {
                setup_error('Nenhum banco local foi preparado. Informe uma conexão existente.', 422);
            }
            $db = setup_validate_db($prepared);
        } else {
            $db = setup_validate_db(is_array($input['database'] ?? null) ? $input['database'] : []);
        }

        $pdo = setup_pdo($db);
        foreach (require SETUP_ROOT . '/database/schema.php' as $statement) {
            $pdo->exec($statement);
        }

        $current = is_file(app_file()) ? require app_file() : [];
        $appConfig = [
            'db' => $db,
            'app_key' => (string)($current['app_key'] ?? bin2hex(random_bytes(32))),
            'session_name' => (string)($current['session_name'] ?? 'central_incidentes_' . bin2hex(random_bytes(8))),
        ];
        setup_write_php_config(app_file(), $appConfig);
        setup_response(['ok' => true, 'message' => 'Banco configurado e tabelas criadas.']);
    }

    if ($action === 'admin') {
        $pdo = setup_application_pdo();
        if ((int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn() > 0) {
            setup_error('O administrador inicial já foi criado.', 409);
        }

        $name = trim((string)($input['name'] ?? ''));
        $username = trim((string)($input['username'] ?? ''));
        $password = (string)($input['password'] ?? '');
        $confirmation = (string)($input['passwordConfirmation'] ?? '');

        if (strlen($name) < 2 || strlen($name) > 120) {
            setup_error('Informe um nome entre 2 e 120 caracteres.', 422);
        }
        if (!preg_match('/^[A-Za-z0-9._-]{3,80}$/', $username)) {
            setup_error('O usuário deve ter entre 3 e 80 caracteres e usar apenas letras, números, ponto, hífen ou sublinhado.', 422);
        }
        if (strlen($password) < 10) {
            setup_error('Use uma senha com pelo menos 10 caracteres.', 422);
        }
        if (!hash_equals($password, $confirmation)) {
            setup_error('A confirmação da senha não corresponde.', 422);
        }

        $stmt = $pdo->prepare('INSERT INTO users (username, password_hash, name) VALUES (?, ?, ?)');
        $stmt->execute([$username, password_hash($password, PASSWORD_DEFAULT), $name]);
        setup_response(['ok' => true, 'message' => 'Administrador criado.']);
    }

    if ($action === 'zabbix') {
        $url = trim((string)($input['url'] ?? ''));
        $token = trim((string)($input['token'] ?? ''));

        if (strlen($url) > 512 || !filter_var($url, FILTER_VALIDATE_URL)) {
            setup_error('Informe uma URL completa e válida para a API do Zabbix.', 422);
        }
        $parts = parse_url($url);
        if (!in_array(strtolower((string)($parts['scheme'] ?? '')), ['http', 'https'], true)
            || stripos((string)($parts['path'] ?? ''), 'api_jsonrpc.php') === false) {
            setup_error('A URL deve usar HTTP ou HTTPS e apontar para api_jsonrpc.php.', 422);
        }
        if ($token === '' || strlen($token) > 8192) {
            setup_error('Informe um token válido do Zabbix.', 422);
        }

        setup_zabbix_request($url, $token);
        $appConfig = setup_app_config();
        $pdo = setup_application_pdo();
        $stmt = $pdo->prepare(
            'UPDATE settings SET zabbix_api_url = ?, zabbix_token_encrypted = ? WHERE id = 1'
        );
        $stmt->execute([$url, setup_encrypt_secret($token, (string)$appConfig['app_key'])]);
        setup_response(['ok' => true, 'message' => 'Conexão com o Zabbix validada.']);
    }

    if ($action === 'finish') {
        $pdo = setup_application_pdo();
        if ((int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn() === 0) {
            setup_error('Crie o administrador antes de finalizar.', 409);
        }

        $lock = json_encode([
            'installed_at' => gmdate('c'),
            'version' => (string)($definition['version'] ?? 'development'),
        ], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
        $temporary = lock_file() . '.tmp-' . bin2hex(random_bytes(6));
        if (file_put_contents($temporary, $lock . PHP_EOL, LOCK_EX) === false || !rename($temporary, lock_file())) {
            @unlink($temporary);
            setup_error('Não foi possível bloquear o instalador.', 500);
        }
        @chmod(lock_file(), 0640);
        if (!unlink(setup_file())) {
            setup_error('A instalação terminou, mas o arquivo temporário não pôde ser removido.', 500);
        }

        $_SESSION = [];
        session_destroy();
        setup_response(['ok' => true, 'loginUrl' => '../login.html']);
    }

    setup_error('Ação desconhecida.', 404);
} catch (PDOException $error) {
    error_log('[Central de Incidentes setup] ' . $error->getMessage());
    setup_error('Não foi possível conectar ou preparar o banco. Revise servidor, banco e credenciais.', 422);
} catch (Throwable $error) {
    error_log('[Central de Incidentes setup] ' . $error->getMessage());
    setup_error('O instalador encontrou um erro interno. Consulte o log do PHP.', 500);
}
