<?php
/**
 * dash/super_admin/roles.php
 * Gestion des rôles & permissions — Super Admin
 */

if (!defined('ROUTER_LOADED')) {
    http_response_code(403);
    exit('Accès direct interdit.');
}

require_once __DIR__ . "/../../api/database.php";
$db = Database::getInstance();

$errors = [];
$success = null;

// ============================================================
// TRAITEMENT DES ACTIONS (POST)
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';

    try {
        // --- Créer un rôle ---
        if ($action === 'create_role') {
            $slug  = trim($_POST['slug'] ?? '');
            $label = trim($_POST['label'] ?? '');
            $level = (int) ($_POST['level'] ?? 10);

            if ($slug === '')   $errors[] = "Le slug est requis.";
            if ($label === '')  $errors[] = "Le libellé est requis.";
            if (!preg_match('/^[a-z_]+$/', $slug)) $errors[] = "Le slug doit contenir uniquement des minuscules et underscores.";

            if ($db->fetch("SELECT id FROM roles WHERE slug = ?", [$slug])) {
                $errors[] = "Ce slug existe déjà.";
            }

            if (empty($errors)) {
                $db->execute(
                    "INSERT INTO roles (slug, label, level, is_system) VALUES (?, ?, ?, 0)",
                    [$slug, $label, $level]
                );
                header("Location: " . app_route_url('roles', null, ['success' => 'created']));
                exit;
            }
        }

        // --- Mettre à jour les permissions d'un rôle ---
        if ($action === 'update_permissions') {
            $roleId = (int) ($_POST['role_id'] ?? 0);
            $permissionIds = $_POST['permissions'] ?? []; // tableau d'IDs

            // Vérifier que le rôle existe et n'est pas système
            $roleRow = $db->fetch("SELECT id, is_system FROM roles WHERE id = ?", [$roleId]);
            if (!$roleRow) {
                $errors[] = "Rôle introuvable.";
            } elseif ($roleRow['is_system'] == 1) {
                $errors[] = "Impossible de modifier les permissions d'un rôle système.";
            } else {
                // Supprimer toutes les permissions actuelles
                $db->execute("DELETE FROM role_permissions WHERE role_id = ?", [$roleId]);

                // Insérer les nouvelles
                if (!empty($permissionIds)) {
                    $values = [];
                    $params = [];
                    foreach ($permissionIds as $pid) {
                        $values[] = "(?, ?)";
                        $params[] = $roleId;
                        $params[] = (int) $pid;
                    }
                    $sql = "INSERT INTO role_permissions (role_id, permission_id) VALUES " . implode(',', $values);
                    $db->execute($sql, $params);
                }

                header("Location: " . app_route_url('roles', null, ['success' => 'updated', 'role' => $roleId]));
                exit;
            }
        }

        // --- Supprimer un rôle ---
        if ($action === 'delete_role') {
            $roleId = (int) ($_POST['role_id'] ?? 0);
            $roleRow = $db->fetch("SELECT id, is_system FROM roles WHERE id = ?", [$roleId]);

            if (!$roleRow) {
                $errors[] = "Rôle introuvable.";
            } elseif ($roleRow['is_system'] == 1) {
                $errors[] = "Impossible de supprimer un rôle système.";
            } else {
                // Vérifier si des users sont liés
                $count = $db->fetch("SELECT COUNT(*) AS n FROM users WHERE role_id = ?", [$roleId])['n'] ?? 0;
                if ($count > 0) {
                    $errors[] = "Impossible de supprimer : $count utilisateur(s) possèdent ce rôle.";
                } else {
                    $db->execute("DELETE FROM roles WHERE id = ?", [$roleId]);
                    header("Location: " . app_route_url('roles', null, ['success' => 'deleted']));
                    exit;
                }
            }
        }
    } catch (Throwable $e) {
        $errors[] = "Erreur : " . $e->getMessage();
    }
}

// ============================================================
// RÉCUPÉRATION DES DONNÉES
// ============================================================

// Tous les rôles avec nombre d'utilisateurs
$roles = $db->fetchAll(
    "SELECT r.id, r.slug, r.label, r.level, r.is_system,
            (SELECT COUNT(*) FROM users u WHERE u.role_id = r.id) AS nb_users
     FROM roles r
     ORDER BY r.level DESC, r.label"
) ?: [];

// Toutes les permissions, groupées par domaine
$allPermissions = $db->fetchAll(
    "SELECT id, slug, description FROM permissions ORDER BY slug"
) ?: [];

// Grouper par domaine (avant le '.')
$permissionsByDomain = [];
foreach ($allPermissions as $p) {
    $domain = explode('.', $p['slug'])[0];
    $permissionsByDomain[$domain][] = $p;
}
ksort($permissionsByDomain);

