<?php
/**
 * dash/super_admin/utilisateur_add.php
 * Ajouter un utilisateur — Super Admin
 */

if (!defined('ROUTER_LOADED')) {
    http_response_code(403);
    exit('Accès direct interdit.');
}

require_once __DIR__ . "/../../api/database.php";
$db = Database::getInstance();

$errors = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $userName = trim($_POST['user_name'] ?? '');
    $email    = trim($_POST['email'] ?? '');
    $phone    = trim($_POST['phone'] ?? '');
    $fName    = trim($_POST['f_name'] ?? '');
    $lName    = trim($_POST['l_name'] ?? '');
    $gender   = $_POST['gender'] ?? 'O';
    $roleSlug = $_POST['role_slug'] ?? '';
    $campusId = !empty($_POST['campus_id']) ? (int) $_POST['campus_id'] : null;
    $status   = $_POST['status'] ?? 'actif';
    $password = $_POST['password'] ?? '';

    if ($userName === '') $errors[] = "L'identifiant est requis.";
    if ($email === '')    $errors[] = "L'email est requis.";
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) $errors[] = "Email invalide.";
    if ($fName === '')    $errors[] = "Le prénom est requis.";
    if ($lName === '')    $errors[] = "Le nom est requis.";
    if ($roleSlug === '') $errors[] = "Le rôle est requis.";
    if (strlen($password) < 8) $errors[] = "Le mot de passe doit faire au moins 8 caractères.";

    if ($db->fetch("SELECT id FROM users WHERE user_name = ?", [$userName])) {
        $errors[] = "Cet identifiant est déjà utilisé.";
    }
    if ($db->fetch("SELECT id FROM users WHERE email = ?", [$email])) {
        $errors[] = "Cet email est déjà utilisé.";
    }

    $roleRow = $db->fetch("SELECT id FROM roles WHERE slug = ?", [$roleSlug]);
    if (!$roleRow) $errors[] = "Rôle invalide.";

    if ($roleSlug === 'super_admin') {
        $errors[] = "Pour créer un Super Admin, utilisez la page <a href='" . app_route_url('admins/ajouter') . "'>Ajouter un Super Admin</a>.";
    }

    if (empty($errors)) {
        try {
            $db->execute(
                "INSERT INTO users
                 (uuid, user_name, email, phone, password_hash, f_name, l_name,
                  gender, category, role_id, campus_id, status, must_change_password)
                 VALUES (UUID(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)",
                [
                    $userName, $email, $phone ?: null,
                    password_hash($password, PASSWORD_BCRYPT),
                    $fName, $lName, $gender,
                    $roleSlug, $roleRow['id'], $campusId, $status
                ]
            );
            header("Location: " . app_route_url('utilisateurs', null, ['success' => 1]));
            exit;
        } catch (Throwable $e) {
            $errors[] = "Erreur lors de l'enregistrement : " . $e->getMessage();
        }
    }
}

$roles    = $db->fetchAll("SELECT id, slug, label FROM roles WHERE is_system = 0 ORDER BY label") ?: [];
$campuses = $db->fetchAll("SELECT id, code, name, city FROM campuses WHERE is_active = 1 ORDER BY name") ?: [];
?>

<div class="pd-20 card-box mb-30">
    <div class="d-flex justify-content-between align-items-center">
        <div>
            <h4 class="h3 mb-1 text-primary">Ajouter un utilisateur</h4>
            <p class="text-muted mb-0">Créer un nouveau compte et l'affecter à un campus</p>
        </div>
        <a href="<?= htmlspecialchars(app_route_url('utilisateurs'), ENT_QUOTES, 'UTF-8') ?>"
           class="btn btn-outline-secondary">
            <i class="dw dw-left-arrow mr-1"></i> Retour
        </a>
    </div>
</div>

<?php if (!empty($errors)): ?>
    <div class="alert alert-danger mb-30">
        <h5 class="alert-heading">Erreurs :</h5>
        <ul class="mb-0">
            <?php foreach ($errors as $err): ?><li><?= $err ?></li><?php endforeach; ?>
        </ul>
    </div>
<?php endif; ?>

