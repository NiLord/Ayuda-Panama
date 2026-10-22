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

import backend.src.handlers.get_miviot_tramite as handler
from backend.src.adapters.miviot_adapter import MiviotConsultaResult


class TestGetMiviotTramite(unittest.TestCase):
    def test_get_miviot_tramite_missing_cedula(self):
        event = {
            "queryStringParameters": {},
            "requestContext": {"http": {"method": "GET"}},
        }
        resp = handler.lambda_handler(event, None)
        self.assertEqual(resp["statusCode"], 400)
        body = json.loads(resp["body"])
        self.assertEqual(body["error"], "PARAMETRO_REQUERIDO")

    @patch.object(handler, "miviot_table")
    def test_get_miviot_tramite_cached_fresh(self, mock_miviot):
        mock_miviot.get_item.return_value = {
            "Item": {
                "PK": "CEDULA#7-71-1473",
                "encontrado": True,
                "reporte": "AFV/07877",
                "fecha_recibido": "12/10/2026",
                "paso_actual": 2,
                "estado_actual": "Evaluación Técnica en Sitio",
                "ultima_actualizacion": "2026-10-22T10:00:00+00:00",
            }
        }

        event = {
            "queryStringParameters": {"cedula": "7-71-1473"},
            "requestContext": {"http": {"method": "GET"}},
        }
        resp = handler.lambda_handler(event, None)
        self.assertEqual(resp["statusCode"], 200)
        body = json.loads(resp["body"])
        self.assertEqual(body["origen"], "CACHE")
        self.assertTrue(body["encontrado"])
        self.assertEqual(body["reporte"], "AFV/07877")
        self.assertEqual(body["cedula_censurada"], "7-*****473")

    @patch.object(handler, "miviot_table")
    def test_get_miviot_tramite_live_call_when_not_cached(self, mock_miviot):
        mock_miviot.get_item.return_value = {}

        with patch("backend.src.handlers.get_miviot_tramite.MiviotAdapter.consultar_cedula") as mock_query:
            mock_query.return_value = MiviotConsultaResult(
                encontrado=True,
                cedula="7-71-1473",
                reporte="AFV/09999",
                fecha_recibido="15/10/2026",
                paso_actual=1,
                estado_actual="Recepción y Registro",
            )

            event = {
                "queryStringParameters": {"cedula": "7-71-1473"},
                "requestContext": {"http": {"method": "GET"}},
            }
            resp = handler.lambda_handler(event, None)
            self.assertEqual(resp["statusCode"], 200)
            body = json.loads(resp["body"])
            self.assertEqual(body["origen"], "MIVIOT_LIVE")
            self.assertTrue(body["encontrado"])
            self.assertEqual(body["reporte"], "AFV/09999")
            mock_miviot.put_item.assert_called_once()
