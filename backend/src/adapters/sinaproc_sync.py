"""
SINAPROC ArcGIS FeatureServer Synchronizer
Transforma y sincroniza registros de evaluación de daños (EDAN) desde el FeatureServer
oficial de SINAPROC hacia la tabla de registros externos (ExternalReportsTable) en DynamoDB.
Soporta:
1. Carga inicial completa paralela por lotes (ThreadPoolExecutor).
2. Sincronización delta incremental por fecha de última modificación (last_edited_date).
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone, timedelta
from decimal import Decimal
import json
import logging
import os
import ssl
import urllib.parse
import urllib.request

_SSL_CONTEXT = ssl.create_default_context()
_SSL_CONTEXT.check_hostname = False
_SSL_CONTEXT.verify_mode = ssl.CERT_NONE
import boto3
from typing import Dict, Any, List, Optional, Callable

from ..utils.cedula_normalizer import normalize_cedula, mask_cedula, mask_person_name
from ..utils.geo_normalizer import (
    PROVINCIAS_HOMOLOGADOS,
    DISTRITOS_HOMOLOGADOS,
    homologar_provincia,
    homologar_distrito,
    format_clean_name,
)

logger = logging.getLogger(__name__)

DEFAULT_FEATURE_SERVER_URL = (
    "https://sig.sinaproc.gob.pa/server/rest/services/Hosted/"
    "survey123_935c7e293909453b82f37e9a151aaf19_results/FeatureServer/0"
)

# Mapeo de severidad en SINAPROC a norma canónica ATC-20
# Regla: Habitable es Leve o Moderado; Restringido es Daño Parcial; Pérdida Total es Inhabitable.
# Colapso sólo es posible desde reportes del app (no existe en AEGIS).
HABITABILIDAD_MAP = {
    "total": "INHABITABLE",
    "inhabitable": "INHABITABLE",
    "severo": "INHABITABLE",
    "parcial": "ACCESO_RESTRINGIDO",
    "moderado": "HABITABLE",
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

    t_afect = str(attr.get("t_afectacion") or "").strip().lower()
    raw_dano = t_afect or attr.get("d_infrestuctura") or attr.get("descripcion_dano")
    if str(attr.get("d_infrestuctura") or "").strip().lower() == "no":
        atc20_habitabilidad = "HABITABLE"
    elif t_afect:
        atc20_habitabilidad = map_sinaproc_damage_to_atc20(t_afect)
    else:
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
        "t_afectacion": t_afect,
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


# ==============================================================================
# CÁLCULO Y AGREGACIÓN DEL DASHBOARD NACIONAL (COEN Y SEVERIDAD HABITACIONAL)
# ==============================================================================

def query_arcgis_statistics(
    feature_server_url: str = DEFAULT_FEATURE_SERVER_URL,
    stats: Optional[List[Dict[str, str]]] = None,
    group_by: Optional[str] = None,
    where: str = "1=1",
    paginate: bool = False,
    timeout: int = 25,
) -> List[Dict[str, Any]]:
    """Consulta outStatistics en ArcGIS FeatureServer reutilizando la conexión segura."""
    if not stats:
        return []

    all_attributes: List[Dict[str, Any]] = []
    offset = 0
    page_size = 1000

    while True:
        params: Dict[str, Any] = {
            "where": where,
            "outStatistics": json.dumps(stats),
            "f": "json",
        }
        if group_by:
            params["groupByFieldsForStatistics"] = group_by
        if paginate:
            params["resultOffset"] = offset
            params["resultRecordCount"] = page_size

        url = f"{feature_server_url}/query"
        post_data = urllib.parse.urlencode(params).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=post_data,
            headers={"User-Agent": "AyudaPanama-Sync/1.1"},
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=_SSL_CONTEXT) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                features = data.get("features", [])
                for f in features:
                    if "attributes" in f:
                        all_attributes.append(f["attributes"])

                exceeded = data.get("exceededTransferLimit", False)
                if not paginate or not exceeded or len(features) < page_size:
                    break
                offset += len(features)
        except Exception as e:
            logger.exception("Error consultando outStatistics en ArcGIS: %s", str(e))
            break

    return all_attributes


def calculate_national_dashboard_stats(
    feature_server_url: str = DEFAULT_FEATURE_SERVER_URL,
    reports_table_name: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Calcula de manera agregada las métricas oficiales del Censo COEN y Severidad Habitacional.
    Reutiliza endpoints estadísticos nativos de ArcGIS y consolida reportes ciudadanos de la App.
    """
    # Filtro oficial del evento de emergencia (activo desde el 9 de octubre de 2026 en el portal COEN/SINAPROC)
    event_start = os.environ.get("SINAPROC_EVENT_START_DATE", "2026-10-09 00:00:00")
    where_clause = f"f_h_registro >= timestamp '{event_start}'" if event_start else "1=1"

    # 1. Totales demográficos y grupos etarios nacionales desde SINAPROC
    stats_poblacion = [
        {"statisticType": "count", "onStatisticField": "objectid", "outStatisticFieldName": "total_familias"},
        {"statisticType": "sum", "onStatisticField": "t_miembros", "outStatisticFieldName": "total_personas"},
        {"statisticType": "sum", "onStatisticField": "c_discapacitados", "outStatisticFieldName": "total_discapacidad"},
        {"statisticType": "sum", "onStatisticField": "c_embarazadas", "outStatisticFieldName": "total_embarazadas"},
        {"statisticType": "sum", "onStatisticField": "t_neonatos", "outStatisticFieldName": "total_neonatos"},
        {"statisticType": "sum", "onStatisticField": "t_ninos", "outStatisticFieldName": "total_ninos"},
        {"statisticType": "sum", "onStatisticField": "t_adolescentes", "outStatisticFieldName": "total_adolescentes"},
        {"statisticType": "sum", "onStatisticField": "t_adultos", "outStatisticFieldName": "total_adultos"},
        {"statisticType": "sum", "onStatisticField": "t_a_mayores", "outStatisticFieldName": "total_a_mayores"},
        {"statisticType": "sum", "onStatisticField": "m_neonato", "outStatisticFieldName": "m_neonato"},
        {"statisticType": "sum", "onStatisticField": "m_ninos", "outStatisticFieldName": "m_ninos"},
        {"statisticType": "sum", "onStatisticField": "m_adolescentes", "outStatisticFieldName": "m_adolescentes"},
        {"statisticType": "sum", "onStatisticField": "m_adultos", "outStatisticFieldName": "m_adultos"},
        {"statisticType": "sum", "onStatisticField": "m_a_mayores", "outStatisticFieldName": "m_a_mayores"},
        {"statisticType": "sum", "onStatisticField": "f_neonato", "outStatisticFieldName": "f_neonato"},
        {"statisticType": "sum", "onStatisticField": "f_ninos", "outStatisticFieldName": "f_ninos"},
        {"statisticType": "sum", "onStatisticField": "f_adolescentes", "outStatisticFieldName": "f_adolescentes"},
        {"statisticType": "sum", "onStatisticField": "f_adultos", "outStatisticFieldName": "f_adultos"},
        {"statisticType": "sum", "onStatisticField": "f_a_mayores", "outStatisticFieldName": "f_a_mayores"},
    ]
    res_pob = query_arcgis_statistics(feature_server_url, stats_poblacion, where=where_clause)
    pob_attrs = res_pob[0] if res_pob else {}

    total_familias = int(pob_attrs.get("total_familias") or 0)
    total_personas = int(pob_attrs.get("total_personas") or 0)
    total_discapacidad = int(pob_attrs.get("total_discapacidad") or 0)
    total_embarazadas = int(pob_attrs.get("total_embarazadas") or 0)
    total_neonatos = int(pob_attrs.get("total_neonatos") or 0)
    total_ninos = int(pob_attrs.get("total_ninos") or 0)
    total_adolescentes = int(pob_attrs.get("total_adolescentes") or 0)
    total_adultos = int(pob_attrs.get("total_adultos") or 0)
    total_a_mayores = int(pob_attrs.get("total_a_mayores") or 0)

    total_masculino = (
        int(pob_attrs.get("m_neonato") or 0)
        + int(pob_attrs.get("m_ninos") or 0)
        + int(pob_attrs.get("m_adolescentes") or 0)
        + int(pob_attrs.get("m_adultos") or 0)
        + int(pob_attrs.get("m_a_mayores") or 0)
    )
    total_femenino = (
        int(pob_attrs.get("f_neonato") or 0)
        + int(pob_attrs.get("f_ninos") or 0)
        + int(pob_attrs.get("f_adolescentes") or 0)
        + int(pob_attrs.get("f_adultos") or 0)
        + int(pob_attrs.get("f_a_mayores") or 0)
    )

    # 2. Desglose demográfico agrupado por provincia
    res_prov_demo = query_arcgis_statistics(
        feature_server_url, stats_poblacion, group_by="provincia", where=where_clause
    )
    prov_demo_map: Dict[str, Dict[str, Any]] = {}
    for item in res_prov_demo:
        raw_p = (item.get("provincia") or "otra").strip().lower()
        can_p = homologar_provincia(raw_p)
        prov_demo_map[can_p] = item

    # 3. Situaciones oficiales de emergencia (colapsos de estructura, inundaciones, etc.)
    stats_situaciones = [
        {"statisticType": "count", "onStatisticField": "objectid", "outStatisticFieldName": "total"}
    ]
    res_situaciones = query_arcgis_statistics(
        feature_server_url, stats_situaciones, group_by="provincia, situacion", where=where_clause
    )
    from collections import defaultdict
    prov_situaciones_map: Dict[str, Dict[str, int]] = defaultdict(dict)
    sinaproc_colapsos = 0
    sinaproc_inundaciones = 0

    for item in res_situaciones:
        raw_p = (item.get("provincia") or "otra").strip().lower()
        can_p = homologar_provincia(raw_p)
        sit = (item.get("situacion") or "").strip().lower()
        cnt = int(item.get("total") or 0)
        prov_situaciones_map[can_p][sit] = cnt
        if sit == "colapso":
            sinaproc_colapsos += cnt
        elif sit == "inundacion":
            sinaproc_inundaciones += cnt

    # 4. Severidad habitacional nacional desde SINAPROC (t_afectacion)
    stats_severidad = [
        {"statisticType": "count", "onStatisticField": "objectid", "outStatisticFieldName": "total"},
    ]
    res_sev = query_arcgis_statistics(
        feature_server_url, stats_severidad, group_by="t_afectacion", where=where_clause
    )

    sinaproc_perdida_total = 0
    sinaproc_dano_parcial = 0
    sinaproc_moderado = 0
    sinaproc_leve_menor = 0

    for item in res_sev:
        t_afect = (item.get("t_afectacion") or "").strip().lower()
        cnt = int(item.get("total") or 0)
        if t_afect == "total":
            sinaproc_perdida_total += cnt
        elif t_afect == "parcial":
            sinaproc_dano_parcial += cnt
        elif t_afect == "moderado":
            sinaproc_moderado += cnt
        else:
            sinaproc_leve_menor += cnt

    # 4. Distribución jerárquica por provincia, distrito, corregimiento y severidad desde SINAPROC
    stats_jerarquicos = [
        {"statisticType": "count", "onStatisticField": "objectid", "outStatisticFieldName": "total"},
        {"statisticType": "sum", "onStatisticField": "t_miembros", "outStatisticFieldName": "total_personas"},
    ]
    res_jerarquico = query_arcgis_statistics(
        feature_server_url,
        stats_jerarquicos,
        group_by="provincia, distrito, corregimiento, t_afectacion",
        where=where_clause,
        paginate=True,
    )

    from collections import defaultdict
    tree: Dict[str, Any] = defaultdict(lambda: defaultdict(lambda: defaultdict(lambda: {
        "total": 0, "personas": 0, "pt": 0, "dp": 0, "mod": 0, "lm": 0
    })))

    for r in res_jerarquico:
        raw_p = (r.get("provincia") or "otra").strip().lower()
        raw_d = (r.get("distrito") or "otro").strip().lower()
        raw_c = (r.get("corregimiento") or "otro").strip().lower()
        t_afect = (r.get("t_afectacion") or "").strip().lower()
        cnt = int(r.get("total") or 0)
        per = int(r.get("total_personas") or 0)

        node = tree[raw_p][raw_d][raw_c]
        node["total"] += cnt
        node["personas"] += per
        if t_afect == "total":
            node["pt"] += cnt
        elif t_afect == "parcial":
            node["dp"] += cnt
        elif t_afect == "moderado":
            node["mod"] += cnt
        else:
            node["lm"] += cnt

    prov_map: Dict[str, Dict[str, Any]] = {}

    for raw_p, dists in tree.items():
        canonical_p = homologar_provincia(raw_p)
        if canonical_p not in prov_map:
            prov_map[canonical_p] = {
                "provincia": canonical_p,
                "perdida_total": 0,
                "dano_parcial": 0,
                "moderado": 0,
                "leve_menor": 0,
                "total": 0,
                "distritos": [],
                "distritos_mas_afectados": [],
                "ranking_corregimientos": [],
            }

        p_entry = prov_map[canonical_p]
        dist_list = []
        all_p_corregs = []

        for raw_d, corregs in dists.items():
            canonical_d = homologar_distrito(raw_d)
            d_pt = sum(c["pt"] for c in corregs.values())
            d_dp = sum(c["dp"] for c in corregs.values())
            d_mod = sum(c["mod"] for c in corregs.values())
            d_lm = sum(c["lm"] for c in corregs.values())
            d_viv = sum(c["total"] for c in corregs.values())
            d_per = sum(c["personas"] for c in corregs.values())

            correg_list = []
            for raw_c, c_data in corregs.items():
                c_clean = format_clean_name(raw_c.strip("_"))
                c_item = {
                    "nombre": c_clean,
                    "distrito": canonical_d,
                    "perdida_total": c_data["pt"],
                    "dano_parcial": c_data["dp"],
                    "moderado": c_data["mod"],
                    "leve_menor": c_data["lm"],
                    "total_viviendas": c_data["total"],
                    "total_personas": c_data["personas"],
                }
                correg_list.append(c_item)
                all_p_corregs.append(c_item)

            correg_list.sort(key=lambda x: (x["perdida_total"], x["total_viviendas"]), reverse=True)

            d_item = {
                "nombre": canonical_d,
                "slug": raw_d,
                "perdida_total": d_pt,
                "dano_parcial": d_dp,
                "moderado": d_mod,
                "leve_menor": d_lm,
                "total_viviendas": d_viv,
                "total_personas": d_per,
                "total_corregimientos": len(correg_list),
                "corregimientos": correg_list,
            }
            dist_list.append(d_item)

            p_entry["perdida_total"] += d_pt
            p_entry["dano_parcial"] += d_dp
            p_entry["moderado"] += d_mod
            p_entry["leve_menor"] += d_lm
            p_entry["total"] += d_viv

        dist_list.sort(key=lambda x: (x["perdida_total"], x["total_viviendas"]), reverse=True)
        all_p_corregs.sort(key=lambda x: (x["perdida_total"], x["total_viviendas"]), reverse=True)

        p_entry["distritos"] = dist_list
        p_entry["ranking_corregimientos"] = all_p_corregs
        p_entry["distritos_mas_afectados"] = [
            {"distrito": d["nombre"], "total_familias": d["total_viviendas"], "total_personas": d["total_personas"]}
            for d in dist_list[:10]
        ]

        # Enriquecer cada provincia con métricas demográficas y de situación oficiales
        p_demo = prov_demo_map.get(canonical_p, {})
        p_sits = prov_situaciones_map.get(canonical_p, {})

        p_familias = int(p_demo.get("total_familias") or p_entry["total"])
        p_personas = int(p_demo.get("total_personas") or 0)
        p_discapacidad = int(p_demo.get("total_discapacidad") or 0)
        p_embarazadas = int(p_demo.get("total_embarazadas") or 0)

        p_colapsos = p_sits.get("colapso", 0)
        p_inundaciones = p_sits.get("inundacion", 0)

        p_masc = (
            int(p_demo.get("m_neonato") or 0)
            + int(p_demo.get("m_ninos") or 0)
            + int(p_demo.get("m_adolescentes") or 0)
            + int(p_demo.get("m_adultos") or 0)
            + int(p_demo.get("m_a_mayores") or 0)
        )
        p_fem = (
            int(p_demo.get("f_neonato") or 0)
            + int(p_demo.get("f_ninos") or 0)
            + int(p_demo.get("f_adolescentes") or 0)
            + int(p_demo.get("f_adultos") or 0)
            + int(p_demo.get("f_a_mayores") or 0)
        )
        p_sum_gen = p_masc + p_fem
        p_pct_masc = round((p_masc / p_sum_gen * 100.0), 1) if p_sum_gen > 0 else 50.0
        p_pct_fem = round((p_fem / p_sum_gen * 100.0), 1) if p_sum_gen > 0 else 50.0

        p_neo = int(p_demo.get("total_neonatos") or 0)
        p_nin = int(p_demo.get("total_ninos") or 0)
        p_ado = int(p_demo.get("total_adolescentes") or 0)
        p_adu = int(p_demo.get("total_adultos") or 0)
        p_may = int(p_demo.get("total_a_mayores") or 0)
        p_base_edad = (p_neo + p_nin + p_ado + p_adu + p_may) or 1

        p_grupos = [
            {"id": "neonatos", "emoji": "👶", "label": "Neonatos (0-1)", "count": p_neo, "porcentaje": round((p_neo / p_base_edad * 100.0), 1), "color": "#38BDF8"},
            {"id": "ninos", "emoji": "🧒", "label": "Niños (1-12)", "count": p_nin, "porcentaje": round((p_nin / p_base_edad * 100.0), 1), "color": "#6366F1"},
            {"id": "adolescentes", "emoji": "🧑", "label": "Adolescentes (13-17)", "count": p_ado, "porcentaje": round((p_ado / p_base_edad * 100.0), 1), "color": "#A855F7"},
            {"id": "adultos", "emoji": "👨👩", "label": "Adultos (18-59)", "count": p_adu, "porcentaje": round((p_adu / p_base_edad * 100.0), 1), "color": "#F59E0B"},
            {"id": "adultos_mayores", "emoji": "🧓", "label": "Adultos Mayores (60+)", "count": p_may, "porcentaje": round((p_may / p_base_edad * 100.0), 1), "color": "#10B981"},
        ]

        p_entry["total_familias"] = p_familias
        p_entry["total_personas"] = p_personas
        p_entry["con_discapacidad"] = p_discapacidad
        p_entry["embarazadas"] = p_embarazadas
        p_entry["colapsos_estructurales"] = p_colapsos
        p_entry["inundaciones"] = p_inundaciones
        p_entry["genero"] = {
            "masculino": {"total": p_masc, "porcentaje": p_pct_masc},
            "femenino": {"total": p_fem, "porcentaje": p_pct_fem},
        }
        p_entry["grupos_etarios"] = p_grupos

    # 5. Integración con reportes ciudadanos directos de la App (DynamoDB ReportsTable)
    app_colapsos = 0
    app_inhabitables = 0
    app_restringidos = 0
    app_habitables = 0
    app_total_reportes = 0

    if reports_table_name:
        try:
            dynamodb = boto3.resource("dynamodb")
            app_table = dynamodb.Table(reports_table_name)
            scan_resp = app_table.scan(
                ProjectionExpression="evaluacion_habitabilidad, ubicacion_provincia, total_afectados",
                Limit=1000,
            )
            for app_item in scan_resp.get("Items", []):
                app_total_reportes += 1
                hab = str(app_item.get("evaluacion_habitabilidad") or "").upper()
                if hab == "COLAPSO_TOTAL":
                    app_colapsos += 1
                elif hab == "INHABITABLE":
                    app_inhabitables += 1
                elif hab == "ACCESO_RESTRINGIDO":
                    app_restringidos += 1
                elif hab == "HABITABLE":
                    app_habitables += 1

                p_app = str(app_item.get("ubicacion_provincia") or "").strip().lower()
                if p_app:
                    can_p = PROVINCIAS_HOMOLOGADOS.get(p_app, p_app.replace("_", " ").title())
                    if can_p in prov_map:
                        prov_map[can_p]["total"] += 1
                        if hab in ["COLAPSO_TOTAL", "INHABITABLE"]:
                            prov_map[can_p]["perdida_total"] += 1
                        elif hab == "ACCESO_RESTRINGIDO":
                            prov_map[can_p]["dano_parcial"] += 1
                        else:
                            prov_map[can_p]["leve_menor"] += 1
        except Exception as app_err:
            logger.warning("No se pudo leer tabla de reportes de app: %s", str(app_err))

    # Consolidar totales
    total_familias_final = total_familias + app_total_reportes
    total_personas_final = total_personas if total_personas > 0 else (total_familias_final * 3)

    suma_genero = total_masculino + total_femenino
    pct_masc = round((total_masculino / suma_genero * 100.0), 1) if suma_genero > 0 else 50.0
    pct_fem = round((total_femenino / suma_genero * 100.0), 1) if suma_genero > 0 else 50.0

    suma_edades = total_neonatos + total_ninos + total_adolescentes + total_adultos + total_a_mayores
    base_edad = suma_edades if suma_edades > 0 else 1

    grupos_etarios = [
        {
            "id": "neonatos",
            "emoji": "👶",
            "label": "Neonatos (0-1)",
            "count": total_neonatos,
            "porcentaje": round((total_neonatos / base_edad * 100.0), 1),
            "color": "#38BDF8",
        },
        {
            "id": "ninos",
            "emoji": "🧒",
            "label": "Niños (1-12)",
            "count": total_ninos,
            "porcentaje": round((total_ninos / base_edad * 100.0), 1),
            "color": "#6366F1",
        },
        {
            "id": "adolescentes",
            "emoji": "🧑",
            "label": "Adolescentes (13-17)",
            "count": total_adolescentes,
            "porcentaje": round((total_adolescentes / base_edad * 100.0), 1),
            "color": "#A855F7",
        },
        {
            "id": "adultos",
            "emoji": "👨👩",
            "label": "Adultos (18-59)",
            "count": total_adultos,
            "porcentaje": round((total_adultos / base_edad * 100.0), 1),
            "color": "#F59E0B",
        },
        {
            "id": "adultos_mayores",
            "emoji": "🧓",
            "label": "Adultos Mayores (60+)",
            "count": total_a_mayores,
            "porcentaje": round((total_a_mayores / base_edad * 100.0), 1),
            "color": "#10B981",
        },
    ]

    lista_provincias = sorted(prov_map.values(), key=lambda x: x["total"], reverse=True)

    ahora_utc = datetime.now(timezone.utc)
    panama_tz = timezone(timedelta(hours=-5))
    ahora_panama = ahora_utc.astimezone(panama_tz)
    meses_es = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
    mes_str = meses_es[ahora_panama.month - 1]
    hora_str = ahora_panama.strftime("%I:%M %p").lstrip("0")
    texto_actualizacion = f"{ahora_panama.day} de {mes_str} de {ahora_panama.year}, {hora_str} (GMT-5)"

    poblacion_data = {
        "familias_afectadas": total_familias_final,
        "personas_afectadas": total_personas_final,
        "con_discapacidad": total_discapacidad,
        "embarazadas": total_embarazadas,
        "colapsos_estructurales": sinaproc_colapsos + app_colapsos,
        "inundaciones": sinaproc_inundaciones,
        "genero": {
            "masculino": {
                "total": total_masculino,
                "porcentaje": pct_masc,
            },
            "femenino": {
                "total": total_femenino,
                "porcentaje": pct_fem,
            },
        },
        "grupos_etarios": grupos_etarios,
    }

    payload: Dict[str, Any] = {
        "poblacion": poblacion_data,
        "censo_coen": poblacion_data,
        "severidad_habitacional": {
            "colapsos_estructurales": sinaproc_colapsos + app_colapsos,
            "inundaciones": sinaproc_inundaciones,
            "categorias": {
                "perdida_total": {
                    "total": sinaproc_perdida_total + app_inhabitables,
                    "etiqueta": "Pérdida Total",
                    "subetiqueta": "Inhabitables",
                    "color": "#EF4444",
                },
                "dano_parcial": {
                    "total": sinaproc_dano_parcial + app_restringidos,
                    "etiqueta": "Daño Parcial",
                    "subetiqueta": "Techos / Muros",
                    "color": "#F97316",
                },
                "moderado": {
                    "total": sinaproc_moderado,
                    "etiqueta": "Moderado",
                    "subetiqueta": "Fisuras Menores",
                    "color": "#F59E0B",
                },
                "leve_menor": {
                    "total": sinaproc_leve_menor + app_habitables,
                    "etiqueta": "Leve / Menor",
                    "subetiqueta": "Habitables",
                    "color": "#10B981",
                },
            },
            "provincias": lista_provincias,
        },
        "metadatos": {
            "ultima_actualizacion_iso": ahora_utc.isoformat(),
            "ultima_actualizacion_texto": texto_actualizacion,
            "total_registros_evaluados": total_familias_final,
        },
    }
    return payload


def _convert_floats_to_decimals(obj: Any) -> Any:
    """Convierte recursivamente flotantes a Decimal para inserción en DynamoDB."""
    if isinstance(obj, float):
        return Decimal(str(round(obj, 2)))
    if isinstance(obj, dict):
        return {k: _convert_floats_to_decimals(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_convert_floats_to_decimals(item) for item in obj]
    return obj


def save_national_dashboard(
    payload: Dict[str, Any],
    external_reports_table_name: str,
) -> bool:
    """Persiste el registro consolidado del dashboard en DynamoDB bajo PK: CONFIG#HOURLY_DASHBOARD, SK: HOURLY."""
    try:
        dynamodb = boto3.resource("dynamodb")
        table = dynamodb.Table(external_reports_table_name)
        item = {
            "PK": "CONFIG#HOURLY_DASHBOARD",
            "SK": "HOURLY",
            "payload": _convert_floats_to_decimals(payload),
            "updated_at": payload["metadatos"]["ultima_actualizacion_iso"],
        }
        table.put_item(Item=item)
        logger.info("Registro horario del dashboard nacional guardado exitosamente en DynamoDB.")
        return True
    except Exception as e:
        logger.exception("Error guardando dashboard nacional en DynamoDB: %s", str(e))
        return False
