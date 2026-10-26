<?php
/**
 * 404.php
 * Page introuvable — U-Connect
 * Affichée quand la route demandée n'existe pas.
 */

// ============================================================
// INITIALISATION
// ============================================================
if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

require_once __DIR__ . "/dash/template/permissions.php";

// Récupérer la route demandée
$requestedRoute = $_GET['route'] ?? ($_SERVER['REQUEST_URI'] ?? '/');
$requestedRoute = '/' . ltrim($requestedRoute, '/');

// Récupérer le rôle si connecté
$role = $_SESSION['role'] ?? null;
$isLoggedIn = !empty($_SESSION['logged_in']);
$roleLabel = $role ? getRoleLabel($role) : null;

// URL de retour
$homeUrl = $isLoggedIn && $role
    ? (defined('APP_BASE_PATH') ? APP_BASE_PATH : '') . '/router.php?route=' . urlencode($role . '/accueil')
    : (defined('APP_BASE_PATH') ? APP_BASE_PATH : '') . '/auth/';
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
    <title>404 — Page introuvable | U-Connect</title>

    <!-- Favicon -->
    <link rel="apple-touch-icon" sizes="180x180" href="vendors/images/apple-touch-icon.png">
    <link rel="icon" type="image/png" sizes="32x32" href="vendors/images/favicon-32x32.png">

    <!-- Google Font -->
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">

    <!-- CSS DeskApp -->
    <link rel="stylesheet" type="text/css" href="vendors/styles/core.css">
    <link rel="stylesheet" type="text/css" href="vendors/styles/icon-font.min.css">
    <link rel="stylesheet" type="text/css" href="vendors/styles/style.css">

    <!-- SweetAlert2 -->
    <script src="https://cdn.jsdelivr.net/npm/sweetalert2@11"></script>

    <style>
        :root {
            --uconnect-green: #36c783;
            --uconnect-dark:  #287957;
            --uconnect-bg:    #f0f3f9;
        }

        body {
            background: var(--uconnect-bg);
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0;
            padding: 20px;
        }

        .error-card {
            background: #ffffff;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(15, 81, 50, 0.10);
            padding: 50px 40px;
            max-width: 560px;
            width: 100%;
            text-align: center;
            position: relative;
            overflow: hidden;
            animation: fadeInUp 0.5s ease-out;
        }

        @keyframes fadeInUp {
            from { opacity: 0; transform: translateY(20px); }
            to   { opacity: 1; transform: translateY(0); }
        }

        .error-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 6px;
            background: linear-gradient(90deg, #36c783, #287957);
        }

        .error-code {
            font-size: 100px;
            font-weight: 800;
            line-height: 1;
            background: linear-gradient(135deg, #36c783, #287957);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            margin-bottom: 10px;
            letter-spacing: -4px;
        }

        .error-icon {
            width: 80px;
            height: 80px;
            border-radius: 50%;
            background: rgba(54, 199, 131, 0.10);
            display: inline-flex;
            align-items: center;
            justify-content: center;
            color: var(--uconnect-green);
            font-size: 40px;
            margin-bottom: 20px;
        }

        .error-title {
            font-size: 24px;
            font-weight: 700;
            color: #1f2937;
            margin-bottom: 10px;
        }

        .error-message {
            font-size: 14px;
            color: #6b7280;
            line-height: 1.6;
            margin-bottom: 24px;
        }

        .error-route {
            display: inline-block;
            background: #f3f4f6;
            border: 1px dashed #d1d5db;
            color: #374151;
            padding: 8px 16px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 13px;
            margin-bottom: 28px;
            max-width: 100%;
            overflow-wrap: break-word;
        }

        .error-actions {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            justify-content: center;
        }

        .btn-uconnect {
            background: var(--uconnect-green) !important;
            border: 1px solid var(--uconnect-green) !important;
            color: #fff !important;
            font-weight: 600;
            padding: 12px 24px;
            border-radius: 10px;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            transition: all 0.2s;
            font-size: 14px;
            cursor: pointer;
        }
        .btn-uconnect:hover {
            background: var(--uconnect-dark) !important;
            border-color: var(--uconnect-dark) !important;
            color: #fff !important;
            transform: translateY(-1px);
            box-shadow: 0 6px 16px rgba(40, 121, 87, 0.25);
            text-decoration: none;
        }

        .btn-outline {
            background: #ffffff !important;
            border: 1px solid #d1d5db !important;
            color: #374151 !important;
            font-weight: 600;
            padding: 12px 24px;
            border-radius: 10px;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            transition: all 0.2s;
            font-size: 14px;
            cursor: pointer;
        }
        .btn-outline:hover {
            background: #f9fafb !important;
            border-color: #9ca3af !important;
            color: #111827 !important;
            text-decoration: none;
        }

        .error-footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #eef1f5;
            font-size: 12px;
            color: #9ca3af;
        }

        .error-footer .role-badge {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 3px 10px;
            border-radius: 999px;
            font-size: 11px;
            font-weight: 600;
            color: #fff;
            background: var(--uconnect-green);
        }
        .error-footer .role-dot {
            width: 6px;
            height: 6px;
            border-radius: 50%;
            background: #fff;
            opacity: 0.9;
        }
    </style>
