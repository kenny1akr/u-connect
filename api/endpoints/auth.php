<?php
/**
 * api/endpoints/auth.php
 * Endpoint d'authentification — adapté à la base uconnect_db
 */

require_once __DIR__ . '/../database.php';
require_once __DIR__ . '/../helpers/Response.php';
require_once __DIR__ . '/../helpers/Jwt.php';

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

$action = $_GET['action'] ?? 'login';

try {
    switch ($action) {
        case 'login':            login();            break;
        case 'logout':           logout();           break;
        case 'me':               me();               break;
        case 'forgot':           forgot();           break;
        case 'check_identifier': checkIdentifier();  break;
        default:
            Response::error('Action inconnue', 404);
    }
} catch (Throwable $e) {
    Response::error(
        APP_DEBUG ? $e->getMessage() : 'Erreur serveur',
        500
    );
}

// ============================================================
// LOGIN
// ============================================================
function login()
{
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        Response::error('Méthode non autorisée', 405);
    }

    $input = getInput();
    $identifier = trim($input['identifier'] ?? '');
    $password   = $input['password'] ?? '';

    $errors = [];
    if (empty($identifier)) $errors['identifier'] = 'L\'identifiant est requis';
    if (empty($password))   $errors['password']   = 'Le mot de passe est requis';
    if (!empty($errors)) {
        Response::validation($errors);
    }

    $db = Database::getInstance();

    // ============================================================
    // 1. VÉRIFIER D'ABORD DANS admin_users (Super Admin)
    // ============================================================
    $adminUser = $db->fetch(
        "SELECT id, user_name, password_hash, admin_role AS category, 
                f_name, l_name, email, phone AS telephone, status, profil,
                shadow_user_id
         FROM admin_users
         WHERE (user_name = ? OR email = ?)
         LIMIT 1",
        [$identifier, $identifier]
    );

    if ($adminUser && password_verify($password, $adminUser['password_hash'])) {
        // Vérifier le statut
        if (strtolower($adminUser['status']) !== 'actif') {
            logLoginAttempt($db, $adminUser['user_name'], 'failed', 'Compte administrateur inactif');
            Response::forbidden('Votre compte administrateur est inactif.');
        }

        // Succès admin
        $role = $adminUser['category'] === 'super_admin' ? 'super_admin' : 'secretaire_general';
        return loginSuccess($db, $adminUser, $role, $adminUser['shadow_user_id']);
    }

    // ============================================================
    // 2. SINON, VÉRIFIER DANS users (tous les autres rôles)
    // ============================================================
    $user = $db->fetch(
        "SELECT u.id, u.user_name, u.password_hash, u.category, 
                u.f_name, u.l_name, u.email, u.phone AS telephone, 
                u.status, u.profil, r.slug AS role_slug
         FROM users u
         LEFT JOIN roles r ON r.id = u.role_id
         WHERE (u.user_name = ? OR u.email = ?)
         LIMIT 1",
        [$identifier, $identifier]
    );

    if (!$user || !password_verify($password, $user['password_hash'])) {
        logLoginAttempt($db, $identifier, 'failed', 'Identifiants incorrects');
        Response::unauthorized('Identifiant ou mot de passe incorrect');
    }

    if (strtolower($user['status']) !== 'actif') {
        logLoginAttempt($db, $user['user_name'], 'failed', 'Compte ' . $user['status']);
        Response::forbidden('Votre compte est ' . $user['status'] . '. Contactez l\'administrateur.');
    }

    // Utiliser le slug du rôle si disponible
    $role = $user['role_slug'] ?: normalizeUserRole($user['category']);
    loginSuccess($db, $user, $role, null);
}

// ============================================================
// LOGIN SUCCESS (mutualisé admin + user)
// ============================================================
function loginSuccess($db, $user, $role, $shadowUserId = null)
{
    $db->execute(
        "UPDATE users SET last_login_at = NOW() WHERE id = ?",
        [$user['id']]
    );

    $tokenPayload = [
        'user_id'  => (int) ($shadowUserId ?: $user['id']),
        'username' => $user['user_name'],
        'role'     => $role,
        'email'    => $user['email'],
    ];
    $token = Jwt::encode($tokenPayload);

    logLoginAttempt($db, $user['user_name'], 'success', 'Connexion réussie');

    if (session_status() === PHP_SESSION_NONE) {
        session_start();
    }
    session_regenerate_id(true);
    $_SESSION['user_id']   = $shadowUserId ?: $user['id'];
    $_SESSION['username']  = $user['user_name'];
    $_SESSION['role']      = $role;
    $_SESSION['logged_in'] = true;

    Response::success([
        'token' => $token,
        'user'  => [
            'id'         => (int) ($shadowUserId ?: $user['id']),
            'username'   => $user['user_name'],
            'full_name'  => trim(($user['f_name'] ?? '') . ' ' . ($user['l_name'] ?? '')),
            'email'      => $user['email'],
            'phone'      => $user['telephone'] ?? null,
            'role'       => $role,
            'role_label' => getRoleLabel($role),
            'avatar'     => $user['profil'] ?: null,
        ],
        'expires_in' => JWT_EXPIRATION,
    ], 'Connexion réussie');
}

