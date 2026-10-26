<?php
if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    http_response_code(405);
    header('Allow: POST');
    exit('Méthode non autorisée.');
}

$submittedToken = (string) ($_POST['csrf_token'] ?? '');
$sessionToken = (string) ($_SESSION['csrf_token'] ?? '');
if ($sessionToken === '' || !hash_equals($sessionToken, $submittedToken)) {
    http_response_code(403);
    exit('Demande invalide. Rechargez la page puis réessayez.');
}

$_SESSION = [];
if (ini_get('session.use_cookies')) {
    $cookie = session_get_cookie_params();
    setcookie(
        session_name(),
        '',
        time() - 42000,
        $cookie['path'],
        $cookie['domain'],
        $cookie['secure'],
        $cookie['httponly']
    );
}
session_destroy();

$scriptDirectory = str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? ''));
$basePath = $scriptDirectory === '/' || $scriptDirectory === '.' ? '' : rtrim($scriptDirectory, '/');
header('Location: ' . $basePath . '/auth/');
exit;