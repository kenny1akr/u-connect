<?php
/**
 * dash/admin/index.php
 * Tableau de bord — Super Admin (U-Connect)
 * Affiché via le router : /super_admin/accueil
 *
 * Ce fichier est inclus par router.php puis rendu dans layout.php
 * via la variable $content.
 */

// Sécurité : accès direct interdit
if (!defined('ROUTER_LOADED')) {
    http_response_code(403);
    exit('Accès direct interdit.');
}

// ============================================================
// CONNEXION BASE DE DONNÉES
// ============================================================
require_once __DIR__ . "/../../api/database.php";
$db = Database::getInstance();

// ============================================================
// 1. KPIs PRINCIPAUX
// ============================================================

// -- Étudiants actifs
$totalEtudiants = $db->fetch(
    "SELECT COUNT(*) AS n FROM students WHERE status = 'actif'"
)['n'] ?? 0;

// -- Enseignants (users avec rôle enseignant)
$totalEnseignants = $db->fetch(
    "SELECT COUNT(*) AS n FROM users u
     JOIN roles r ON r.id = u.role_id
     WHERE r.slug = 'enseignant' AND u.status = 'actif'"
)['n'] ?? 0;

// -- Campus actifs
$totalCampus = $db->fetch(
    "SELECT COUNT(*) AS n FROM campuses WHERE is_active = 1"
)['n'] ?? 0;

// -- Filières / programmes actifs
$totalProgrammes = $db->fetch(
    "SELECT COUNT(*) AS n FROM programs WHERE is_active = 1"
)['n'] ?? 0;

// -- Paiements du mois (somme)
$paiementsMois = $db->fetch(
    "SELECT COALESCE(SUM(amount), 0) AS total
     FROM payments
     WHERE MONTH(paid_at) = MONTH(CURDATE())
       AND YEAR(paid_at) = YEAR(CURDATE())"
)['total'] ?? 0;

// -- Frais attendus (factures)
$fraisAttendus = $db->fetch(
    "SELECT COALESCE(SUM(amount_due), 0) AS total
     FROM invoices
     WHERE status <> 'annulée'"
)['total'] ?? 0;

// -- Frais payés
$fraisPayes = $db->fetch(
    "SELECT COALESCE(SUM(amount_paid), 0) AS total
     FROM invoices
     WHERE status <> 'annulée'"
)['total'] ?? 0;

// -- Taux de recouvrement
$tauxRecouvrement = $fraisAttendus > 0
    ? round(($fraisPayes / $fraisAttendus) * 100, 1)
    : 0;

// -- Nombre de paiements du mois
$nbPaiementsMois = $db->fetch(
    "SELECT COUNT(*) AS n FROM payments
     WHERE MONTH(paid_at) = MONTH(CURDATE())
       AND YEAR(paid_at) = YEAR(CURDATE())"
)['n'] ?? 0;

// -- Taux de réussite (année en cours)
$tauxReussite = $db->fetch(
    "SELECT
        CASE WHEN COUNT(*) = 0 THEN 0
        ELSE ROUND(100.0 * SUM(CASE WHEN decision = 'admis' THEN 1 ELSE 0 END) / COUNT(*), 1)
        END AS taux
     FROM year_results yr
     JOIN academic_years ay ON ay.id = yr.academic_year_id
     WHERE ay.is_current = 1"
)['taux'] ?? 0;

// -- Taux de présence moyen
$tauxPresence = $db->fetch(
    "SELECT
        CASE WHEN COUNT(*) = 0 THEN 0
        ELSE ROUND(100.0 * SUM(CASE WHEN status IN ('présent','retard') THEN 1 ELSE 0 END) / COUNT(*), 1)
        END AS taux
     FROM attendance"
)['taux'] ?? 0;

// -- Nombre d'inscriptions en attente
$inscriptionsEnAttente = $db->fetch(
    "SELECT COUNT(*) AS n FROM enrollments WHERE status = 'en_attente'"
)['n'] ?? 0;

// -- Nombre d'admissions en cours
$admissionsEnCours = $db->fetch(
    "SELECT COUNT(*) AS n FROM admission_applications
     WHERE status IN ('soumise','en_examen','liste_attente')"
)['n'] ?? 0;

// -- Notes non validées (par les enseignants)
$notesNonSoumises = $db->fetch(
    "SELECT COUNT(*) AS n FROM evaluations
     WHERE is_published = 0
       AND academic_year_id = (SELECT id FROM academic_years WHERE is_current = 1 LIMIT 1)"
)['n'] ?? 0;

