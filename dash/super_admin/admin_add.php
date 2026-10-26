<?php
if (!defined('ROUTER_LOADED')) { exit('Accès interdit'); }
require_once __DIR__ . "/../../api/database.php";
$db = Database::getInstance();

$errors = [];
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $userName = trim($_POST['user_name'] ?? '');
    $email    = trim($_POST['email'] ?? '');
    $phone    = trim($_POST['phone'] ?? '');
    $fName    = trim($_POST['f_name'] ?? '');
    $lName    = trim($_POST['l_name'] ?? '');
    $adminRole= $_POST['admin_role'] ?? 'admin';
    $campusId = !empty($_POST['campus_id']) ? (int)$_POST['campus_id'] : null;
    $status   = $_POST['status'] ?? 'actif';
    $password = $_POST['password'] ?? '';

    if (!$userName || !$email || !$fName || !$lName || strlen($password) < 8) {
        $errors[] = "Tous les champs obligatoires doivent être remplis (mot de passe ≥ 8 caractères).";
    }

    if (empty($errors)) {
        try {
            // L'insertion déclenche automatiquement le trigger
            $db->execute(
                "INSERT INTO admin_users
                 (uuid, user_name, email, phone, password_hash, f_name, l_name,
                  admin_role, campus_id, status, must_change_password)
                 VALUES (UUID(), ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)",
                [
                    $userName, $email, $phone ?: null,
                    password_hash($password, PASSWORD_BCRYPT),
                    $fName, $lName, $adminRole, $campusId, $status
                ]
            );
            header("Location: " . app_route_url('admins') . "&success=1");
            exit;
        } catch (Throwable $e) {
            $errors[] = "Erreur : " . $e->getMessage();
        }
    }
}

$campuses = $db->fetchAll("SELECT id, name FROM campuses WHERE is_active = 1 ORDER BY name");
?>

<!-- En-tête -->
<div class="pd-20 card-box mb-30">
    <h4 class="h3 mb-1 text-primary">Ajouter un Super Admin</h4>
    <p class="text-muted mb-0">Un compte shadow sera créé automatiquement dans users.</p>
</div>

<?php if (!empty($errors)): ?>
    <div class="alert alert-danger">
        <ul><?php foreach ($errors as $e) echo "<li>" . htmlspecialchars($e) . "</li>"; ?></ul>
    </div>
<?php endif; ?>

<form method="post">
    <div class="row">
        <div class="col-lg-8">
            <div class="card-box pd-20 mb-30">
                <div class="row">
                    <div class="col-md-6 mb-3">
                        <label>Prénom *</label>
                        <input type="text" name="f_name" class="form-control" required>
                    </div>
                    <div class="col-md-6 mb-3">
                        <label>Nom *</label>
                        <input type="text" name="l_name" class="form-control" required>
                    </div>
                    <div class="col-md-6 mb-3">
                        <label>Identifiant *</label>
                        <input type="text" name="user_name" class="form-control" required>
                    </div>
                    <div class="col-md-6 mb-3">
                        <label>Email *</label>
                        <input type="email" name="email" class="form-control" required>
                    </div>
                    <div class="col-md-6 mb-3">
                        <label>Téléphone</label>
                        <input type="text" name="phone" class="form-control">
                    </div>
                    <div class="col-md-6 mb-3">
                        <label>Mot de passe * (min 8)</label>
                        <input type="password" name="password" class="form-control" required minlength="8">
                    </div>
                </div>
            </div>
        </div>
        <div class="col-lg-4">
            <div class="card-box pd-20 mb-30">
                <div class="mb-3">
                    <label>Type de compte *</label>
                    <select name="admin_role" class="form-control" required>
                        <option value="admin">Admin (sans droits super)</option>
                        <option value="super_admin">Super Admin (tous droits)</option>
                    </select>
                </div>
                <div class="mb-3">
                    <label>Campus</label>
                    <select name="campus_id" class="form-control">
                        <option value="">— Tous les campus —</option>
                        <?php foreach ($campuses as $c): ?>
                            <option value="<?= (int)$c['id'] ?>"><?= htmlspecialchars($c['name']) ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="mb-3">
                    <label>Statut</label>
                    <select name="status" class="form-control">
                        <option value="actif">Actif</option>
                        <option value="suspendu">Suspendu</option>
                    </select>
                </div>
                <button type="submit" class="btn btn-danger btn-block">
                    <i class="dw dw-shield mr-1"></i> Créer le compte admin
                </button>
            </div>
        </div>
    </div>
</form>