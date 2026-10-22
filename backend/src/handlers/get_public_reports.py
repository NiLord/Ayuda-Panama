"""
Lambda Handler: lse-get-public-reports
Entrega las evaluaciones ciudadanas y los reportes oficiales de SINAPROC en formato
GeoJSON público unificado con semáforo de habitabilidad (ATC-20).
Filtra y anonimiza el 100% de la información personal identificable (PII) según la Ley 81.
"""

import base64
import json
import logging
import os
from typing import Optional, Dict, Any
import boto3

from ..models.disaster_assessment import (
    DisasterAssessment,
    Informante,
    TitularAfectado,
    Ubicacion,
    Coordenadas,
    EvaluacionEstructural,
    ServiciosVitales,
    CensoDemografico,
    NecesidadesHumanitarias,
    AuditoriaDeviceKYC,
    RolInformante,
    NivelHabitabilidad,
    TipoInmueble,
    SistemaConstructivo,
    PrioridadTriage,
)
from ..adapters.public_map_adapter import PublicMapAdapter

logger = logging.getLogger(__name__)

REPORTS_TABLE_NAME = os.environ.get("REPORTS_TABLE_NAME", "lse-reports-table")
EXTERNAL_REPORTS_TABLE_NAME = os.environ.get("EXTERNAL_REPORTS_TABLE_NAME", "lse-external-reports-table")

dynamodb = boto3.resource("dynamodb")
reports_table = dynamodb.Table(REPORTS_TABLE_NAME)
external_table = dynamodb.Table(EXTERNAL_REPORTS_TABLE_NAME)


def encode_token(key_dict: Optional[dict]) -> Optional[str]:
    if not key_dict:
        return None
    try:
        raw_json = json.dumps(key_dict)
        return base64.urlsafe_b64encode(raw_json.encode("utf-8")).decode("utf-8")
    except Exception:
        return None


def decode_token(token_str: Optional[str]) -> Optional[dict]:
    if not token_str:
        return None
    try:
        raw_json = base64.urlsafe_b64decode(token_str.encode("utf-8")).decode("utf-8")
        return json.loads(raw_json)
    except Exception:
        return None


