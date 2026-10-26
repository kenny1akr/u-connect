<?php
/**
 * dash/super_admin/utilisateur_edit.php
 * Modifier un utilisateur — Super Admin
 */

if (!defined('ROUTER_LOADED')) {
    http_response_code(403);
    exit('Accès direct interdit.');
}

require_once __DIR__ . "/../../api/database.php";
$db = Database::getInstance();

$id = (int) ($_GET['id'] ?? 0);
if ($id === 0) {
    header("Location: " . app_route_url('utilisateurs'));
    exit;
}

// ✅ RENOMMÉ : $editUser au lieu de $user (pour ne pas écraser $user du layout)
$editUser = $db->fetch(
    "SELECT u.*, r.slug AS role_slug, r.label AS role_label
     FROM users u
     LEFT JOIN roles r ON r.id = u.role_id
     WHERE u.id = ? LIMIT 1",
    [$id]
);

if (!$editUser) {
    header("Location: " . app_route_url('utilisateurs'));
    exit;
}

$errors = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $email    = trim($_POST['email'] ?? '');
    $phone    = trim($_POST['phone'] ?? '');
    $fName    = trim($_POST['f_name'] ?? '');
    $lName    = trim($_POST['l_name'] ?? '');
    $gender   = $_POST['gender'] ?? 'O';
    $roleSlug = $_POST['role_slug'] ?? '';
    $campusId = !empty($_POST['campus_id']) ? (int) $_POST['campus_id'] : null;
    $status   = $_POST['status'] ?? 'actif';
    $newPass  = $_POST['new_password'] ?? '';

    if ($email === '')  $errors[] = "L'email est requis.";
    if ($fName === '')  $errors[] = "Le prénom est requis.";
    if ($lName === '')  $errors[] = "Le nom est requis.";
    if ($roleSlug === '') $errors[] = "Le rôle est requis.";

    $existing = $db->fetch("SELECT id FROM users WHERE email = ? AND id <> ?", [$email, $id]);
    if ($existing) $errors[] = "Cet email est déjà utilisé.";

    $roleRow = $db->fetch("SELECT id FROM roles WHERE slug = ?", [$roleSlug]);
    if (!$roleRow) $errors[] = "Rôle invalide.";

    if (empty($errors)) {
        try {
            if ($newPass !== '') {
                if (strlen($newPass) < 8) {
                    $errors[] = "Le nouveau mot de passe doit faire au moins 8 caractères.";
                } else {
                    $db->execute(
                        "UPDATE users SET
                            email = ?, phone = ?, f_name = ?, l_name = ?, gender = ?,
                            category = ?, role_id = ?, campus_id = ?, status = ?,
                            password_hash = ?, must_change_password = 1
                         WHERE id = ?",
                        [
                            $email, $phone ?: null, $fName, $lName, $gender,
                            $roleSlug, $roleRow['id'], $campusId, $status,
                            password_hash($newPass, PASSWORD_BCRYPT), $id
                        ]
                    );
                }
            } else {
                $db->execute(
                    "UPDATE users SET
                        email = ?, phone = ?, f_name = ?, l_name = ?, gender = ?,
                        category = ?, role_id = ?, campus_id = ?, status = ?
                     WHERE id = ?",
                    [
                        $email, $phone ?: null, $fName, $lName, $gender,
                        $roleSlug, $roleRow['id'], $campusId, $status, $id
                    ]
                );
            }

            if (empty($errors)) {
                header("Location: " . app_route_url('utilisateurs', null, ['success' => 'edit']));
                exit;
            }
        } catch (Throwable $e) {
            $errors[] = "Erreur : " . $e->getMessage();
        }
    }
}

$roles    = $db->fetchAll("SELECT id, slug, label FROM roles WHERE is_system = 0 ORDER BY label") ?: [];
$campuses = $db->fetchAll("SELECT id, code, name, city FROM campuses WHERE is_active = 1 ORDER BY name") ?: [];
?>

