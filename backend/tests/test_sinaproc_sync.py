import pytest
from unittest.mock import patch, MagicMock
from decimal import Decimal
from backend.src.adapters.sinaproc_sync import (
    map_sinaproc_damage_to_atc20,
    parse_sinaproc_timestamp,
    transform_sinaproc_to_dynamo_item,
    fetch_sinaproc_features,
)


def test_map_sinaproc_damage_to_atc20():
    assert map_sinaproc_damage_to_atc20("Colapso total de paredes") == "COLAPSO_TOTAL"
    assert map_sinaproc_damage_to_atc20("Daño severo en techo") == "INHABITABLE"
    assert map_sinaproc_damage_to_atc20("Daño parcial en muros") == "ACCESO_RESTRINGIDO"
    assert map_sinaproc_damage_to_atc20("Fisura leve en repello") == "HABITABLE"
    assert map_sinaproc_damage_to_atc20(None) == "HABITABLE"


def test_parse_sinaproc_timestamp():
    # Test epoch in ms: 1729555200000 -> 2024-10-22
    iso = parse_sinaproc_timestamp(1729555200000)
    assert "2024-10-22" in iso

    # Test string format
    iso_str = parse_sinaproc_timestamp("15/10/2026 14:30:00")
    assert "2026-10-15" in iso_str


def test_transform_sinaproc_to_dynamo_item():
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
    assert item is not None
    assert item["PK"] == "SINAPROC#10492"
    assert item["fuente"] == "SINAPROC"
    assert item["cedula_normalizada"] == "7-71-1473"
    assert item["GSI_CedulaPK"] == "CEDULA#7-71-1473"
    assert item["cedula_censurada"] == "7-*****473"
    assert item["nombre_titular_censurado"] == "Carlos M."
    assert item["habitabilidad"] == "ACCESO_RESTRINGIDO"
    assert item["ubicacion"]["coordenadas"]["lat"] == Decimal("7.7654")
    assert item["ubicacion"]["coordenadas"]["lng"] == Decimal("-80.2845")


@patch("urllib.request.urlopen")
def test_fetch_sinaproc_features_mock(mock_urlopen):
    mock_resp = MagicMock()
    mock_resp.read.return_value = b'{"features": [{"attributes": {"objectid": 1, "cedula": "7-1-1"}}]}'
    mock_resp.__enter__.return_value = mock_resp
    mock_urlopen.return_value = mock_resp

    features = fetch_sinaproc_features(last_edited_ms=100)
    assert len(features) == 1
    assert features[0]["objectid"] == 1
