<?php
/**
 * api/database.php
 * Classe PDO Singleton — U-Connect
 * PHP pur - Sans framework
 *
 * ⚠️ CORRECTION : alignement de la collation sur utf8mb4_general_ci
 *    (celle utilisée par la base uconnect_db)
 */

require_once __DIR__ . '/config.php';

class Database
{
    /** @var Database|null Instance unique */
    private static $instance = null;

    /** @var PDO Connexion PDO */
    private $pdo;

    /** @var int Compteur de transactions imbriquées */
    private $transactionLevel = 0;

    /** @var array Statistiques de requêtes (debug) */
    private $queryStats = [
        'count'   => 0,
        'time'    => 0.0,
        'queries' => [],
    ];

    /**
     * Constructeur privé (Singleton)
     */
    private function __construct()
    {
        // ============================================================
        // CONSTANTES PAR DÉFAUT (si non définies dans config.php)
        // ============================================================
        if (!defined('DB_CHARSET'))    define('DB_CHARSET', 'utf8mb4');
        if (!defined('DB_COLLATION'))  define('DB_COLLATION', 'utf8mb4_general_ci'); // ← FORCÉ
        if (!defined('DB_HOST'))       define('DB_HOST', 'localhost');
        if (!defined('DB_PORT'))       define('DB_PORT', '3306');
        if (!defined('DB_NAME'))       define('DB_NAME', 'uconnect_db');
        if (!defined('DB_USER'))       define('DB_USER', 'root');
        if (!defined('DB_PASS'))       define('DB_PASS', '');
        if (!defined('APP_DEBUG'))     define('APP_DEBUG', true);
        if (!defined('LOG_PATH'))      define('LOG_PATH', __DIR__ . '/../logs/error.log');

        // ============================================================
        // FORCER LA COLLATION (indépendamment de config.php)
        // ============================================================
        $charset   = 'utf8mb4';
        $collation = 'utf8mb4_general_ci';  // ← même collation que votre base

        $dsn = "mysql:host=" . DB_HOST
             . ";port=" . DB_PORT
             . ";dbname=" . DB_NAME
             . ";charset=" . $charset;

        $options = [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
            PDO::ATTR_PERSISTENT         => false,
            PDO::ATTR_TIMEOUT            => 5,
            PDO::ATTR_STRINGIFY_FETCHES  => false,
            // ⚠️ Utiliser directement la collation correcte
            PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES $charset COLLATE $collation, time_zone = '+02:00'",
        ];

        try {
            $this->pdo = new PDO($dsn, DB_USER, DB_PASS, $options);

            // ============================================================
            // SÉCURITÉ SUPPLÉMENTAIRE : forcer la collation au niveau session
            // ============================================================
            $this->pdo->exec("SET NAMES $charset COLLATE $collation");
            $this->pdo->exec("SET collation_connection = $collation");
            $this->pdo->exec("SET time_zone = '+02:00'");

        } catch (PDOException $e) {
            $this->logError($e);
            throw $e;
        }
    }

    /**
     * Empêche le clonage
     */
    private function __clone() {}

    /**
     * Empêche la désérialisation
     */
    public function __wakeup()
    {
        throw new RuntimeException("Impossible de désérialiser un Singleton");
    }