// -- Documents générés ce mois
$documentsMois = $db->fetch(
    "SELECT COUNT(*) AS n FROM documents
     WHERE MONTH(issued_at) = MONTH(CURDATE())
       AND YEAR(issued_at) = YEAR(CURDATE())"
)['n'] ?? 0;

// -- Prêts de livres en cours
$pretsEnCours = $db->fetch(
    "SELECT COUNT(*) AS n FROM book_loans WHERE returned_at IS NULL"
)['n'] ?? 0;

// -- Amendes impayées
$amendesImpayees = $db->fetch(
    "SELECT COALESCE(SUM(amount), 0) AS total
     FROM library_fines WHERE status = 'impayée'"
)['total'] ?? 0;

// -- Alertes non traitées
$alertesActives = $db->fetch(
    "SELECT COUNT(*) AS n FROM alerts WHERE is_dismissed = 0"
)['n'] ?? 0;

// ============================================================
// 2. STATS PAR CAMPUS
// ============================================================
$campusStats = $db->fetchAll(
    "SELECT
        c.id,
        c.code,
        c.name,
        c.city,
        (SELECT COUNT(*) FROM students s WHERE s.campus_id = c.id AND s.status = 'actif') AS etudiants,
        (SELECT COUNT(*) FROM enrollments e WHERE e.campus_id = c.id AND e.status = 'validée') AS inscriptions,
        (SELECT COALESCE(SUM(i.amount_due), 0) FROM invoices i
            JOIN students s2 ON s2.id = i.student_id
            WHERE s2.campus_id = c.id AND i.status <> 'annulée') AS attendu,
        (SELECT COALESCE(SUM(i.amount_paid), 0) FROM invoices i
            JOIN students s2 ON s2.id = i.student_id
            WHERE s2.campus_id = c.id AND i.status <> 'annulée') AS paye
     FROM campuses c
     WHERE c.is_active = 1
     ORDER BY c.name"
) ?: [];

// Calcul du taux de recouvrement par campus
foreach ($campusStats as &$cs) {
    $cs['recouvrement'] = $cs['attendu'] > 0
        ? round(($cs['paye'] / $cs['attendu']) * 100, 1)
        : 0;
}
unset($cs);

// ============================================================
// 3. ACTIVITÉS RÉCENTES (derniers paiements, inscriptions, notes)
// ============================================================
$recentActivities = [];

// Derniers paiements
$recentPayments = $db->fetchAll(
    "SELECT
        p.id,
        p.amount,
        p.currency,
        p.paid_at,
        s.matricule,
        CONCAT(s.last_name, ' ', s.first_name) AS student_name
     FROM payments p
     JOIN invoices i ON i.id = p.invoice_id
     JOIN students s ON s.id = i.student_id
     ORDER BY p.paid_at DESC
     LIMIT 3"
) ?: [];

foreach ($recentPayments as $pay) {
    $recentActivities[] = [
        'type'  => 'paiement',
        'icon'  => 'dw dw-dollar',
        'color' => '#36c783',
        'title' => 'Paiement reçu — ' . $pay['student_name'],
        'desc'  => number_format($pay['amount'], 0, ',', ' ') . ' ' . $pay['currency']
                   . ' (matricule ' . $pay['matricule'] . ')',
        'time'  => 'Le ' . date('d/m/Y à H:i', strtotime($pay['paid_at'])),
    ];
}

// Dernières inscriptions
$recentEnrollments = $db->fetchAll(
    "SELECT
        e.id,
        e.created_at,
        e.level,
        e.status,
        s.matricule,
        CONCAT(s.last_name, ' ', s.first_name) AS student_name,
        p.name AS program_name,
        c.name AS campus_name
     FROM enrollments e
     JOIN students s ON s.id = e.student_id
     JOIN programs p ON p.id = e.program_id
     JOIN campuses c ON c.id = e.campus_id
     ORDER BY e.created_at DESC
     LIMIT 3"
) ?: [];

foreach ($recentEnrollments as $enr) {
    $recentActivities[] = [
        'type'  => 'inscription',
        'icon'  => 'dw dw-add-user',
        'color' => '#3b82f6',
        'title' => 'Inscription — ' . $enr['student_name'],
        'desc'  => $enr['level'] . ' ' . $enr['program_name'] . ' — ' . $enr['campus_name']
                   . ' (' . $enr['status'] . ')',
        'time'  => 'Le ' . date('d/m/Y à H:i', strtotime($enr['created_at'])),
    ];
}

