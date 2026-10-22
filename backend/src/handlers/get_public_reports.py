"""
Lambda Handler: lse-get-public-reports
Entrega las evaluaciones ciudadanas y los reportes oficiales de SINAPROC en formato
GeoJSON público unificado con semáforo de habitabilidad (ATC-20).
Filtra y anonimiza el 100% de la información personal identificable (PII) según la Ley 81.
"""

import json
import logging
import os
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


def build_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/geo+json",
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

        # 1. Escaneo de reportes ciudadanos de la App
        if since_filter:
            from boto3.dynamodb.conditions import Attr
            response_app = reports_table.scan(
                FilterExpression=Attr("timestamp").gt(since_filter),
                Limit=300,
            )
        else:
            response_app = reports_table.scan(Limit=300)

        app_items = response_app.get("Items", [])

        # 2. Escaneo de reportes oficiales de SINAPROC
        ext_items = []
        try:
            # En la vista pública unificada, asegurar la disponibilidad de los registros oficiales de SINAPROC
            response_ext = external_table.scan(Limit=500)
            ext_items = response_ext.get("Items", [])
        except Exception as ext_err:
            logger.warning("Error leyendo ExternalReportsTable: %s", str(ext_err))

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

        geojson = PublicMapAdapter.to_feature_collection(assessments=assessments, external_items=ext_items)
        return build_response(200, geojson)

    except Exception as e:
        logger.exception("Error recuperando reportes públicos: %s", str(e))
        return build_response(500, {"type": "FeatureCollection", "features": [], "error": str(e)})
