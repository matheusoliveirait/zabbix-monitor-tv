<?php

declare(strict_types=1);

require_once __DIR__ . '/includes/installation.php';

if (!application_is_installed()) {
    redirect_to_installer();
}

require __DIR__ . '/api/bootstrap.php';

header_remove('Content-Type');

function redirect_to_login(): never
{
    $next = $_SERVER['REQUEST_URI'] ?? '/';
    header('Location: login.html?next=' . rawurlencode($next), true, 302);
    exit;
}

try {
    start_app_session();

    if (users_count() === 0 || !current_user()) {
        redirect_to_login();
    }
} catch (Throwable) {
    redirect_to_login();
}

header('Content-Type: text/html; charset=utf-8');
readfile(__DIR__ . '/index.html');