<div class="pd-20 card-box mb-30">
    <div class="d-flex justify-content-between align-items-center">
        <div>
            <h4 class="h3 mb-1 text-primary">Modifier un utilisateur</h4>
            <p class="text-muted mb-0">
                <?= htmlspecialchars($editUser['f_name'] . ' ' . $editUser['l_name']) ?>
                — @<?= htmlspecialchars($editUser['user_name']) ?>
            </p>
        </div>
        <a href="<?= htmlspecialchars(app_route_url('utilisateurs'), ENT_QUOTES, 'UTF-8') ?>"
           class="btn btn-outline-secondary">
            <i class="dw dw-left-arrow mr-1"></i> Retour
        </a>
    </div>
</div>

<?php if (!empty($errors)): ?>
    <div class="alert alert-danger mb-30">
        <ul class="mb-0">
            <?php foreach ($errors as $err): ?><li><?= htmlspecialchars($err) ?></li><?php endforeach; ?>
        </ul>
    </div>
<?php endif; ?>

<form method="post" action="">
    <div class="row">
        <div class="col-lg-8">
            <div class="card-box pd-20 mb-30">
                <h4 class="h4 mb-3">Informations</h4>
                <div class="row">
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Prénom</label>
                        <input type="text" name="f_name" class="form-control" required
                               value="<?= htmlspecialchars($_POST['f_name'] ?? $editUser['f_name']) ?>">
                    </div>
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Nom</label>
                        <input type="text" name="l_name" class="form-control" required
                               value="<?= htmlspecialchars($_POST['l_name'] ?? $editUser['l_name']) ?>">
                    </div>
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Email</label>
                        <input type="email" name="email" class="form-control" required
                               value="<?= htmlspecialchars($_POST['email'] ?? $editUser['email']) ?>">
                    </div>
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Téléphone</label>
                        <input type="text" name="phone" class="form-control"
                               value="<?= htmlspecialchars($_POST['phone'] ?? $editUser['phone']) ?>">
                    </div>
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Genre</label>
                        <select name="gender" class="form-control">
                            <option value="O">Non précisé</option>
                            <option value="M" <?= ($editUser['gender'] === 'M') ? 'selected' : '' ?>>Masculin</option>
                            <option value="F" <?= ($editUser['gender'] === 'F') ? 'selected' : '' ?>>Féminin</option>
                        </select>
                    </div>
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Nouveau mot de passe</label>
                        <input type="password" name="new_password" class="form-control"
                               minlength="8" placeholder="Laisser vide pour ne pas changer">
                    </div>
                </div>
            </div>
        </div>

        <div class="col-lg-4">
            <div class="card-box pd-20 mb-30">
                <h4 class="h4 mb-3">Rôle & Campus</h4>
                <div class="mb-3">
                    <label class="weight-500 mb-1">Rôle</label>
                    <select name="role_slug" class="form-control" required>
                        <?php foreach ($roles as $r): ?>
                            <option value="<?= htmlspecialchars($r['slug']) ?>"
                                <?= ($editUser['role_slug'] === $r['slug']) ? 'selected' : '' ?>>
                                <?= htmlspecialchars($r['label']) ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="mb-3">
                    <label class="weight-500 mb-1">Campus</label>
                    <select name="campus_id" class="form-control">
                        <option value="">— Tous les campus —</option>
                        <?php foreach ($campuses as $c): ?>
                            <option value="<?= (int)$c['id'] ?>"
                                <?= ((int)$editUser['campus_id'] === (int)$c['id']) ? 'selected' : '' ?>>
                                <?= htmlspecialchars($c['name']) ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="mb-3">
                    <label class="weight-500 mb-1">Statut</label>
                    <select name="status" class="form-control">
                        <option value="actif" <?= $editUser['status'] === 'actif' ? 'selected' : '' ?>>Actif</option>
                        <option value="suspendu" <?= $editUser['status'] === 'suspendu' ? 'selected' : '' ?>>Suspendu</option>
                        <option value="désactivé" <?= $editUser['status'] === 'désactivé' ? 'selected' : '' ?>>Désactivé</option>
                    </select>
                </div>
            </div>

            <div class="card-box pd-20">
                <button type="submit" class="btn btn-primary btn-lg btn-block">
                    <i class="dw dw-save mr-1"></i> Enregistrer les modifications
                </button>
                <a href="<?= htmlspecialchars(app_route_url('utilisateurs'), ENT_QUOTES, 'UTF-8') ?>"
                   class="btn btn-outline-secondary btn-block mt-2">Annuler</a>
            </div>
        </div>
    </div>
</form>