import json
import sys
import unittest
from unittest.mock import patch, MagicMock

# Mock boto3 for zero-dependency local test execution
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

import backend.src.handlers.check_duplicate as handler
from backend.src.adapters.miviot_adapter import MiviotConsultaResult


class TestCheckDuplicate(unittest.TestCase):
    def test_check_duplicate_missing_cedula(self):
        event = {
            "body": json.dumps({}),
            "requestContext": {"http": {"method": "POST"}},
        }
        resp = handler.lambda_handler(event, None)
        self.assertEqual(resp["statusCode"], 400)
        body = json.loads(resp["body"])
        self.assertEqual(body["error"], "PARAMETRO_REQUERIDO")

    def test_check_duplicate_invalid_cedula(self):
        event = {
            "body": json.dumps({"cedula": "bad-id"}),
            "requestContext": {"http": {"method": "POST"}},
        }
        resp = handler.lambda_handler(event, None)
        self.assertEqual(resp["statusCode"], 400)
        body = json.loads(resp["body"])
        self.assertEqual(body["error"], "FORMATO_INVALIDO")

    @patch.object(handler, "reports_table")
    @patch.object(handler, "external_table")
    @patch.object(handler, "miviot_table")
    def test_check_duplicate_no_duplicates(self, mock_miviot, mock_ext, mock_reports):
        mock_reports.query.return_value = {"Items": []}
        mock_ext.query.return_value = {"Items": []}
        mock_miviot.get_item.return_value = {}

        with patch("backend.src.handlers.check_duplicate.MiviotAdapter.consultar_cedula") as mock_miv_query:
            mock_miv_query.return_value = MiviotConsultaResult(encontrado=False, cedula="7-71-1473")
            event = {
                "body": json.dumps({"cedula": "7-71-1473"}),
                "requestContext": {"http": {"method": "POST"}},
            }
            resp = handler.lambda_handler(event, None)
            self.assertEqual(resp["statusCode"], 200)
            body = json.loads(resp["body"])
            self.assertFalse(body["existe_duplicado"])
            self.assertEqual(body["cedula"], "7-71-1473")
            self.assertEqual(body["cedula_censurada"], "7-*****473")
            self.assertEqual(len(body["sistemas"]), 0)

    @patch.object(handler, "reports_table")
    @patch.object(handler, "external_table")
    @patch.object(handler, "miviot_table")
    def test_check_duplicate_found_in_sinaproc(self, mock_miviot, mock_ext, mock_reports):
        mock_reports.query.return_value = {"Items": []}
        mock_ext.query.return_value = {
            "Items": [{
                "PK": "SINAPROC#10492",
                "external_id": "10492",
                "timestamp": "2026-10-15T10:00:00Z",
                "habitabilidad": "HABITABLE",
                "evaluador": "SINAPROC Brigada 1",
            }]
        }
        mock_miviot.get_item.return_value = {}

        with patch("backend.src.handlers.check_duplicate.MiviotAdapter.consultar_cedula") as mock_miv_query:
            mock_miv_query.return_value = MiviotConsultaResult(encontrado=False, cedula="7-71-1473")
            event = {
                "body": json.dumps({"cedula": "7-71-1473"}),
                "requestContext": {"http": {"method": "POST"}},
            }
            resp = handler.lambda_handler(event, None)
            self.assertEqual(resp["statusCode"], 200)
            body = json.loads(resp["body"])
            self.assertTrue(body["existe_duplicado"])
            self.assertIn("SINAPROC", body["sistemas"])
            self.assertGreaterEqual(len(body["detalles"]), 1)

    @patch.object(handler, "reports_table")
    @patch.object(handler, "external_table")
    @patch.object(handler, "miviot_table")
    def test_check_duplicate_found_in_miviot_cached(self, mock_miviot, mock_ext, mock_reports):
        mock_reports.query.return_value = {"Items": []}
        mock_ext.query.return_value = {"Items": []}
        mock_miviot.get_item.return_value = {
            "Item": {
                "PK": "CEDULA#7-71-1473",
                "encontrado": True,
                "reporte": "AFV/07877",
                "fecha_recibido": "12/10/2026",
                "paso_actual": 2,
                "estado_actual": "Evaluación Técnica en Sitio",
            }
        }

        event = {
            "body": json.dumps({"cedula": "7-71-1473"}),
            "requestContext": {"http": {"method": "POST"}},
        }
        resp = handler.lambda_handler(event, None)
        self.assertEqual(resp["statusCode"], 200)
        body = json.loads(resp["body"])
        self.assertTrue(body["existe_duplicado"])
        self.assertIn("MIVIOT", body["sistemas"])
        self.assertEqual(body["tramite_miviot"]["reporte"], "AFV/07877")
        self.assertEqual(body["tramite_miviot"]["paso_actual"], 2)
