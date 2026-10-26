<?php
/**
 * dash/super_admin/utilisateurs_liste.php
 * Liste des utilisateurs — Super Admin
 */

if (!defined('ROUTER_LOADED')) {
    http_response_code(403);
    exit('Accès direct interdit.');
}

require_once __DIR__ . "/../../api/database.php";
$db = Database::getInstance();

// ============================================================
// FILTRES
// ============================================================
$search       = trim($_GET['q'] ?? '');
$roleFilter   = $_GET['role'] ?? '';
$campusFilter = $_GET['campus'] ?? '';
$statusFilter = $_GET['status'] ?? '';

$where = ['1=1'];
$params = [];

if ($search !== '') {
    $where[] = "(u.user_name LIKE ? OR u.email LIKE ? OR u.f_name LIKE ? OR u.l_name LIKE ?)";
    $like = "%$search%";
    $params[] = $like; $params[] = $like; $params[] = $like; $params[] = $like;
}
if ($roleFilter !== '') {
    $where[] = "r.slug = ?";
    $params[] = $roleFilter;
}
if ($campusFilter !== '') {
    $where[] = "u.campus_id = ?";
    $params[] = (int) $campusFilter;
}
if ($statusFilter !== '') {
    $where[] = "u.status = ?";
    $params[] = $statusFilter;
}

$whereSql = implode(' AND ', $where);

// ============================================================
// PAGINATION
// ============================================================
$perPage = 20;
$page    = max(1, (int) ($_GET['page'] ?? 1));
$offset  = ($page - 1) * $perPage;

// ============================================================
// REQUÊTE PRINCIPALE
// ============================================================
$sql = "
    SELECT
        u.id, u.user_name, u.email, u.phone, u.f_name, u.l_name,
        u.category, u.campus_id, u.status, u.last_login_at, u.created_at, u.profil,
        r.label AS role_label, r.slug AS role_slug,
        c.name AS campus_name, c.code AS campus_code
    FROM users u
    LEFT JOIN roles r ON r.id = u.role_id
    LEFT JOIN campuses c ON c.id = u.campus_id
    WHERE $whereSql
    ORDER BY u.created_at DESC
    LIMIT $perPage OFFSET $offset
";

$users = $db->fetchAll($sql, $params);

$countSql = "SELECT COUNT(*) AS n FROM users u
             LEFT JOIN roles r ON r.id = u.role_id
             WHERE $whereSql";
$total = $db->fetch($countSql, $params)['n'] ?? 0;
$totalPages = ceil($total / $perPage);

// ============================================================
// LISTES POUR FILTRES
// ============================================================
$roles    = $db->fetchAll("SELECT id, slug, label FROM roles WHERE is_system = 0 ORDER BY label") ?: [];
$campuses = $db->fetchAll("SELECT id, code, name FROM campuses WHERE is_active = 1 ORDER BY name") ?: [];

// ============================================================
// STATISTIQUES
// ============================================================
$stats = [
    'total'      => $db->fetch("SELECT COUNT(*) AS n FROM users")['n'] ?? 0,
    'actifs'     => $db->fetch("SELECT COUNT(*) AS n FROM users WHERE status = 'actif'")['n'] ?? 0,
    'suspendus'  => $db->fetch("SELECT COUNT(*) AS n FROM users WHERE status = 'suspendu'")['n'] ?? 0,
    'desactives' => $db->fetch("SELECT COUNT(*) AS n FROM users WHERE status = 'désactivé'")['n'] ?? 0,
];

// ============================================================
// TOGGLE STATUS (traitement en PHP)
// ============================================================
if (isset($_GET['action']) && $_GET['action'] === 'toggle_status' && !empty($_GET['id'])) {
    $toggleId = (int) $_GET['id'];
    $currentUser = $db->fetch("SELECT status FROM users WHERE id = ?", [$toggleId]);
    if ($currentUser) {
        $newStatus = $currentUser['status'] === 'actif' ? 'désactivé' : 'actif';
        $db->execute("UPDATE users SET status = ? WHERE id = ?", [$newStatus, $toggleId]);
    }
    header("Location: " . app_route_url('utilisateurs', null, ['success' => 'status']));
    exit;
}
?>

