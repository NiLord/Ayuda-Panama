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
import backend.src.handlers.get_public_reports
import backend.src.handlers.get_presigned_url
import backend.src.handlers.export_edan


class TestLambdaHandlers(unittest.TestCase):
    @patch("backend.src.handlers.submit_report.reporters_table")
    @patch("backend.src.handlers.submit_report.reports_table")
    def test_submit_report_handler_success(self, mock_reports_table, mock_reporters_table):
        from backend.src.handlers.submit_report import lambda_handler

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

    @patch("backend.src.handlers.get_public_reports.reports_table")
    def test_get_public_reports_handler_redacts_pii(self, mock_reports_table):
        from backend.src.handlers.get_public_reports import lambda_handler

        # Mock DynamoDB scan response with sensitive PII
        mock_reports_table.scan.return_value = {
            "Items": [
                {
                    "report_id": "rep_999",
                    "timestamp": "2026-10-21T10:00:00Z",
                    "prioridad": "P1_CRITICO_VIDA",
                    "informante": {
                        "nombre_completo": "NOMBRE_SUPER_SECRETO",
                        "telefono_contacto": "TELEFONO_PRIVADO_1234",
                    },
                    "titular_afectado": {
                        "nombre_jefe_hogar": "Fernando Perez Secreto",
                        "documento_numero": "7-708-417",
                    },
                    "ubicacion": {
                        "coordenadas": {"lat": 7.62, "lng": -80.35},
                        "provincia": "Los Santos",
                        "distrito": "Las Tablas",
                        "corregimiento": "Las Tablas",
                        "comunidad_sector": "Barrio Centro",
                    },
                    "evaluacion_estructural": {
                        "habitabilidad": "INHABITABLE",
                        "riesgo_colapso_inminente": True,
                    },
                    "censo_demografico": {"total_ocupantes": 4},
                    "servicios_vitales": {"agua_potable": "SIN_SERVICIO"},
                    "necesidades_humanitarias": {"requiere_albergue_inmediato": True},
                }
            ]
        }

        event = {"requestContext": {"http": {"method": "GET"}}}
        response = lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 200)

        geojson = json.loads(response["body"])
        self.assertEqual(geojson["type"], "FeatureCollection")
        self.assertEqual(len(geojson["features"]), 1)

        feature = geojson["features"][0]
        self.assertEqual(feature["properties"]["id"], "rep_999")
        self.assertEqual(feature["properties"]["report_id"], "rep_999")
        self.assertEqual(feature["properties"]["habitabilidad"], "INHABITABLE")
        self.assertEqual(feature["properties"]["semaforo_color"], "#E74C3C")
        self.assertEqual(feature["properties"]["nombre_mascarado"], "Fernando P.")
        self.assertEqual(feature["properties"]["cedula_mascarada"], "7-***-417")
        self.assertIn("APP", feature["properties"]["sistemas_vinculados"])
        self.assertIn("SINAPROC", feature["properties"]["sistemas_vinculados"])

        # Verificar ausencia total de PII en el payload público
        raw_body = response["body"]
        self.assertNotIn("NOMBRE_SUPER_SECRETO", raw_body)
        self.assertNotIn("TELEFONO_PRIVADO_1234", raw_body)
        self.assertNotIn("Perez Secreto", raw_body)
        self.assertNotIn("708", feature["properties"]["cedula_mascarada"])

        # Prueba con delta query parameter since
        delta_event = {
            "requestContext": {"http": {"method": "GET"}},
            "queryStringParameters": {"since": "2026-10-21T00:00:00Z"},
        }
        delta_response = lambda_handler(delta_event, None)
        self.assertEqual(delta_response["statusCode"], 200)
        self.assertTrue(mock_reports_table.scan.called)

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

    @patch("backend.src.handlers.export_edan.reports_table")
    def test_export_edan_handler_auth_and_format(self, mock_reports_table):
        from backend.src.handlers.export_edan import lambda_handler

        mock_reports_table.scan.return_value = {
            "Items": [
                {
                    "report_id": "rep_exp_001",
                    "timestamp": "2026-10-21T10:00:00Z",
                    "prioridad": "P2_URGENTE_ALBERGUE",
                    "informante": {
                        "nombre_completo": "Evaluador Oficial",
                        "organizacion": "SINAPROC",
                        "rol": "FUNCIONARIO_ESTATAL",
                    },
                    "titular_afectado": {
                        "nombre_jefe_hogar": "Pedro Martínez",
                        "documento_tipo": "CEDULA",
                        "documento_numero": "7-55-444",
                        "telefono_afectado": "+507 6111-2222",
                    },
                    "ubicacion": {
                        "coordenadas": {"lat": 7.625, "lng": -80.354},
                        "provincia": "Los Santos",
                        "distrito": "Las Tablas",
                        "corregimiento": "Las Tablas",
                    },
                    "evaluacion_estructural": {
                        "habitabilidad": "INHABITABLE",
                        "tipo_inmueble": "RESIDENCIAL_CASA",
                        "sistema_constructivo": "MAMPOSTERIA_BLOQUE",
                    },
                    "censo_demografico": {"total_ocupantes": 5, "embarazadas": 1},
                    "necesidades_humanitarias": {"requiere_albergue_inmediato": True, "colchon_doble_qty": 2},
                }
            ]
        }

        # Intento sin clave: 401 Unauthorized
        with patch.dict(os.environ, {"ADMIN_SECRET_KEY": "test-admin-key"}):
            unauth_event = {"requestContext": {"http": {"method": "GET"}}, "headers": {}}
            unauth_response = lambda_handler(unauth_event, None)
            self.assertEqual(unauth_response["statusCode"], 401)

            # Intento con clave autorizada
            auth_event = {
                "requestContext": {"http": {"method": "GET"}},
                "headers": {"x-admin-key": "test-admin-key"},
            }
            auth_response = lambda_handler(auth_event, None)
            self.assertEqual(auth_response["statusCode"], 200)

            esri_result = json.loads(auth_response["body"])
            self.assertIn("features", esri_result)
            feature = esri_result["features"][0]
            attrs = feature["attributes"]
            self.assertEqual(attrs["evaluador"], "Evaluador Oficial")
            self.assertEqual(attrs["nombre_jefe"], "Pedro Martínez")
        self.assertEqual(attrs["cedula"], "7-55-444")
        self.assertEqual(attrs["c_embarazadas"], 1.0)
        self.assertEqual(attrs["colchon_doble"], 2.0)


if __name__ == "__main__":
    unittest.main()
