<?php

declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

try {
    start_app_session();
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

    if ($method === 'GET') {
        json_response([
            'ok' => true,
            'user' => current_user(),
            'needsSetup' => users_count() === 0,
        ]);
    }

    if ($method === 'POST') {
        $input = json_input();
        $setupMode = !empty($input['setup']);
        $username = trim((string)($input['username'] ?? ''));
        $password = (string)($input['password'] ?? '');

        if ($username === '' || $password === '') {
            json_error('Informe usuario e senha.', 422);
        }
        if (strlen($username) > 80 || strlen($password) > 4096) {
            json_error('Usuario ou senha excede o tamanho permitido.', 422);
        }

        if ($setupMode) {
            if (users_count() > 0) {
                json_error('Setup inicial ja foi concluido.', 409);
            }

            if (strlen($password) < 8) {
                json_error('A senha inicial deve ter pelo menos 8 caracteres.', 422);
            }
            if (strlen($username) < 3) {
                json_error('O usuario inicial deve ter pelo menos 3 caracteres.', 422);
            }

            $name = trim((string)($input['name'] ?? 'Administrador'));
            if (strlen($name) > 120) {
                json_error('O nome deve ter no maximo 120 caracteres.', 422);
            }
            $stmt = db()->prepare('INSERT INTO users (username, password_hash, name) VALUES (?, ?, ?)');
            $stmt->execute([$username, password_hash($password, PASSWORD_DEFAULT), $name ?: 'Administrador']);
            login_user((int)db()->lastInsertId());

            json_response(['ok' => true, 'user' => current_user(), 'needsSetup' => false]);
        }

        $stmt = db()->prepare('SELECT id, username, password_hash, name FROM users WHERE username = ?');
        $stmt->execute([$username]);
        $user = $stmt->fetch();

        if (!$user || !password_verify($password, $user['password_hash'])) {
            json_error('Usuario ou senha invalidos.', 401);
        }

        login_user((int)$user['id']);
        json_response(['ok' => true, 'user' => current_user(), 'needsSetup' => false]);
    }

    if ($method === 'DELETE') {
        logout_user();
        json_response(['ok' => true]);
    }

    json_error('Metodo nao permitido.', 405);
} catch (Throwable $error) {
    handle_api_exception($error);
}