// Dernières notes publiées
$recentGrades = $db->fetchAll(
    "SELECT
        ev.id,
        ev.title,
        ev.type,
        ev.evaluation_date,
        c.title AS course_title,
        c.code AS course_code,
        u.f_name,
        u.l_name
     FROM evaluations ev
     JOIN courses c ON c.id = ev.course_id
     JOIN users u ON u.id = ev.teacher_id
     WHERE ev.is_published = 1
     ORDER BY ev.evaluation_date DESC
     LIMIT 3"
) ?: [];

foreach ($recentGrades as $gr) {
    $recentActivities[] = [
        'type'  => 'note',
        'icon'  => 'dw dw-file',
        'color' => '#f59e0b',
        'title' => 'Notes publiées — ' . $gr['course_title'],
        'desc'  => $gr['type'] . ' (' . $gr['course_code'] . ') par '
                   . $gr['f_name'] . ' ' . $gr['l_name'],
        'time'  => 'Le ' . date('d/m/Y', strtotime($gr['evaluation_date'])),
    ];
}

// Trier par date décroissante (approximatif via l'ordre déjà fait)
$recentActivities = array_slice($recentActivities, 0, 8);

// ============================================================
// 4. ALERTES DYNAMIQUES (basées sur la BDD)
// ============================================================
$alerts = [];

// Factures impayées
$impayees = $db->fetch(
    "SELECT COUNT(*) AS n FROM invoices WHERE status = 'impayée'"
)['n'] ?? 0;
if ($impayees > 0) {
    $alerts[] = [
        'priority' => 'critique',
        'title'    => 'Factures impayées',
        'message'  => $impayees . ' facture(s) en attente de paiement.',
        'icon'     => 'dw dw-warning',
    ];
}

// Dossiers d'inscription incomplets
$incomplets = $db->fetch(
    "SELECT COUNT(*) AS n FROM v_enrollment_dossier WHERE dossier_status = 'incomplet'"
)['n'] ?? 0;
if ($incomplets > 0) {
    $alerts[] = [
        'priority' => 'haute',
        'title'    => 'Dossiers incomplets',
        'message'  => $incomplets . ' inscription(s) avec pièces manquantes.',
        'icon'     => 'dw dw-file',
    ];
}

// Notes non publiées
if ($notesNonSoumises > 0) {
    $alerts[] = [
        'priority' => 'haute',
        'title'    => 'Notes en attente',
        'message'  => $notesNonSoumises . ' évaluation(s) non publiée(s).',
        'icon'     => 'dw dw-clock',
    ];
}

// Amendes bibliothèque
if ($amendesImpayees > 0) {
    $alerts[] = [
        'priority' => 'moyenne',
        'title'    => 'Amendes bibliothèque',
        'message'  => number_format($amendesImpayees, 0, ',', ' ') . ' BIF impayés.',
        'icon'     => 'dw dw-book',
    ];
}

// Contrats expirant
$contratsExpirants = $db->fetchAll(
    "SELECT full_name, end_date, days_left
     FROM v_contracts_expiring
     ORDER BY days_left ASC LIMIT 3"
) ?: [];
foreach ($contratsExpirants as $ce) {
    $alerts[] = [
        'priority' => $ce['days_left'] <= 15 ? 'haute' : 'moyenne',
        'title'    => 'Contrat expirant',
        'message'  => $ce['full_name'] . ' — expire dans ' . $ce['days_left'] . ' jour(s).',
        'icon'     => 'dw dw-user1',
    ];
}

$alerts = array_slice($alerts, 0, 5);

// ============================================================
// 5. TOP 5 MEILLEURS ÉTUDIANTS
// ============================================================
$topStudents = $db->fetchAll(
    "SELECT
        s.matricule,
        CONCAT(s.last_name, ' ', s.first_name) AS student_name,
        s.current_level,
        p.name AS program_name,
        yr.average,
        yr.decision,
        yr.mention_label
     FROM year_results yr
     JOIN students s ON s.id = yr.student_id
     JOIN programs p ON p.id = yr.program_id
     JOIN academic_years ay ON ay.id = yr.academic_year_id
     WHERE ay.is_current = 1 AND yr.average IS NOT NULL
     ORDER BY yr.average DESC
     LIMIT 5"
) ?: [];

