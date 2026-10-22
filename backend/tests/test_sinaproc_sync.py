import json
import sys
import unittest
from unittest.mock import patch, MagicMock
from decimal import Decimal

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

from backend.src.adapters.sinaproc_sync import (
    map_sinaproc_damage_to_atc20,
    parse_sinaproc_timestamp,
    transform_sinaproc_to_dynamo_item,
    fetch_sinaproc_features,
)


class TestSinaprocSync(unittest.TestCase):
    def test_map_sinaproc_damage_to_atc20(self):
        self.assertEqual(map_sinaproc_damage_to_atc20("Colapso total de paredes"), "COLAPSO_TOTAL")
        self.assertEqual(map_sinaproc_damage_to_atc20("Daño severo en techo"), "INHABITABLE")
        self.assertEqual(map_sinaproc_damage_to_atc20("Daño parcial en muros"), "ACCESO_RESTRINGIDO")
        self.assertEqual(map_sinaproc_damage_to_atc20("Fisura leve en repello"), "HABITABLE")
        self.assertEqual(map_sinaproc_damage_to_atc20(None), "HABITABLE")

    def test_parse_sinaproc_timestamp(self):
        # Test epoch in ms: 1729555200000 -> 2024-10-22
        iso = parse_sinaproc_timestamp(1729555200000)
        self.assertIn("2024-10-22", iso)

        # Test string format
        iso_str = parse_sinaproc_timestamp("15/10/2026 14:30:00")
        self.assertIn("2026-10-15", iso_str)

    def test_transform_sinaproc_to_dynamo_item(self):
        raw_attr = {
            "objectid": 10492,
            "cedula": "7 71 1473",
            "nombre_jefe": "Carlos Mendoza",
            "provincia": "los_santos",
            "distrito": "las_tablas",
            "corregimiento": "el_cocal",
            "latitud": "7.7654",
            "longitud": "-80.2845",
            "d_infrestuctura": "Parcial",
            "created_date": 1729555200000,
            "evaluador": "Juan Brigadista",
        }

        item = transform_sinaproc_to_dynamo_item(raw_attr)
        self.assertIsNotNone(item)
        self.assertEqual(item["PK"], "SINAPROC#10492")
        self.assertEqual(item["fuente"], "SINAPROC")
        self.assertEqual(item["cedula_normalizada"], "7-71-1473")
        self.assertEqual(item["GSI_CedulaPK"], "CEDULA#7-71-1473")
        self.assertEqual(item["cedula_censurada"], "7-*****473")
        self.assertEqual(item["nombre_titular_censurado"], "Carlos M.")
        self.assertEqual(item["habitabilidad"], "ACCESO_RESTRINGIDO")
        self.assertEqual(item["ubicacion"]["coordenadas"]["lat"], Decimal("7.7654"))
        self.assertEqual(item["ubicacion"]["coordenadas"]["lng"], Decimal("-80.2845"))

    @patch("urllib.request.urlopen")
    def test_fetch_sinaproc_features_mock(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = b'{"features": [{"attributes": {"objectid": 1, "cedula": "7-1-1"}}]}'
        mock_resp.__enter__.return_value = mock_resp
        mock_urlopen.return_value = mock_resp

        features = fetch_sinaproc_features(last_edited_ms=100)
        self.assertEqual(len(features), 1)
        self.assertEqual(features[0]["objectid"], 1)

    @patch("backend.src.handlers.sync_sinaproc.external_table")
    @patch("backend.src.handlers.sync_sinaproc.fetch_sinaproc_features")
    def test_sync_sinaproc_handler_checkpoint(self, mock_fetch, mock_table):
        from backend.src.handlers.sync_sinaproc import lambda_handler

        mock_table.get_item.return_value = {
            "Item": {"last_sync_ms": 1700000000000}
        }
        mock_fetch.return_value = [
            {
                "objectid": 100,
                "cedula": "7-71-1473",
                "last_edited_date": 1700005000000,
            }
        ]

        event = {}  # EventBridge trigger
        response = lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 200)
        body = json.loads(response["body"])
        self.assertTrue(body["success"])
        self.assertEqual(body["items_guardados"], 1)
        self.assertEqual(body["checkpoint_ms"], 1700005000000)
        mock_table.put_item.assert_called_once()
