<?php
/**
 * config/config.php
 * Configuration centralisée - DH TELECOM AND ADVERTISING HOUSE
 * PHP pur - Sans framework, sans .env
 */

// ============================================================
// SÉCURITÉ : empêche l'accès direct au fichier via URL
// ============================================================
if (!defined('DH_TELECOM_APP')) {
    define('DH_TELECOM_APP', true);
}

// ============================================================
// ENVIRONNEMENT
// ============================================================
define('APP_ENV',   'development');     // 'development' | 'production'
define('APP_DEBUG', true);              // true en dev, false en prod
define('APP_NAME',  'U-CONNECT');
define('APP_URL',   'http://localhost/IGD/u-connect'); // URL de base du projet
define('APP_VERSION', '2.0');

// ============================================================
// BASE DE DONNÉES (MariaDB / MySQL)
// ============================================================
define('DB_HOST',    '127.0.0.1');
define('DB_PORT',    3306);
define('DB_NAME',    'uconnect_db');
define('DB_USER',    'root');
define('DB_PASS',    '');                       // Vide sous XAMPP par défaut
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATION', 'utf8mb4_unicode_ci');

// ============================================================
// JWT (MS-01 Authentification)
// ============================================================
define('JWT_SECRET',     'uconnect_secret_key_change_me_2026_a7f8b9c0d1e2f3a4b5c6d7e8f9a0b1c2');
define('JWT_ALGO',       'HS256');
define('JWT_EXPIRATION', 86400);                // 24 heures

// ============================================================
// LICENCE (MS-09 Configuration)
// ============================================================
define('LICENSE_KEY',    'UCONNECT-2023-1-9195-2653');
define('LICENSE_STATUS', 0);                    // 0 = inactif, 1 = actif

// ============================================================
// LOGS
// ============================================================
define('LOG_PATH',  dirname(__DIR__) . '/logs/error.log');
define('LOG_LEVEL', 'debug');                   // debug | info | warning | error

// ============================================================
// EMAIL (MS-07 Documents)
// ============================================================
define('MAIL_HOST',      'smtp.gmail.com');
define('MAIL_PORT',      587);
define('MAIL_USER',      '');
define('MAIL_PASS',      '');
define('MAIL_FROM',      'noreply@dh-telecom.bi');
define('MAIL_FROM_NAME', APP_NAME);

// ============================================================
// PARAMÈTRES MÉTIER
// ============================================================
define('TVA_DEFAULT',     18);                  // 18% TVA par défaut
define('CURRENCY',        'FBu');
define('DATE_FORMAT',     'd/m/Y');
define('TIMEZONE',        'Africa/Bujumbura');

// Seuils VIP (Module #11)
define('VIP_THRESHOLD_AMOUNT',    500000);      // 500 000 FBu
define('VIP_THRESHOLD_FREQUENCY', 10);          // 10 achats
define('REGULIER_THRESHOLD',      100000);      // 100 000 FBu

// Alertes (Module #10)
define('ALERT_STOCK_DAYS',        30);          // Alerte expiration 30 jours
define('ALERT_BIRTHDAY_DAYS',     7);           // Alerte anniversaire J-7
define('ALERT_INVOICE_OVERDUE',   14);          // Facture impayée > 14 jours

// ============================================================
// UPLOAD DOCUMENTS (MS-07)
// ============================================================
define('UPLOAD_MAX_SIZE',  10 * 1024 * 1024);   // 10 Mo
define('UPLOAD_ALLOWED',   'pdf,jpg,jpeg,png,docx,xlsx');
define('UPLOAD_PATH',      dirname(__DIR__) . '/uploads');

// ============================================================
// APPLICATION DES PARAMÈTRES
// ============================================================

// Affichage des erreurs selon l'environnement
if (APP_ENV === 'development') {
    error_reporting(E_ALL);
    ini_set('display_errors', '1');
    ini_set('display_startup_errors', '1');
} else {
    error_reporting(E_ALL & ~E_DEPRECATED & ~E_STRICT);
    ini_set('display_errors', '0');
    ini_set('log_errors', '1');
    ini_set('error_log', LOG_PATH);
}

// Fuseau horaire
date_default_timezone_set(TIMEZONE);

// Encodage par défaut
mb_internal_encoding('UTF-8');
mb_http_output('UTF-8');

// Créer le dossier logs s'il n'existe pas
$logDir = dirname(LOG_PATH);
if (!is_dir($logDir)) {
    @mkdir($logDir, 0775, true);
}

// Créer le dossier uploads s'il n'existe pas
if (!is_dir(UPLOAD_PATH)) {
    @mkdir(UPLOAD_PATH, 0775, true);
}