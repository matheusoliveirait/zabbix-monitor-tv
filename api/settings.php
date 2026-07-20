<?php

declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

function validate_zabbix_api_url(string $url): string
{
    $url = trim($url);
    $templateTokens = ['DIGITE-O-IP-DO-ZABBIX', 'DIGITE O IP DO ZABBIX'];

    if ($url === '') {
        json_error('Informe a URL da API do Zabbix.', 422);
    }
    if (strlen($url) > 512) {
        json_error('A URL da API deve ter no maximo 512 caracteres.', 422);
    }

    foreach ($templateTokens as $token) {
        if (stripos($url, $token) !== false) {
            json_error('Substitua o modelo pelo IP ou DNS real do Zabbix.', 422);
        }
    }

    $parts = parse_url($url);
    $scheme = strtolower((string)($parts['scheme'] ?? ''));
    if (!in_array($scheme, ['http', 'https'], true) || empty($parts['host'])) {
        json_error('Use uma URL completa, por exemplo http://zabbix.example.local/zabbix/api_jsonrpc.php.', 422);
    }

    if (stripos((string)($parts['path'] ?? ''), 'api_jsonrpc.php') === false) {
        json_error('A URL deve apontar para o api_jsonrpc.php do Zabbix.', 422);
    }

    return $url;
}

try {
    require_admin();
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

    if ($method === 'GET') {
        $settings = settings_row();
        json_response([
            'ok' => true,
            'settings' => [
                'zabbix_api_url' => $settings['zabbix_api_url'],
                'has_zabbix_token' => !empty($settings['zabbix_token_encrypted']),
                'refresh_seconds' => (int)$settings['refresh_seconds'],
                'api_limit' => (int)$settings['api_limit'],
                'page_interval_seconds' => (int)$settings['page_interval_seconds'],
                'sort_mode' => $settings['sort_mode'],
                'page_transition' => $settings['page_transition'] ?? 'fade',
                'incident_font_scale' => (int)($settings['incident_font_scale'] ?? 100),
                'card_font_scale' => (int)($settings['card_font_scale'] ?? 100),
                'fetch_mode' => $settings['fetch_mode'],
                'monitored_group_ids' => decode_ids($settings['monitored_group_ids'] ?? ''),
                'monitored_host_ids' => decode_ids($settings['monitored_host_ids'] ?? ''),
            ],
            'usingExampleConfig' => (bool)(app_config()['_using_example_config'] ?? false),
        ]);
    }

    if ($method === 'PATCH') {
        $input = json_input();
        $current = settings_row();
        $incidentFontScale = clamp_int(
            $input['incident_font_scale'] ?? $current['incident_font_scale'],
            85,
            125,
            (int)$current['incident_font_scale']
        );
        $cardFontScale = clamp_int(
            $input['card_font_scale'] ?? $current['card_font_scale'],
            85,
            125,
            (int)$current['card_font_scale']
        );

        $stmt = db()->prepare(
            'UPDATE settings
             SET incident_font_scale = ?, card_font_scale = ?
             WHERE id = 1'
        );
        $stmt->execute([$incidentFontScale, $cardFontScale]);

        json_response([
            'ok' => true,
            'settings' => [
                'incident_font_scale' => $incidentFontScale,
                'card_font_scale' => $cardFontScale,
            ],
        ]);
    }

    if ($method === 'POST' || $method === 'PUT') {
        $input = json_input();
        $current = settings_row();
        $sortMode = in_array(($input['sort_mode'] ?? 'recent'), ['recent', 'severity', 'duration', 'client', 'problem'], true)
            ? (string)$input['sort_mode']
            : 'recent';
        $fetchMode = in_array(($input['fetch_mode'] ?? 'incidents'), ['incidents', 'problems'], true)
            ? (string)$input['fetch_mode']
            : 'incidents';
        $pageTransition = in_array(($input['page_transition'] ?? 'fade'), ['none', 'fade', 'slide', 'zoom'], true)
            ? (string)$input['page_transition']
            : 'fade';

        $tokenEncrypted = $current['zabbix_token_encrypted'];
        if (!empty($input['zabbix_token'])) {
            $token = trim((string)$input['zabbix_token']);
            if (strlen($token) > 8192) {
                json_error('O token excede o tamanho permitido.', 422);
            }
            $tokenEncrypted = encrypt_secret($token);
        } elseif (!empty($input['clear_zabbix_token'])) {
            $tokenEncrypted = null;
        }
        $zabbixApiUrl = validate_zabbix_api_url((string)($input['zabbix_api_url'] ?? ''));

        $stmt = db()->prepare(
            'UPDATE settings
             SET zabbix_api_url = ?,
                 zabbix_token_encrypted = ?,
                 refresh_seconds = ?,
                 api_limit = ?,
                 page_interval_seconds = ?,
                 sort_mode = ?,
                 page_transition = ?,
                 incident_font_scale = ?,
                 card_font_scale = ?,
                 fetch_mode = ?,
                 monitored_group_ids = ?,
                 monitored_host_ids = ?
             WHERE id = 1'
        );
        $stmt->execute([
            $zabbixApiUrl,
            $tokenEncrypted,
            clamp_int($input['refresh_seconds'] ?? 10, 5, 900, 10),
            clamp_int($input['api_limit'] ?? 500, 20, 5000, 500),
            clamp_int($input['page_interval_seconds'] ?? 15, 5, 120, 15),
            $sortMode,
            $pageTransition,
            clamp_int($input['incident_font_scale'] ?? 100, 85, 125, 100),
            clamp_int($input['card_font_scale'] ?? 100, 85, 125, 100),
            $fetchMode,
            encode_ids($input['monitored_group_ids'] ?? []),
            encode_ids($input['monitored_host_ids'] ?? []),
        ]);

        json_response(['ok' => true]);
    }

    json_error('Metodo nao permitido.', 405);
} catch (Throwable $error) {
    handle_api_exception($error);
}
