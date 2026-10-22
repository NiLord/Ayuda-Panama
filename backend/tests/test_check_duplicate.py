import json
import pytest
from unittest.mock import patch, MagicMock

import backend.src.handlers.check_duplicate as handler
from backend.src.adapters.miviot_adapter import MiviotConsultaResult


def test_check_duplicate_missing_cedula():
    event = {
        "body": json.dumps({}),
        "requestContext": {"http": {"method": "POST"}},
    }
    resp = handler.lambda_handler(event, None)
    assert resp["statusCode"] == 400
    body = json.loads(resp["body"])
    assert body["error"] == "PARAMETRO_REQUERIDO"


def test_check_duplicate_invalid_cedula():
    event = {
        "body": json.dumps({"cedula": "bad-id"}),
        "requestContext": {"http": {"method": "POST"}},
    }
    resp = handler.lambda_handler(event, None)
    assert resp["statusCode"] == 400
    body = json.loads(resp["body"])
    assert body["error"] == "FORMATO_INVALIDO"


@patch.object(handler, "reports_table")
@patch.object(handler, "external_table")
@patch.object(handler, "miviot_table")
def test_check_duplicate_no_duplicates(mock_miviot, mock_ext, mock_reports):
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
        assert resp["statusCode"] == 200
        body = json.loads(resp["body"])
        assert body["existe_duplicado"] is False
        assert body["cedula"] == "7-71-1473"
        assert body["cedula_censurada"] == "7-*****473"
        assert len(body["sistemas"]) == 0


@patch.object(handler, "reports_table")
@patch.object(handler, "external_table")
@patch.object(handler, "miviot_table")
def test_check_duplicate_found_in_sinaproc(mock_miviot, mock_ext, mock_reports):
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
        assert resp["statusCode"] == 200
        body = json.loads(resp["body"])
        assert body["existe_duplicado"] is True
        assert "SINAPROC" in body["sistemas"]
        assert len(body["detalles"]) >= 1


@patch.object(handler, "reports_table")
@patch.object(handler, "external_table")
@patch.object(handler, "miviot_table")
def test_check_duplicate_found_in_miviot_cached(mock_miviot, mock_ext, mock_reports):
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
    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert body["existe_duplicado"] is True
    assert "MIVIOT" in body["sistemas"]
    assert body["tramite_miviot"]["reporte"] == "AFV/07877"
    assert body["tramite_miviot"]["paso_actual"] == 2
