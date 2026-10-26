<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <title>Connexion | U-Connect — Gestion Universitaire</title>

    <!-- Site favicon -->
    <link rel="apple-touch-icon" sizes="180x180" href="../dash/template/vendors/images/apple-touch-icon.png">
    <link rel="icon" type="image/png" sizes="32x32" href="../dash/template/vendors/images/favicon-32x32.png">
    <link rel="icon" type="image/png" sizes="16x16" href="../dash/template/vendors/images/favicon-16x16.png">

    <!-- Mobile Specific Metas -->
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">

    <!-- Google Font -->
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">

    <!-- CSS DeskApp -->
    <link rel="stylesheet" type="text/css" href="../dash/template/vendors/styles/core.css">
    <link rel="stylesheet" type="text/css" href="../dash/template/vendors/styles/icon-font.min.css">
    <link rel="stylesheet" type="text/css" href="../dash/template/vendors/styles/style.css">

    <!-- SweetAlert2 -->
    <script src="https://cdn.jsdelivr.net/npm/sweetalert2@11"></script>

    <style>
        :root {
            --uconnect-green:      #36c783;
            --uconnect-dark:       #287957;
            --uconnect-green-soft: rgba(54, 199, 131, 0.12);
            --uconnect-green-mid:  rgba(54, 199, 131, 0.30);
        }

        .uconnect-brand {
            display: inline-flex;
            align-items: center;
            gap: 10px;
            text-decoration: none;
        }
        .uconnect-logo-icon { display: inline-flex; color: var(--uconnect-dark); }
        .uconnect-brand-text {
            font-size: 22px;
            font-weight: 800;
            color: var(--uconnect-dark);
            letter-spacing: -0.5px;
        }
        .uconnect-help-link {
            color: #6b7280;
            font-weight: 500;
            transition: color .2s;
        }
        .uconnect-help-link:hover { color: var(--uconnect-green); }

        .uconnect-illustration { max-width: 100%; height: auto; }

        .uconnect-btn {
            background-color: var(--uconnect-green) !important;
            border-color:     var(--uconnect-green) !important;
            color: #fff !important;
            font-weight: 600 !important;
            transition: background-color .2s, transform .1s;
        }
        .uconnect-btn:hover,
        .uconnect-btn:focus {
            background-color: var(--uconnect-dark) !important;
            border-color:     var(--uconnect-dark) !important;
        }
        .uconnect-btn:disabled { opacity: .6; cursor: not-allowed; }

        .uconnect-toggle-password {
            cursor: pointer;
            user-select: none;
            transition: color .2s;
        }
        .uconnect-toggle-password:hover { color: var(--uconnect-dark) !important; }
        .uconnect-toggle-password i { font-size: 18px; }

        .uconnect-message {
            padding: 10px 14px;
            border-radius: 8px;
            font-size: 13px;
            margin-bottom: 16px;
            line-height: 1.4;
        }
        .uconnect-message-error {
            background-color: #fef2f2;
            color: #b91c1c;
            border: 1px solid #fecaca;
        }
        .uconnect-message-success {
            background-color: #ecfdf5;
            color: #065f46;
            border: 1px solid #a7f3d0;
        }
        .hidden { display: none !important; }

        .uconnect-user-banner {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 10px 14px;
            background-color: var(--uconnect-green-soft);
            border: 1px solid var(--uconnect-green-mid);
            border-radius: 10px;
            margin-bottom: 18px;
        }
        .uconnect-avatar {
            width: 38px;
            height: 38px;
            border-radius: 50%;
            background-color: var(--uconnect-green);
            color: #fff;
            font-weight: 700;
            font-size: 16px;
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
        }
        .uconnect-user-info { flex: 1; min-width: 0; }
        .uconnect-user-label {
            font-size: 11px;
            color: #6b7280;
            text-transform: uppercase;
            letter-spacing: .3px;
        }
        .uconnect-user-name {
            font-size: 14px;
            font-weight: 600;
            color: var(--uconnect-dark);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        .uconnect-change-user {
            background: none;
            border: none;
            color: var(--uconnect-green);
            font-size: 12px;
            text-decoration: underline;
            cursor: pointer;
            padding: 0;
        }
        .uconnect-change-user:hover { color: var(--uconnect-dark); }

        .uconnect-back-btn {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 6px;
            background: none;
            border: none;
            width: 100%;
            margin-top: 14px;
            font-size: 12px;
            color: #6b7280;
            cursor: pointer;
        }
        .uconnect-back-btn:hover { color: var(--uconnect-dark); }
        .uconnect-back-btn i { font-size: 14px; }

        .uconnect-slide-in { animation: uconnectSlideIn .4s cubic-bezier(0.34, 1.56, 0.64, 1) both; }
        @keyframes uconnectSlideIn {
            from { opacity: 0; transform: translateY(-15px); }
            to   { opacity: 1; transform: translateY(0); }
        }

        .uconnect-footer-text {
            text-align: center;
            font-size: 11px;
            color: #9ca3af;
            margin-top: 24px;
            line-height: 1.5;
        }
        .uconnect-copyright {
            text-align: center;
            font-size: 11px;
            color: #9ca3af;
            margin-top: 12px;
        }

        .uconnect-swal-popup { border-radius: 16px !important; padding: 24px !important; }
        .uconnect-swal-confirm {
            padding: 10px 22px !important;
            border-radius: 8px !important;
            background-color: var(--uconnect-green) !important;
            color: #fff !important;
            font-weight: 600 !important;
            border: none !important;
        }
        .uconnect-swal-confirm:hover { background-color: var(--uconnect-dark) !important; }
        .uconnect-swal-cancel {
            padding: 10px 22px !important;
            border-radius: 8px !important;
            background-color: #e5e7eb !important;
            color: #374151 !important;
            font-weight: 600 !important;
            border: none !important;
        }
        .uconnect-swal-cancel:hover { background-color: #d1d5db !important; }

        /* Badge rôle dans la bannière */
        .uconnect-role-badge {
            display: inline-flex;
            align-items: center;
            gap: 4px;
            padding: 2px 8px;
            border-radius: 999px;
            font-size: 10px;
            font-weight: 700;
            color: #fff;
            background: var(--uconnect-green);
            text-transform: uppercase;
            letter-spacing: 0.3px;
        }

        @media (max-width: 767px) {
            .uconnect-brand-text { font-size: 18px; }
            .uconnect-footer-text { font-size: 10px; }
        }
    </style>
</head>
<body class="login-page">

    <!-- HEADER DESKAPP -->
    <div class="login-header box-shadow">
        <div class="container-fluid d-flex justify-content-between align-items-center">
            <div class="brand-logo">
                <a href="index.php" class="uconnect-brand">
                    <span class="uconnect-logo-icon">
                        <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"
                             viewBox="0 0 24 24" fill="none" stroke="currentColor"
                             stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                            <path d="M22 10L12 5 2 10l10 5 10-5Z"></path>
                            <path d="M6 12v5c0 1.7 2.7 3 6 3s6-1.3 6-3v-5"></path>
                            <path d="M22 10v6"></path>
                        </svg>
                    </span>
                    <span class="uconnect-brand-text">U-Connect</span>
                </a>
            </div>
            <div class="login-menu">
                <ul>
                    <li><a href="#" class="uconnect-help-link">Aide</a></li>
                </ul>
            </div>
        </div>
    </div>

    <!-- CORPS -->
    <div class="login-wrap d-flex align-items-center flex-wrap justify-content-center">
        <div class="container">
            <div class="row align-items-center">
                <div class="col-md-6 col-lg-7 d-none d-md-block">
                    <img src="../dash/template/src/images/login-page-img.png" alt="U-Connect" class="uconnect-illustration">
                </div>

                <div class="col-md-6 col-lg-5">
                    <div class="login-box bg-white box-shadow border-radius-10">

                        <div class="login-title text-center">
                            <h2 class="text-primary">Connexion U-Connect</h2>
                            <p class="text-muted small mt-1">
                                Accédez à votre espace universitaire
                            </p>
                        </div>

                        <div id="message" class="uconnect-message hidden" role="status" aria-live="polite"></div>

                        <div id="userBanner" class="uconnect-user-banner hidden">
                            <div class="uconnect-avatar" id="userAvatar">?</div>
                            <div class="uconnect-user-info">
                                <div class="uconnect-user-label">Identifié(e) comme</div>
                                <div class="uconnect-user-name" id="userName">—</div>
                                <div class="mt-1">
                                    <span class="uconnect-role-badge" id="userRoleBadge">—</span>
                                </div>
                            </div>
                            <button type="button" id="changeUser" class="uconnect-change-user">Changer</button>
                        </div>

                        <form id="loginForm" novalidate>

                            <!-- ÉTAPE 1 : Identifiant -->
                            <div id="step1">
                                <div class="input-group custom mb-3">
                                    <input
                                        type="text"
                                        id="identifier"
                                        name="identifier"
                                        class="form-control form-control-lg"
                                        placeholder="Identifiant ou email institutionnel"
                                        autocomplete="username"
                                        required
                                        autofocus
                                    >
                                    <div class="input-group-append custom">
                                        <span class="input-group-text">
                                            <i class="icon-copy dw dw-user1"></i>
                                        </span>
                                    </div>
                                </div>

                                <button
                                    type="button"
                                    id="nextButton"
                                    class="btn btn-primary btn-lg btn-block uconnect-btn"
                                >
                                    Continuer
                                </button>
                            </div>

                            <!-- ÉTAPE 2 : Mot de passe -->
                            <div id="step2" class="hidden uconnect-step2">
                                <div class="input-group custom mb-3">
                                    <input
                                        type="password"
                                        id="password"
                                        name="password"
                                        class="form-control form-control-lg"
                                        placeholder="Mot de passe"
                                        autocomplete="current-password"
                                        required
                                    >
                                    <div class="input-group-append custom">
                                        <span class="input-group-text uconnect-toggle-password"
                                              id="togglePassword"
                                              role="button"
                                              aria-label="Afficher le mot de passe"
                                              aria-pressed="false">
                                            <i class="dw dw-padlock1" id="eyeIcon"></i>
                                        </span>
                                    </div>
                                </div>

                                <div class="row pb-3">
                                    <div class="col-6">
                                        <div class="custom-control custom-checkbox">
                                            <input type="checkbox" class="custom-control-input" id="remember">
                                            <label class="custom-control-label" for="remember">Se souvenir</label>
                                        </div>
                                    </div>
                                    <div class="col-6">
                                        <div class="forgot-password text-right">
                                            <a href="forgot-password.php">Mot de passe oublié ?</a>
                                        </div>
                                    </div>
                                </div>

                                <div class="row">
                                    <div class="col-sm-12">
                                        <div class="input-group mb-0">
                                            <button
                                                type="submit"
                                                id="loginButton"
                                                class="btn btn-primary btn-lg btn-block uconnect-btn"
                                            >
                                                Se connecter
                                            </button>
                                        </div>

                                        <button type="button" id="backButton" class="uconnect-back-btn">
                                            <i class="dw dw-left-arrow1"></i>
                                            Utiliser un autre identifiant
                                        </button>
                                    </div>
                                </div>
                            </div>

                        </form>
                    </div>

                    <p class="uconnect-footer-text">
                        Plateforme intégrée de gestion universitaire :<br>
                        Étudiants | Notes & Relevés | Emplois du temps | Finances | Bibliothèque
                    </p>

                    <p class="uconnect-copyright">
                        &copy; <span id="year"></span> U-Connect — EALI
                    </p>
                </div>
            </div>
        </div>
    </div>

    <!-- SWEETALERT2 — Config -->
    <script>
        const SwalUConnect = Swal.mixin({
            customClass: {
                confirmButton: 'uconnect-swal-confirm',
                cancelButton:  'uconnect-swal-cancel',
                popup:         'uconnect-swal-popup'
            },
            buttonsStyling: false,
            confirmButtonColor: '#36c783',
            cancelButtonColor:  '#6b7280'
        });

        const Toast = Swal.mixin({
            toast: true,
            position: 'top-end',
            showConfirmButton: false,
            timer: 3500,
            timerProgressBar: true,
            didOpen: (toast) => {
                toast.addEventListener('mouseenter', Swal.stopTimer);
                toast.addEventListener('mouseleave', Swal.resumeTimer);
            }
        });
    </script>

    <!-- LOGIQUE PRINCIPALE -->
    <script>
        document.getElementById('year').textContent = new Date().getFullYear();

        const loginForm       = document.getElementById('loginForm');
        const identifierInput = document.getElementById('identifier');
        const passwordInput   = document.getElementById('password');
        const togglePassword  = document.getElementById('togglePassword');
        const eyeIcon         = document.getElementById('eyeIcon');
        const message         = document.getElementById('message');
        const loginButton     = document.getElementById('loginButton');
        const nextButton      = document.getElementById('nextButton');
        const backButton      = document.getElementById('backButton');
        const changeUser      = document.getElementById('changeUser');
        const step1           = document.getElementById('step1');
        const step2           = document.getElementById('step2');
        const userBanner      = document.getElementById('userBanner');
        const userName        = document.getElementById('userName');
        const userRoleBadge   = document.getElementById('userRoleBadge');
        const userAvatar      = document.getElementById('userAvatar');

        let currentIdentifier = '';
        let currentUser       = null;
        const authEndpoint = new URL('../api/endpoints/auth.php', window.location.href);

        async function postAuth(action, payload) {
            const endpoint = new URL(authEndpoint);
            endpoint.searchParams.set('action', action);

            const response = await fetch(endpoint, {
                method: 'POST',
                credentials: 'same-origin',
                headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json'
                },
                body: JSON.stringify(payload)
            });

            const responseText = await response.text();
            let data;
            try {
                data = JSON.parse(responseText);
            } catch {
                throw new Error(`Réponse invalide du serveur (HTTP ${response.status}).`);
            }

            return { response, data };
        }

        // Toggle password
        togglePassword.addEventListener('click', function () {
            const isHidden = passwordInput.type === 'password';
            passwordInput.type = isHidden ? 'text' : 'password';
            togglePassword.setAttribute('aria-label',
                isHidden ? 'Masquer le mot de passe' : 'Afficher le mot de passe');
            togglePassword.setAttribute('aria-pressed', String(isHidden));
            eyeIcon.className = isHidden ? 'dw dw-eye' : 'dw dw-padlock1';
        });

        function showInlineMessage(text, type = 'error') {
            message.textContent = text;
            message.className = 'uconnect-message ' + (type === 'success'
                ? 'uconnect-message-success'
                : 'uconnect-message-error');
        }
        function hideInlineMessage() {
            message.className = 'uconnect-message hidden';
        }

        // ÉTAPE 1 → Vérifier l'identifiant
        async function goToStep2() {
            hideInlineMessage();
            const identifier = identifierInput.value.trim();

            if (!identifier) {
                Toast.fire({
                    icon: 'warning',
                    title: 'Veuillez saisir votre identifiant ou email.'
                });
                identifierInput.focus();
                return;
            }

            nextButton.disabled = true;
            nextButton.textContent = 'Vérification...';

            try {
                const { response, data } = await postAuth('check_identifier', { identifier });

                if (!response.ok || !data.success) {
                    let errorMessage = data.message || 'Identifiant introuvable.';
                    if (data.errors) {
                        errorMessage = Object.values(data.errors)[0] || errorMessage;
                    }
                    showInlineMessage(errorMessage, 'error');
                    identifierInput.focus();
                    nextButton.disabled = false;
                    nextButton.textContent = 'Continuer';
                    return;
                }

                currentIdentifier = identifier;
                currentUser       = data.data;

                userName.textContent = data.data.first_name || data.data.username || 'Utilisateur';
                userRoleBadge.textContent = data.data.role_label || '—';
                userAvatar.textContent = (data.data.first_name || data.data.username || '?')
                    .trim().charAt(0).toUpperCase();
                userBanner.classList.remove('hidden');

                step1.classList.add('hidden');
                step2.classList.remove('hidden');
                step2.classList.add('uconnect-slide-in');

                setTimeout(() => passwordInput.focus(), 100);

                Toast.fire({
                    icon: 'success',
                    title: `Bonjour ${data.data.first_name || data.data.username} !`
                });

            } catch (error) {
                console.error('Erreur réseau:', error);
                const errorMessage = error instanceof TypeError
                    ? 'Impossible de joindre le serveur. Vérifiez que XAMPP et Apache sont démarrés.'
                    : error.message;
                showInlineMessage(errorMessage, 'error');
                SwalUConnect.fire({
                    icon: 'error',
                    title: error instanceof TypeError ? 'Serveur injoignable' : 'Erreur du serveur',
                    text: errorMessage,
                    confirmButtonText: 'Fermer'
                });
            } finally {
                nextButton.disabled = false;
                nextButton.textContent = 'Continuer';
            }
        }

        function backToStep1() {
            step2.classList.add('hidden');
            step2.classList.remove('uconnect-slide-in');
            step1.classList.remove('hidden');
            userBanner.classList.add('hidden');
            passwordInput.value = '';
            hideInlineMessage();
            setTimeout(() => identifierInput.focus(), 100);
        }

        nextButton.addEventListener('click', goToStep2);
        backButton.addEventListener('click', backToStep1);
        changeUser.addEventListener('click', backToStep1);

        identifierInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                goToStep2();
            }
        });

        // ÉTAPE 2 → Connexion
        loginForm.addEventListener('submit', async function (event) {
            event.preventDefault();
            hideInlineMessage();

            const password = passwordInput.value;
            const remember = document.getElementById('remember').checked;

            if (!currentIdentifier) { backToStep1(); return; }
            if (!password) {
                Toast.fire({ icon: 'warning', title: 'Veuillez saisir votre mot de passe.' });
                passwordInput.focus();
                return;
            }
            if (password.length < 6) {
                Toast.fire({
                    icon: 'warning',
                    title: 'Le mot de passe doit contenir au moins 6 caractères.'
                });
                passwordInput.focus();
                return;
            }

            Swal.fire({
                title: 'Connexion en cours...',
                html: 'Vérification de vos identifiants',
                allowOutsideClick: false,
                allowEscapeKey: false,
                didOpen: () => Swal.showLoading()
            });

            loginButton.disabled = true;
            loginButton.textContent = 'Connexion...';

            try {
                const { response, data } = await postAuth('login', {
                    identifier: currentIdentifier,
                    password
                });

                if (!response.ok || !data.success) {
                    Swal.close();
                    let errorMessage = data.message || 'Erreur de connexion';
                    if (data.errors) {
                        errorMessage = Object.values(data.errors)[0] || errorMessage;
                    }
                    showInlineMessage(errorMessage, 'error');
                    SwalUConnect.fire({
                        icon: 'error',
                        title: 'Connexion échouée',
                        text: errorMessage,
                        confirmButtonText: 'Réessayer'
                    });
                    loginButton.disabled = false;
                    loginButton.textContent = 'Se connecter';
                    passwordInput.focus();
                    return;
                }

                Swal.close();

                try {
                    const storage = remember ? localStorage : sessionStorage;
                    storage.setItem('auth_token', data.data.token);
                    storage.setItem('auth_user', JSON.stringify(data.data.user));
                } catch (error) {
                    console.warn('Le navigateur ne permet pas de mémoriser la session :', error);
                }

                showInlineMessage(
                    `Bienvenue ${data.data.user.full_name} — ${data.data.user.role_label}`,
                    'success'
                );

                Toast.fire({
                    icon: 'success',
                    title: `Bienvenue ${data.data.user.full_name} !`
                });

                // ============================================================
                // MAPPING DES RÔLES → ROUTES U-CONNECT
                // Chaque rôle est redirigé vers SA PROPRE route d'accueil.
                // Le Super Admin ne peut PAS aller vers 'etudiant/accueil'.
                // ============================================================
                const roleRoutes = {
                    super_admin:           'super_admin/accueil',
                    recteur:               'recteur/accueil',
                    secretaire_general:    'secretaire_general/accueil',
                    directeur_campus:      'directeur_campus/accueil',
                    daf:                   'daf/accueil',
                    doyen:                 'doyen/accueil',
                    chef_departement:      'chef_departement/accueil',
                    drh:                   'drh/accueil',
                    assurance_qualite:     'assurance_qualite/accueil',
                    recherche_innovation:  'recherche_innovation/accueil',
                    comptable:             'comptable/accueil',
                    agent_scolarite:       'agent_scolarite/accueil',
                    caissier:              'caissier/accueil',
                    lecteur:               'lecteur/accueil',
                    enseignant:            'enseignant/accueil',
                    etudiant:              'etudiant/accueil',
                    parent:                'parent/accueil',
                };

                // ⚠️ Récupération stricte du rôle : on utilise celui retourné par l'API
                const userRole = data.data.user.role;

                // Si le rôle n'est pas reconnu → erreur explicite (pas de fallback silencieux)
                if (!roleRoutes[userRole]) {
                    SwalUConnect.fire({
                        icon: 'error',
                        title: 'Rôle non reconnu',
                        html: `
                            <p>Votre compte a un rôle qui n'est pas configuré dans l'application.</p>
                            <p style="font-size:12px;color:#888;margin-top:8px;">
                                Rôle reçu : <strong>${userRole}</strong><br>
                                Contactez l'administrateur système.
                            </p>
                        `,
                        confirmButtonText: 'Fermer'
                    });
                    loginButton.disabled = false;
                    loginButton.textContent = 'Se connecter';
                    return;
                }

                const roleRoute = roleRoutes[userRole];

                // Redirection vers la route du rôle courant UNIQUEMENT
                window.location.href = `../router.php?route=${encodeURIComponent(roleRoute)}`;

            } catch (error) {
                console.error('Erreur de connexion:', error);
                Swal.close();
                const errorMessage = error instanceof TypeError
                    ? 'Impossible de joindre le serveur. Vérifiez que XAMPP et Apache sont démarrés.'
                    : error.message;
                showInlineMessage(errorMessage, 'error');
                SwalUConnect.fire({
                    icon: 'error',
                    title: error instanceof TypeError ? 'Serveur injoignable' : 'Erreur du serveur',
                    text: errorMessage,
                    confirmButtonText: 'Fermer'
                });
                loginButton.disabled = false;
                loginButton.textContent = 'Se connecter';
            }
        });

        window.addEventListener('load', () => identifierInput.focus());
    </script>

    <!-- JS DeskApp -->
    <script src="../dash/template/vendors/scripts/core.js"></script>
    <script src="../dash/template/vendors/scripts/script.min.js"></script>
    <script src="../dash/template/vendors/scripts/process.js"></script>
    <script src="../dash/template/vendors/scripts/layout-settings.js"></script>
</body>
</html>