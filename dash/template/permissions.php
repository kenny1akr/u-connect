<?php
/**
 * dash/template/permissions.php
 * Rôles et permissions U-Connect — alignés sur la base uconnect_db
 */

// ============================================================
// RÔLES
// ============================================================
$ROLES = [
    'super_admin'           => ['label' => 'Super Administrateur',                'level' => 100],
    'recteur'               => ['label' => 'Recteur / Vice-recteur',              'level' => 90],
    'secretaire_general'    => ['label' => 'Secrétaire Général',                   'level' => 80],
    'directeur_campus'      => ['label' => 'Directeur de Campus',                  'level' => 78],
    'daf'                   => ['label' => 'Directeur Administratif et Financier', 'level' => 75],
    'doyen'                 => ['label' => 'Doyen de Faculté',                     'level' => 70],
    'chef_departement'      => ['label' => 'Chef de Département',                  'level' => 65],
    'drh'                   => ['label' => 'Responsable des Ressources Humaines',  'level' => 65],
    'assurance_qualite'     => ['label' => 'Responsable Assurance Qualité',        'level' => 60],
    'recherche_innovation'  => ['label' => 'Directeur Recherche & Innovation',     'level' => 60],
    'comptable'             => ['label' => 'Comptable',                            'level' => 60],
    'agent_scolarite'       => ['label' => 'Agent de Scolarité',                   'level' => 55],
    'caissier'              => ['label' => 'Caissier',                             'level' => 55],
    'lecteur'               => ['label' => 'Lecteur / Bibliothécaire',             'level' => 50],
    'enseignant'            => ['label' => 'Enseignant',                           'level' => 40],
    'parent'                => ['label' => 'Parent',                               'level' => 15],
    'etudiant'              => ['label' => 'Étudiant',                             'level' => 10],
];