</head>
<body>

    <div class="error-card">

        <!-- Icône -->
        <div class="error-icon">
            <i class="dw dw-warning"></i>
        </div>

        <!-- Code -->
        <div class="error-code">404</div>

        <!-- Titre -->
        <h1 class="error-title">Page introuvable</h1>

        <!-- Message -->
        <p class="error-message">
            La route demandée n'existe pas ou n'est plus accessible.<br>
            Vérifiez l'URL ou retournez à votre espace de gestion.
        </p>

        <!-- Route demandée -->
        <div class="error-route">
            <strong>Route :</strong> <?= htmlspecialchars($requestedRoute, ENT_QUOTES, 'UTF-8') ?>
        </div>

        <!-- Actions -->
        <div class="error-actions">
            <a href="<?= htmlspecialchars($homeUrl, ENT_QUOTES, 'UTF-8') ?>" class="btn-uconnect">
                <i class="dw dw-house-1"></i>
                Retour au tableau de bord
            </a>
            <button type="button" onclick="history.back()" class="btn-outline">
                <i class="dw dw-left-arrow"></i>
                Page précédente
            </button>
        </div>

        <!-- Footer -->
        <div class="error-footer">
            <?php if ($isLoggedIn && $roleLabel): ?>
                Connecté(e) en tant que
                <span class="role-badge">
                    <span class="role-dot"></span>
                    <?= htmlspecialchars($roleLabel, ENT_QUOTES, 'UTF-8') ?>
                </span>
            <?php else: ?>
                <span>U-Connect — EALI</span>
            <?php endif; ?>
            <br>
            &copy; <?= date('Y') ?> U-Connect — Tous droits réservés
        </div>

    </div>

    <!-- ============================================================
         SWEETALERT2 — Log de l'erreur en console
         ============================================================ -->
    <script>
        // Affiche un petit toast d'aide en bas à droite (optionnel)
        const Toast = Swal.mixin({
            toast: true,
            position: 'bottom-end',
            showConfirmButton: false,
            timer: 6000,
            timerProgressBar: true,
            didOpen: (toast) => {
                toast.addEventListener('mouseenter', Swal.stopTimer);
                toast.addEventListener('mouseleave', Swal.resumeTimer);
            }
        });

        // Toast informatif après 800 ms
        setTimeout(() => {
            Toast.fire({
                icon: 'info',
                title: 'Page introuvable',
                text: 'Utilisez le bouton « Retour au tableau de bord » pour continuer.'
            });
        }, 800);

        // Log console pour le débogage
        console.warn('[U-Connect 404] Route demandée :', <?= json_encode($requestedRoute) ?>);
    </script>

</body>
</html>