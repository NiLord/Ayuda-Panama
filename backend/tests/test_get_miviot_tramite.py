import json
import pytest
from unittest.mock import patch, MagicMock

import backend.src.handlers.get_miviot_tramite as handler
from backend.src.adapters.miviot_adapter import MiviotConsultaResult


def test_get_miviot_tramite_missing_cedula():
    event = {
        "queryStringParameters": {},
        "requestContext": {"http": {"method": "GET"}},
    }
    resp = handler.lambda_handler(event, None)
    assert resp["statusCode"] == 400
    body = json.loads(resp["body"])
    assert body["error"] == "PARAMETRO_REQUERIDO"


@patch.object(handler, "miviot_table")
def test_get_miviot_tramite_cached_fresh(mock_miviot):
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
    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert body["origen"] == "CACHE"
    assert body["encontrado"] is True
    assert body["reporte"] == "AFV/07877"
    assert body["cedula_censurada"] == "7-*****473"


@patch.object(handler, "miviot_table")
def test_get_miviot_tramite_live_call_when_not_cached(mock_miviot):
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
        assert resp["statusCode"] == 200
        body = json.loads(resp["body"])
        assert body["origen"] == "MIVIOT_LIVE"
        assert body["encontrado"] is True
        assert body["reporte"] == "AFV/09999"
        mock_miviot.put_item.assert_called_once()
