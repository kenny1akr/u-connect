<?php
/**
 * api/helpers/Jwt.php
 * Génération et vérification JWT - Sans librairie externe
 * Implémentation HS256
 */

require_once __DIR__ . '/../config.php';

class Jwt
{
    /**
     * Génère un token JWT
     */
    public static function encode(array $payload, $expiration = null)
    {
        $expiration = $expiration ?? JWT_EXPIRATION;

        $header = [
            'alg' => JWT_ALGO,
            'typ' => 'JWT',
        ];

        $payload['iat'] = time();
        $payload['exp'] = time() + $expiration;

        $base64Header  = self::base64UrlEncode(json_encode($header));
        $base64Payload = self::base64UrlEncode(json_encode($payload));

        $signature = hash_hmac(
            'sha256',
            "$base64Header.$base64Payload",
            JWT_SECRET,
            true
        );
        $base64Signature = self::base64UrlEncode($signature);

        return "$base64Header.$base64Payload.$base64Signature";
    }

    /**
     * Décode et vérifie un token JWT
     * @return array|false Payload si valide, false sinon
     */
    public static function decode($token)
    {
        $parts = explode('.', $token);
        if (count($parts) !== 3) {
            return false;
        }

        [$base64Header, $base64Payload, $base64Signature] = $parts;

        // Vérifier la signature
        $expectedSignature = hash_hmac(
            'sha256',
            "$base64Header.$base64Payload",
            JWT_SECRET,
            true
        );
        $expectedBase64 = self::base64UrlEncode($expectedSignature);

        if (!hash_equals($expectedBase64, $base64Signature)) {
            return false;
        }

        // Décoder le payload
        $payload = json_decode(self::base64UrlDecode($base64Payload), true);
        if (!is_array($payload)) {
            return false;
        }

        // Vérifier l'expiration
        if (isset($payload['exp']) && $payload['exp'] < time()) {
            return false;
        }

        return $payload;
    }

    /**
     * Extrait le token depuis les headers HTTP
     */
    public static function getBearerToken()
    {
        $headers = self::getAuthorizationHeader();
        if (empty($headers)) {
            return null;
        }

        if (preg_match('/Bearer\s(\S+)/', $headers, $matches)) {
            return $matches[1];
        }
        return null;
    }

    /**
     * Récupère le header Authorization
     */
    private static function getAuthorizationHeader()
    {
        if (isset($_SERVER['HTTP_AUTHORIZATION'])) {
            return trim($_SERVER['HTTP_AUTHORIZATION']);
        }
        if (isset($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
            return trim($_SERVER['REDIRECT_HTTP_AUTHORIZATION']);
        }
        if (function_exists('apache_request_headers')) {
            $headers = apache_request_headers();
            if (isset($headers['Authorization'])) {
                return trim($headers['Authorization']);
            }
        }
        return null;
    }

    private static function base64UrlEncode($data)
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    private static function base64UrlDecode($data)
    {
        $remainder = strlen($data) % 4;
        if ($remainder) {
            $data .= str_repeat('=', 4 - $remainder);
        }
        return base64_decode(strtr($data, '-_', '+/'));
    }
}