// ============================================================
// 6. RÉPARTITION PAR NIVEAU (LMD)
// ============================================================
$repartitionNiveau = $db->fetchAll(
    "SELECT
        current_level AS level,
        COUNT(*) AS total
     FROM students
     WHERE status = 'actif'
     GROUP BY current_level
     ORDER BY FIELD(current_level, 'L1','L2','L3','M1','M2','D')"
) ?: [];

// ============================================================
// 7. PAIEMENTS 6 DERNIERS MOIS (pour graphique)
// ============================================================
$paiements6Mois = $db->fetchAll(
    "SELECT
        DATE_FORMAT(paid_at, '%Y-%m') AS mois,
        COUNT(*) AS nb,
        COALESCE(SUM(amount), 0) AS total
     FROM payments
     WHERE paid_at >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
     GROUP BY DATE_FORMAT(paid_at, '%Y-%m')
     ORDER BY mois ASC"
) ?: [];

// ============================================================
// HELPERS
// ============================================================
function formatMontant($n, $devise = 'BIF') {
    return number_format($n, 0, ',', ' ') . ' ' . $devise;
}
function formatNombre($n) {
    return number_format($n, 0, ',', ' ');
}
?>

<!-- ============================================================
     BANNIÈRE DE BIENVENUE
     ============================================================ -->
<div class="card-box pd-20 mb-30">
    <div class="row align-items-center">
        <div class="col-md-8">
            <h4 class="font-22 weight-500 mb-10">
                Bonjour <span class="weight-700 text-primary"><?= htmlspecialchars($user['nom_complet'] ?? 'Super Administrateur') ?></span> 👋
            </h4>
            <p class="font-16 text-muted mb-0">
                Voici l'état de l'université au
                <strong><?= date('d/m/Y à H:i') ?></strong> —
                Année académique en cours : <strong>2026-2027</strong>
            </p>
        </div>
        <div class="col-md-4 text-right">
            <a href="<?= htmlspecialchars(app_route_url('etudiants/ajouter'), ENT_QUOTES, 'UTF-8') ?>"
               class="btn btn-primary btn-lg">
                <i class="dw dw-add-user mr-1"></i> Nouvelle inscription
            </a>
        </div>
    </div>
</div>

<!-- ============================================================
     LIGNE 1 : 4 KPIs PRINCIPAUX
     ============================================================ -->
<div class="row">
    <!-- Étudiants -->
    <div class="col-xl-3 col-lg-6 col-md-6 mb-30">
        <div class="card-box pd-20 height-100-p widget-style1">
            <div class="d-flex align-items-center justify-content-between">
                <div>
                    <div class="h3 mb-1 font-30 weight-700 text-dark"><?= formatNombre($totalEtudiants) ?></div>
                    <div class="weight-500 font-14 text-muted">Étudiants inscrits</div>
                </div>
                <div class="widget-icon" style="background:rgba(54,199,131,0.12);color:#36c783;">
                    <i class="dw dw-group"></i>
                </div>
            </div>
            <div class="mt-3 d-flex justify-content-between align-items-center">
                <span class="badge badge-success">+ <?= $totalCampus ?> campus</span>
                <a href="<?= htmlspecialchars(app_route_url('etudiants'), ENT_QUOTES, 'UTF-8') ?>" class="font-13 text-primary">Voir →</a>
            </div>
        </div>
    </div>

    <!-- Enseignants -->
    <div class="col-xl-3 col-lg-6 col-md-6 mb-30">
        <div class="card-box pd-20 height-100-p widget-style1">
            <div class="d-flex align-items-center justify-content-between">
                <div>
                    <div class="h3 mb-1 font-30 weight-700 text-dark"><?= formatNombre($totalEnseignants) ?></div>
                    <div class="weight-500 font-14 text-muted">Enseignants actifs</div>
                </div>
                <div class="widget-icon" style="background:rgba(59,130,246,0.12);color:#3b82f6;">
                    <i class="dw dw-user1"></i>
                </div>
            </div>
            <div class="mt-3 d-flex justify-content-between align-items-center">
                <span class="badge badge-primary"><?= $totalProgrammes ?> filières</span>
                <a href="<?= htmlspecialchars(app_route_url('enseignants'), ENT_QUOTES, 'UTF-8') ?>" class="font-13 text-primary">Voir →</a>
            </div>
        </div>
    </div>

    <!-- Paiements du mois -->
    <div class="col-xl-3 col-lg-6 col-md-6 mb-30">
        <div class="card-box pd-20 height-100-p widget-style1">
            <div class="d-flex align-items-center justify-content-between">
                <div>
                    <div class="h3 mb-1 font-30 weight-700 text-dark"><?= formatMontant($paiementsMois) ?></div>
                    <div class="weight-500 font-14 text-muted">Paiements du mois</div>
                </div>
                <div class="widget-icon" style="background:rgba(245,158,11,0.12);color:#f59e0b;">
                    <i class="dw dw-dollar"></i>
                </div>
            </div>
            <div class="mt-3 d-flex justify-content-between align-items-center">
                <span class="badge badge-warning"><?= $nbPaiementsMois ?> paiements</span>
                <a href="<?= htmlspecialchars(app_route_url('finances/paiements'), ENT_QUOTES, 'UTF-8') ?>" class="font-13 text-primary">Voir →</a>
            </div>
        </div>
    </div>

    <!-- Taux de réussite -->
    <div class="col-xl-3 col-lg-6 col-md-6 mb-30">
        <div class="card-box pd-20 height-100-p widget-style1">
            <div class="d-flex align-items-center justify-content-between">
                <div>
                    <div class="h3 mb-1 font-30 weight-700 text-dark"><?= $tauxReussite ?>%</div>
                    <div class="weight-500 font-14 text-muted">Taux de réussite</div>
                </div>
                <div class="widget-icon" style="background:rgba(139,92,246,0.12);color:#8b5cf6;">
                    <i class="dw dw-award"></i>
                </div>
            </div>
            <div class="mt-3 d-flex justify-content-between align-items-center">
                <span class="badge badge-info">Année 2026-2027</span>
                <a href="<?= htmlspecialchars(app_route_url('rapports/academique'), ENT_QUOTES, 'UTF-8') ?>" class="font-13 text-primary">Voir →</a>
            </div>
        </div>
    </div>
