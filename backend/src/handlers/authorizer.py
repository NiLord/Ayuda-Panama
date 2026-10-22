"""
Lambda Authorizer: lse-authorizer
Valida las solicitudes provenientes de la aplicación móvil 'Ayuda Panamá'
en API Gateway HTTP API v2 (formato simple response 2.0).
Protege los endpoints contra accesos no autorizados mediante verificación
criptográfica de tiempo constante de X-Api-Key y X-App-Secret.
"""

import hmac
import os


APP_API_KEY = os.environ.get("APP_API_KEY", "")
APP_API_SECRET = os.environ.get("APP_API_SECRET", "")


def lambda_handler(event: dict, context) -> dict:
    """
    HTTP API v2 Simple Lambda Authorizer.
    Retorna {"isAuthorized": True/False, "context": {...}}
    """
    if not APP_API_KEY or not APP_API_SECRET:
        # Si la configuración de servidor no está definida, denegar por seguridad
        return {"isAuthorized": False}

    headers = event.get("headers") or {}
    
    # Normalizar headers a minúsculas para búsqueda insensible a mayúsculas
    headers_lower = {k.lower(): v for k, v in headers.items() if isinstance(k, str) and isinstance(v, str)}

    provided_key = headers_lower.get("x-api-key", "")
    provided_secret = headers_lower.get("x-app-secret", "")

    # Comparación segura de tiempo constante para prevenir timing attacks
    key_valid = hmac.compare_digest(provided_key, APP_API_KEY)
    secret_valid = hmac.compare_digest(provided_secret, APP_API_SECRET)

    if key_valid and secret_valid:
        return {
            "isAuthorized": True,
            "context": {
                "app": "ayuda-panama",
                "clientType": "mobile-app",
                "authMethod": "api-key-secret",
            },
        }

    return {"isAuthorized": False}
