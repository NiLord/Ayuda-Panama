"""
Comprehensive Unit Tests for AWS Lambda Handlers
Uses unittest.mock to mock boto3 services (DynamoDB, S3) with zero external dependencies.
"""

import unittest
from unittest.mock import patch, MagicMock
import json
import os
import sys

# Mock boto3 and botocore before handler imports for zero-dependency local testing
mock_boto3 = MagicMock()
mock_boto3_dynamodb = MagicMock()
mock_boto3_conditions = MagicMock()
mock_boto3_dynamodb.conditions = mock_boto3_conditions
mock_botocore = MagicMock()
mock_botocore_config = MagicMock()
mock_botocore.config = mock_botocore_config
if "boto3" not in sys.modules:
    sys.modules["boto3"] = mock_boto3
if "boto3.dynamodb" not in sys.modules:
    sys.modules["boto3.dynamodb"] = mock_boto3_dynamodb
if "boto3.dynamodb.conditions" not in sys.modules:
    sys.modules["boto3.dynamodb.conditions"] = mock_boto3_conditions
if "botocore" not in sys.modules:
    sys.modules["botocore"] = mock_botocore
if "botocore.config" not in sys.modules:
    sys.modules["botocore.config"] = mock_botocore_config

import backend.src.handlers.submit_report
import backend.src.handlers.get_national_dashboard
import backend.src.handlers.get_presigned_url


class TestLambdaHandlers(unittest.TestCase):
    @patch("backend.src.handlers.submit_report.external_table")
    @patch("backend.src.handlers.submit_report.reporters_table")
    @patch("backend.src.handlers.submit_report.reports_table")
    def test_submit_report_handler_success(self, mock_reports_table, mock_reporters_table, mock_external_table):
        from backend.src.handlers.submit_report import lambda_handler

        mock_reports_table.query.return_value = {"Items": []}
        mock_external_table.query.return_value = {"Items": []}

        event = {
            "requestContext": {
                "http": {
                    "method": "POST",
                    "sourceIp": "190.140.20.1",
                    "userAgent": "AyudaLosSantos/1.0",
                }
            },
            "body": json.dumps({
                "informante": {
                    "reporter_id": "rep_test_123",
                    "rol": "VECINO_O_TERCERO",
                    "nombre_completo": "Juan Pérez",
                    "telefono_contacto": "+507 6000-1111",
                },
                "titular_afectado": {
                    "nombre_jefe_hogar": "María Gómez",
                    "documento_numero": "7-99-888",
                },
                "ubicacion": {
                    "coordenadas": {"lat": 7.625, "lng": -80.354},
                    "provincia": "Los Santos",
                    "distrito": "Las Tablas",
                    "corregimiento": "Las Tablas",
                },
                "evaluacion_estructural": {
                    "habitabilidad": "INHABITABLE",
                    "riesgo_colapso_inminente": True,
                },
                "censo_demografico": {
                    "total_ocupantes": 3,
                    "atrapados_o_desaparecidos": 1,
                },
                "necesidades_humanitarias": {
                    "requiere_albergue_inmediato": True,
                },
            }),
        }

        response = lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 201)
        body = json.loads(response["body"])
        self.assertTrue(body["success"])
        self.assertEqual(body["prioridad"], "P1_CRITICO_VIDA")
        self.assertTrue(mock_reports_table.put_item.called)
        self.assertTrue(mock_reporters_table.update_item.called)

    @patch("backend.src.handlers.get_national_dashboard.external_table")
    def test_get_national_dashboard_cached(self, mock_external_table):
        from backend.src.handlers.get_national_dashboard import lambda_handler

        mock_external_table.get_item.return_value = {
            "Item": {
                "PK": "CONFIG#HOURLY_DASHBOARD",
                "SK": "HOURLY",
                "payload": {
                    "censo_coen": {
                        "familias_afectadas": 20101,
                        "personas_afectadas": 71668,
                    },
                    "severidad_habitacional": {
                        "colapsos_estructurales": 0,
                    },
                    "metadatos": {
                        "ultima_actualizacion_iso": "2026-10-22T21:00:00Z",
                    },
                },
                "updated_at": "2026-10-22T21:00:00Z",
            }
        }

        event = {"requestContext": {"http": {"method": "GET"}}, "queryStringParameters": {}}
        response = lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 200)

        body = json.loads(response["body"])
        self.assertTrue(body["success"])
        self.assertTrue(body["cached"])
        self.assertEqual(body["data"]["censo_coen"]["familias_afectadas"], 20101)

    @patch("backend.src.handlers.get_presigned_url.s3_client")
    def test_get_presigned_url_handler(self, mock_s3_client):
        from backend.src.handlers.get_presigned_url import lambda_handler

        mock_s3_client.generate_presigned_url.return_value = "https://s3.amazonaws.com/test-presigned-url"

        # Formato válido
        event = {
            "requestContext": {"http": {"method": "POST"}},
            "body": json.dumps({"report_id": "rep_123", "extension": "jpg"}),
        }
        response = lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 200)
        body = json.loads(response["body"])
        self.assertIn("upload_url", body)
        self.assertIn("s3_key", body)
        self.assertTrue(body["s3_key"].startswith("reports/rep_123/danos/"))
        self.assertEqual(body["category"], "danos")

        # Formato válido con categoría identificacion y photo_id personalizado
        id_event = {
            "requestContext": {"http": {"method": "POST"}},
            "body": json.dumps({
                "report_id": "rep_123",
                "category": "identificacion",
                "photo_id": "cedula_001",
                "file_name": "cedula.png"
            }),
        }
        id_response = lambda_handler(id_event, None)
        self.assertEqual(id_response["statusCode"], 200)
        id_body = json.loads(id_response["body"])
        self.assertEqual(id_body["s3_key"], "reports/rep_123/identificacion/cedula_001.png")
        self.assertEqual(id_body["category"], "identificacion")

        # Formato no permitido
        bad_event = {
            "requestContext": {"http": {"method": "POST"}},
            "body": json.dumps({"report_id": "rep_123", "extension": "exe"}),
        }
        bad_response = lambda_handler(bad_event, None)
        self.assertEqual(bad_response["statusCode"], 400)

    @patch("backend.src.handlers.submit_report.external_table")
    @patch("backend.src.handlers.submit_report.reporters_table")
    @patch("backend.src.handlers.submit_report.reports_table")
    def test_submit_report_handler_rejects_duplicate_cedula(self, mock_reports_table, mock_reporters_table, mock_external_table):
        from backend.src.handlers.submit_report import lambda_handler

        # Mock that GSI2_Cedula in reports_table already has a report for this cedula
        mock_reports_table.query.return_value = {
            "Items": [{"report_id": "rep_existing", "cedula_normalizada": "7-99-888"}]
        }
        mock_external_table.query.return_value = {"Items": []}

        event = {
            "requestContext": {"http": {"method": "POST"}},
            "body": json.dumps({
                "titular_afectado": {
                    "nombre_jefe_hogar": "María Gómez",
                    "documento_numero": "7-99-888",
                },
                "ubicacion": {"coordenadas": {"lat": 7.625, "lng": -80.354}},
                "evaluacion_estructural": {"habitabilidad": "HABITABLE"},
                "censo_demografico": {"total_ocupantes": 1},
                "necesidades_humanitarias": {},
            }),
        }

        response = lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 409)
        body = json.loads(response["body"])
        self.assertFalse(body["success"])
        self.assertEqual(body["error"], "REPORTE_DUPLICADO")


if __name__ == "__main__":
    unittest.main()