</div>

<!-- ============================================================
     LIGNE 2 : 4 KPIs SECONDAIRES
     ============================================================ -->
<div class="row">
    <!-- Taux de recouvrement -->
    <div class="col-xl-3 col-lg-6 col-md-6 mb-30">
        <div class="card-box pd-20 height-100-p">
            <div class="d-flex align-items-center justify-content-between mb-2">
                <div class="weight-600 font-14 text-muted">Recouvrement financier</div>
                <i class="dw dw-dollar" style="color:#36c783;font-size:20px;"></i>
            </div>
            <div class="h2 weight-700 mb-2"><?= $tauxRecouvrement ?>%</div>
            <div class="progress mb-2" style="height:10px;">
                <div class="progress-bar" role="progressbar"
                     style="width:<?= $tauxRecouvrement ?>%;background:#36c783;"
                     aria-valuenow="<?= $tauxRecouvrement ?>" aria-valuemin="0" aria-valuemax="100"></div>
            </div>
            <div class="font-12 text-muted">
                <?= formatMontant($fraisPayes) ?> / <?= formatMontant($fraisAttendus) ?>
            </div>
        </div>
    </div>

    <!-- Taux de présence -->
    <div class="col-xl-3 col-lg-6 col-md-6 mb-30">
        <div class="card-box pd-20 height-100-p">
            <div class="d-flex align-items-center justify-content-between mb-2">
                <div class="weight-600 font-14 text-muted">Taux de présence</div>
                <i class="dw dw-check" style="color:#3b82f6;font-size:20px;"></i>
            </div>
            <div class="h2 weight-700 mb-2"><?= $tauxPresence ?>%</div>
            <div class="progress mb-2" style="height:10px;">
                <div class="progress-bar" role="progressbar"
                     style="width:<?= $tauxPresence ?>%;background:#3b82f6;"
                     aria-valuenow="<?= $tauxPresence ?>" aria-valuemin="0" aria-valuemax="100"></div>
            </div>
            <div class="font-12 text-muted">Sur l'ensemble des cours enregistrés</div>
        </div>
    </div>

    <!-- Inscriptions en attente -->
    <div class="col-xl-3 col-lg-6 col-md-6 mb-30">
        <div class="card-box pd-20 height-100-p">
            <div class="d-flex align-items-center justify-content-between mb-2">
                <div class="weight-600 font-14 text-muted">Inscriptions en attente</div>
                <i class="dw dw-add-user" style="color:#f59e0b;font-size:20px;"></i>
            </div>
            <div class="h2 weight-700 mb-2"><?= formatNombre($inscriptionsEnAttente) ?></div>
            <div class="font-12 text-muted">
                <?= formatNombre($admissionsEnCours) ?> candidature(s) en cours d'examen
            </div>
            <a href="<?= htmlspecialchars(app_route_url('etudiants/inscriptions'), ENT_QUOTES, 'UTF-8') ?>"
               class="font-13 text-primary d-block mt-2">Traiter les dossiers →</a>
        </div>
    </div>

    <!-- Documents générés -->
    <div class="col-xl-3 col-lg-6 col-md-6 mb-30">
        <div class="card-box pd-20 height-100-p">
            <div class="d-flex align-items-center justify-content-between mb-2">
                <div class="weight-600 font-14 text-muted">Documents ce mois</div>
                <i class="dw dw-file" style="color:#8b5cf6;font-size:20px;"></i>
            </div>
            <div class="h2 weight-700 mb-2"><?= formatNombre($documentsMois) ?></div>
            <div class="font-12 text-muted">
                Relevés, certificats, diplômes générés
            </div>
            <a href="<?= htmlspecialchars(app_route_url('documents'), ENT_QUOTES, 'UTF-8') ?>"
               class="font-13 text-primary d-block mt-2">Voir les documents →</a>
        </div>
    </div>