// ============================================================
// CHECK IDENTIFIER — Étape 1 du login
// ============================================================
function checkIdentifier()
{
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        Response::error('Méthode non autorisée', 405);
    }

    $input = getInput();
    $identifier = trim($input['identifier'] ?? '');

    if (empty($identifier)) {
        Response::validation(['identifier' => 'L\'identifiant est requis']);
    }

    $db = Database::getInstance();

    // 1. Chercher dans admin_users
    $adminUser = $db->fetch(
        "SELECT id, user_name, f_name, l_name, status, profil, admin_role AS category
         FROM admin_users
         WHERE (user_name = ? OR email = ?)
         LIMIT 1",
        [$identifier, $identifier]
    );

    if ($adminUser) {
        if (strtolower($adminUser['status']) !== 'actif') {
            Response::forbidden('Votre compte administrateur est inactif.');
        }
        $role = $adminUser['category'] === 'super_admin' ? 'super_admin' : 'secretaire_general';
        Response::success([
            'user_id'    => (int) $adminUser['id'],
            'username'   => $adminUser['user_name'],
            'first_name' => $adminUser['f_name'] ?? $adminUser['user_name'],
            'avatar'     => $adminUser['profil'] ?: null,
            'role'       => $role,
            'role_label' => getRoleLabel($role),
        ], 'Identifiant reconnu.');
    }

    // 2. Chercher dans users
    $user = $db->fetch(
        "SELECT u.id, u.user_name, u.f_name, u.l_name, u.status, u.profil, 
                u.category, r.slug AS role_slug
         FROM users u
         LEFT JOIN roles r ON r.id = u.role_id
         WHERE (u.user_name = ? OR u.email = ?)
         LIMIT 1",
        [$identifier, $identifier]
    );

    if (!$user) {
        Response::unauthorized('Aucun compte trouvé avec cet identifiant.');
    }

    if (strtolower($user['status']) !== 'actif') {
        Response::forbidden('Votre compte est ' . $user['status'] . '. Contactez l\'administrateur.');
    }

    $role = $user['role_slug'] ?: normalizeUserRole($user['category']);

    Response::success([
        'user_id'    => (int) $user['id'],
        'username'   => $user['user_name'],
        'first_name' => $user['f_name'] ?? $user['user_name'],
        'avatar'     => $user['profil'] ?: null,
        'role'       => $role,
        'role_label' => getRoleLabel($role),
    ], 'Identifiant reconnu.');
}

// ============================================================
// LOGOUT
// ============================================================
function logout()
{
    if (session_status() === PHP_SESSION_NONE) {
        session_start();
    }

    $username = $_SESSION['username'] ?? 'Inconnu';

    $db = Database::getInstance();
    logLoginAttempt($db, $username, 'success', 'Déconnexion');

    $_SESSION = [];
    if (ini_get("session.use_cookies")) {
        $params = session_get_cookie_params();
        setcookie(
            session_name(), '', time() - 42000,
            $params["path"], $params["domain"],
            $params["secure"], $params["httponly"]
        );
    }
    session_destroy();

    Response::success(null, 'Déconnexion réussie');
}

// ============================================================
// ME
// ============================================================
function me()
{
    $token = Jwt::getBearerToken();
    if ($token) {
        $payload = Jwt::decode($token);
        if ($payload) {
            $db = Database::getInstance();
            $user = $db->fetch(
                "SELECT u.id, u.user_name, u.category, u.f_name, u.l_name, 
                        u.email, u.phone AS telephone, u.profil, r.slug AS role_slug
                 FROM users u
                 LEFT JOIN roles r ON r.id = u.role_id
                 WHERE u.id = ?",
                [$payload['user_id']]
            );
            if ($user) {
                $role = $user['role_slug'] ?: normalizeUserRole($user['category']);
                Response::success([
                    'id'         => (int) $user['id'],
                    'username'   => $user['user_name'],
                    'full_name'  => trim(($user['f_name'] ?? '') . ' ' . ($user['l_name'] ?? '')),
                    'email'      => $user['email'],
                    'phone'      => $user['telephone'],
                    'role'       => $role,
                    'role_label' => getRoleLabel($role),
                ]);
            }
        }
    }

    if (session_status() === PHP_SESSION_NONE) {
        session_start();
    }
    if (!empty($_SESSION['user_id'])) {
        $db = Database::getInstance();
        $user = $db->fetch(
            "SELECT id, user_name, category, f_name, l_name, email 
             FROM users WHERE id = ?",
            [$_SESSION['user_id']]
        );
        if ($user) {
            Response::success($user);
        }
    }

    Response::unauthorized('Non authentifié');
}

