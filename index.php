<?php

declare(strict_types=1);

require __DIR__ . '/api/bootstrap.php';

header_remove('Content-Type');

function redirect_to_admin(): never
{
    $next = $_SERVER['REQUEST_URI'] ?? '/';
    header('Location: admin.html?next=' . rawurlencode($next), true, 302);
    exit;
}

try {
    start_app_session();

    if (users_count() === 0 || !current_user()) {
        redirect_to_admin();
    }
} catch (Throwable) {
    redirect_to_admin();
}

header('Content-Type: text/html; charset=utf-8');
readfile(__DIR__ . '/index.html');
