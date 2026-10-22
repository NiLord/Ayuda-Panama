"""
SINAPROC ArcGIS FeatureServer Synchronizer
Transforma y sincroniza registros de evaluación de daños (EDAN) desde el FeatureServer
oficial de SINAPROC hacia la tabla de registros externos (ExternalReportsTable) en DynamoDB.
"""

from datetime import datetime, timezone
from decimal import Decimal
import json
import logging
import re
import urllib.parse
import urllib.request
from typing import Dict, Any, List, Optional, Tuple

from ..utils.cedula_normalizer import normalize_cedula, mask_cedula, mask_person_name

logger = logging.getLogger(__name__)

DEFAULT_FEATURE_SERVER_URL = (
    "https://sig.sinaproc.gob.pa/server/rest/services/Hosted/"
    "survey123_935c7e293909453b82f37e9a151aaf19_results/FeatureServer/0"
)

# Mapeo de daño en SINAPROC a norma de habitabilidad ATC-20
HABITABILIDAD_MAP = {
    "total": "COLAPSO_TOTAL",
    "colapso": "COLAPSO_TOTAL",
    "severo": "INHABITABLE",
    "inhabitable": "INHABITABLE",
    "parcial": "ACCESO_RESTRINGIDO",
    "moderado": "ACCESO_RESTRINGIDO",
    "leve": "HABITABLE",
    "menor": "HABITABLE",
    "habitable": "HABITABLE",
}


def map_sinaproc_damage_to_atc20(dano_infra: Optional[str]) -> str:
    """Traduce el nivel descriptivo de SINAPROC a la categoría canónica ATC-20."""
    if not dano_infra:
        return "HABITABLE"
    cleaned = dano_infra.strip().lower()
    for key, atc20 in HABITABILIDAD_MAP.items():
        if key in cleaned:
            return atc20
    return "ACCESO_RESTRINGIDO"


def parse_sinaproc_timestamp(val: Any) -> str:
    """Convierte epoch ms o strings de fecha de ArcGIS a ISO-8601 UTC."""
    if val is None:
        return datetime.now(timezone.utc).isoformat()
    if isinstance(val, (int, float)):
        # Si es epoch en milisegundos
        try:
            return datetime.fromtimestamp(val / 1000.0, tz=timezone.utc).isoformat()
        except Exception:
            return datetime.now(timezone.utc).isoformat()
    # Si viene como string
    val_str = str(val).strip()
    for fmt in ["%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M", "%d/%m/%Y", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"]:
        try:
            return datetime.strptime(val_str, fmt).replace(tzinfo=timezone.utc).isoformat()
        except ValueError:
            pass
    return datetime.now(timezone.utc).isoformat()


def transform_sinaproc_to_dynamo_item(attr: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Convierte una fila/atributo de ArcGIS FeatureServer en un ítem de DynamoDB
    para ExternalReportsTable con partición PK/SK e índices GSI_Cedula y GSI_Ubicacion.
    """
    object_id = attr.get("objectid") or attr.get("OBJECTID")
    if not object_id:
        return None

    raw_cedula = str(attr.get("cedula") or "").strip()
    norm_cedula = normalize_cedula(raw_cedula)
    censored_cedula = mask_cedula(norm_cedula or raw_cedula)

    raw_jefe = str(attr.get("nombre_jefe") or "").strip()
    censored_name = mask_person_name(raw_jefe)

    ts_iso = parse_sinaproc_timestamp(attr.get("last_edited_date") or attr.get("created_date") or attr.get("f_h_registro"))

    provincia = (attr.get("provincia") or "Los Santos").strip().title()
    distrito = (attr.get("distrito") or "Las Tablas").strip().title()
    corregimiento = (attr.get("corregimiento") or "").strip().title()
    comunidad = (attr.get("comunidad") or "").strip().title()

    lat = None
    lng = None
    try:
        if attr.get("latitud") and attr.get("longitud"):
            lat = float(attr["latitud"])
            lng = float(attr["longitud"])
    except (ValueError, TypeError):
        pass

    dano_infra = attr.get("t_d_infrestuctura") or attr.get("d_infrestuctura") or ""
    habitabilidad = map_sinaproc_damage_to_atc20(str(dano_infra))

    # Construir item para DynamoDB
    item = {
        "PK": f"SINAPROC#{object_id}",
        "SK": f"METADATA#{ts_iso}",
        "fuente": "SINAPROC",
        "external_id": str(object_id),
        "timestamp": ts_iso,
        "habitabilidad": habitabilidad,
        "nivel_dano": str(dano_infra),
        "evaluador": attr.get("evaluador") or "SINAPROC Oficial",
        "institucion": attr.get("institucion") or "SINAPROC",
        "cedula_censurada": censored_cedula,
        "nombre_titular_censurado": censored_name,
        "ubicacion": {
            "provincia": provincia,
            "distrito": distrito,
            "corregimiento": corregimiento,
            "comunidad_sector": comunidad,
            "calle_o_direccion": str(attr.get("calle") or attr.get("sector_barrio") or ""),
            "coordenadas": {
                "lat": Decimal(str(lat)) if lat is not None else Decimal("0.0"),
                "lng": Decimal(str(lng)) if lng is not None else Decimal("0.0"),
            }
        },
        "GSI_UbicacionPK": f"PROVINCIA#{provincia.upper()}",
        "GSI_UbicacionSK": f"DISTRITO#{distrito.upper()}#{ts_iso}",
    }

    # Si hay cédula normalizada, indexar en GSI_Cedula
    if norm_cedula:
        item["cedula_normalizada"] = norm_cedula
        item["GSI_CedulaPK"] = f"CEDULA#{norm_cedula}"
        item["GSI_CedulaSK"] = f"SINAPROC#{ts_iso}"

    return item


def fetch_sinaproc_features(
    feature_server_url: str = DEFAULT_FEATURE_SERVER_URL,
    last_edited_ms: int = 0,
    max_records: int = 500,
    timeout: int = 15,
) -> List[Dict[str, Any]]:
    """
    Descarga registros del FeatureServer de ArcGIS vía REST API filtrando por last_edited_date.
    """
    where_clause = f"last_edited_date >= {last_edited_ms}" if last_edited_ms > 0 else "1=1"
    params = {
        "where": where_clause,
        "outFields": "*",
        "f": "json",
        "resultRecordCount": str(max_records),
        "orderByFields": "last_edited_date ASC",
    }

    url = f"{feature_server_url}/query?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "AyudaPanama-Sync/1.1"})

    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
            features = payload.get("features", [])
            return [f.get("attributes", {}) for f in features if "attributes" in f]
    except Exception as e:
        logger.exception("Error consultando FeatureServer de SINAPROC: %s", str(e))
        return []
