<?php

declare(strict_types=1);

require_once __DIR__ . '/includes/installation.php';

if (!application_is_installed()) {
    redirect_to_installer();
}

require __DIR__ . '/api/bootstrap.php';

header_remove('Content-Type');

function redirect_admin_to_login(): never
{
    header('Location: login.html?next=' . rawurlencode('admin.html'), true, 302);
    exit;
}

try {
    start_app_session();

    if (users_count() === 0 || !current_user()) {
        redirect_admin_to_login();
    }
} catch (Throwable) {
    redirect_admin_to_login();
}

header('Content-Type: text/html; charset=utf-8');
readfile(__DIR__ . '/admin.html');