</div>

<!-- ============================================================
     LIGNE 3 : RÉPARTITION PAR CAMPUS + ALERTES
     ============================================================ -->
<div class="row">
    <!-- Campus -->
    <div class="col-xl-8 mb-30">
        <div class="card-box height-100-p pd-20">
            <div class="d-flex justify-content-between align-items-center mb-3">
                <h2 class="h4 mb-0">Répartition par campus</h2>
                <span class="badge badge-light"><?= count($campusStats) ?> campus actifs</span>
            </div>
            <div class="table-responsive">
                <table class="table table-hover mb-0">
                    <thead>
                        <tr>
                            <th>Campus</th>
                            <th class="text-right">Étudiants</th>
                            <th class="text-right">Inscriptions</th>
                            <th class="text-right">Recouvrement</th>
                            <th class="text-right">Montant payé</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($campusStats as $c): ?>
                            <tr>
                                <td>
                                    <strong><?= htmlspecialchars($c['name']) ?></strong>
                                    <br>
                                    <small class="text-muted"><?= htmlspecialchars($c['city'] ?? '') ?></small>
                                </td>
                                <td class="text-right"><?= formatNombre($c['etudiants']) ?></td>
                                <td class="text-right"><?= formatNombre($c['inscriptions']) ?></td>
                                <td class="text-right">
                                    <div class="progress" style="height:8px;min-width:80px;">
                                        <div class="progress-bar" role="progressbar"
                                             style="width:<?= $c['recouvrement'] ?>%;background:#36c783;"
                                             aria-valuenow="<?= $c['recouvrement'] ?>" aria-valuemin="0" aria-valuemax="100"></div>
                                    </div>
                                    <small class="text-muted"><?= $c['recouvrement'] ?>%</small>
                                </td>
                                <td class="text-right font-14 weight-600">
                                    <?= formatMontant($c['paye']) ?>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                        <?php if (empty($campusStats)): ?>
                            <tr><td colspan="5" class="text-center text-muted">Aucun campus enregistré.</td></tr>
                        <?php endif; ?>
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <!-- Alertes -->
    <div class="col-xl-4 mb-30">
        <div class="card-box height-100-p pd-20">
            <div class="d-flex justify-content-between align-items-center mb-3">
                <h2 class="h4 mb-0">Alertes</h2>
                <a href="<?= htmlspecialchars(app_route_url('alertes'), ENT_QUOTES, 'UTF-8') ?>" class="font-13 text-primary">Tout voir</a>
            </div>
            <?php if (empty($alerts)): ?>
                <div class="text-center text-muted py-4">
                    <i class="dw dw-check" style="font-size:40px;color:#36c783;"></i>
                    <p class="mt-2 mb-0">Aucune alerte active.</p>
                </div>
            <?php else: ?>
                <?php foreach ($alerts as $a): ?>
                    <?php
                    $colors = [
                        'critique' => ['bg' => '#fef2f2', 'border' => '#fecaca', 'text' => '#b91c1c'],
                        'haute'    => ['bg' => '#fff7ed', 'border' => '#fed7aa', 'text' => '#c2410c'],
                        'moyenne'  => ['bg' => '#eff6ff', 'border' => '#bfdbfe', 'text' => '#1d4ed8'],
                        'basse'    => ['bg' => '#f0fdf4', 'border' => '#bbf7d0', 'text' => '#166534'],
                    ];
                    $c = $colors[$a['priority']] ?? $colors['moyenne'];
                    ?>
                    <div class="alert-item mb-2" style="background:<?= $c['bg'] ?>;border:1px solid <?= $c['border'] ?>;border-radius:10px;padding:12px;">
                        <div class="d-flex align-items-start gap-2">
                            <i class="<?= htmlspecialchars($a['icon']) ?>" style="color:<?= $c['text'] ?>;font-size:18px;margin-top:2px;"></i>
                            <div class="flex-grow-1">
                                <div class="font-14 weight-600" style="color:<?= $c['text'] ?>;"><?= htmlspecialchars($a['title']) ?></div>
                                <div class="font-12 text-muted mt-1"><?= htmlspecialchars($a['message']) ?></div>
                            </div>
                        </div>
                    </div>
                <?php endforeach; ?>
            <?php endif; ?>
        </div>
    </div>
