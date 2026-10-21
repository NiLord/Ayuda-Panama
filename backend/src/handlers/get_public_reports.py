"""
Lambda Handler: lse-get-public-reports
Entrega las evaluaciones en formato GeoJSON público con semáforo de habitabilidad (ATC-20).
Filtra y anonimiza el 100% de la información personal identificable (PII) según la Ley 81.
"""

import json
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

REPORTS_TABLE_NAME = os.environ.get("REPORTS_TABLE_NAME", "lse-reports-table")
dynamodb = boto3.resource("dynamodb")
reports_table = dynamodb.Table(REPORTS_TABLE_NAME)


def build_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/geo+json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "GET,OPTIONS",
            "Cache-Control": "public, max-age=60",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def lambda_handler(event: dict, context) -> dict:
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return build_response(200, {"message": "OK"})

    try:
        # Escaneo paginado de reportes recientes (en producción acotado por GSI de provincia)
        response = reports_table.scan(Limit=500)
        items = response.get("Items", [])

        assessments = []
        for item in items:
            try:
                coords = item.get("ubicacion", {}).get("coordenadas", {})
                cen_data = item.get("censo_demografico", {})
                est_data = item.get("evaluacion_estructural", {})
                ser_data = item.get("servicios_vitales", {})
                nec_data = item.get("necesidades_humanitarias", {})

                assessment = DisasterAssessment(
                    report_id=item.get("report_id", ""),
                    timestamp=item.get("timestamp", ""),
                    prioridad=PrioridadTriage(item.get("prioridad", PrioridadTriage.P3_MONITOREO_ENSERES.value)),
                    consentimiento_informado=item.get("consentimiento_informado", True),
                    informante=Informante(reporter_id="", rol=RolInformante.AFECTADO_DIRECTO),
                    titular_afectado=TitularAfectado(),
                    ubicacion=Ubicacion(
                        coordenadas=Coordenadas(
                            lat=float(coords.get("lat", 7.625)),
                            lng=float(coords.get("lng", -80.354)),
                        ),
                        provincia=item.get("ubicacion", {}).get("provincia", "Los Santos"),
                        distrito=item.get("ubicacion", {}).get("distrito", "Las Tablas"),
                        corregimiento=item.get("ubicacion", {}).get("corregimiento", ""),
                        comunidad_sector=item.get("ubicacion", {}).get("comunidad_sector", ""),
                        calle_o_direccion="", # Oculto en vista pública para proteger privacidad
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
                )
                assessments.append(assessment)
            except Exception as parse_err:
                print(f"Error procesando item: {parse_err}")
                continue

        geojson = PublicMapAdapter.to_feature_collection(assessments)
        return build_response(200, geojson)

    except Exception as e:
        print(f"Error recuperando reportes públicos: {e}")
        return build_response(500, {"type": "FeatureCollection", "features": [], "error": str(e)})
