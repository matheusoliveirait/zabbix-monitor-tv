<?php

declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

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
                'fetch_mode' => $settings['fetch_mode'],
                'monitored_group_ids' => decode_ids($settings['monitored_group_ids'] ?? ''),
                'monitored_host_ids' => decode_ids($settings['monitored_host_ids'] ?? ''),
            ],
            'usingExampleConfig' => (bool)(app_config()['_using_example_config'] ?? false),
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

        $tokenEncrypted = $current['zabbix_token_encrypted'];
        if (!empty($input['zabbix_token'])) {
            $tokenEncrypted = encrypt_secret((string)$input['zabbix_token']);
        } elseif (!empty($input['clear_zabbix_token'])) {
            $tokenEncrypted = null;
        }

        $stmt = db()->prepare(
            'UPDATE settings
             SET zabbix_api_url = ?,
                 zabbix_token_encrypted = ?,
                 refresh_seconds = ?,
                 api_limit = ?,
                 page_interval_seconds = ?,
                 sort_mode = ?,
                 fetch_mode = ?,
                 monitored_group_ids = ?,
                 monitored_host_ids = ?
             WHERE id = 1'
        );
        $stmt->execute([
            trim((string)($input['zabbix_api_url'] ?? '')),
            $tokenEncrypted,
            clamp_int($input['refresh_seconds'] ?? 10, 5, 900, 10),
            clamp_int($input['api_limit'] ?? 500, 20, 5000, 500),
            clamp_int($input['page_interval_seconds'] ?? 15, 5, 120, 15),
            $sortMode,
            $fetchMode,
            encode_ids(parse_ids($input['monitored_group_ids'] ?? [])),
            encode_ids(parse_ids($input['monitored_host_ids'] ?? [])),
        ]);

        json_response(['ok' => true]);
    }

    json_error('Metodo nao permitido.', 405);
} catch (Throwable $error) {
    handle_api_exception($error);
}