</div>

<!-- ============================================================
     LIGNE 4 : ACTIVITÉS RÉCENTES + TOP ÉTUDIANTS
     ============================================================ -->
<div class="row">
    <!-- Activités récentes -->
    <div class="col-xl-7 mb-30">
        <div class="card-box height-100-p pd-20">
            <div class="d-flex justify-content-between align-items-center mb-3">
                <h2 class="h4 mb-0">Activités récentes</h2>
                <a href="<?= htmlspecialchars(app_route_url('rapports'), ENT_QUOTES, 'UTF-8') ?>" class="font-13 text-primary">Voir tout</a>
            </div>
            <ul class="list-unstyled mb-0">
                <?php foreach ($recentActivities as $act): ?>
                    <li class="d-flex align-items-start gap-3 py-2" style="border-bottom:1px solid #f1f5f9;">
                        <div class="activity-icon" style="background:<?= $act['color'] ?>15;color:<?= $act['color'] ?>;">
                            <i class="<?= htmlspecialchars($act['icon']) ?>"></i>
                        </div>
                        <div class="flex-grow-1 min-w-0">
                            <div class="font-14 weight-600 text-dark"><?= htmlspecialchars($act['title']) ?></div>
                            <div class="font-12 text-muted"><?= htmlspecialchars($act['desc']) ?></div>
                        </div>
                        <div class="font-12 text-muted flex-shrink-0"><?= htmlspecialchars($act['time']) ?></div>
                    </li>
                <?php endforeach; ?>
                <?php if (empty($recentActivities)): ?>
                    <li class="text-center text-muted py-4">Aucune activité récente.</li>
                <?php endif; ?>
            </ul>
        </div>
    </div>

    <!-- Top étudiants -->
    <div class="col-xl-5 mb-30">
        <div class="card-box height-100-p pd-20">
            <h2 class="h4 mb-3"> Top 5 étudiants</h2>
            <?php if (empty($topStudents)): ?>
                <div class="text-center text-muted py-4">
                    <i class="dw dw-award" style="font-size:40px;color:#f59e0b;"></i>
                    <p class="mt-2 mb-0">Aucun résultat académique disponible.</p>
                </div>
            <?php else: ?>
                <ul class="list-unstyled mb-0">
                    <?php foreach ($topStudents as $i => $st): ?>
                        <li class="d-flex align-items-center gap-3 py-2" style="border-bottom:1px solid #f1f5f9;">
                            <div class="font-18 weight-700" style="width:30px;color:#f59e0b;">
                                #<?= $i + 1 ?>
                            </div>
                            <div class="flex-grow-1 min-w-0">
                                <div class="font-14 weight-600 text-dark"><?= htmlspecialchars($st['student_name']) ?></div>
                                <div class="font-12 text-muted">
                                    <?= htmlspecialchars($st['current_level']) ?> — <?= htmlspecialchars($st['program_name']) ?>
                                    — <span class="text-primary"><?= htmlspecialchars($st['mention_label'] ?? '') ?></span>
                                </div>
                            </div>
                            <div class="font-16 weight-700 text-success"><?= $st['average'] ?>/20</div>
                        </li>
                    <?php endforeach; ?>
                </ul>
            <?php endif; ?>
        </div>
    </div>
</div>

<!-- ============================================================
     LIGNE 5 : RÉPARTITION PAR NIVEAU + ACTIONS RAPIDES
     ============================================================ -->
