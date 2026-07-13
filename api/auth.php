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

        if ($setupMode) {
            if (users_count() > 0) {
                json_error('Setup inicial ja foi concluido.', 409);
            }

            if (strlen($password) < 8) {
                json_error('A senha inicial deve ter pelo menos 8 caracteres.', 422);
            }

            $name = trim((string)($input['name'] ?? 'Administrador'));
            $stmt = db()->prepare('INSERT INTO users (username, password_hash, name) VALUES (?, ?, ?)');
            $stmt->execute([$username, password_hash($password, PASSWORD_DEFAULT), $name ?: 'Administrador']);
            $_SESSION['user_id'] = (int)db()->lastInsertId();

            json_response(['ok' => true, 'user' => current_user(), 'needsSetup' => false]);
        }

        $stmt = db()->prepare('SELECT id, username, password_hash, name FROM users WHERE username = ?');
        $stmt->execute([$username]);
        $user = $stmt->fetch();

        if (!$user || !password_verify($password, $user['password_hash'])) {
            json_error('Usuario ou senha invalidos.', 401);
        }

        $_SESSION['user_id'] = (int)$user['id'];
        json_response(['ok' => true, 'user' => current_user(), 'needsSetup' => false]);
    }

    if ($method === 'DELETE') {
        $_SESSION = [];
        session_destroy();
        json_response(['ok' => true]);
    }

    json_error('Metodo nao permitido.', 405);
} catch (Throwable $error) {
    handle_api_exception($error);
}
