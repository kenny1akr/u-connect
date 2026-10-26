<?php
/**
 * dash/template/layout.php
 * Layout DeskApp — U-Connect
 * Conserve toute la logique PHP (utilisateur, rôles, permissions, sidebar dynamique)
 * et le rendu du contenu via $content.
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once __DIR__ . "/permissions.php";
require_once __DIR__ . "/sidebar_config.php";

// ============================================================
// ROUTE ACTIVE
// ============================================================
if (!isset($route)) {
    $route = $_GET['route'] ?? 'accueil';
}
$route = trim(strtolower($route), '/');
if ($route === '' || $route === 'index.php') {
    $route = 'accueil';
}

// ============================================================
// UTILISATEUR
// ============================================================
if (!isset($user) || !is_array($user)) {
    $TEST_ROLE = $_GET['role'] ?? 'super_admin';
    global $ROLES;
    if (!isset($ROLES[$TEST_ROLE])) {
        $TEST_ROLE = 'super_admin';
    }
    $user = [
        "utilisateur_id"  => 1,
        "nom_complet"     => "Super Administrateur",
        "nom_utilisateur" => "superadmin",
        "role_system"     => $TEST_ROLE,
        "statut"          => "actif",
        "avatar"          => "",
    ];
}

// ============================================================
// ENTREPRISE / UNIVERSITÉ
// ============================================================
if (!isset($company) || !is_array($company)) {
    $company = [
        "company_name" => "EALI",
        "country"      => "Burundi",
        "logo"         => "",
    ];
}

// ============================================================
// VARIABLES DÉRIVÉES
// ============================================================
$escName   = htmlspecialchars($user["nom_complet"] ?? "Utilisateur", ENT_QUOTES, 'UTF-8');
$escRole   = htmlspecialchars(getRoleLabel($user["role_system"] ?? ""), ENT_QUOTES, 'UTF-8');
$escAvatar = !empty($user["avatar"]) ? htmlspecialchars($user["avatar"], ENT_QUOTES, 'UTF-8') : null;
$rolePrefix = !empty($user["role_system"]) ? $user["role_system"] . "/" : "";
$activeRoute = $rolePrefix !== "" && strpos($route, $rolePrefix) === 0
    ? substr($route, strlen($rolePrefix))
    : $route;

// ============================================================
// ICON MAP — Feather names → dw (DeskApp) classes VÉRIFIÉES
// ============================================================
if (!function_exists('dwIcon')) {
    function dwIcon(?string $feather): string
    {
        $map = [
            'home'           => 'dw dw-house-1',
            'database'       => 'dw dw-database',
            'dollar-sign'    => 'dw dw-dollar',
            'credit-card'    => 'dw dw-credit-card',
            'shopping-cart'  => 'dw dw-cart',
            'file-text'      => 'dw dw-file',
            'repeat'         => 'dw dw-refresh',
            'truck'          => 'dw dw-truck',
            'trending-up'    => 'dw dw-line-chart',
            'book-open'      => 'dw dw-book',
            'clipboard'      => 'dw dw-clipboard',
            'briefcase'      => 'dw dw-briefcase',
            'users'          => 'dw dw-group',
            'package'        => 'dw dw-box',
            'gift'           => 'dw dw-gift',
            'cake'           => 'dw dw-cake',
            'activity'       => 'dw dw-activity',
            'bar-chart-2'    => 'dw dw-bar-chart',
            'message-circle' => 'dw dw-chat',
            'bell'           => 'dw dw-notification',
            'shield'         => 'dw dw-shield',
            'settings'       => 'dw dw-settings2',
            'user'           => 'dw dw-user1',
            'log-out'        => 'dw dw-logout',
            'chevrons-left'  => 'dw dw-left-arrow',
            'chevron-down'   => 'fa fa-angle-down',
            'menu'           => 'dw dw-menu',
            'map-pin'        => 'dw dw-map-pin',
            'power'          => 'dw dw-power',
            'search'         => 'dw dw-search2',
            'plus'           => 'dw dw-plus',
            'check'          => 'dw dw-check',
            'x'              => 'dw dw-close',
            'eye'            => 'dw dw-eye',
            'printer'        => 'dw dw-printer',
            'edit-2'         => 'dw dw-edit2',
            'trash-2'        => 'dw dw-delete-3',
            'save'           => 'dw dw-save',
            'file-plus'      => 'dw dw-file',
            'check-circle'   => 'dw dw-check',
            'alert-triangle' => 'dw dw-warning',
            'clock'          => 'dw dw-clock',
            'list'           => 'dw dw-list3',
            'award'          => 'dw dw-award',
            'star'           => 'dw dw-star',
            'calendar'       => 'dw dw-calendar1',
            'phone'          => 'dw dw-phone',
            'arrow-left'     => 'dw dw-left-arrow',
            'user-plus'      => 'dw dw-add-user',
            'link'           => 'dw dw-link',
        ];
        return $map[$feather] ?? 'dw dw-circle';
    }
}
// ============================================================
// RENDU SIDEBAR ITEM (DeskApp)
// ============================================================
if (!function_exists('renderSidebarItem')) {
    function renderSidebarItem(array $item, string $currentRoute, array $user): void
    {
        if (!empty($item['permission']) && !userCan($user, $item['permission'])) {
            return;
        }

        $itemHref  = $item['href'] ?? '';
        $itemRoute = ltrim($itemHref, '/');
        $isActive  = ($itemRoute === $currentRoute);

        if ($item['type'] === 'link') {
            $activeClass = $isActive ? 'active' : '';
            ?>
            <li>
                <a href="<?= htmlspecialchars(app_route_url($itemHref, $user['role_system'] ?? null), ENT_QUOTES, 'UTF-8') ?>"
                   class="dropdown-toggle no-arrow <?= $activeClass ?>">
                    <span class="micon <?= htmlspecialchars(dwIcon($item['icon'] ?? '')) ?>"></span>
                    <span class="mtext"><?= htmlspecialchars($item['label']) ?></span>
                    <?php if (!empty($item['badge'])): ?>
                        <span class="badge badge-<?= htmlspecialchars($item['badge']['color'] ?? 'primary') ?> ml-2">
                            <?= htmlspecialchars($item['badge']['text']) ?>
                        </span>
                    <?php endif; ?>
                </a>
            </li>
            <?php
        } elseif ($item['type'] === 'dropdown') {
            $visibleChildren = array_filter($item['items'] ?? [], function ($sub) use ($user) {
                if (empty($sub['permission'])) return true;
                return userCan($user, $sub['permission']);
            });

            if (empty($visibleChildren)) return;

            $hasActiveChild = false;
            foreach ($visibleChildren as $sub) {
                $subRoute = ltrim($sub['href'] ?? '', '/');
                if ($subRoute === $currentRoute) { $hasActiveChild = true; break; }
            }
            ?>
            <li class="dropdown">
                <a href="javascript:;" class="dropdown-toggle <?= $hasActiveChild ? 'active' : '' ?>">
                    <span class="micon <?= htmlspecialchars(dwIcon($item['icon'] ?? '')) ?>"></span>
                    <span class="mtext"><?= htmlspecialchars($item['label']) ?></span>
                </a>
                <ul class="submenu <?= $hasActiveChild ? '' : 'hidden' ?>">
                    <?php foreach ($visibleChildren as $sub): ?>
                        <?php
                        $subHref   = $sub['href'] ?? '';
                        $subRoute  = ltrim($subHref, '/');
                        $subActive = ($subRoute === $currentRoute);
                        ?>
                        <li>
                            <a href="<?= htmlspecialchars(app_route_url($subHref, $user['role_system'] ?? null), ENT_QUOTES, 'UTF-8') ?>"
                               class="<?= $subActive ? 'active' : '' ?>">
                                <?= htmlspecialchars($sub['label']) ?>
                            </a>
                        </li>
                    <?php endforeach; ?>
                </ul>
            </li>
            <?php
        }
    }
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
    <title>U-Connect — <?= htmlspecialchars($pageTitle ?? 'Tableau de bord') ?></title>

    <!-- Favicon -->
    <link rel="apple-touch-icon" sizes="180x180" href="<?= htmlspecialchars(app_url('dash/template/vendors/images/apple-touch-icon.png')) ?>">
    <link rel="icon" type="image/png" sizes="32x32" href="<?= htmlspecialchars(app_url('dash/template/vendors/images/favicon-32x32.png')) ?>">

    <!-- Google Font -->
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">

    <!-- CSS DeskApp -->
    <link rel="stylesheet" type="text/css" href="<?= htmlspecialchars(app_url('dash/template/vendors/styles/core.css')) ?>">
    <link rel="stylesheet" type="text/css" href="<?= htmlspecialchars(app_url('dash/template/vendors/styles/icon-font.min.css')) ?>">
    <link rel="stylesheet" type="text/css" href="<?= htmlspecialchars(app_url('dash/template/vendors/styles/style.css')) ?>">

    <!-- Fallback Font Awesome si les dw-* ne chargent pas -->
<link rel="stylesheet"
      href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css"
      crossorigin="anonymous" referrerpolicy="no-referrer">

<style>
    /* Fallback : si les .dw::before n'ont pas de glyphe, Font Awesome prend le relais */
    .dw-house-1::before   { content: "\f015"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-database::before  { content: "\f1c0"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-dollar::before    { content: "\f155"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-credit-card::before { content: "\f09d"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-cart::before      { content: "\f07a"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-file::before      { content: "\f15c"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-truck::before     { content: "\f0d1"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-line-chart::before{ content: "\f201"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-book::before      { content: "\f02d"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-group::before     { content: "\f0c0"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-box::before       { content: "\f466"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-gift::before      { content: "\f06b"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-cake::before      { content: "\f1fd"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-activity::before  { content: "\f201"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-bar-chart::before { content: "\f080"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-chat::before      { content: "\f086"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-notification::before { content: "\f0f3"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-shield::before    { content: "\f3ed"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-settings2::before { content: "\f013"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-user1::before     { content: "\f007"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-logout::before    { content: "\f2f5"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-menu::before      { content: "\f0c9"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-search2::before   { content: "\f002"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-plus::before      { content: "\f067"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-check::before     { content: "\f00c"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-close::before     { content: "\f00d"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-eye::before       { content: "\f06e"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-printer::before   { content: "\f02f"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-edit2::before     { content: "\f044"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-delete-3::before  { content: "\f2ed"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-save::before      { content: "\f0c7"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-warning::before   { content: "\f071"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-clock::before     { content: "\f017"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-list3::before     { content: "\f03a"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-award::before     { content: "\f559"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-star::before      { content: "\f005"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-calendar1::before { content: "\f133"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-phone::before     { content: "\f095"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-left-arrow::before{ content: "\f060"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-add-user::before  { content: "\f234"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-link::before      { content: "\f0c1"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-briefcase::before { content: "\f0b1"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-clipboard::before { content: "\f46d"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-refresh::before   { content: "\f021"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-map-pin::before   { content: "\f3c5"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-power::before     { content: "\f011"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
    .dw-circle::before    { content: "\f111"; font-family: "Font Awesome 6 Free"; font-weight: 900; }
</style>


    <!-- SweetAlert2 -->
    <script src="https://cdn.jsdelivr.net/npm/sweetalert2@11"></script>

    <!-- CSS personnalisé U-Connect (couleurs + détails) -->
    <style>
        :root {
            --uconnect-green: #36c783;
            --uconnect-dark:  #287957;
            --uconnect-bg:    #f0f3f9;
        }

        /* ---- Header / Sidebar couleurs U-Connect ---- */
        .header {
            background: #ffffff;
            border-bottom: 1px solid #e5e7eb;
        }
        .left-side-bar {
            background: var(--uconnect-dark) !important;
        }
        .left-side-bar .brand-logo {
            background: var(--uconnect-dark) !important;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .left-side-bar .brand-logo .uconnect-brand-text {
            color: #fff;
            font-weight: 800;
            font-size: 18px;
            letter-spacing: -0.5px;
        }
        .left-side-bar .sidebar-menu ul#accordion-menu > li > a {
            color: #e5e7eb;
            border-radius: 8px;
            margin: 2px 6px;
            transition: background .15s, color .15s;
        }
        .left-side-bar .sidebar-menu ul#accordion-menu > li > a:hover,
        .left-side-bar .sidebar-menu ul#accordion-menu > li > a.active {
            background: var(--uconnect-green);
            color: #fff;
        }
        .left-side-bar .sidebar-menu ul#accordion-menu > li > ul.submenu > li > a {
            color: #d1d5db;
        }
        .left-side-bar .sidebar-menu ul#accordion-menu > li > ul.submenu > li > a:hover,
        .left-side-bar .sidebar-menu ul#accordion-menu > li > ul.submenu > li > a.active {
            color: #fff;
            background: rgba(54,199,131,0.25);
            border-radius: 6px;
        }
        .left-side-bar .sidebar-menu .micon {
            color: inherit;
            font-size: 18px;
            min-width: 24px;
            text-align: center;
        }
        .left-side-bar .sidebar-menu .mtext {
            font-weight: 500;
            font-size: 14px;
        }

        /* ---- Boutons principaux U-Connect ---- */
        .btn-uconnect {
            background: var(--uconnect-green) !important;
            border-color: var(--uconnect-green) !important;
            color: #fff !important;
            font-weight: 600;
        }
        .btn-uconnect:hover,
        .btn-uconnect:focus {
            background: var(--uconnect-dark) !important;
            border-color: var(--uconnect-dark) !important;
        }

        /* ---- User dropdown ---- */
        .user-info-dropdown .user-name { font-weight: 600; color: #1f2937; }
        .user-info-dropdown .user-icon img { border-radius: 50%; }

        /* ---- Cards ---- */
        .card-box {
            border-radius: 10px;
            border: 1px solid #eef1f5;
            box-shadow: 0 4px 16px rgba(15,81,50,0.04);
        }

        /* ---- Rôle badge ---- */
        .uconnect-role-badge {
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
        .uconnect-role-dot {
            width: 6px; height: 6px; border-radius: 50%;
            background: #fff; opacity: .9;
        }

        /* ---- Notification dot ---- */
        .notification-active {
            background: #ef4444 !important;
        }

        /* ---- Préloader personnalisé ---- */
        .pre-loader .loader-logo {
            font-size: 28px;
            font-weight: 800;
            color: var(--uconnect-dark);
            text-align: center;
        }

        /* ---- Scrollbar subtile dans la sidebar ---- */
        .left-side-bar .menu-block::-webkit-scrollbar { width: 5px; }
        .left-side-bar .menu-block::-webkit-scrollbar-thumb {
            background: rgba(255,255,255,0.15);
            border-radius: 8px;
        }
    </style>
</head>
<body>

    <!-- ============================================================
         PRE-LOADER
         ============================================================ -->
    <div class="pre-loader">
        <div class="pre-loader-box">
            <div class="loader-logo">U-Connect</div>
            <div class='loader-progress' id="progress_div">
                <div class='bar' id='bar1'></div>
            </div>
            <div class='percent' id='percent1'>0%</div>
            <div class="loading-text">Chargement...</div>
        </div>
    </div>

    <!-- ============================================================
         HEADER
         ============================================================ -->
    <div class="header">
        <div class="header-left">
            <div class="menu-icon dw dw-menu"></div>
            <div class="search-toggle-icon dw dw-search2" data-toggle="header_search"></div>
            <div class="header-search">
                <form>
                    <div class="form-group mb-0">
                        <i class="dw dw-search2 search-icon"></i>
                        <input type="text" class="form-control search-input" placeholder="Rechercher...">
                    </div>
                </form>
            </div>
        </div>
        <div class="header-right">
            <div class="dashboard-setting user-notification">
                <div class="dropdown">
                    <a class="dropdown-toggle no-arrow" href="javascript:;" data-toggle="right-sidebar">
                        <i class="dw dw-settings2"></i>
                    </a>
                </div>
            </div>

            <!-- Notifications -->
            <div class="user-notification">
                <div class="dropdown">
                    <a class="dropdown-toggle no-arrow" href="#" role="button" data-toggle="dropdown" id="notificationBell">
                        <i class="icon-copy dw dw-notification"></i>
                        <span class="badge notification-active" id="notificationBadge"></span>
                    </a>
                    <div class="dropdown-menu dropdown-menu-right">
                        <div class="notification-list mx-h-350 customscroll">
                            <ul>
                                <li>
                                    <a href="#">
                                        <h3>Système</h3>
                                        <p>Aucune notification pour le moment.</p>
                                    </a>
                                </li>
                            </ul>
                        </div>
                    </div>
                </div>
            </div>

            <!-- User info -->
            <div class="user-info-dropdown">
                <div class="dropdown">
                    <a class="dropdown-toggle" href="#" role="button" data-toggle="dropdown">
                        <span class="user-icon">
                            <?php if ($escAvatar): ?>
                                <img src="<?= $escAvatar ?>" alt="<?= $escName ?>" style="width:100%;height:100%;object-fit:cover;">
                            <?php else: ?>
                                <span style="display:inline-flex;width:100%;height:100%;align-items:center;justify-content:center;background:var(--uconnect-green);color:#fff;font-weight:700;border-radius:50%;">
                                    <?= strtoupper(substr($escName, 0, 1)) ?>
                                </span>
                            <?php endif; ?>
                        </span>
                        <span class="user-name"><?= $escName ?></span>
                    </a>
                    <div class="dropdown-menu dropdown-menu-right dropdown-menu-icon-list">
                        <div class="pd-10" style="border-bottom:1px solid #eef1f5;">
                            <div class="font-14 weight-600 text-dark"><?= $escName ?></div>
                            <div class="mt-1">
                                <span class="uconnect-role-badge">
                                    <span class="uconnect-role-dot"></span>
                                    <?= $escRole ?>
                                </span>
                            </div>
                        </div>
                        <a class="dropdown-item" href="<?= htmlspecialchars(app_route_url('profile', $user['role_system'] ?? null), ENT_QUOTES, 'UTF-8') ?>">
                            <i class="dw dw-user1"></i> Mon profil
                        </a>
                        <a class="dropdown-item" href="<?= htmlspecialchars(app_route_url('messagerie', $user['role_system'] ?? null), ENT_QUOTES, 'UTF-8') ?>">
                            <i class="dw dw-chat"></i> Messagerie
                        </a>
                        <a class="dropdown-item" href="<?= htmlspecialchars(app_route_url('alertes', $user['role_system'] ?? null), ENT_QUOTES, 'UTF-8') ?>">
                            <i class="dw dw-notification"></i> Rappels & alertes
                        </a>
                        <?php if (userCan($user, 'utilisateurs.roles') || userCan($user, 'parametres.view')): ?>
                            <a class="dropdown-item" href="<?= htmlspecialchars(app_route_url('parametres', $user['role_system'] ?? null), ENT_QUOTES, 'UTF-8') ?>">
                                <i class="dw dw-settings2"></i> Paramètres
                            </a>
                        <?php endif; ?>
                        <div class="dropdown-divider"></div>
                        <a class="dropdown-item text-danger" href="#" id="logoutBtn2">
                            <i class="dw dw-logout"></i> Se déconnecter
                        </a>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- ============================================================
         RIGHT SIDEBAR (paramètres layout)
         ============================================================ -->
    <div class="right-sidebar">
        <div class="sidebar-title">
            <h3 class="weight-600 font-16 text-blue">
                Paramètres d'affichage
                <span class="btn-block font-weight-400 font-12">Interface</span>
            </h3>
            <div class="close-sidebar" data-toggle="right-sidebar-close">
                <i class="icon-copy ion-close-round"></i>
            </div>
        </div>
        <div class="right-sidebar-body customscroll">
            <div class="right-sidebar-body-content">
                <h4 class="weight-600 font-18 pb-10">Thème</h4>
                <div class="sidebar-btn-group pb-30 mb-10">
                    <a href="javascript:void(0);" class="btn btn-outline-primary header-white active">Clair</a>
                    <a href="javascript:void(0);" class="btn btn-outline-primary header-dark">Sombre</a>
                </div>
                <div class="reset-options pt-30 text-center">
                    <button class="btn btn-danger" id="reset-settings">Réinitialiser</button>
                </div>
            </div>
        </div>
    </div>

    <!-- ============================================================
         LEFT SIDEBAR
         ============================================================ -->
    <div class="left-side-bar">
        <div class="brand-logo">
            <a href="<?= htmlspecialchars(app_route_url('accueil'), ENT_QUOTES, 'UTF-8') ?>">
                <span class="uconnect-brand-text">U-Connect</span>
            </a>
            <div class="close-sidebar" data-toggle="left-sidebar-close">
                <i class="ion-close-round"></i>
            </div>
        </div>
        <div class="menu-block customscroll">
            <div class="sidebar-menu">
                <ul id="accordion-menu">
                    <?php if (!empty($SIDEBAR_CONFIG)): ?>
                        <?php foreach ($SIDEBAR_CONFIG as $sectionKey => $section): ?>
                            <?php
                            $visibleItems = array_filter($section['items'], function ($item) use ($user) {
                                if (empty($item['permission'])) return true;
                                return userCan($user, $item['permission']);
                            });
                            if (empty($visibleItems)) continue;
                            ?>

                            <?php if (!empty($section['label'])): ?>
                                <li>
                                    <div class="sidebar-small-cap"><?= htmlspecialchars($section['label']) ?></div>
                                </li>
                            <?php endif; ?>

                            <?php foreach ($visibleItems as $item) renderSidebarItem($item, $activeRoute, $user); ?>
                        <?php endforeach; ?>
                    <?php endif; ?>

                    <!-- Déconnexion -->
                    <li>
                        <div class="dropdown-divider"></div>
                    </li>
                    <li>
                        <a href="#" id="logoutBtn" class="dropdown-toggle no-arrow text-danger">
                            <span class="micon dw dw-logout"></span>
                            <span class="mtext">Déconnexion</span>
                        </a>
                    </li>
                </ul>
            </div>
        </div>
    </div>

    <div class="mobile-menu-overlay"></div>

    <!-- ============================================================
         MAIN CONTENT
         ============================================================ -->
    <div class="main-container">
        <div class="pd-ltr-20">


            <!-- CONTENU DYNAMIQUE -->
            <?php
            if (isset($content) && $content !== '') {
                echo $content;
            } else {
                echo '<div class="alert alert-warning">Aucun contenu à afficher.</div>';
            }
            ?>

            <!-- Footer -->
            <div class="footer-wrap pd-20 mb-20 card-box">
                <div class="d-flex flex-wrap justify-content-between align-items-center">
                    <div class="font-13 text-muted">
                        &copy; <span id="year"></span> <strong>U-Connect</strong> — EALI
                    </div>
                    <div class="font-12 text-muted">
                        Version 1.0 — <?= $escRole ?>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- ============================================================
         FORMULAIRE DE DÉCONNEXION
         ============================================================ -->
    <form id="logoutForm" method="post" action="<?= htmlspecialchars(app_url('logout.php'), ENT_QUOTES, 'UTF-8') ?>" class="d-none">
        <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($_SESSION['csrf_token'] ?? '', ENT_QUOTES, 'UTF-8') ?>">
    </form>

    <!-- ============================================================
         JS DESKAPP
         ============================================================ -->
    <script src="<?= htmlspecialchars(app_url('dash/template/vendors/scripts/core.js')) ?>"></script>
    <script src="<?= htmlspecialchars(app_url('dash/template/vendors/scripts/script.min.js')) ?>"></script>
    <script src="<?= htmlspecialchars(app_url('dash/template/vendors/scripts/process.js')) ?>"></script>
    <script src="<?= htmlspecialchars(app_url('dash/template/vendors/scripts/layout-settings.js')) ?>"></script>

    <!-- ============================================================
         LOGIQUE PERSONNALISÉE
         ============================================================ -->
    <script>
    (function () {
        // ---- Année automatique ----
        const yearEl = document.getElementById('year');
        if (yearEl) yearEl.textContent = new Date().getFullYear();

        // ---- Logout avec SweetAlert2 ----
        function handleLogout(e) {
            if (e) e.preventDefault();
            Swal.fire({
                title: 'Se déconnecter ?',
                text: 'Votre session sera fermée.',
                icon: 'warning',
                showCancelButton: true,
                confirmButtonText: 'Oui, se déconnecter',
                cancelButtonText: 'Annuler',
                confirmButtonColor: '#36c783',
                cancelButtonColor: '#6b7280',
                reverseButtons: true
            }).then((r) => {
                if (r.isConfirmed) {
                    localStorage.removeItem('auth_token');
                    localStorage.removeItem('auth_user');
                    sessionStorage.removeItem('auth_token');
                    sessionStorage.removeItem('auth_user');
                    const f = document.getElementById('logoutForm');
                    if (f) f.requestSubmit();
                }
            });
        }
        document.getElementById('logoutBtn')?.addEventListener('click', handleLogout);
        document.getElementById('logoutBtn2')?.addEventListener('click', handleLogout);

        // ---- Notification badge (masqué par défaut) ----
        const badge = document.getElementById('notificationBadge');
        if (badge) badge.style.display = 'none';

        // ---- Sidebar: garder ouvert le sous-menu actif ----
        document.querySelectorAll('#accordion-menu > li.dropdown').forEach(function (li) {
            const activeChild = li.querySelector('.submenu a.active');
            const submenu = li.querySelector('.submenu');
            const parentLink = li.querySelector('a.dropdown-toggle');
            if (activeChild && submenu) {
                submenu.classList.remove('hidden');
                submenu.style.display = 'block';
                if (parentLink) parentLink.classList.add('active');
            }
        });
    })();
    </script>
</body>
</html>