// Permissions actuelles par rôle
$rolePermissions = [];
$rows = $db->fetchAll("SELECT role_id, permission_id FROM role_permissions") ?: [];
foreach ($rows as $r) {
    $rolePermissions[$r['role_id']][] = $r['permission_id'];
}

// Rôle sélectionné pour édition
$selectedRoleId = (int) ($_GET['role'] ?? 0);
if ($selectedRoleId === 0 && !empty($roles)) {
    $selectedRoleId = $roles[0]['id'];
}
$selectedRole = null;
foreach ($roles as $r) {
    if ($r['id'] == $selectedRoleId) {
        $selectedRole = $r;
        break;
    }
}

// Messages
$successMessages = [
    'created' => 'Rôle créé avec succès.',
    'updated' => 'Permissions mises à jour.',
    'deleted' => 'Rôle supprimé.',
];
$success = $successMessages[$_GET['success'] ?? ''] ?? null;
?>

<!-- ============================================================
     EN-TÊTE
     ============================================================ -->
<div class="pd-20 card-box mb-30">
    <div class="d-flex justify-content-between align-items-center flex-wrap">
        <div>
            <h4 class="h3 mb-1 text-primary">Rôles & Permissions</h4>
            <p class="text-muted mb-0">
                Gérez les rôles et leurs permissions dans l'application
            </p>
        </div>
        <button type="button" class="btn btn-primary" data-toggle="modal" data-target="#createRoleModal">
            <i class="dw dw-add-user mr-1"></i> Nouveau rôle
        </button>
    </div>
</div>

<!-- Messages -->
<?php if ($success): ?>
    <div class="alert alert-success mb-30">
        <i class="dw dw-check"></i> <?= htmlspecialchars($success) ?>
    </div>
<?php endif; ?>
<?php if (!empty($errors)): ?>
    <div class="alert alert-danger mb-30">
        <ul class="mb-0">
            <?php foreach ($errors as $err): ?><li><?= htmlspecialchars($err) ?></li><?php endforeach; ?>
        </ul>
    </div>
<?php endif; ?>

<!-- ============================================================
     LAYOUT : RÔLES À GAUCHE, PERMISSIONS À DROITE
     ============================================================ -->
