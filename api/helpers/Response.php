<?php
/**
 * api/helpers/Response.php
 * Helper pour réponses JSON standardisées
 */

class Response
{
    /**
     * Envoie une réponse JSON
     */
    public static function json($data, $statusCode = 200)
    {
        http_response_code($statusCode);
        header('Content-Type: application/json; charset=utf-8');
        header('Access-Control-Allow-Origin: *');
        header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
        header('Access-Control-Allow-Headers: Content-Type, Authorization');

        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }

    /**
     * Réponse de succès
     */
    public static function success($data = null, $message = 'Opération réussie', $statusCode = 200)
    {
        $response = [
            'success' => true,
            'message' => $message,
        ];
        if ($data !== null) {
            $response['data'] = $data;
        }
        self::json($response, $statusCode);
    }

    /**
     * Réponse d'erreur
     */
    public static function error($message = 'Erreur', $statusCode = 400, $details = null)
    {
        $response = [
            'success' => false,
            'message' => $message,
        ];
        if ($details !== null && APP_DEBUG) {
            $response['details'] = $details;
        }
        self::json($response, $statusCode);
    }

    /**
     * Réponse de validation échouée
     */
    public static function validation($errors)
    {
        self::json([
            'success' => false,
            'message' => 'Erreur de validation',
            'errors'  => $errors,
        ], 422);
    }

    /**
     * Réponse non autorisée
     */
    public static function unauthorized($message = 'Non autorisé')
    {
        self::json([
            'success' => false,
            'message' => $message,
        ], 401);
    }

    /**
     * Réponse interdite
     */
    public static function forbidden($message = 'Accès interdit')
    {
        self::json([
            'success' => false,
            'message' => $message,
        ], 403);
    }
}