<!-- EN-TÊTE -->
<div class="pd-20 card-box mb-30">
    <div class="d-flex justify-content-between align-items-center flex-wrap">
        <div>
            <h4 class="h3 mb-1 text-primary">Gestion des utilisateurs</h4>
            <p class="text-muted mb-0"><?= number_format($stats['total'], 0, ',', ' ') ?> utilisateur(s) au total</p>
        </div>
        <div class="d-flex gap-2 mt-3 mt-md-0">
            <a href="<?= htmlspecialchars(app_route_url('admins'), ENT_QUOTES, 'UTF-8') ?>"
               class="btn btn-outline-secondary">
                <i class="dw dw-shield mr-1"></i> Super Admins
            </a>
            <a href="<?= htmlspecialchars(app_route_url('utilisateurs/ajouter'), ENT_QUOTES, 'UTF-8') ?>"
               class="btn btn-primary">
                <i class="dw dw-add-user mr-1"></i> Ajouter un utilisateur
            </a>
        </div>
    </div>
</div>

<!-- CARTES STATISTIQUES -->
<div class="row">
    <div class="col-xl-3 col-md-6 mb-30">
        <div class="card-box pd-20">
            <div class="d-flex justify-content-between">
                <div>
                    <div class="h3 weight-700"><?= number_format($stats['total']) ?></div>
                    <div class="font-14 text-muted">Total utilisateurs</div>
                </div>
                <i class="dw dw-group" style="font-size:32px;color:#36c783;"></i>
            </div>
        </div>
    </div>
    <div class="col-xl-3 col-md-6 mb-30">
        <div class="card-box pd-20">
            <div class="d-flex justify-content-between">
                <div>
                    <div class="h3 weight-700 text-success"><?= number_format($stats['actifs']) ?></div>
                    <div class="font-14 text-muted">Actifs</div>
                </div>
                <i class="dw dw-check" style="font-size:32px;color:#22c55e;"></i>
            </div>
        </div>
    </div>
    <div class="col-xl-3 col-md-6 mb-30">
        <div class="card-box pd-20">
            <div class="d-flex justify-content-between">
                <div>
                    <div class="h3 weight-700 text-warning"><?= number_format($stats['suspendus']) ?></div>
                    <div class="font-14 text-muted">Suspendus</div>
                </div>
                <i class="dw dw-warning" style="font-size:32px;color:#f59e0b;"></i>
            </div>
        </div>
    </div>
    <div class="col-xl-3 col-md-6 mb-30">
        <div class="card-box pd-20">
            <div class="d-flex justify-content-between">
                <div>
                    <div class="h3 weight-700 text-danger"><?= number_format($stats['desactives']) ?></div>
                    <div class="font-14 text-muted">Désactivés</div>
                </div>
                <i class="dw dw-close" style="font-size:32px;color:#ef4444;"></i>
            </div>
        </div>
    </div>
</div>

