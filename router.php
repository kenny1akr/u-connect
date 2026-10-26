<?php
/**
 * router.php — Point d'entrée unique U-Connect
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

if (empty($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

require_once __DIR__ . "/dash/template/permissions.php";
require_once __DIR__ . "/dash/template/sidebar_config.php";

if (!defined('ROUTER_LOADED')) {
    define('ROUTER_LOADED', true);
}

if (!defined('APP_BASE_PATH')) {
    $scriptDirectory = str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? ''));
    define('APP_BASE_PATH', $scriptDirectory === '/' || $scriptDirectory === '.' ? '' : rtrim($scriptDirectory, '/'));
}

if (!function_exists('app_url')) {
    function app_url(string $path = ''): string
    {
        return APP_BASE_PATH . '/' . ltrim($path, '/');
    }
}

if (!function_exists('app_route_url')) {
    function app_route_url(string $path, ?string $role = null, array $params = []): string
    {
        $role = $role ?? ($_SESSION['role'] ?? '');
        $path = trim($path, '/');
        if ($role !== '' && $path !== $role && strpos($path, $role . '/') !== 0) {
            $path = $role . '/' . $path;
        }

        // ✅ URL correcte : router.php?route=...
        $url = app_url('router.php') . '?route=' . urlencode($path);

        // Ajouter des paramètres supplémentaires (id, page, etc.)
        if (!empty($params)) {
            $url .= '&' . http_build_query($params);
        }

        return $url;
    }
}

// ============================================================
// DOSSIERS PHYSIQUES PAR RÔLE
// ============================================================
$ROLE_DIRECTORIES = [
    'super_admin'           => 'dash/super_admin',
    'recteur'               => 'dash/admin',
    'secretaire_general'    => 'dash/direction_administrative/Secrétaire Général',
    'directeur_campus'      => 'dash/admin',
    'daf'                   => 'dash/direction_administrative/daf',
    'doyen'                 => 'dash/direction_des_services_académiques/Doyen',
    'chef_departement'      => 'dash/direction_des_services_académiques/Chef de Département',
    'drh'                   => 'dash/direction_administrative/drh',
    'assurance_qualite'     => 'dash/direction_d_assurance _qualite',
    'recherche_innovation'  => 'dash/Direction_de_la_echerche_et_de_innovation',
    'comptable'             => 'dash/direction_administrative/comptable',
    'agent_scolarite'       => 'dash/direction_des_services_académiques/agent_scolarite',
    'caissier'              => 'dash/direction_administrative/comptable',
    'lecteur'               => 'dash/direction_administrative/lecteur',
    'enseignant'            => 'dash/enseignant',
    'etudiant'              => 'dash/etudiant',
    'parent'                => 'dash/parent',
];

$HOME_BY_ROLE = [
    'super_admin'           => 'dash/super_admin/index.php',
    'recteur'               => 'dash/admin/index.php',
    'secretaire_general'    => 'dash/direction_administrative/Secrétaire Général/index.php',
    'directeur_campus'      => 'dash/admin/index.php',
    'daf'                   => 'dash/direction_administrative/daf/index.php',
    'doyen'                 => 'dash/direction_des_services_académiques/Doyen/index.php',
    'chef_departement'      => 'dash/direction_des_services_académiques/Chef de Département/index.php',
    'drh'                   => 'dash/direction_administrative/drh/index.php',
    'assurance_qualite'     => 'dash/direction_d_assurance _qualite/index.php',
    'recherche_innovation'  => 'dash/Direction_de_la_echerche_et_de_innovation/index.php',
    'comptable'             => 'dash/direction_administrative/comptable/index.php',
    'agent_scolarite'       => 'dash/direction_des_services_académiques/agent_scolarite/index.php',
    'caissier'              => 'dash/direction_administrative/comptable/index.php',
    'lecteur'               => 'dash/direction_administrative/lecteur/index.php',
    'enseignant'            => 'dash/enseignant/index.php',
    'etudiant'              => 'dash/etudiant/index.php',
    'parent'                => 'dash/parent/index.php',
];

// ============================================================
// CATALOGUE DES ROUTES
// ============================================================
$ROUTE_DEFINITIONS = [
    'accueil'               => ['index.php',          'dashboard.view', 'Tableau de bord'],
    'dashboard'             => ['index.php',          'dashboard.view', 'Tableau de bord'],
    'profil'                => ['profile.php',        'dashboard.view', 'Mon profil'],
    'notifications'         => ['notifications.php',  'dashboard.view', 'Notifications'],

    'etudiants'                    => ['etudiants_liste.php',      'etudiants.view', 'Étudiants'],
    'etudiants/liste'              => ['etudiants_liste.php',      'etudiants.view', 'Liste des étudiants'],
    'etudiants/ajouter'            => ['etudiant_add.php',         'etudiants.create', 'Ajouter un étudiant'],
    'etudiants/modifier'           => ['etudiant_edit.php',        'etudiants.edit', 'Modifier un étudiant'],
    'etudiants/detail'             => ['etudiant_detail.php',      'etudiants.view', 'Fiche étudiant'],
    'etudiants/transfert'          => ['etudiant_transfert.php',   'etudiants.transfer', 'Transfert inter-campus'],
    'etudiants/inscriptions'       => ['inscriptions_liste.php',   'etudiants.view', 'Inscriptions'],
    'etudiants/inscription/nouvelle' => ['inscription_nouvelle.php','etudiants.create', 'Nouvelle inscription'],
    'etudiants/documents'          => ['etudiant_documents.php',   'etudiants.view', 'Documents étudiant'],
    'etudiants/statut-financier'   => ['etudiant_finances.php',    'etudiants.statut_financier', 'Statut financier'],
    'etudiants/mes-etudiants'      => ['mes_etudiants.php',        'etudiants.mes_etudiants', 'Mes étudiants'],

    'notes'                        => ['notes_liste.php',          'notes.view', 'Notes'],
    'notes/saisie'                 => ['notes_saisie.php',         'notes.edit', 'Saisie des notes'],
    'notes/modifier'               => ['notes_modifier.php',       'notes.edit', 'Modifier une note'],
    'notes/validation'             => ['notes_validation.php',     'notes.validate', 'Validation des notes'],
    'notes/soumission'             => ['notes_soumission.php',     'notes.soumettre', 'Soumission des notes'],
    'notes/mes-notes'              => ['mes_notes.php',            'notes.mes_notes', 'Mes notes'],
    'notes/evaluations'            => ['evaluations_liste.php',    'notes.view', 'Évaluations'],
    'notes/evaluation/creer'       => ['evaluation_create.php',    'notes.edit', 'Créer une évaluation'],
    'cours'                        => ['cours_liste.php',          'ue.view', 'Cours / UE'],
    'cours/ajouter'                => ['cours_add.php',            'ue.edit', 'Ajouter un cours'],
    'cours/modifier'               => ['cours_edit.php',           'ue.edit', 'Modifier un cours'],
    'syllabus'                     => ['syllabus_liste.php',       'syllabus.view', 'Programmes (Syllabus)'],
    'syllabus/detail'              => ['syllabus_detail.php',      'syllabus.view', 'Détail du programme'],
    'syllabus/modifier'            => ['syllabus_edit.php',        'syllabus.edit', 'Modifier le programme'],
    'syllabus/coverage'            => ['syllabus_coverage.php',    'syllabus.edit', 'Couverture du programme'],
    'syllabus/validation'          => ['syllabus_validation.php',  'syllabus.validate', 'Valider le programme'],

    'enseignants'                  => ['enseignants_liste.php',    'enseignants.view', 'Enseignants'],
    'enseignants/liste'            => ['enseignants_liste.php',    'enseignants.view', 'Liste des enseignants'],
    'enseignants/ajouter'          => ['enseignant_add.php',       'enseignants.create', 'Ajouter un enseignant'],
    'enseignants/modifier'         => ['enseignant_edit.php',      'enseignants.edit', 'Modifier un enseignant'],
    'enseignants/detail'           => ['enseignant_detail.php',    'enseignants.view', 'Fiche enseignant'],
    'enseignants/affectations'     => ['enseignant_affectations.php', 'enseignants.view', 'Affectations'],
    'enseignants/charge'           => ['enseignant_charge.php',    'enseignants.view', 'Charge horaire'],
    'emploi-temps'                 => ['emploi_temps.php',         'emploi_temps.view', 'Emplois du temps'],
    'emploi-temps/creer'           => ['emploi_temps_create.php',  'emploi_temps.edit', 'Créer un emploi du temps'],
    'emploi-temps/modifier'        => ['emploi_temps_edit.php',    'emploi_temps.edit', 'Modifier l\'emploi du temps'],
    'emploi-temps/conflits'        => ['emploi_temps_conflits.php','emploi_temps.edit', 'Détection de conflits'],
    'emploi-temps/mon'             => ['mon_emploi_temps.php',     'emploi_temps.mon', 'Mon emploi du temps'],
    'salles'                       => ['salles_liste.php',         'emploi_temps.view', 'Gestion des salles'],

    'finances'                     => ['finances_index.php',       'finances.view', 'Finances'],
    'finances/frais'               => ['frais_liste.php',          'finances.view', 'Frais de scolarité'],
    'finances/frais/creer'         => ['frais_create.php',         'finances.create', 'Créer un frais'],
    'finances/paiements'           => ['paiements_liste.php',      'paiements.view', 'Paiements'],
    'finances/paiement/nouveau'    => ['paiement_nouveau.php',     'paiements.create', 'Nouveau paiement'],
    'finances/paiement/valider'    => ['paiement_valider.php',     'paiements.validate', 'Valider un paiement'],
    'finances/caisse'              => ['caisse.php',               'finances.caisse', 'Caisse'],
    'finances/caisse/operations'   => ['caisse_operations.php',    'finances.caisse', 'Opérations de caisse'],
    'finances/bourses'             => ['bourses_liste.php',        'bourses.view', 'Bourses & Aides'],
    'finances/bourse/creer'        => ['bourse_create.php',        'bourses.edit', 'Attribuer une bourse'],
    'finances/statut-financier'    => ['statut_financier.php',     'finances.view', 'Statut financier'],
    'finances/mon-statut'          => ['mon_statut.php',           'finances.mon_statut', 'Mon statut financier'],

    'documents'                    => ['documents_liste.php',      'documents.view', 'Documents'],
    'documents/releves'            => ['releves_liste.php',        'documents.view', 'Relevés de notes'],
    'documents/releve/generer'     => ['releve_generer.php',       'documents.generer_releve', 'Générer un relevé'],
    'documents/certificat/generer' => ['certificat_generer.php',   'documents.generer_certificat', 'Générer un certificat'],
    'documents/diplome/generer'    => ['diplome_generer.php',      'documents.generer_diplome', 'Générer un diplôme'],
    'documents/archives'           => ['documents_archives.php',   'documents.archive', 'Archives documentaires'],
    'documents/mon-releve'         => ['mon_releve.php',           'documents.mon_releve', 'Mon relevé de notes'],

    'messagerie'                   => ['messagerie.php',           'messagerie.view', 'Messagerie interne'],
    'messagerie/envoyer'           => ['messagerie_envoyer.php',   'messagerie.send', 'Envoyer un message'],
    'messagerie/annonces'          => ['annonces_liste.php',       'messagerie.view', 'Annonces'],
    'messagerie/annonce/creer'     => ['annonce_create.php',       'messagerie.send', 'Créer une annonce'],

    'rapports'                     => ['rapports_index.php',       'rapports.view', 'Rapports'],
    'rapports/academique'          => ['rapports_academique.php',  'rapports.academique', 'Rapports académiques'],
    'rapports/financier'           => ['rapports_financier.php',   'rapports.financier', 'Rapports financiers'],
    'rapports/caisse'              => ['rapports_caisse.php',      'rapports.caisse', 'Rapports de caisse'],
    'rapports/global'              => ['rapports_global.php',      'rapports.global', 'Rapports globaux'],
    'rapports/campus'              => ['rapports_campus.php',      'rapports.campus', 'Rapports par campus'],
    'rapports/faculte'             => ['rapports_faculte.php',     'rapports.faculte', 'Rapports de faculté'],
    'rapports/departement'         => ['rapports_departement.php', 'rapports.departement', 'Rapports de département'],
    'rapports/administratif'       => ['rapports_admin.php',       'rapports.administratif', 'Rapports administratifs'],
    'statistiques'                 => ['statistiques.php',         'dashboard.view', 'Statistiques'],
    'alertes'                      => ['alertes.php',              'dashboard.view', 'Alertes & Rappels'],

    'utilisateurs'                 => ['utilisateurs_liste.php',   'utilisateurs.view', 'Utilisateurs'],
    'utilisateurs/ajouter'         => ['utilisateur_add.php',      'utilisateurs.create', 'Ajouter un utilisateur'],
    'utilisateurs/modifier'        => ['utilisateur_edit.php',     'utilisateurs.edit', 'Modifier un utilisateur'],
    'roles'                        => ['roles.php',                'utilisateurs.view', 'Rôles & Permissions'],
    'parametres'                   => ['parametres.php',           'parametres.view', 'Paramètres'],
    'parametres/annee-academique'  => ['annee_academique.php',     'parametres.edit', 'Année académique'],
    'parametres/campus'            => ['campus_liste.php',         'parametres.edit', 'Gestion des campus'],
    'parametres/facultes'          => ['facultes_liste.php',       'parametres.edit', 'Facultés & Départements'],

    'bibliotheque'                 => ['bibliotheque_liste.php',   'bibliotheque.view', 'Bibliothèque'],
    'bibliotheque/preter'          => ['bibliotheque_preter.php',  'bibliotheque.preter', 'Prêter un livre'],
    'bibliotheque/retourner'       => ['bibliotheque_retourner.php','bibliotheque.retourner', 'Retourner un livre'],
    'bibliotheque/livres'          => ['livres_liste.php',         'bibliotheque.view', 'Catalogue de livres'],

    'mes-notes'                    => ['mes_notes.php',            'notes.mes_notes', 'Mes notes'],
    'mon-emploi-temps'             => ['mon_emploi_temps.php',     'emploi_temps.mon', 'Mon emploi du temps'],
    'mes-documents'                => ['mes_documents.php',        'documents.view', 'Mes documents'],
    'mon-statut'                   => ['mon_statut.php',           'finances.mon_statut', 'Ma situation financière'],
    'ma-bibliotheque'              => ['bibliotheque.php',         'bibliotheque.view', 'Bibliothèque'],

    'enfant/notes'                 => ['notes_enfant.php',         'notes.mes_notes', 'Notes de mon enfant'],
    'enfant/emploi-temps'          => ['emploi_temps_enfant.php',  'emploi_temps.mon', 'Emploi du temps'],
    'enfant/statut-financier'      => ['statut_financier.php',     'finances.mon_statut', 'Situation financière'],
    'enfant/documents'             => ['documents_enfant.php',     'documents.view', 'Documents'],
    'parent/messages'              => ['messagerie.php',           'messagerie.view', 'Messages'],

    'documents-officiels'          => ['documents_officiels.php',  'documents.view', 'Documents officiels'],
    'courrier'                     => ['courrier.php',             'messagerie.view', 'Courrier'],
    'personnel'                    => ['personnel.php',            'utilisateurs.view', 'Gestion du personnel'],
    'budget'                       => ['budget.php',               'finances.view', 'Budget'],
    'tresorerie'                   => ['tresorerie.php',           'finances.view', 'Trésorerie'],
    'immobilisations'              => ['immobilisations.php',      'finances.view', 'Immobilisations'],
    'audit'                        => ['audit.php',                'rapports.financier', 'Audit financier'],
    'mon-departement'              => ['mon_departement.php',      'dashboard.view', 'Mon département'],
    'mes-enseignants'              => ['mes_enseignants.php',      'enseignants.view', 'Mes enseignants'],
    'mes-cours'                    => ['mes_cours.php',            'notes.view', 'Mes cours'],
    'validation-notes'             => ['validation_notes.php',     'notes.validate', 'Validation des notes'],
    'controles'                    => ['controles.php',            'syllabus.view', 'Contrôles qualité'],
    'evaluations-qualite'          => ['evaluations.php',          'notes.view', 'Évaluations qualité'],
    'rapports-qualite'             => ['rapports.php',             'rapports.view', 'Rapports qualité'],
    'certifications'               => ['certifications.php',       'documents.view', 'Certifications'],
    'projets'                      => ['projets.php',              'syllabus.view', 'Projets de recherche'],
    'publications'                 => ['publications.php',         'documents.view', 'Publications'],
    'partenariats'                 => ['partenariats.php',         'rapports.view', 'Partenariats'],
    'financements'                 => ['financements.php',         'finances.view', 'Financements recherche'],


    // Gestion des Super Admins (admin_users)
    'admins'                       => ['admins_liste.php',         'admin_users.view',    'Super Administrateurs'],
    'admins/ajouter'               => ['admin_add.php',            'admin_users.create',  'Ajouter un Super Admin'],
    'admins/modifier'              => ['admin_edit.php',           'admin_users.edit',    'Modifier un Super Admin'],
];

// ============================================================
// CONSTRUCTION DES ROUTES PAR RÔLE
// ============================================================
$ROUTES_BY_ROLE = [];
$ALL_ROLE_ROUTES = [];

foreach ($ROLES as $roleName => $roleDefinition) {
    $roleUser = ["role_system" => $roleName];
    $ROUTES_BY_ROLE[$roleName] = [];
    $roleDir = $ROLE_DIRECTORIES[$roleName] ?? ('dash/' . $roleName);

    foreach ($ROUTE_DEFINITIONS as $routeName => $routeDefinition) {
        $roleRoute = $roleName . '/' . $routeName;
        $ALL_ROLE_ROUTES[$roleRoute] = true;

        if (userCan($roleUser, $routeDefinition[1])) {
            $fileName = $routeDefinition[0];
            if ($routeName === 'accueil' && isset($HOME_BY_ROLE[$roleName])) {
                $fullPath = $HOME_BY_ROLE[$roleName];
            } else {
                $fullPath = rtrim($roleDir, '/') . '/' . $fileName;
            }
            $ROUTES_BY_ROLE[$roleName][$roleRoute] = [
                $fullPath,
                $routeDefinition[1],
                $routeDefinition[2],
            ];
        }
    }
}

// ============================================================
// UTILISATEUR AUTHENTIFIÉ (admin_users OU users)
// ============================================================
if (empty($_SESSION["logged_in"]) || empty($_SESSION["user_id"])) {
    header("Location: " . app_url("auth/"));
    exit;
}

require_once __DIR__ . "/api/database.php";
$db = Database::getInstance();

$rawRole = null;
$userRecord = null;

// 1. Chercher dans admin_users
$adminRecord = $db->fetch(
    "SELECT id, user_name, admin_role AS raw_role, f_name, l_name, status, profil
     FROM admin_users
     WHERE id = ?
     LIMIT 1",
    [$_SESSION["user_id"]]
);

if ($adminRecord) {
    $userRecord = $adminRecord;
    $rawRole = $adminRecord["raw_role"]; // "super_admin" ou "admin"
    // Mapping admin_users.admin_role → slug U-Connect
    if ($rawRole === 'super_admin') {
        $rawRole = 'super_admin';
    } elseif ($rawRole === 'admin') {
        $rawRole = 'secretaire_general'; // Un "admin" sans rôle spécifique → SG par défaut
    }
} else {
    // 2. Chercher dans users
    $userRecord = $db->fetch(
        "SELECT id, user_name, category AS raw_role, f_name, l_name, status, profil
         FROM users
         WHERE id = ?
         LIMIT 1",
        [$_SESSION["user_id"]]
    );
    if ($userRecord) {
        $rawRole = $userRecord["raw_role"];
    }
}

if (!$userRecord || strtolower($userRecord["status"] ?? "") !== "actif") {
    $_SESSION = [];
    session_destroy();
    header("Location: " . app_url("auth/"));
    exit;
}

// Normaliser le rôle
$role = normalizeUserRole($rawRole);
if ($role === null) {
    // Rôle inconnu → on déconnecte et on affiche un message clair
    $_SESSION = [];
    session_destroy();
    header("Location: " . app_url("auth/") . "?error=role_inconnu");
    exit;
}

$user = [
    "utilisateur_id"  => (int) $userRecord["id"],
    "nom_complet"     => trim(($userRecord["f_name"] ?? "") . " " . ($userRecord["l_name"] ?? "")),
    "nom_utilisateur" => $userRecord["user_name"],
    "role_system"     => $role,
    "statut"          => $userRecord["status"],
    "avatar"          => $userRecord["profil"] ?? "",
];
$_SESSION["role"] = $role;
$ROUTES = $ROUTES_BY_ROLE[$role] ?? [];

// ============================================================
// ROUTE ACTUELLE
// ============================================================
$route = $_GET['route'] ?? ($role . '/accueil');
$route = strtolower(trim($route, '/'));
if ($route === '' || $route === 'index.php') {
    $route = $role . '/accueil';
}

// ============================================================
// RECHERCHE DE LA ROUTE
// ============================================================
if (!isset($ALL_ROLE_ROUTES[$route])) {
    http_response_code(404);
    require __DIR__ . "/404.php";
    exit;
}

if (!isset($ROUTES[$route])) {
    http_response_code(403);
    $pageTitle = "Accès refusé";
    ob_start();
    ?>
    <div class="max-w-lg mx-auto mt-16 text-center">
        <h1 class="text-2xl font-bold text-red-600 mb-2">Accès refusé</h1>
        <p class="text-slate-600 mb-6">
            Le rôle <strong><?= htmlspecialchars(getRoleLabel($user["role_system"])) ?></strong>
            ne possède pas la permission nécessaire pour cette route.
        </p>
        <p class="text-xs text-slate-400 mb-6">Route : <?= htmlspecialchars($route) ?></p>
        <a href="<?= htmlspecialchars(app_route_url('accueil'), ENT_QUOTES, 'UTF-8') ?>" class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg bg-muco text-white hover:bg-muco-dark transition">
            <i data-feather="arrow-left" class="w-4 h-4"></i> Retour au tableau de bord
        </a>
    </div>
    <?php
    $content = ob_get_clean();
    require_once __DIR__ . "/dash/template/layout.php";
    exit;
}

list($file, $requiredPermission, $pageTitle) = $ROUTES[$route];

if (!userCan($user, $requiredPermission)) {
    http_response_code(403);
    $pageTitle = "Accès refusé";
    ob_start();
    ?>
    <div class="max-w-lg mx-auto mt-16 text-center">
        <div class="text-6xl mb-4">🔒</div>
        <h1 class="text-2xl font-bold text-red-600 mb-2">Accès refusé</h1>
        <p class="text-slate-600 mb-6">
            Votre rôle <strong><?= htmlspecialchars(getRoleLabel($user["role_system"])) ?></strong>
            ne vous autorise pas à accéder à cette section.
        </p>
        <a href="<?= htmlspecialchars(app_route_url('accueil'), ENT_QUOTES, 'UTF-8') ?>" class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg bg-muco text-white hover:bg-muco-dark transition">
            <i data-feather="arrow-left" class="w-4 h-4"></i> Retour au tableau de bord
        </a>
    </div>
    <?php
    $content = ob_get_clean();
    require_once __DIR__ . "/dash/template/layout.php";
    exit;
}

// ============================================================
// CHARGEMENT DE LA PAGE
// ============================================================
$pagePath = __DIR__ . "/" . $file;

if (!file_exists($pagePath)) {
    http_response_code(404);
    require __DIR__ . "/404.php";
    exit;
}

ob_start();
require $pagePath;
$content = ob_get_clean();

require_once __DIR__ . "/dash/template/layout.php";