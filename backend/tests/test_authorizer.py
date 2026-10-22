import os
import unittest
from unittest.mock import patch
from backend.src.handlers import authorizer


class TestAuthorizer(unittest.TestCase):
    def setUp(self):
        self.valid_key = "test-api-key-12345"
        self.valid_secret = "test-api-secret-67890"

    def test_authorized_when_headers_match(self):
        with patch.dict(os.environ, {"APP_API_KEY": self.valid_key, "APP_API_SECRET": self.valid_secret}):
            # Recargar variables de módulo si aplican
            authorizer.APP_API_KEY = self.valid_key
            authorizer.APP_API_SECRET = self.valid_secret

            event = {
                "version": "2.0",
                "type": "REQUEST",
                "headers": {
                    "X-Api-Key": self.valid_key,
                    "X-App-Secret": self.valid_secret,
                },
            }
            response = authorizer.lambda_handler(event, None)
            self.assertTrue(response.get("isAuthorized"))
            self.assertEqual(response.get("context", {}).get("app"), "ayuda-panama")

    def test_unauthorized_when_key_is_wrong(self):
        with patch.dict(os.environ, {"APP_API_KEY": self.valid_key, "APP_API_SECRET": self.valid_secret}):
            authorizer.APP_API_KEY = self.valid_key
            authorizer.APP_API_SECRET = self.valid_secret

            event = {
                "version": "2.0",
                "type": "REQUEST",
                "headers": {
                    "x-api-key": "wrong-key",
                    "x-app-secret": self.valid_secret,
                },
            }
            response = authorizer.lambda_handler(event, None)
            self.assertFalse(response.get("isAuthorized"))

    def test_unauthorized_when_secret_is_wrong(self):
        with patch.dict(os.environ, {"APP_API_KEY": self.valid_key, "APP_API_SECRET": self.valid_secret}):
            authorizer.APP_API_KEY = self.valid_key
            authorizer.APP_API_SECRET = self.valid_secret

            event = {
                "version": "2.0",
                "type": "REQUEST",
                "headers": {
                    "x-api-key": self.valid_key,
                    "x-app-secret": "wrong-secret",
                },
            }
            response = authorizer.lambda_handler(event, None)
            self.assertFalse(response.get("isAuthorized"))

    def test_unauthorized_when_headers_missing(self):
        with patch.dict(os.environ, {"APP_API_KEY": self.valid_key, "APP_API_SECRET": self.valid_secret}):
            authorizer.APP_API_KEY = self.valid_key
            authorizer.APP_API_SECRET = self.valid_secret

            event = {
                "version": "2.0",
                "type": "REQUEST",
                "headers": {},
            }
            response = authorizer.lambda_handler(event, None)
            self.assertFalse(response.get("isAuthorized"))

    def test_unauthorized_when_env_not_configured(self):
        authorizer.APP_API_KEY = ""
        authorizer.APP_API_SECRET = ""

        event = {
            "version": "2.0",
            "type": "REQUEST",
            "headers": {
                "x-api-key": "any",
                "x-app-secret": "any",
            },
        }
        response = authorizer.lambda_handler(event, None)
        self.assertFalse(response.get("isAuthorized"))


if __name__ == "__main__":
    unittest.main()
