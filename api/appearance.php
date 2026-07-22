<?php

declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

try {
    $settings = settings_row();
    json_response([
        'ok' => true,
        'theme' => normalize_dashboard_theme($settings['dashboard_theme'] ?? null),
    ]);
} catch (Throwable $error) {
    handle_api_exception($error);
}
