# 🎓 U-Connect — Plateforme de Gestion Universitaire Multi-Campus

> **Empowering Minds, Building Futures**
> Ubuntu International Academy (UIA)

U-Connect est une application web complète de gestion universitaire conçue pour piloter l'ensemble des activités académiques, administratives et financières d'une université multi-campus.

---

## 📋 Table des matières

1. [Présentation](#-présentation)
2. [Fonctionnalités](#-fonctionnalités)
3. [Stack technique](#-stack-technique)
4. [Architecture](#-architecture)
5. [Installation](#-installation)
6. [Configuration](#-configuration)
7. [Structure des dossiers](#-structure-des-dossiers)
8. [Rôles et permissions](#-rôles-et-permissions)
9. [Routes principales](#-routes-principales)
10. [Comptes de test](#-comptes-de-test)
11. [Sécurité](#-sécurité)
12. [Maintenance](#-maintenance)
13. [Contribution](#-contribution)
14. [Licence](#-licence)

---

## 🎯 Présentation

**U-Connect** est le système d'information centralisé d'Ubuntu International Academy. Il couvre :

- La gestion des **étudiants** et des **inscriptions**
- La **scolarité** et les **notes** (LMD)
- Les **finances** (frais de scolarité, paiements, bourses)
- La **bibliothèque** (catalogue, prêts, amendes)
- La **communication** interne (messagerie, annonces, notifications)
- Les **rapports** et **statistiques** de pilotage
- La **gestion des utilisateurs** et des **campus**

L'application fonctionne sur **3 campus** (Bujumbura, Gitega, Ngozi) et gère **10 rôles** différents avec des permissions granulaires.

---

## ✨ Fonctionnalités

### 📚 Gestion académique
- Années académiques, semestres, facultés, départements
- Programmes LMD (Licence / Master / Doctorat)
- Unités d'enseignement (UE) et cours
- Système de crédits ECTS et de compensation
- Calcul automatique des moyennes et mentions
- Génération de relevés de notes et diplômes

### 👥 Gestion des étudiants
- Dossiers étudiants complets (matricule, documents, historique)
- Inscriptions (nouvelle, réinscription, redoublement, transfert)
- Vérification des pièces justificatives
- Suivi des transferts inter-campus
- Cartes étudiantes

### 📊 Évaluations & Résultats
- Évaluations (TD, TP, Interrogations, Examens, Rattrapages)
- Saisie des notes avec vérification des barèmes
- Délibérations et jurys
- Calcul automatique des résultats par cours, UE, semestre et année
- Réclamations de notes

### 💰 Gestion financière
- Structures de frais par programme et niveau
- Factures et échéanciers
- Paiements multiples (espèces, virement, mobile money, chèque, carte)
- Bourses et exonérations
- Caisse quotidienne
- Rapports financiers et taux de recouvrement

### 📖 Bibliothèque
- Catalogue de livres (physiques et numériques)
- Gestion des exemplaires (code-barres)
- Prêts et retours avec politiques configurables
- Amendes de retard
- Réservations

### 💬 Communication
- Messagerie interne
- Annonces ciblées (par rôle, campus, programme)
- Notifications
- Journal d'audit

### 📈 Rapports & Pilotage
- Tableau de bord Super Admin (KPIs stratégiques)
- Rapports par campus, faculté, département
- Statistiques de réussite, recouvrement, présence
- Top étudiants
- Alertes automatiques

---

## 🛠️ Stack technique

| Composant | Technologie |
|-----------|-------------|
| **Langage backend** | PHP 8.2 (natif, sans framework) |
| **Base de données** | MariaDB 10.4 / MySQL 8.0 |
| **Accès BDD** | PDO (requêtes préparées) |
| **Frontend** | HTML5, CSS3, Bootstrap 4 (via DeskApp) |
| **Icônes** | Dropways Icons (DeskApp) |
| **Alertes** | SweetAlert2 |
| **Graphiques** | ApexCharts |
| **Serveur local** | XAMPP / MAMP |
| **Versioning** | Git |

---

## 🏗️ Architecture

### Architecture globale