<div class="row">
    <!-- Colonne gauche : liste des rôles -->
    <div class="col-lg-4 mb-30">
        <div class="card-box height-100-p pd-20">
            <h4 class="h4 mb-3">Rôles (<?= count($roles) ?>)</h4>
            <div class="list-group">
                <?php foreach ($roles as $r): ?>
                    <?php
                    $isActive = ($r['id'] == $selectedRoleId);
                    ?>
                    <a href="<?= htmlspecialchars(app_route_url('roles', null, ['role' => $r['id']]), ENT_QUOTES, 'UTF-8') ?>"
                       class="list-group-item list-group-item-action d-flex justify-content-between align-items-center <?= $isActive ? 'active' : '' ?>">
                        <div>
                            <div class="weight-600"><?= htmlspecialchars($r['label']) ?></div>
                            <small class="<?= $isActive ? 'text-white-50' : 'text-muted' ?>">
                                <?= htmlspecialchars($r['slug']) ?>
                                — Niveau <?= (int)$r['level'] ?>
                            </small>
                        </div>
                        <div class="d-flex align-items-center gap-2">
                            <span class="badge <?= $isActive ? 'badge-light' : 'badge-secondary' ?>">
                                <?= (int)$r['nb_users'] ?> user(s)
                            </span>
                            <?php if ($r['is_system'] == 1): ?>
                                <i class="dw dw-shield" title="Rôle système protégé"></i>
                            <?php endif; ?>
                        </div>
                    </a>
                <?php endforeach; ?>
            </div>
        </div>
    </div>

    <!-- Colonne droite : permissions du rôle sélectionné -->
    <div class="col-lg-8 mb-30">
        <div class="card-box height-100-p pd-20">
            <?php if (!$selectedRole): ?>
                <div class="text-center text-muted py-5">
                    <i class="dw dw-shield" style="font-size:60px;color:#ddd;"></i>
                    <p class="mt-3">Sélectionnez un rôle à gauche pour voir ses permissions.</p>
                </div>
            <?php else: ?>
                <div class="d-flex justify-content-between align-items-start mb-3">
                    <div>
                        <h4 class="h4 mb-1"><?= htmlspecialchars($selectedRole['label']) ?></h4>
                        <p class="text-muted mb-0">
                            <code><?= htmlspecialchars($selectedRole['slug']) ?></code>
                            — Niveau <?= (int)$selectedRole['level'] ?>
                            — <?= (int)$selectedRole['nb_users'] ?> utilisateur(s)
                        </p>
                    </div>
                    <?php if ($selectedRole['is_system'] == 1): ?>
                        <span class="badge badge-danger">
                            <i class="dw dw-shield"></i> Rôle système protégé
                        </span>
                    <?php else: ?>
                        <form method="post" action=""
                              onsubmit="return confirm('Supprimer définitivement le rôle &quot;<?= htmlspecialchars($selectedRole['label']) ?>&quot; ?');">
                            <input type="hidden" name="action" value="delete_role">
                            <input type="hidden" name="role_id" value="<?= (int)$selectedRole['id'] ?>">
                            <button type="submit" class="btn btn-sm btn-outline-danger">
                                <i class="dw dw-delete-3"></i> Supprimer le rôle
                            </button>
                        </form>
                    <?php endif; ?>
                </div>

                <hr>

                <?php if ($selectedRole['is_system'] == 1): ?>
                    <div class="alert alert-warning">
                        <i class="dw dw-warning"></i>
                        Ce rôle est <strong>protégé</strong>. Ses permissions ne peuvent pas être modifiées.
                        <?php if ($selectedRole['slug'] === 'super_admin'): ?>
                            Le Super Admin a <strong>tous les droits</strong> par défaut (<code>*</code>).
                        <?php endif; ?>
                    </div>
                    <!-- Afficher les permissions en lecture seule -->
                    <?php
                    $perms = $rolePermissions[$selectedRole['id']] ?? [];
                    $isSuperAdmin = ($selectedRole['slug'] === 'super_admin');
                    ?>
                    <?php if ($isSuperAdmin): ?>
                        <div class="alert alert-info">
                            <i class="dw dw-info"></i>
                            <strong>Super Admin</strong> possède la permission <code>*</code> (toutes les permissions).
                        </div>
                    <?php else: ?>
                        <p class="text-muted"><?= count($perms) ?> permission(s) assignée(s).</p>
                        <div class="d-flex flex-wrap gap-1">
                            <?php foreach ($perms as $pid):
                                $permSlug = '';
                                foreach ($allPermissions as $p) if ($p['id'] == $pid) $permSlug = $p['slug'];
                            ?>
                                <span class="badge badge-light"><?= htmlspecialchars($permSlug) ?></span>
                            <?php endforeach; ?>
                        </div>
                    <?php endif; ?>

                <?php else: ?>
                    <!-- Formulaire éditable -->
                    <form method="post" action="" id="permissionsForm">
                        <input type="hidden" name="action" value="update_permissions">
                        <input type="hidden" name="role_id" value="<?= (int)$selectedRole['id'] ?>">

                        <div class="d-flex justify-content-between align-items-center mb-3">
                            <h5 class="mb-0">Permissions (<?= count($permissionsByDomain) ?> domaines)</h5>
                            <div>
                                <button type="button" class="btn btn-sm btn-outline-secondary" onclick="toggleAll(true)">
                                    <i class="dw dw-check"></i> Tout cocher
                                </button>
                                <button type="button" class="btn btn-sm btn-outline-secondary" onclick="toggleAll(false)">
                                    <i class="dw dw-close"></i> Tout décocher
                                </button>
                            </div>
                        </div>

                        <?php
                        $currentPerms = $rolePermissions[$selectedRole['id']] ?? [];
                        ?>

                        <div class="row">
                            <?php foreach ($permissionsByDomain as $domain => $perms): ?>
                                <div class="col-md-6 mb-3">
                                    <div class="card border">
                                        <div class="card-header bg-light">
                                            <div class="d-flex justify-content-between align-items-center">
                                                <label class="mb-0 weight-600">
                                                    <input type="checkbox"
                                                           class="domain-toggle"
                                                           data-domain="<?= htmlspecialchars($domain) ?>"
                                                           <?= (function() use ($domain, $perms, $currentPerms) {
                                                               foreach ($perms as $p) {
                                                                   if (!in_array($p['id'], $currentPerms)) return '';
                                                               }
                                                               return 'checked';
                                                           })() ?>>
                                                    <?= htmlspecialchars(ucfirst($domain)) ?>
                                                </label>
                                                <span class="badge badge-secondary"><?= count($perms) ?></span>
                                            </div>
                                        </div>
                                        <div class="card-body py-2">
                                            <?php foreach ($perms as $p): ?>
                                                <div class="form-check mb-1">
                                                    <input type="checkbox"
                                                           class="form-check-input perm-checkbox domain-<?= htmlspecialchars($domain) ?>"
                                                           name="permissions[]"
                                                           value="<?= (int)$p['id'] ?>"
                                                           id="perm_<?= (int)$p['id'] ?>"
                                                           <?= in_array($p['id'], $currentPerms) ? 'checked' : '' ?>>
                                                    <label class="form-check-label small" for="perm_<?= (int)$p['id'] ?>">
                                                        <?= htmlspecialchars($p['slug']) ?>
                                                    </label>
                                                </div>
                                            <?php endforeach; ?>
                                        </div>
                                    </div>
                                </div>
                            <?php endforeach; ?>
                        </div>

                        <div class="text-right mt-3">
                            <button type="submit" class="btn btn-primary btn-lg">
                                <i class="dw dw-save mr-1"></i> Enregistrer les permissions
                            </button>
                        </div>
                    </form>
                <?php endif; ?>
            <?php endif; ?>
        </div>
    </div>
