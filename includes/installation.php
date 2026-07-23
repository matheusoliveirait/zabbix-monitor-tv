<?php

declare(strict_types=1);

function application_root(): string
{
    return dirname(__DIR__);
}

function installation_paths(): array
{
    $root = application_root();

    return [
        'app' => $root . '/config/app.php',
        'setup' => $root . '/config/setup.php',
        'lock' => $root . '/config/installed.lock',
    ];
}

function installation_is_pending(): bool
{
    return is_file(installation_paths()['setup']);
}

function application_is_installed(): bool
{
    $paths = installation_paths();

    // app.php without setup.php represents an installation created before the wizard.
    return is_file($paths['app']) && !installation_is_pending();
}

function application_base_path(): string
{
    $script = str_replace('\\', '/', (string)($_SERVER['SCRIPT_NAME'] ?? '/'));
    foreach (['/api/', '/setup/'] as $marker) {
        $position = strpos($script, $marker);
        if ($position !== false) {
            return rtrim(substr($script, 0, $position), '/');
        }
    }

    $directory = str_replace('\\', '/', dirname($script));
    return $directory === '/' || $directory === '.' ? '' : rtrim($directory, '/');
}

function setup_url(): string
{
    return application_base_path() . '/setup/';
}

function redirect_to_installer(): never
{
    header('Location: ' . setup_url(), true, 302);
    exit;
}
