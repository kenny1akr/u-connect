<?php
/**
 * dash/template/sidebar_config.php
 * Sidebar U-Connect — modules universitaires
 */

$SIDEBAR_CONFIG = [

    // ============================================================
    // TABLEAU DE BORD
    // ============================================================
    "main" => [
        "label" => null,
        "items" => [
            [
                "type"       => "link",
                "label"      => "Tableau de bord",
                "icon"       => "home",
                "href"       => "/accueil",
                "permission" => "dashboard.view",
            ],
        ],
    ],

    // ============================================================
    // SCOLARITÉ & ÉTUDIANTS
    // ============================================================
    "scolarite" => [
        "label" => "Scolarité",
        "items" => [
            [
                "type"       => "dropdown",
                "label"      => "Étudiants",
                "icon"       => "users",
                "permission" => "etudiants.view",
                "items"      => [
                    ["label" => "Liste des étudiants",       "href" => "/etudiants",                  "permission" => "etudiants.view"],
                    ["label" => "Ajouter un étudiant",       "href" => "/etudiants/ajouter",          "permission" => "etudiants.create"],
                    ["label" => "Inscriptions",              "href" => "/etudiants/inscriptions",     "permission" => "etudiants.view"],
                    ["label" => "Nouvelle inscription",      "href" => "/etudiants/inscription/nouvelle", "permission" => "etudiants.create"],
                    ["label" => "Transferts inter-campus",   "href" => "/etudiants/transfert",        "permission" => "etudiants.transfer"],
                    ["label" => "Statut financier",          "href" => "/etudiants/statut-financier", "permission" => "etudiants.statut_financier"],
                ],
            ],
            [
                "type"       => "dropdown",
                "label"      => "Admissions",
                "icon"       => "file-plus",
                "permission" => "admissions.view",
                "items"      => [
                    ["label" => "Candidatures",   "href" => "/etudiants/inscriptions",     "permission" => "admissions.view"],
                    ["label" => "Nouvelle demande","href" => "/etudiants/inscription/nouvelle", "permission" => "admissions.manage"],
                ],
            ],
        ],
    ],

    // ============================================================
    // ACADÉMIQUE
    // ============================================================
    "academique" => [
        "label" => "Académique",
        "items" => [
            [
                "type"       => "dropdown",
                "label"      => "Notes & Évaluations",
                "icon"       => "file-text",
                "permission" => "notes.view",
                "items"      => [
                    ["label" => "Toutes les notes",       "href" => "/notes",                "permission" => "notes.view"],
                    ["label" => "Saisir des notes",       "href" => "/notes/saisie",         "permission" => "notes.edit"],
                    ["label" => "Validation des notes",   "href" => "/notes/validation",     "permission" => "notes.validate"],
                    ["label" => "Soumission des notes",   "href" => "/notes/soumission",     "permission" => "notes.soumettre"],
                    ["label" => "Mes notes",              "href" => "/notes/mes-notes",      "permission" => "notes.mes_notes"],
                    ["label" => "Évaluations",            "href" => "/notes/evaluations",    "permission" => "notes.view"],
                    ["label" => "Créer une évaluation",   "href" => "/notes/evaluation/creer","permission" => "notes.edit"],
                ],
            ],
            [
                "type"       => "dropdown",
                "label"      => "Cours & Programmes",
                "icon"       => "book-open",
                "permission" => "notes.view",
                "items"      => [
                    ["label" => "Cours / UE",            "href" => "/cours",                "permission" => "ue.view"],
                    ["label" => "Ajouter un cours",      "href" => "/cours/ajouter",        "permission" => "ue.edit"],
                    ["label" => "Programmes (Syllabus)", "href" => "/syllabus",             "permission" => "syllabus.view"],
                    ["label" => "Couverture",            "href" => "/syllabus/coverage",    "permission" => "syllabus.edit"],
                    ["label" => "Validation",            "href" => "/syllabus/validation",  "permission" => "syllabus.validate"],
                ],
            ],
        ],
    ],

    // ============================================================
    // EMPLOI DU TEMPS & ENSEIGNANTS
    // ============================================================
    "emploi_temps" => [
        "label" => "Enseignants & Emplois du temps",
        "items" => [
            [
                "type"       => "link",
                "label"      => "Emplois du temps",
                "icon"       => "calendar",
                "href"       => "/emploi-temps",
                "permission" => "emploi_temps.view",
            ],
            [
                "type"       => "link",
                "label"      => "Mon emploi du temps",
                "icon"       => "clock",
                "href"       => "/emploi-temps/mon",
                "permission" => "emploi_temps.mon",
            ],
            [
                "type"       => "dropdown",
                "label"      => "Enseignants",
                "icon"       => "users",
                "permission" => "enseignants.view",
                "items"      => [
                    ["label" => "Liste des enseignants", "href" => "/enseignants",             "permission" => "enseignants.view"],
                    ["label" => "Ajouter",               "href" => "/enseignants/ajouter",     "permission" => "enseignants.create"],
                    ["label" => "Affectations",          "href" => "/enseignants/affectations", "permission" => "enseignants.view"],
                    ["label" => "Charge horaire",        "href" => "/enseignants/charge",      "permission" => "enseignants.view"],
                ],
            ],
            [
                "type"       => "link",
                "label"      => "Salles",
                "icon"       => "map-pin",
                "href"       => "/salles",
                "permission" => "emploi_temps.view",
            ],
        ],
    ],

    // ============================================================
    // FINANCES
    // ============================================================
    "finances" => [
        "label" => "Finances",
        "items" => [
            [
                "type"       => "link",
                "label"      => "Tableau financier",
                "icon"       => "dollar-sign",
                "href"       => "/finances",
                "permission" => "finances.view",
            ],
            [
                "type"       => "dropdown",
                "label"      => "Paiements",
                "icon"       => "credit-card",
                "permission" => "paiements.view",
                "items"      => [
                    ["label" => "Liste des paiements",  "href" => "/finances/paiements",          "permission" => "paiements.view"],
                    ["label" => "Nouveau paiement",     "href" => "/finances/paiement/nouveau",   "permission" => "paiements.create"],
                    ["label" => "Valider un paiement",  "href" => "/finances/paiement/valider",   "permission" => "paiements.validate"],
                ],
            ],
            [
                "type"       => "link",
                "label"      => "Caisse",
                "icon"       => "credit-card",
                "href"       => "/finances/caisse",
                "permission" => "finances.caisse",
            ],
            [
                "type"       => "link",
                "label"      => "Bourses & Aides",
                "icon"       => "award",
                "href"       => "/finances/bourses",
                "permission" => "bourses.view",
            ],
            [
                "type"       => "link",
                "label"      => "Mon statut financier",
                "icon"       => "dollar-sign",
                "href"       => "/finances/mon-statut",
                "permission" => "finances.mon_statut",
            ],
        ],
    ],

    // ============================================================
    // DOCUMENTS
    // ============================================================
    "documents" => [
        "label" => "Documents",
        "items" => [
            [
                "type"       => "dropdown",
                "label"      => "Documents",
                "icon"       => "file-text",
                "permission" => "documents.view",
                "items"      => [
                    ["label" => "Tous les documents",   "href" => "/documents",                "permission" => "documents.view"],
                    ["label" => "Relevés de notes",     "href" => "/documents/releves",        "permission" => "documents.view"],
                    ["label" => "Générer un relevé",    "href" => "/documents/releve/generer", "permission" => "documents.generer_releve"],
                    ["label" => "Générer un certificat","href" => "/documents/certificat/generer", "permission" => "documents.generer_certificat"],
                    ["label" => "Générer un diplôme",   "href" => "/documents/diplome/generer", "permission" => "documents.generer_diplome"],
                    ["label" => "Archives",             "href" => "/documents/archives",       "permission" => "documents.archive"],
                    ["label" => "Mon relevé de notes",  "href" => "/documents/mon-releve",     "permission" => "documents.mon_releve"],
                ],
            ],
        ],
    ],

    // ============================================================
    // BIBLIOTHÈQUE
    // ============================================================
    "bibliotheque" => [
        "label" => "Bibliothèque",
        "items" => [
            [
                "type"       => "link",
                "label"      => "Catalogue",
                "icon"       => "book-open",
                "href"       => "/bibliotheque",
                "permission" => "bibliotheque.view",
            ],
            [
                "type"       => "link",
                "label"      => "Prêter un livre",
                "icon"       => "file-plus",
                "href"       => "/bibliotheque/preter",
                "permission" => "bibliotheque.preter",
            ],
            [
                "type"       => "link",
                "label"      => "Retourner un livre",
                "icon"       => "check-circle",
                "href"       => "/bibliotheque/retourner",
                "permission" => "bibliotheque.retourner",
            ],
        ],
    ],

    // ============================================================
    // COMMUNICATION
    // ============================================================
    "communication" => [
        "label" => "Communication",
        "items" => [
            [
                "type"       => "link",
                "label"      => "Messagerie interne",
                "icon"       => "message-circle",
                "href"       => "/messagerie",
                "permission" => "messagerie.view",
            ],
            [
                "type"       => "link",
                "label"      => "Notifications",
                "icon"       => "bell",
                "href"       => "/notifications",
                "permission" => "dashboard.view",
            ],
        ],
    ],

    // ============================================================
    // RAPPORTS
    // ============================================================
    "rapports" => [
        "label" => "Rapports",
        "items" => [
            [
                "type"       => "dropdown",
                "label"      => "Rapports",
                "icon"       => "bar-chart-2",
                "permission" => "rapports.view",
                "items"      => [
                    ["label" => "Rapports académiques",  "href" => "/rapports/academique",  "permission" => "rapports.academique"],
                    ["label" => "Rapports financiers",   "href" => "/rapports/financier",   "permission" => "rapports.financier"],
                    ["label" => "Rapports de caisse",    "href" => "/rapports/caisse",      "permission" => "rapports.caisse"],
                    ["label" => "Rapports administratifs","href" => "/rapports/administratif","permission" => "rapports.administratif"],
                    ["label" => "Rapports de département","href" => "/rapports/departement","permission" => "rapports.departement"],
                ],
            ],
            [
                "type"       => "link",
                "label"      => "Statistiques",
                "icon"       => "trending-up",
                "href"       => "/statistiques",
                "permission" => "dashboard.view",
            ],
        ],
    ],

    // ============================================================
    // ADMINISTRATION
    // ============================================================
    "admin" => [
        "label" => "Administration",
        "items" => [
            [
                "type"       => "dropdown",
                "label"      => "Utilisateurs",
                "icon"       => "shield",
                "permission" => "utilisateurs.view",
                "items"      => [
                    ["label" => "Liste des utilisateurs", "href" => "/utilisateurs",          "permission" => "utilisateurs.view"],
                    ["label" => "Ajouter un utilisateur", "href" => "/utilisateurs/ajouter",  "permission" => "utilisateurs.create"],
                    ["label" => "Modifier un utilisateur","href" => "/utilisateurs/modifier", "permission" => "utilisateurs.edit"],
                ],
            ],
            [
                "type"       => "link",
                "label"      => "Rôles & Permissions",
                "icon"       => "shield",
                "href"       => "/roles",
                "permission" => "utilisateurs.view",
            ],
            [
                "type"       => "link",
                "label"      => "Paramètres",
                "icon"       => "settings",
                "href"       => "/parametres",
                "permission" => "parametres.view",
            ],
            [
                "type"       => "link",
                "label"      => "Mon profil",
                "icon"       => "user",
                "href"       => "/profil",
                "permission" => "dashboard.view",
            ],
        ],
    ],
];