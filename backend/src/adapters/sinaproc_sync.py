"""
SINAPROC ArcGIS FeatureServer Synchronizer
Transforma y sincroniza registros de evaluación de daños (EDAN) desde el FeatureServer
oficial de SINAPROC hacia la tabla de registros externos (ExternalReportsTable) en DynamoDB.
Soporta:
1. Carga inicial completa paralela por lotes (ThreadPoolExecutor).
2. Sincronización delta incremental por fecha de última modificación (last_edited_date).
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from decimal import Decimal
import json
import logging
import ssl
import urllib.parse
import urllib.request

_SSL_CONTEXT = ssl.create_default_context()
_SSL_CONTEXT.check_hostname = False
_SSL_CONTEXT.verify_mode = ssl.CERT_NONE
from typing import Dict, Any, List, Optional, Callable

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
        try:
            return datetime.fromtimestamp(val / 1000.0, tz=timezone.utc).isoformat()
        except Exception:
            return datetime.now(timezone.utc).isoformat()
    val_str = str(val).strip()
    for fmt in ["%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M", "%d/%m/%Y", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"]:
        try:
            return datetime.strptime(val_str, fmt).replace(tzinfo=timezone.utc).isoformat()
        except ValueError:
            pass
    return datetime.now(timezone.utc).isoformat()


def parse_date_to_dt(val: Any) -> Optional[datetime]:
    """Convierte un valor de fecha a objeto datetime timezone-aware UTC."""
    if not val:
        return None
    if isinstance(val, (int, float)):
        try:
            return datetime.fromtimestamp(val / 1000.0, tz=timezone.utc)
        except Exception:
            return None
    val_str = str(val).strip()
    for fmt in ["%d/%m/%Y %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%d/%m/%Y %H:%M", "%Y-%m-%d"]:
        try:
            return datetime.strptime(val_str, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return None


def build_where_clause(since_dt: Optional[datetime] = None) -> str:
    """
    Construye la cláusula WHERE requerida por ArcGIS FeatureServer.
    Usa el formato SQL de timestamp: last_edited_date >= timestamp 'YYYY-MM-DD HH:MM:SS'.
    """
    if not since_dt:
        return "1=1"
    dt_str = since_dt.strftime("%Y-%m-%d %H:%M:%S")
    return f"last_edited_date >= timestamp '{dt_str}'"


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
    censored_cedula = mask_cedula(norm_cedula) if norm_cedula else mask_cedula(raw_cedula)

    raw_nombre = str(attr.get("nombre_jefe") or "").strip()
    censored_nombre = mask_person_name(raw_nombre)

    raw_dano = attr.get("d_infrestuctura") or attr.get("descripcion_dano")
    atc20_habitabilidad = map_sinaproc_damage_to_atc20(str(raw_dano) if raw_dano else None)

    ts_raw = attr.get("last_edited_date") or attr.get("created_date") or attr.get("f_h_registro")
    ts_iso = parse_sinaproc_timestamp(ts_raw)

    provincia = str(attr.get("provincia") or "los_santos").strip().lower()
    distrito = str(attr.get("distrito") or "general").strip().lower()
    corregimiento = str(attr.get("corregimiento") or "general").strip().lower()
    comunidad = str(attr.get("comunidad") or "").strip()

    lat = attr.get("latitud") or attr.get("y")
    lng = attr.get("longitud") or attr.get("x")

    item: Dict[str, Any] = {
        "PK": f"SINAPROC#{object_id}",
        "SK": "METADATA",
        "fuente": "SINAPROC",
        "external_id": str(object_id),
        "global_id": str(attr.get("globalid") or ""),
        "timestamp": ts_iso,
        "evaluador": str(attr.get("evaluador") or "SINAPROC"),
        "institucion": str(attr.get("institucion") or "SINAPROC"),
        "nombre_titular_censurado": censored_nombre,
        "cedula_censurada": censored_cedula,
        "habitabilidad": atc20_habitabilidad,
        "dano_descripcion": str(raw_dano or "Sin descripción"),
        "tipo_vivienda": str(attr.get("tipo_vivienda") or ""),
        "tipo_construccion": str(attr.get("tipo_construcion") or ""),
        "total_afectados": int(attr.get("t_miembros") or 0) if str(attr.get("t_miembros") or "").isdigit() else 0,
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

    if norm_cedula:
        item["cedula_normalizada"] = norm_cedula
        item["GSI_CedulaPK"] = f"CEDULA#{norm_cedula}"
        item["GSI_CedulaSK"] = f"SINAPROC#{ts_iso}"

    return item


def fetch_sinaproc_object_ids(
    feature_server_url: str = DEFAULT_FEATURE_SERVER_URL,
    where_clause: str = "1=1",
    timeout: int = 30,
) -> List[int]:
    """
    Obtiene la lista completa de ObjectIDs de SINAPROC que coincidan con la condición WHERE.
    ArcGIS retorna todos los IDs en una sola consulta rápida sin límite de paginación.
    """
    params = {
        "where": where_clause,
        "returnIdsOnly": "true",
        "f": "json",
    }
    url = f"{feature_server_url}/query?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "AyudaPanama-Sync/1.1"})

    try:
        with urllib.request.urlopen(req, timeout=timeout, context=_SSL_CONTEXT) as response:
            payload = json.loads(response.read().decode("utf-8"))
            return payload.get("objectIds") or []
    except Exception as e:
        logger.exception("Error consultando ObjectIDs de SINAPROC: %s", str(e))
        return []


def fetch_sinaproc_chunk(
    feature_server_url: str,
    object_ids_chunk: List[int],
    timeout: int = 30,
) -> List[Dict[str, Any]]:
    """
    Descarga los atributos completos de un lote de ObjectIDs usando POST.
    """
    if not object_ids_chunk:
        return []

    params = {
        "objectIds": ",".join(map(str, object_ids_chunk)),
        "outFields": "*",
        "returnGeometry": "true",
        "f": "json",
    }
    encoded_data = urllib.parse.urlencode(params).encode("utf-8")
    req = urllib.request.Request(
        f"{feature_server_url}/query",
        data=encoded_data,
        headers={"User-Agent": "AyudaPanama-Sync/1.1"},
    )

    try:
        with urllib.request.urlopen(req, timeout=timeout, context=_SSL_CONTEXT) as response:
            payload = json.loads(response.read().decode("utf-8"))
            features = payload.get("features", [])
            return [f.get("attributes", {}) for f in features if "attributes" in f]
    except Exception as e:
        logger.exception("Error descargando lote de SINAPROC (%d IDs): %s", len(object_ids_chunk), str(e))
        return []


def fetch_sinaproc_features_concurrent(
    feature_server_url: str = DEFAULT_FEATURE_SERVER_URL,
    where_clause: str = "1=1",
    chunk_size: int = 1000,
    max_workers: int = 6,
    timeout: int = 30,
    on_chunk_downloaded: Optional[Callable[[List[Dict[str, Any]]], None]] = None,
) -> List[Dict[str, Any]]:
    """
    Descarga concurrente y paralelizada de todos los registros de SINAPROC.
    Si se proporciona `on_chunk_downloaded`, cada lote se procesa inmediatamente
    (evitando acumulación excesiva de memoria).
    """
    all_ids = fetch_sinaproc_object_ids(feature_server_url, where_clause, timeout=timeout)
    total_ids = len(all_ids)
    logger.info("Total ObjectIDs encontrados en SINAPROC para '%s': %d", where_clause, total_ids)

    if total_ids == 0:
        return []

    chunks = [all_ids[i:i + chunk_size] for i in range(0, total_ids, chunk_size)]
    logger.info("Iniciando descarga en %d lotes paralelos con %d hilos", len(chunks), max_workers)

    all_downloaded = []
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_chunk = {
            executor.submit(fetch_sinaproc_chunk, feature_server_url, ch, timeout): ch
            for ch in chunks
        }
        for future in as_completed(future_to_chunk):
            try:
                features = future.result()
                if on_chunk_downloaded:
                    on_chunk_downloaded(features)
                else:
                    all_downloaded.extend(features)
            except Exception as ch_err:
                logger.error("Error en procesamiento de lote concurrente: %s", str(ch_err))

    return all_downloaded


def fetch_sinaproc_features(
    feature_server_url: str = DEFAULT_FEATURE_SERVER_URL,
    last_edited_ms: int = 0,
    max_records: int = 500,
    timeout: int = 15,
) -> List[Dict[str, Any]]:
    """
    Función de compatibilidad para consultas directas y pruebas unitarias.
    """
    since_dt = datetime.fromtimestamp(last_edited_ms / 1000.0, tz=timezone.utc) if last_edited_ms > 0 else None
    where_clause = build_where_clause(since_dt)
    return fetch_sinaproc_features_concurrent(
        feature_server_url=feature_server_url,
        where_clause=where_clause,
        max_workers=4,
        timeout=timeout,
    )