<!-- FILTRES -->
<div class="card-box pd-20 mb-30">
    <form method="get" action="<?= htmlspecialchars(app_url('router.php'), ENT_QUOTES, 'UTF-8') ?>">
        <input type="hidden" name="route" value="<?= htmlspecialchars($route ?? 'super_admin/utilisateurs') ?>">
        <div class="row">
            <div class="col-md-3 mb-2">
                <input type="text" name="q" class="form-control"
                       placeholder="Rechercher (nom, email, identifiant)"
                       value="<?= htmlspecialchars($search) ?>">
            </div>
            <div class="col-md-2 mb-2">
                <select name="role" class="form-control">
                    <option value="">Tous les rôles</option>
                    <?php foreach ($roles as $r): ?>
                        <option value="<?= htmlspecialchars($r['slug']) ?>"
                            <?= $roleFilter === $r['slug'] ? 'selected' : '' ?>>
                            <?= htmlspecialchars($r['label']) ?>
                        </option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="col-md-2 mb-2">
                <select name="campus" class="form-control">
                    <option value="">Tous les campus</option>
                    <?php foreach ($campuses as $c): ?>
                        <option value="<?= (int)$c['id'] ?>"
                            <?= (string)$campusFilter === (string)$c['id'] ? 'selected' : '' ?>>
                            <?= htmlspecialchars($c['name']) ?>
                        </option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="col-md-2 mb-2">
                <select name="status" class="form-control">
                    <option value="">Tous les statuts</option>
                    <option value="actif" <?= $statusFilter === 'actif' ? 'selected' : '' ?>>Actif</option>
                    <option value="suspendu" <?= $statusFilter === 'suspendu' ? 'selected' : '' ?>>Suspendu</option>
                    <option value="désactivé" <?= $statusFilter === 'désactivé' ? 'selected' : '' ?>>Désactivé</option>
                </select>
            </div>
            <div class="col-md-3 mb-2 d-flex gap-2">
                <button type="submit" class="btn btn-primary flex-grow-1">
                    <i class="dw dw-search2 mr-1"></i> Filtrer
                </button>
                <a href="<?= htmlspecialchars(app_route_url('utilisateurs'), ENT_QUOTES, 'UTF-8') ?>"
                   class="btn btn-outline-secondary">Reset</a>
            </div>
        </div>
    </form>
</div>