</div>

<!-- ============================================================
     MODAL : CRÉER UN NOUVEAU RÔLE
     ============================================================ -->
<div class="modal fade" id="createRoleModal" tabindex="-1" role="dialog">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <form method="post" action="">
                <input type="hidden" name="action" value="create_role">
                <div class="modal-header">
                    <h5 class="modal-title">Créer un nouveau rôle</h5>
                    <button type="button" class="close" data-dismiss="modal">
                        <span>&times;</span>
                    </button>
                </div>
                <div class="modal-body">
                    <div class="form-group">
                        <label>Libellé <span class="text-danger">*</span></label>
                        <input type="text" name="label" class="form-control" required
                               placeholder="ex: Coordinateur pédagogique">
                    </div>
                    <div class="form-group">
                        <label>Slug (identifiant technique) <span class="text-danger">*</span></label>
                        <input type="text" name="slug" class="form-control" required
                               pattern="[a-z_]+"
                               placeholder="ex: coordinateur_pedagogique">
                        <small class="text-muted">
                            Minuscules et underscores uniquement. Ex: <code>coordinateur_pedagogique</code>
                        </small>
                    </div>
                    <div class="form-group">
                        <label>Niveau hiérarchique</label>
                        <input type="number" name="level" class="form-control" value="50" min="1" max="100">
                        <small class="text-muted">Plus le niveau est élevé, plus le rôle est haut dans la hiérarchie.</small>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-dismiss="modal">Annuler</button>
                    <button type="submit" class="btn btn-primary">
                        <i class="dw dw-save mr-1"></i> Créer le rôle
                    </button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- ============================================================
     STYLES
     ============================================================ -->
<style>
    .list-group-item.active {
        background: #36c783;
        border-color: #36c783;
        color: #fff;
    }
    .list-group-item.active small {
        color: rgba(255,255,255,0.8) !important;
    }
    .badge { font-size: 11px; padding: 4px 10px; border-radius: 6px; }
    .badge-secondary { background: #f3f4f6; color: #374151; }
    .badge-light { background: #fff; color: #374151; }
    .badge-danger { background: #fee2e2; color: #991b1b; }
    .card-header { padding: 10px 15px; }
    .card-body.py-2 { padding-top: 10px; padding-bottom: 10px; }
    .form-check-input:checked { background-color: #36c783; border-color: #36c783; }
    .gap-2 { gap: 0.5rem; }
</style>

<!-- ============================================================
     SCRIPTS
     ============================================================ -->
<script>
// Cocher/décocher toutes les permissions
function toggleAll(checked) {
    document.querySelectorAll('.perm-checkbox').forEach(cb => {
        cb.checked = checked;
    });
    document.querySelectorAll('.domain-toggle').forEach(cb => {
        cb.checked = checked;
    });
}

// Cocher/décocher tout un domaine
document.querySelectorAll('.domain-toggle').forEach(toggle => {
    toggle.addEventListener('change', function() {
        const domain = this.dataset.domain;
        const checked = this.checked;
        document.querySelectorAll('.domain-' + domain).forEach(cb => {
            cb.checked = checked;
        });
    });
});

// Synchroniser les domain-toggle quand on coche un élément individuel
document.querySelectorAll('.perm-checkbox').forEach(cb => {
    cb.addEventListener('change', function() {
        const domain = this.className.match(/domain-(\w+)/)?.[1];
        if (!domain) return;
        const domainCheckboxes = document.querySelectorAll('.domain-' + domain);
        const allChecked = Array.from(domainCheckboxes).every(c => c.checked);
        const toggle = document.querySelector(`.domain-toggle[data-domain="${domain}"]`);
        if (toggle) toggle.checked = allChecked;
    });
});
</script>