def build_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/geo+json; charset=utf-8",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,X-Api-Key,X-App-Secret,Authorization",
            "Access-Control-Allow-Methods": "GET,OPTIONS",
            "Cache-Control": "public, max-age=60",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def lambda_handler(event: dict, context) -> dict:
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return build_response(200, {"message": "OK"})

    try:
        query_params = event.get("queryStringParameters") or {}
        since_filter = query_params.get("since")
        limit_param = query_params.get("limit")
        page_size = min(max(int(limit_param), 1), 100) if limit_param and limit_param.isdigit() else 20
        next_token_in = query_params.get("next_token")
        exclusive_start_key = decode_token(next_token_in)

        # 1. Total real acumulado de reportes en la plataforma consultado dinámicamente
        total_sinaproc = 0
        try:
            st = external_table.get_item(Key={"PK": "CONFIG#SYNC_STATE", "SK": "SINAPROC"})
            if isinstance(st, dict):
                item_st = st.get("Item", {})
                for key in ("total_registros", "total_historico", "total_items_procesados"):
                    if key in item_st and str(item_st[key]).isdigit():
                        total_sinaproc = int(item_st[key])
                        break
        except Exception as st_err:
            logger.warning("Error leyendo total dinámico de SINAPROC: %s", str(st_err))

        total_app = 0
        try:
            count_resp = reports_table.scan(Select="COUNT")
            if isinstance(count_resp, dict):
                total_app = int(count_resp.get("Count", 0))
        except Exception as app_cnt_err:
            logger.warning("Error contando reportes en ReportsTable: %s", str(app_cnt_err))

        total_real = total_app + total_sinaproc

        app_items = []
        ext_items = []
        next_token_out = None

        if exclusive_start_key:
            # Página subsiguiente: paginar exclusivamente ExternalReportsTable
            scan_kwargs: Dict[str, Any] = {"Limit": page_size, "ExclusiveStartKey": exclusive_start_key}
            if since_filter:
                from boto3.dynamodb.conditions import Attr
                scan_kwargs["FilterExpression"] = Attr("timestamp").gt(since_filter)
            response_ext = external_table.scan(**scan_kwargs)
            raw_ext = response_ext.get("Items", [])
            ext_items = [it for it in raw_ext if not str(it.get("PK", "")).startswith("CONFIG#")]
            next_token_out = encode_token(response_ext.get("LastEvaluatedKey"))
        else:
            # Primera página: obtener reportes ciudadanos primero y completar hasta page_size con SINAPROC
            app_scan_kwargs: Dict[str, Any] = {"Limit": page_size}
            if since_filter:
                from boto3.dynamodb.conditions import Attr
                app_scan_kwargs["FilterExpression"] = Attr("timestamp").gt(since_filter)
            response_app = reports_table.scan(**app_scan_kwargs)
            app_items = response_app.get("Items", [])

            slots_left = page_size - len(app_items)
            if slots_left > 0:
                ext_scan_kwargs: Dict[str, Any] = {"Limit": slots_left}
                if since_filter:
                    from boto3.dynamodb.conditions import Attr
                    ext_scan_kwargs["FilterExpression"] = Attr("timestamp").gt(since_filter)
                response_ext = external_table.scan(**ext_scan_kwargs)
                raw_ext = response_ext.get("Items", [])
                ext_items = [it for it in raw_ext if not str(it.get("PK", "")).startswith("CONFIG#")]
                next_token_out = encode_token(response_ext.get("LastEvaluatedKey"))

        assessments = []
        for item in app_items:
            try:
                coords = item.get("ubicacion", {}).get("coordenadas", {})
                cen_data = item.get("censo_demografico", {})
                est_data = item.get("evaluacion_estructural", {})
                ser_data = item.get("servicios_vitales", {})
                nec_data = item.get("necesidades_humanitarias", {})
                inf_data = item.get("informante", {})
                tit_data = item.get("titular_afectado", {})
                metadatos_evento = item.get("metadatos_evento", {})
                sistemas = item.get("sistemas_vinculados") or metadatos_evento.get("sistemas_vinculados") or ["APP"]
                metadatos_evento["sistemas_vinculados"] = sistemas

                raw_fotos = item.get("fotos_urls", [])
                public_fotos = [
                    f for f in raw_fotos
                    if isinstance(f, str) and "identificacion" not in f.lower()
                ]

                assessment = DisasterAssessment(
                    report_id=item.get("report_id", ""),
                    timestamp=item.get("timestamp", ""),
                    prioridad=PrioridadTriage(item.get("prioridad", PrioridadTriage.P3_MONITOREO_ENSERES.value)),
                    consentimiento_informado=item.get("consentimiento_informado", True),
                    informante=Informante(
                        reporter_id=inf_data.get("reporter_id", ""),
                        rol=RolInformante(inf_data.get("rol", RolInformante.AFECTADO_DIRECTO.value)),
                    ),
                    titular_afectado=TitularAfectado(
                        nombre_jefe_hogar=tit_data.get("nombre_jefe_hogar"),
                        documento_numero=tit_data.get("documento_numero"),
                    ),
                    metadatos_evento=metadatos_evento,
                    ubicacion=Ubicacion(
                        coordenadas=Coordenadas(
                            lat=float(coords.get("lat", 7.625)),
                            lng=float(coords.get("lng", -80.354)),
                        ),
                        provincia=item.get("ubicacion", {}).get("provincia", "Los Santos"),
                        distrito=item.get("ubicacion", {}).get("distrito", "Las Tablas"),
                        corregimiento=item.get("ubicacion", {}).get("corregimiento", ""),
                        comunidad_sector=item.get("ubicacion", {}).get("comunidad_sector", ""),
                        calle_o_direccion="",
                        accesibilidad_vial=item.get("ubicacion", {}).get("accesibilidad_vial", "TRANSITABLE"),
                    ),
                    evaluacion_estructural=EvaluacionEstructural(
                        tipo_inmueble=TipoInmueble(est_data.get("tipo_inmueble", TipoInmueble.RESIDENCIAL_CASA.value)),
                        sistema_constructivo=SistemaConstructivo(est_data.get("sistema_constructivo", SistemaConstructivo.MAMPOSTERIA_BLOQUE.value)),
                        habitabilidad=NivelHabitabilidad(est_data.get("habitabilidad", NivelHabitabilidad.HABITABLE.value)),
                        riesgo_colapso_inminente=est_data.get("riesgo_colapso_inminente", False),
                    ),
                    servicios_vitales=ServiciosVitales(
                        agua_potable=ser_data.get("agua_potable", "NORMAL"),
                        electricidad=ser_data.get("electricidad", "NORMAL"),
                        fuga_gas=ser_data.get("fuga_gas", False),
                    ),
                    censo_demografico=CensoDemografico(
                        total_ocupantes=int(cen_data.get("total_ocupantes", 1)),
                    ),
                    necesidades_humanitarias=NecesidadesHumanitarias(
                        requiere_albergue_inmediato=nec_data.get("requiere_albergue_inmediato", False),
                        requiere_agua_alimentos=nec_data.get("requiere_agua_alimentos", False),
                        requiere_rescate_medico=nec_data.get("requiere_rescate_medico", False),
                    ),
                    auditoria_kyc=AuditoriaDeviceKYC(installation_id=""),
                    fotos_urls=public_fotos,
                )
                assessments.append(assessment)
            except Exception as parse_err:
                logger.warning("Error procesando item: %s", str(parse_err))
                continue

        geojson = PublicMapAdapter.to_feature_collection(
            assessments=assessments,
            external_items=ext_items,
            total_count=total_real,
            next_token=next_token_out,
        )
        return build_response(200, geojson)

    except Exception as e:
        logger.exception("Error recuperando reportes públicos: %s", str(e))
        return build_response(500, {"type": "FeatureCollection", "features": [], "error": str(e)})