<!-- TABLEAU -->
<div class="card-box mb-30">
    <div class="pd-20">
        <h4 class="h4 mb-0">Liste des utilisateurs</h4>
    </div>
    <div class="pb-20">
        <table class="table table-hover nowrap">
            <thead>
                <tr>
                    <th>Utilisateur</th>
                    <th>Rôle</th>
                    <th>Campus</th>
                    <th>Statut</th>
                    <th>Dernière connexion</th>
                    <th class="text-right">Actions</th>
                </tr>
            </thead>
            <tbody>
                <?php if (empty($users)): ?>
                    <tr><td colspan="6" class="text-center text-muted py-4">Aucun utilisateur trouvé.</td></tr>
                <?php else: ?>
                    <?php foreach ($users as $u): ?>
                        <tr>
                            <td>
                                <div class="d-flex align-items-center gap-2">
                                    <?php if (!empty($u['profil'])): ?>
                                        <img src="<?= htmlspecialchars($u['profil']) ?>" class="rounded-circle" width="40" height="40">
                                    <?php else: ?>
                                        <span class="rounded-circle bg-primary text-white d-inline-flex align-items-center justify-content-center"
                                              style="width:40px;height:40px;font-weight:700;">
                                            <?= strtoupper(substr($u['f_name'] ?? '?', 0, 1)) ?>
                                        </span>
                                    <?php endif; ?>
                                    <div>
                                        <div class="weight-600"><?= htmlspecialchars($u['f_name'] . ' ' . $u['l_name']) ?></div>
                                        <div class="font-12 text-muted">
                                            @<?= htmlspecialchars($u['user_name']) ?> — <?= htmlspecialchars($u['email']) ?>
                                        </div>
                                    </div>
                                </div>
                            </td>
                            <td>
                                <span class="badge badge-info">
                                    <?= htmlspecialchars($u['role_label'] ?? $u['category']) ?>
                                </span>
                            </td>
                            <td>
                                <?php if (!empty($u['campus_name'])): ?>
                                    <span class="badge badge-light">
                                        <i class="dw dw-map-pin"></i> <?= htmlspecialchars($u['campus_name']) ?>
                                    </span>
                                <?php else: ?>
                                    <span class="text-muted">— (tous)</span>
                                <?php endif; ?>
                            </td>
                            <td>
                                <?php
                                $statusColor = match ($u['status']) {
                                    'actif' => 'success',
                                    'suspendu' => 'warning',
                                    'désactivé' => 'danger',
                                    default => 'secondary',
                                };
                                ?>
                                <span class="badge badge-<?= $statusColor ?>"><?= htmlspecialchars(ucfirst($u['status'])) ?></span>
                            </td>
                            <td>
                                <?php if ($u['last_login_at']): ?>
                                    <span class="font-12"><?= date('d/m/Y H:i', strtotime($u['last_login_at'])) ?></span>
                                <?php else: ?>
                                    <span class="text-muted font-12">Jamais</span>
                                <?php endif; ?>
                            </td>
                            <td class="text-right">
                                <div class="dropdown">
                                    <a class="btn btn-link font-24 p-0 no-arrow dropdown-toggle"
                                       href="#" role="button" data-toggle="dropdown">
                                        <i class="dw dw-more"></i>
                                    </a>
                                    <div class="dropdown-menu dropdown-menu-right dropdown-menu-icon-list">
                                        <a class="dropdown-item"
                                           href="<?= htmlspecialchars(app_route_url('utilisateurs/modifier', null, ['id' => $u['id']]), ENT_QUOTES, 'UTF-8') ?>">
                                            <i class="dw dw-edit2"></i> Modifier
                                        </a>
                                        <div class="dropdown-divider"></div>
                                        <a class="dropdown-item text-danger" href="#"
                                           onclick="confirmToggleStatus(<?= $u['id'] ?>, '<?= htmlspecialchars($u['status']) ?>'); return false;">
                                            <i class="dw dw-<?= $u['status'] === 'actif' ? 'close' : 'check' ?>"></i>
                                            <?= $u['status'] === 'actif' ? 'Désactiver' : 'Activer' ?>
                                        </a>
                                    </div>
                                </div>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                <?php endif; ?>
            </tbody>
        </table>
    </div>

    <!-- Pagination -->
    <?php if ($totalPages > 1): ?>
        <div class="pd-20 border-top">
            <nav>
                <ul class="pagination mb-0 justify-content-center">
                    <?php for ($p = 1; $p <= $totalPages; $p++): ?>
                        <li class="page-item <?= $p === $page ? 'active' : '' ?>">
                            <a class="page-link"
                               href="<?= htmlspecialchars(app_route_url('utilisateurs', null, [
                                   'page' => $p,
                                   'q' => $search,
                                   'role' => $roleFilter,
                                   'campus' => $campusFilter,
                                   'status' => $statusFilter
                               ]), ENT_QUOTES, 'UTF-8') ?>">
                                <?= $p ?>
                            </a>
                        </li>
                    <?php endfor; ?>
                </ul>
            </nav>
        </div>
    <?php endif; ?>
</div>

<script>
function confirmToggleStatus(userId, currentStatus) {
    const action = currentStatus === 'actif' ? 'désactiver' : 'activer';
    Swal.fire({
        title: `Confirmer la ${action}ation ?`,
        text: `L'utilisateur sera ${action === 'désactiver' ? 'désactivé' : 'réactivé'}.`,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonText: `Oui, ${action}`,
        cancelButtonText: 'Annuler',
        confirmButtonColor: '#36c783',
        reverseButtons: true
    }).then((r) => {
        if (r.isConfirmed) {
            window.location.href = `<?= htmlspecialchars(app_url('router.php'), ENT_QUOTES, 'UTF-8') ?>?route=<?= urlencode(($route ?? 'super_admin/utilisateurs')) ?>&action=toggle_status&id=${userId}`;
        }
    });
}
</script>

<style>
    .badge { font-size: 11px; padding: 4px 10px; border-radius: 6px; }
    .badge-success { background: #dcfce7; color: #166534; }
    .badge-warning { background: #fef3c7; color: #92400e; }
    .badge-danger { background: #fee2e2; color: #991b1b; }
    .badge-info { background: #dbeafe; color: #1e40af; }
    .badge-light { background: #f3f4f6; color: #374151; }
</style>