<form method="post" action="">
    <div class="row">
        <div class="col-lg-8">
            <div class="card-box pd-20 mb-30">
                <h4 class="h4 mb-3">Informations personnelles</h4>
                <div class="row">
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Prénom <span class="text-danger">*</span></label>
                        <input type="text" name="f_name" class="form-control" required
                               value="<?= htmlspecialchars($_POST['f_name'] ?? '') ?>">
                    </div>
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Nom <span class="text-danger">*</span></label>
                        <input type="text" name="l_name" class="form-control" required
                               value="<?= htmlspecialchars($_POST['l_name'] ?? '') ?>">
                    </div>
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Genre</label>
                        <select name="gender" class="form-control">
                            <option value="O">Non précisé</option>
                            <option value="M" <?= ($_POST['gender'] ?? '') === 'M' ? 'selected' : '' ?>>Masculin</option>
                            <option value="F" <?= ($_POST['gender'] ?? '') === 'F' ? 'selected' : '' ?>>Féminin</option>
                        </select>
                    </div>
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Téléphone</label>
                        <input type="text" name="phone" class="form-control"
                               value="<?= htmlspecialchars($_POST['phone'] ?? '') ?>">
                    </div>
                </div>
            </div>

            <div class="card-box pd-20 mb-30">
                <h4 class="h4 mb-3">Identifiants de connexion</h4>
                <div class="row">
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Identifiant <span class="text-danger">*</span></label>
                        <input type="text" name="user_name" class="form-control" required
                               value="<?= htmlspecialchars($_POST['user_name'] ?? '') ?>"
                               placeholder="ex: jdupont">
                    </div>
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Email <span class="text-danger">*</span></label>
                        <input type="email" name="email" class="form-control" required
                               value="<?= htmlspecialchars($_POST['email'] ?? '') ?>"
                               placeholder="ex: jdupont@uia.edu.bi">
                    </div>
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Mot de passe <span class="text-danger">*</span></label>
                        <input type="password" name="password" class="form-control" required minlength="8">
                        <small class="text-muted">Min. 8 caractères — devra être changé à la 1ère connexion</small>
                    </div>
                    <div class="col-md-6 mb-3">
                        <label class="weight-500 mb-1">Statut</label>
                        <select name="status" class="form-control">
                            <option value="actif">Actif</option>
                            <option value="suspendu">Suspendu</option>
                            <option value="désactivé">Désactivé</option>
                        </select>
                    </div>
                </div>
            </div>
        </div>

        <div class="col-lg-4">
            <div class="card-box pd-20 mb-30">
                <h4 class="h4 mb-3">Rôle & Campus</h4>
                <div class="mb-3">
                    <label class="weight-500 mb-1">Rôle <span class="text-danger">*</span></label>
                    <select name="role_slug" class="form-control" required>
                        <option value="">— Sélectionner —</option>
                        <?php foreach ($roles as $r): ?>
                            <option value="<?= htmlspecialchars($r['slug']) ?>"
                                <?= ($_POST['role_slug'] ?? '') === $r['slug'] ? 'selected' : '' ?>>
                                <?= htmlspecialchars($r['label']) ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                    <small class="text-muted d-block mt-1">
                        <i class="dw dw-info"></i> Pour créer un Super Admin, allez sur
                        <a href="<?= htmlspecialchars(app_route_url('admins/ajouter'), ENT_QUOTES, 'UTF-8') ?>">Ajouter un Super Admin</a>.
                    </small>
                </div>
                <div class="mb-3">
                    <label class="weight-500 mb-1">Campus</label>
                    <select name="campus_id" class="form-control">
                        <option value="">— Tous les campus —</option>
                        <?php foreach ($campuses as $c): ?>
                            <option value="<?= (int)$c['id'] ?>"
                                <?= (string)($_POST['campus_id'] ?? '') === (string)$c['id'] ? 'selected' : '' ?>>
                                <?= htmlspecialchars($c['name']) ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                    <small class="text-muted d-block mt-1">Laisser vide pour un accès multi-campus.</small>
                </div>
            </div>

            <div class="card-box pd-20">
                <button type="submit" class="btn btn-primary btn-lg btn-block">
                    <i class="dw dw-save mr-1"></i> Enregistrer
                </button>
                <a href="<?= htmlspecialchars(app_route_url('utilisateurs'), ENT_QUOTES, 'UTF-8') ?>"
                   class="btn btn-outline-secondary btn-block mt-2">Annuler</a>
            </div>
        </div>
    </div>
</form>