<div class="row">
    <!-- Répartition par niveau -->
    <div class="col-xl-7 mb-30">
        <div class="card-box height-100-p pd-20">
            <h2 class="h4 mb-3"> Répartition par niveau (LMD)</h2>
            <?php if (empty($repartitionNiveau)): ?>
                <p class="text-muted">Aucune donnée disponible.</p>
            <?php else: ?>
                <?php
                $totalNiveau = array_sum(array_column($repartitionNiveau, 'total'));
                foreach ($repartitionNiveau as $n):
                    $pct = $totalNiveau > 0 ? round(($n['total'] / $totalNiveau) * 100, 1) : 0;
                    $color = match ($n['level']) {
                        'L1' => '#36c783', 'L2' => '#22c55e', 'L3' => '#16a34a',
                        'M1' => '#3b82f6', 'M2' => '#6366f1', 'D'  => '#8b5cf6',
                        default => '#6b7280',
                    };
                ?>
                    <div class="mb-3">
                        <div class="d-flex justify-content-between mb-1">
                            <span class="font-14 weight-600"><?= htmlspecialchars($n['level']) ?></span>
                            <span class="font-13 text-muted"><?= formatNombre($n['total']) ?> étudiants (<?= $pct ?>%)</span>
                        </div>
                        <div class="progress" style="height:12px;">
                            <div class="progress-bar" role="progressbar"
                                 style="width:<?= $pct ?>%;background:<?= $color ?>;"
                                 aria-valuenow="<?= $pct ?>" aria-valuemin="0" aria-valuemax="100"></div>
                        </div>
                    </div>
                <?php endforeach; ?>
            <?php endif; ?>
        </div>
    </div>

    <!-- Actions rapides -->
    <div class="col-xl-5 mb-30">
        <div class="card-box height-100-p pd-20">
            <h2 class="h4 mb-3"> Actions rapides</h2>
            <div class="d-grid gap-2">
                <a href="<?= htmlspecialchars(app_route_url('etudiants/ajouter'), ENT_QUOTES, 'UTF-8') ?>"
                   class="btn btn-primary btn-block text-left">
                    <i class="dw dw-add-user mr-2"></i> Ajouter un étudiant
                </a>
                <a href="<?= htmlspecialchars(app_route_url('notes/saisie'), ENT_QUOTES, 'UTF-8') ?>"
                   class="btn btn-outline-primary btn-block text-left mt-2">
                    <i class="dw dw-file mr-2"></i> Saisir des notes
                </a>
                <a href="<?= htmlspecialchars(app_route_url('finances/paiement/nouveau'), ENT_QUOTES, 'UTF-8') ?>"
                   class="btn btn-outline-primary btn-block text-left mt-2">
                    <i class="dw dw-dollar mr-2"></i> Enregistrer un paiement
                </a>
                <a href="<?= htmlspecialchars(app_route_url('documents/releve/generer'), ENT_QUOTES, 'UTF-8') ?>"
                   class="btn btn-outline-primary btn-block text-left mt-2">
                    <i class="dw dw-file mr-2"></i> Générer un relevé
                </a>
                <a href="<?= htmlspecialchars(app_route_url('rapports/global'), ENT_QUOTES, 'UTF-8') ?>"
                   class="btn btn-outline-primary btn-block text-left mt-2">
                    <i class="dw dw-bar-chart mr-2"></i> Voir les rapports
                </a>
            </div>
        </div>
    </div>
</div>

<!-- ============================================================
     STYLES SPÉCIFIQUES AU DASHBOARD
     ============================================================ -->
<style>
    .widget-icon {
        width: 56px;
        height: 56px;
        border-radius: 12px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        font-size: 26px;
        flex-shrink: 0;
    }
    .activity-icon {
        width: 38px;
        height: 38px;
        border-radius: 10px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        font-size: 18px;
        flex-shrink: 0;
    }
    .badge {
        font-size: 11px;
        font-weight: 600;
        padding: 4px 10px;
        border-radius: 6px;
    }
    .badge-light { background: #f3f4f6; color: #374151; }
    .badge-success { background: #dcfce7; color: #166534; }
    .badge-primary { background: #dbeafe; color: #1e40af; }
    .badge-warning { background: #fef3c7; color: #92400e; }
    .badge-info { background: #e0e7ff; color: #3730a3; }
    .badge-danger { background: #fee2e2; color: #991b1b; }
    .min-w-0 { min-width: 0; }
    .d-grid { display: grid; }
    .text-left { text-align: left; }
    .progress { background: #f1f5f9; border-radius: 999px; overflow: hidden; }
    .table-borderless td, .table-borderless th { border: 0; padding: 10px 8px; vertical-align: middle; }
    .table-hover tbody tr:hover { background: #f8fafc; }
</style>