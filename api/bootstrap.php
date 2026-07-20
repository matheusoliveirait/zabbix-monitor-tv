<?php

declare(strict_types=1);

error_reporting(E_ALL);
ini_set('display_errors', '0');

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

final class ZabbixApiException extends RuntimeException
{
}

function app_config(): array
{
    static $config = null;

    if ($config !== null) {
        return $config;
    }

    $root = dirname(__DIR__);
    $localConfig = $root . '/config/app.php';
    $exampleConfig = $root . '/config/app.example.php';
    $config = require (is_file($localConfig) ? $localConfig : $exampleConfig);
    $config['_using_example_config'] = !is_file($localConfig);

    return $config;
}

function start_app_session(): void
{
    if (session_status() === PHP_SESSION_ACTIVE) {
        return;
    }

    $config = app_config();
    $secureCookie = (!empty($_SERVER['HTTPS']) && strtolower((string)$_SERVER['HTTPS']) !== 'off') ||
        (int)($_SERVER['SERVER_PORT'] ?? 0) === 443;
    ini_set('session.use_strict_mode', '1');
    session_name((string)($config['session_name'] ?? 'zabbix_monitor_tv_session'));
    session_set_cookie_params([
        'lifetime' => 0,
        'path' => '/',
        'secure' => $secureCookie,
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
    session_start();
}

function login_user(int $userId): void
{
    start_app_session();
    session_regenerate_id(true);
    $_SESSION['user_id'] = $userId;
}

function logout_user(): void
{
    start_app_session();
    $_SESSION = [];

    if (ini_get('session.use_cookies')) {
        $params = session_get_cookie_params();
        setcookie(session_name(), '', [
            'expires' => time() - 42000,
            'path' => $params['path'],
            'domain' => $params['domain'],
            'secure' => $params['secure'],
            'httponly' => $params['httponly'],
            'samesite' => $params['samesite'] ?? 'Lax',
        ]);
    }

    session_destroy();
}

function db(): PDO
{
    static $pdo = null;

    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $db = app_config()['db'];
    $charset = $db['charset'] ?? 'utf8mb4';
    $dsn = sprintf(
        'mysql:host=%s;port=%d;dbname=%s;charset=%s',
        $db['host'] ?? '127.0.0.1',
        (int)($db['port'] ?? 3306),
        $db['database'] ?? 'zabbix_monitor_tv',
        $charset
    );

    $pdo = new PDO($dsn, $db['username'] ?? 'root', $db['password'] ?? '', [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
        PDO::ATTR_TIMEOUT => 2,
    ]);

    return $pdo;
}

function json_response(array $payload, int $status = 200): never
{
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function json_error(string $message, int $status = 400, array $extra = []): never
{
    json_response(['ok' => false, 'error' => $message] + $extra, $status);
}

function json_input(): array
{
    $raw = file_get_contents('php://input') ?: '';
    if ($raw === '') {
        return [];
    }

    $data = json_decode($raw, true);
    if (!is_array($data)) {
        json_error('JSON invalido.', 400);
    }

    return $data;
}

function users_count(): int
{
    return (int)db()->query('SELECT COUNT(*) FROM users')->fetchColumn();
}

function current_user(): ?array
{
    start_app_session();

    if (empty($_SESSION['user_id'])) {
        return null;
    }

    $stmt = db()->prepare('SELECT id, username, name FROM users WHERE id = ?');
    $stmt->execute([(int)$_SESSION['user_id']]);
    $user = $stmt->fetch();

    return $user ?: null;
}

function require_admin(): array
{
    $user = current_user();

    if (!$user) {
        json_error('Login necessario.', 401, ['needsSetup' => users_count() === 0]);
    }

    return $user;
}

function clamp_int(mixed $value, int $min, int $max, int $fallback): int
{
    if (!is_numeric($value)) {
        return $fallback;
    }

    return max($min, min($max, (int)$value));
}

function parse_ids(mixed $value): array
{
    $items = is_array($value) ? $value : explode(',', (string)$value);
    $ids = [];

    foreach ($items as $item) {
        $id = trim((string)$item);
        if ($id === '') {
            continue;
        }
        if (!ctype_digit($id) || $id === '0') {
            json_error('IDs de grupos e hosts devem ser numeros positivos.', 422);
        }
        $ids[$id] = $id;
    }

    return array_values($ids);
}

function encode_ids(array $ids): string
{
    return implode(',', parse_ids($ids));
}

function decode_ids(?string $value): array
{
    return parse_ids($value ?? '');
}

function crypto_key(): string
{
    $key = (string)(app_config()['app_key'] ?? '');

    return hash('sha256', $key, true);
}

function encrypt_secret(string $plain): string
{
    $iv = random_bytes(16);
    $cipher = openssl_encrypt($plain, 'AES-256-CBC', crypto_key(), OPENSSL_RAW_DATA, $iv);

    if ($cipher === false) {
        json_error('Falha ao criptografar segredo.', 500);
    }

    return base64_encode($iv . $cipher);
}

function decrypt_secret(?string $encoded): string
{
    if (!$encoded) {
        return '';
    }

    $raw = base64_decode($encoded, true);
    if ($raw === false || strlen($raw) <= 16) {
        return '';
    }

    $iv = substr($raw, 0, 16);
    $cipher = substr($raw, 16);
    $plain = openssl_decrypt($cipher, 'AES-256-CBC', crypto_key(), OPENSSL_RAW_DATA, $iv);

    return $plain === false ? '' : $plain;
}

function ensure_settings_schema(): void
{
    static $ready = false;

    if ($ready) {
        return;
    }

    $columns = db()->query('SHOW COLUMNS FROM settings')->fetchAll(PDO::FETCH_COLUMN);
    $missingColumns = [
        'page_transition' => "VARCHAR(32) NOT NULL DEFAULT 'fade'",
        'incident_font_scale' => 'TINYINT UNSIGNED NOT NULL DEFAULT 100',
        'card_font_scale' => 'TINYINT UNSIGNED NOT NULL DEFAULT 100',
    ];

    foreach ($missingColumns as $name => $definition) {
        if (!in_array($name, $columns, true)) {
            try {
                db()->exec("ALTER TABLE settings ADD COLUMN {$name} {$definition}");
            } catch (PDOException $error) {
                // Another request may have completed the same lightweight migration.
                if ((int)($error->errorInfo[1] ?? 0) !== 1060) {
                    throw $error;
                }
            }
        }
    }

    $ready = true;
}

function settings_row(): array
{
    ensure_settings_schema();
    $stmt = db()->query('SELECT * FROM settings WHERE id = 1');
    $row = $stmt->fetch();

    if ($row) {
        return $row;
    }

    db()->exec('INSERT INTO settings (id) VALUES (1)');

    return settings_row();
}

function frontend_config_from_settings(array $settings): array
{
    return [
        'REFRESH_SECONDS' => (int)$settings['refresh_seconds'],
        'PAGE_INTERVAL_SECONDS' => (int)$settings['page_interval_seconds'],
        'SORT_MODE' => $settings['sort_mode'],
        'PAGE_TRANSITION' => $settings['page_transition'] ?? 'fade',
        'INCIDENT_FONT_SCALE' => (int)($settings['incident_font_scale'] ?? 100),
        'CARD_FONT_SCALE' => (int)($settings['card_font_scale'] ?? 100),
    ];
}

function zabbix_request(string $method, array $params, string $apiUrl, string $token): array
{
    $payload = json_encode([
        'jsonrpc' => '2.0',
        'method' => $method,
        'params' => $params,
        'id' => time(),
    ], JSON_UNESCAPED_SLASHES);

    $headers = [
        'Content-Type: application/json-rpc',
        'Authorization: Bearer ' . $token,
    ];

    if (function_exists('curl_init')) {
        $curl = curl_init($apiUrl);
        curl_setopt_array($curl, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 20,
        ]);

        $body = curl_exec($curl);
        $httpCode = (int)curl_getinfo($curl, CURLINFO_HTTP_CODE);
        $curlError = curl_error($curl);
        curl_close($curl);

        if ($body === false || $httpCode >= 400) {
            throw new ZabbixApiException($curlError ?: 'HTTP ' . $httpCode . ' ao consultar Zabbix.');
        }
    } else {
        $context = stream_context_create([
            'http' => [
                'method' => 'POST',
                'header' => implode("\r\n", $headers),
                'content' => $payload,
                'timeout' => 20,
            ],
        ]);
        $body = file_get_contents($apiUrl, false, $context);

        if ($body === false) {
            throw new ZabbixApiException('Falha ao consultar Zabbix.');
        }
    }

    $data = json_decode((string)$body, true);
    if (!is_array($data)) {
        throw new ZabbixApiException('Resposta invalida do Zabbix.');
    }

    if (isset($data['error'])) {
        $message = $data['error']['data'] ?? $data['error']['message'] ?? 'Erro desconhecido na API do Zabbix.';
        throw new ZabbixApiException((string)$message);
    }

    return $data['result'] ?? [];
}

function handle_api_exception(Throwable $error): never
{
    error_log(sprintf(
        '[Central de Incidentes] %s: %s in %s:%d',
        $error::class,
        $error->getMessage(),
        $error->getFile(),
        $error->getLine()
    ));

    $message = $error instanceof ZabbixApiException
        ? $error->getMessage()
        : 'Erro interno no servidor. Consulte o log do PHP.';
    json_error($message, 500);
}