// ============================================================
// FORGOT PASSWORD — Adapté à la table password_resets
// (email, token, expires_at — PAS de user_id)
// ============================================================
function forgot()
{
    $input = getInput();
    $email = trim($input['email'] ?? '');

    if (empty($email) || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
        Response::validation(['email' => 'Email invalide']);
    }

    $db = Database::getInstance();

    // Chercher dans users ET admin_users
    $user = $db->fetch("SELECT id, user_name FROM users WHERE email = ?", [$email]);
    if (!$user) {
        $user = $db->fetch("SELECT id, user_name FROM admin_users WHERE email = ?", [$email]);
    }

    // Toujours retourner succès (sécurité)
    if ($user) {
        $token = bin2hex(random_bytes(32));
        $expiresAt = date('Y-m-d H:i:s', time() + 3600);

        $db->execute(
            "INSERT INTO password_resets (email, token, expires_at) VALUES (?, ?, ?)",
            [$email, $token, $expiresAt]
        );

        // TODO : Envoyer email avec le lien
    }

    Response::success(null, 'Si cet email existe, un lien de réinitialisation a été envoyé.');
}

// ============================================================
// HELPERS
// ============================================================
function getInput()
{
    $contentType = $_SERVER['CONTENT_TYPE'] ?? '';
    if (stripos($contentType, 'application/json') !== false) {
        $raw = file_get_contents('php://input');
        return json_decode($raw, true) ?: [];
    }
    return $_POST;
}

// ============================================================
// LOGIN LOGS — Adapté à la table login_logs
// (user_id, user_name, ip_address, user_agent, status, created_at)
// ============================================================
function logLoginAttempt($db, $username, $status, $description = '')
{
    try {
        $ip = $_SERVER['REMOTE_ADDR'] ?? null;
        $ua = $_SERVER['HTTP_USER_AGENT'] ?? null;

        // Trouver l'ID utilisateur
        $userId = null;
        if ($username !== 'Inconnu') {
            $u = $db->fetch("SELECT id FROM users WHERE user_name = ? LIMIT 1", [$username]);
            if (!$u) {
                $u = $db->fetch("SELECT id FROM admin_users WHERE user_name = ? LIMIT 1", [$username]);
            }
            $userId = $u['id'] ?? null;
        }

        $db->execute(
            "INSERT INTO login_logs (user_id, user_name, ip_address, user_agent, status, created_at) 
             VALUES (?, ?, ?, ?, ?, NOW())",
            [$userId, $username, $ip, $ua, $status === 'success' ? 'success' : 'failed']
        );
    } catch (Exception $e) {
        // Silencieux
    }
}

// ============================================================
// getRoleLabel() — Libellés des rôles U-Connect
// ============================================================
function getRoleLabel($role)
{
    $labels = [
        // Rôles actifs U-Connect
        'super_admin'           => 'Super Administrateur',
        'secretaire_general'    => 'Secrétaire Général',
        'daf'                   => 'Directeur Administratif et Financier',
        'comptable'             => 'Comptable',
        'lecteur'               => 'Lecteur / Bibliothécaire',
        'chef_departement'      => 'Chef de Département',
        'assurance_qualite'     => 'Responsable Assurance Qualité',
        'recherche_innovation'  => 'Directeur Recherche & Innovation',
        'etudiant'              => 'Étudiant',
        'parent'                => 'Parent',
        // Rôles additionnels présents dans la base
        'recteur'               => 'Recteur',
        'directeur_campus'      => 'Directeur de Campus',
        'doyen'                 => 'Doyen de Faculté',
        'agent_scolarite'       => 'Agent de Scolarité',
        'caissier'              => 'Caissier',
        'enseignant'            => 'Enseignant',
        'drh'                   => 'Responsable RH',
        'system_admin'          => 'Administrateur Système',
    ];
    return $labels[$role] ?? ucfirst(str_replace('_', ' ', $role));
}

// ============================================================
// normalizeUserRole() — Alias vers slugs U-Connect
// ============================================================
function normalizeUserRole($role)
{
    $aliases = [
        'Super Admin'           => 'super_admin',
        'Admin'                 => 'secretaire_general',
        'directeur_general'     => 'secretaire_general',
        'directeur_financier'   => 'daf',
        'caissier'              => 'comptable',
        'bibliothecaire'        => 'lecteur',
        'chef_de_departement'   => 'chef_departement',
        'responsable_qualite'   => 'assurance_qualite',
        'directeur_recherche'   => 'recherche_innovation',
        'Utilisateur'           => 'etudiant',
        'Etudiant'              => 'etudiant',
        'Étudiant'              => 'etudiant',
    ];
    $normalized = $aliases[$role] ?? $role;
    return strtolower(trim($normalized));
}