// ============================================================
// PERMISSIONS
// ============================================================
$PERMISSIONS = [
    'super_admin' => [
        // ============================================================
        // 1. TABLEAU DE BORD & RAPPORTS STRATÉGIQUES
        // ============================================================
        'dashboard.view',
        'rapports.view',
        'rapports.global',
        'rapports.campus',
        'rapports.faculte',
        'rapports.academique',
        'rapports.financier',
        'rapports.administratif',
        'rapports.departement',

        // ============================================================
        // 2. SUIVI DES ÉTUDIANTS (lecture seule + statistiques)
        // ============================================================
        'etudiants.view',
        'etudiants.stats',

        // ============================================================
        // 3. SUIVI ACADÉMIQUE (lecture seule)
        // ============================================================
        'notes.view',
        'syllabus.view',
        'ue.view',
        'deliberations.view',

        // ============================================================
        // 4. SUIVI DES ENSEIGNANTS (lecture seule)
        // ============================================================
        'enseignants.view',
        'emploi_temps.view',

        // ============================================================
        // 5. SUIVI FINANCIER (lecture seule + rapports)
        // ============================================================
        'finances.view',
        'paiements.view',
        'bourses.view',
        'paie.view',

        // ============================================================
        // 6. SUIVI DOCUMENTAIRE (lecture seule)
        // ============================================================
        'documents.view',
        'documents.archive',

        // ============================================================
        // 7. GESTION DES UTILISATEURS & ADMINS
        // ============================================================
        'utilisateurs.view',
        'utilisateurs.create',
        'utilisateurs.edit',
        'admin_users.view',
        'admin_users.create',
        'admin_users.edit',
        'admin_users.suspend',
        'admin_users.promote',
        'admin_logs.view',
        'journal.view',

        // ============================================================
        // 8. CONFIGURATION DE L'UNIVERSITÉ
        // ============================================================
        'parametres.view',
        'parametres.edit',

        // ============================================================
        // 9. COMMUNICATION
        // ============================================================
        'messagerie.view',
        'messagerie.send',

        // ============================================================
        // 10. SUIVI BIBLIOTHÈQUE & RECHERCHE (lecture seule)
        // ============================================================
        'bibliotheque.view',
        'memoires.view',
        'stages.view',
    ],

    'recteur' => [
        'dashboard.view', 'etudiants.view', 'notes.view', 'finances.view',
        'enseignants.view', 'emploi_temps.view', 'documents.view',
        'documents.generer_diplome', 'rapports.view', 'rapports.administratif',
        'rapports.financier', 'rapports.academique', 'rapports.departement',
        'utilisateurs.view', 'parametres.view', 'parametres.edit',
        'messagerie.view', 'messagerie.send', 'ue.view', 'deliberations.view',
        'admissions.view', 'presences.view', 'memoires.view', 'stages.view',
        'calendrier.view', 'examens.view', 'personnel.view', 'paie.view', 'journal.view',
    ],

    'secretaire_general' => [
        'dashboard.view', 'etudiants.view', 'etudiants.create', 'etudiants.edit',
        'etudiants.transfer', 'notes.view', 'notes.edit', 'notes.validate',
        'notes.soumettre', 'finances.view', 'finances.mon_statut', 'paiements.view',
        'paiements.imprimer', 'bourses.view', 'bourses.edit', 'documents.view',
        'documents.archive', 'documents.generer_releve', 'documents.generer_certificat',
        'documents.generer_diplome', 'documents.mon_releve', 'messagerie.view',
        'messagerie.send', 'rapports.view', 'rapports.administratif', 'rapports.financier',
        'rapports.caisse', 'rapports.academique', 'rapports.departement',
        'utilisateurs.view', 'utilisateurs.create', 'utilisateurs.edit',
        'parametres.view', 'bibliotheque.view', 'bibliotheque.preter',
        'bibliotheque.retourner', 'ue.view', 'ue.edit', 'deliberations.view',
        'deliberations.manage', 'deliberations.pv', 'admissions.view',
        'admissions.manage', 'presences.view', 'presences.saisir', 'memoires.view',
        'memoires.manage', 'stages.view', 'stages.manage', 'reclamations.create',
        'reclamations.traiter', 'calendrier.view', 'calendrier.edit', 'examens.view',
        'examens.edit', 'cartes.generer', 'enseignants.view', 'enseignants.edit',
        'enseignants.heures_valider', 'parents.mes_enfants', 'journal.view',
        'inscriptions.documents.view', 'inscriptions.documents.verify',
        'inscriptions.derogation', 'documents_requis.manage', 'personnel.view',
        'personnel.evaluations', 'conges.demander', 'conges.approuver',
        'pointage.view', 'pointage.edit', 
        'admin_users.view',  // ← optionnel
    ],

    'directeur_campus' => [
        'dashboard.view', 'etudiants.view', 'etudiants.create', 'etudiants.edit',
        'etudiants.transfer', 'notes.view', 'syllabus.view', 'enseignants.view',
        'emploi_temps.view', 'emploi_temps.edit', 'finances.view', 'paiements.view',
        'bourses.view', 'documents.view', 'documents.generer_releve', 'messagerie.view',
        'messagerie.send', 'rapports.view', 'rapports.administratif', 'rapports.academique',
        'utilisateurs.view', 'parametres.view', 'ue.view', 'deliberations.view',
        'admissions.view', 'admissions.manage', 'presences.view', 'memoires.view',
        'stages.view', 'calendrier.view', 'calendrier.edit', 'examens.view',
        'examens.edit', 'journal.view', 'inscriptions.documents.view',
        'inscriptions.documents.verify', 'inscriptions.derogation',
        'documents_requis.manage', 'personnel.view', 'personnel.evaluations',
        'conges.demander', 'conges.approuver', 'pointage.view', 'pointage.edit',
    ],

    'daf' => [
        'dashboard.view', 'etudiants.view', 'etudiants.statut_financier', 'finances.view',
        'finances.create', 'finances.edit', 'finances.caisse', 'finances.mon_statut',
        'paiements.view', 'paiements.create', 'paiements.validate', 'paiements.imprimer',
        'bourses.view', 'bourses.edit', 'rapports.view', 'rapports.financier',
        'rapports.caisse', 'rapports.administratif', 'utilisateurs.view',
        'messagerie.view', 'messagerie.send', 'calendrier.view',
        'enseignants.heures_valider', 'personnel.view', 'personnel.contrats',
        'conges.demander', 'paie.view', 'paie.manage', 'paie.config',
    ],

    'doyen' => [
        'dashboard.view', 'etudiants.view', 'notes.view', 'notes.validate',
        'syllabus.view', 'syllabus.edit', 'enseignants.view', 'emploi_temps.view',
        'emploi_temps.edit', 'documents.view', 'documents.generer_releve',
        'messagerie.view', 'messagerie.send', 'rapports.view', 'rapports.academique',
        'rapports.departement', 'ue.view', 'ue.edit', 'deliberations.view',
        'deliberations.manage', 'deliberations.pv', 'admissions.view', 'admissions.manage',
        'presences.view', 'presences.saisir', 'memoires.view', 'memoires.manage',
        'stages.view', 'stages.manage', 'reclamations.traiter', 'calendrier.view',
        'examens.view', 'examens.edit', 'enseignants.heures_valider',
        'personnel.evaluations', 'conges.demander', 'conges.approuver',
        'pointage.view', 'pointage.edit',
    ],

    'chef_departement' => [
        'dashboard.view', 'etudiants.view', 'etudiants.mes_etudiants', 'notes.view',
        'notes.edit', 'notes.validate', 'notes.soumettre', 'syllabus.view',
        'syllabus.edit', 'enseignants.view', 'emploi_temps.view', 'emploi_temps.edit',
        'messagerie.view', 'messagerie.send', 'rapports.view', 'rapports.departement',
        'rapports.academique', 'ue.view', 'ue.edit', 'deliberations.view',
        'presences.view', 'presences.saisir', 'memoires.view', 'memoires.manage',
        'stages.view', 'stages.manage', 'reclamations.traiter', 'calendrier.view',
        'examens.view', 'examens.edit', 'enseignants.heures_valider',
        'conges.demander', 'pointage.view', 'pointage.edit',
    ],

    'drh' => [
        'dashboard.view', 'enseignants.view', 'enseignants.edit',
        'enseignants.heures_valider', 'documents.view', 'messagerie.view',
        'messagerie.send', 'rapports.view', 'rapports.administratif', 'calendrier.view',
        'personnel.view', 'personnel.edit', 'personnel.contrats', 'personnel.sanctions',
        'personnel.evaluations', 'conges.demander', 'conges.approuver',
        'pointage.view', 'pointage.edit', 'paie.view',
    ],

    'assurance_qualite' => [
        'dashboard.view', 'etudiants.view', 'notes.view', 'syllabus.view',
        'syllabus.edit', 'enseignants.view', 'emploi_temps.view', 'finances.view',
        'paiements.view', 'bourses.view', 'documents.view', 'documents.archive',
        'messagerie.view', 'messagerie.send', 'rapports.view', 'rapports.administratif',
        'rapports.financier', 'rapports.caisse', 'rapports.academique',
        'rapports.departement', 'ue.view', 'deliberations.view', 'admissions.view',
        'presences.view', 'memoires.view', 'stages.view', 'calendrier.view',
        'examens.view', 'journal.view', 'inscriptions.documents.view',
        'personnel.view', 'conges.demander', 'pointage.view',
    ],

    'recherche_innovation' => [
        'dashboard.view', 'enseignants.view', 'messagerie.view', 'messagerie.send',
        'rapports.view', 'rapports.academique', 'ue.view', 'memoires.view',
        'memoires.manage', 'conges.demander',
    ],

    'comptable' => [
        'dashboard.view', 'etudiants.view', 'etudiants.statut_financier', 'finances.view',
        'finances.create', 'finances.edit', 'finances.caisse', 'paiements.view',
        'paiements.create', 'paiements.validate', 'paiements.imprimer', 'bourses.view',
        'documents.view', 'messagerie.view', 'messagerie.send', 'rapports.view',
        'rapports.financier', 'rapports.caisse', 'conges.demander', 'paie.view',
    ],

    'agent_scolarite' => [
        'dashboard.view', 'etudiants.view', 'etudiants.create', 'etudiants.edit',
        'etudiants.transfer', 'notes.view', 'syllabus.view', 'emploi_temps.view',
        'documents.view', 'documents.generer_releve', 'documents.generer_certificat',
        'documents.mon_releve', 'messagerie.view', 'messagerie.send', 'ue.view',
        'admissions.view', 'admissions.manage', 'calendrier.view', 'examens.view',
        'cartes.generer', 'inscriptions.documents.view', 'inscriptions.documents.verify',
        'conges.demander',
    ],

    'caissier' => [
        'dashboard.view', 'etudiants.view', 'etudiants.statut_financier', 'finances.view',
        'finances.caisse', 'paiements.view', 'paiements.create', 'paiements.imprimer',
        'rapports.view', 'rapports.caisse', 'conges.demander',
    ],

    'lecteur' => [
        'dashboard.view', 'etudiants.view', 'messagerie.view', 'messagerie.send',
        'bibliotheque.view', 'bibliotheque.preter', 'bibliotheque.retourner',
        'bibliotheque.manage', 'bibliotheque.pret', 'bibliotheque.amendes',
        'bibliotheque.reservations', 'bibliotheque.acquisitions', 'conges.demander',
    ],

    'enseignant' => [
        'dashboard.view', 'etudiants.view', 'etudiants.mes_etudiants', 'notes.view',
        'notes.edit', 'notes.soumettre', 'syllabus.view', 'syllabus.edit',
        'emploi_temps.view', 'emploi_temps.mon', 'messagerie.view', 'messagerie.send',
        'bibliotheque.view', 'ue.view', 'presences.view', 'presences.saisir',
        'memoires.view', 'stages.view', 'reclamations.traiter', 'calendrier.view',
        'examens.view', 'conges.demander',
    ],

    'parent' => [
        'dashboard.view', 'notes.view', 'notes.mes_notes', 'finances.view',
        'finances.mon_statut', 'messagerie.view', 'messagerie.send',
        'calendrier.view', 'parents.mes_enfants',
    ],

    'etudiant' => [
        'dashboard.view', 'notes.view', 'notes.mes_notes', 'syllabus.view',
        'emploi_temps.view', 'emploi_temps.mon', 'documents.view',
        'documents.mon_releve', 'finances.view', 'finances.mon_statut',
        'messagerie.view', 'messagerie.send', 'bibliotheque.view',
        'reclamations.create', 'calendrier.view', 'examens.view',
    ],
];