    /**
     * Récupère l'instance unique
     */
    public static function getInstance()
    {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    /**
     * Récupère la connexion PDO brute
     */
    public function getPdo()
    {
        return $this->pdo;
    }

    // ============================================================
    // REQUÊTES PRÉPARÉES
    // ============================================================

    public function query($sql, $params = [])
    {
        $start = microtime(true);

        try {
            $stmt = $this->pdo->prepare($sql);
            $stmt->execute($params);

            $this->queryStats['count']++;
            $this->queryStats['time'] += microtime(true) - $start;
            if (APP_DEBUG) {
                $this->queryStats['queries'][] = [
                    'sql'    => $sql,
                    'params' => $params,
                    'time'   => round((microtime(true) - $start) * 1000, 2) . 'ms',
                ];
            }

            return $stmt;
        } catch (PDOException $e) {
            $this->logError($e, $sql, $params);
            throw $e;
        }
    }

    public function fetch($sql, $params = [])
    {
        $result = $this->query($sql, $params)->fetch();
        return $result === false ? null : $result;
    }

    public function fetchAll($sql, $params = [])
    {
        return $this->query($sql, $params)->fetchAll();
    }

    public function fetchColumn($sql, $params = [], $column = 0)
    {
        $result = $this->query($sql, $params)->fetchColumn($column);
        return $result === false ? null : $result;
    }

    public function fetchCol($sql, $params = [], $column = 0)
    {
        return $this->query($sql, $params)->fetchAll(PDO::FETCH_COLUMN, $column);
    }

    public function fetchPairs($sql, $params = [])
    {
        return $this->query($sql, $params)->fetchAll(PDO::FETCH_KEY_PAIR);
    }

    public function execute($sql, $params = [])
    {
        return $this->query($sql, $params)->rowCount();
    }

    public function insert($sql, $params = [])
    {
        $this->query($sql, $params);
        return (int) $this->pdo->lastInsertId();
    }

    public function exists($sql, $params = [])
    {
        return $this->fetchColumn($sql, $params) !== null;
    }

    // ============================================================
    // TRANSACTIONS
    // ============================================================

    public function beginTransaction()
    {
        if ($this->transactionLevel === 0) {
            $this->pdo->beginTransaction();
        } else {
            $this->pdo->exec("SAVEPOINT trans_{$this->transactionLevel}");
        }
        $this->transactionLevel++;
        return true;
    }

    public function commit()
    {
        if ($this->transactionLevel === 0) {
            throw new RuntimeException("Aucune transaction active");
        }
        $this->transactionLevel--;
        if ($this->transactionLevel === 0) {
            return $this->pdo->commit();
        }
        $this->pdo->exec("RELEASE SAVEPOINT trans_{$this->transactionLevel}");
        return true;
    }

    public function rollback()
    {
        if ($this->transactionLevel === 0) {
            throw new RuntimeException("Aucune transaction active");
        }
        $this->transactionLevel--;
        if ($this->transactionLevel === 0) {
            return $this->pdo->rollBack();
        }
        $this->pdo->exec("ROLLBACK TO SAVEPOINT trans_{$this->transactionLevel}");
        return true;
    }

    public function transaction($callback)
    {
        $this->beginTransaction();
        try {
            $result = $callback($this);
            $this->commit();
            return $result;
        } catch (Exception $e) {
            $this->rollback();
            throw $e;
        }
    }

    public function inTransaction()
    {
        return $this->pdo->inTransaction();
    }

    // ============================================================
    // UTILITAIRES
    // ============================================================

    public function getDatabaseName()
    {
        return (string) $this->fetchColumn("SELECT DATABASE()");
    }

    public function tableExists($table)
    {
        try {
            $result = $this->fetch(
                "SELECT 1 FROM information_schema.tables
                 WHERE table_schema = ? AND table_name = ? LIMIT 1",
                [DB_NAME, $table]
            );
            return $result !== null;
        } catch (PDOException $e) {
            return false;
        }
    }

    public function ping()
    {
        try {
            $this->pdo->query("SELECT 1");
            return true;
        } catch (PDOException $e) {
            return false;
        }
    }

    /**
     * Retourne la collation effective de la connexion (debug)
     */
    public function getCollation()
    {
        try {
            return $this->fetch(
                "SELECT @@collation_connection AS collation,
                        @@character_set_connection AS charset"
            );
        } catch (PDOException $e) {
            return null;
        }
    }

    public function getStats()
    {
        return [
            'query_count'    => $this->queryStats['count'],
            'total_time_ms'  => round($this->queryStats['time'] * 1000, 2),
            'queries'        => APP_DEBUG ? $this->queryStats['queries'] : [],
        ];
    }

    public function resetStats()
    {
        $this->queryStats = ['count' => 0, 'time' => 0.0, 'queries' => []];
    }

    private function logError($e, $sql = '', $params = [])
    {
        $logDir = dirname(LOG_PATH);
        if (!is_dir($logDir)) {
            @mkdir($logDir, 0775, true);
        }

        $message = sprintf(
            "[%s] PDO ERROR: %s\n  SQL: %s\n  Params: %s\n  File: %s:%d\n\n",
            date('Y-m-d H:i:s'),
            $e->getMessage(),
            $sql ?: 'N/A',
            json_encode($params, JSON_UNESCAPED_UNICODE),
            $e->getFile(),
            $e->getLine()
        );

        @file_put_contents(LOG_PATH, $message, FILE_APPEND | LOCK_EX);
    }
}