// ============================================================
// FONCTIONS UTILITAIRES
// ============================================================
function userCan(array $user, string $permission): bool
{
    $role = $user['role_system'] ?? '';
    if (!isset($GLOBALS['PERMISSIONS'][$role])) {
        return false;
    }
    $perms = $GLOBALS['PERMISSIONS'][$role];

    // Wildcard global
    if (in_array('*', $perms, true)) {
        return true;
    }

    // Permission exacte
    if (in_array($permission, $perms, true)) {
        return true;
    }

    // Wildcard par domaine (notes.*, finances.*, etc.)
    $domain = explode('.', $permission)[0] ?? '';
    if ($domain && in_array($domain . '.*', $perms, true)) {
        return true;
    }

    return false;
}

function getRoleLabel(string $role): string
{
    global $ROLES;
    return $ROLES[$role]['label'] ?? $role;
}

function getRoleLevel(string $role): int
{
    global $ROLES;
    return $ROLES[$role]['level'] ?? 0;
}

/**
 * Normalise le rôle à partir de la valeur brute de la base.
 * Gère admin_users.admin_role ET users.category.
 */
function normalizeUserRole(string $rawRole): ?string
{
    global $ROLES;

    $aliases = [
        'Super Admin'           => 'super_admin',
        'Admin'                 => 'secretaire_general',
        'admin'                 => 'secretaire_general',
        'system_admin'          => 'super_admin',
        'directeur_general'     => 'secretaire_general',
        'directeur_financier'   => 'daf',
        'caissier'              => 'caissier',
        'bibliothecaire'        => 'lecteur',
        'Utilisateur'           => 'etudiant',
        'Etudiant'              => 'etudiant',
        'Étudiant'              => 'etudiant',
        'Parent'                => 'parent',
        'DG'                    => 'daf',
    ];

    $normalized = $aliases[$rawRole] ?? strtolower(trim($rawRole));

    return isset($ROLES[$normalized]) ? $normalized : null;
}