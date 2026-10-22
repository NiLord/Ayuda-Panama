"""
Lambda Handler: lse-export-edan
Exporta los reportes recopilados al formato exacto del FeatureServer de SINAPROC
(_3_de_formulario / Survey123) para alimentar sus paneles oficiales de comando de incidentes.
Ruta protegida para cuerpos de rescate y autoridades autorizadas.
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
from ..adapters.sinaproc_adapter import SinaprocSurvey123Adapter

REPORTS_TABLE_NAME = os.environ.get("REPORTS_TABLE_NAME", "lse-reports-table")
ADMIN_SECRET_KEY = os.environ.get("ADMIN_SECRET_KEY", "")

dynamodb = boto3.resource("dynamodb")
reports_table = dynamodb.Table(REPORTS_TABLE_NAME)


def build_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Admin-Key",
            "Access-Control-Allow-Methods": "GET,OPTIONS",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def lambda_handler(event: dict, context) -> dict:
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return build_response(200, {"message": "OK"})

    # Verificación de autenticación para salvaguardar PII
    headers = event.get("headers", {})
    provided_key = headers.get("x-admin-key") or headers.get("authorization", "").replace("Bearer ", "")

    if provided_key != ADMIN_SECRET_KEY:
        return build_response(401, {
            "error": "Acceso denegado. Este endpoint con PII requiere autorización oficial de SINAPROC / COE."
        })

    try:
        response = reports_table.scan(Limit=1000)
        items = response.get("Items", [])

        esri_features = []
        for item in items:
            try:
                coords = item.get("ubicacion", {}).get("coordenadas", {})
                inf_data = item.get("informante", {})
                tit_data = item.get("titular_afectado", {})
                est_data = item.get("evaluacion_estructural", {})
                ser_data = item.get("servicios_vitales", {})
                cen_data = item.get("censo_demografico", {})
                nec_data = item.get("necesidades_humanitarias", {})

                assessment = DisasterAssessment(
                    report_id=item.get("report_id", ""),
                    timestamp=item.get("timestamp", ""),
                    prioridad=PrioridadTriage(item.get("prioridad", PrioridadTriage.P3_MONITOREO_ENSERES.value)),
                    consentimiento_informado=item.get("consentimiento_informado", True),
                    informante=Informante(
                        reporter_id=inf_data.get("reporter_id", ""),
                        rol=RolInformante(inf_data.get("rol", RolInformante.AFECTADO_DIRECTO.value)),
                        nombre_completo=inf_data.get("nombre_completo"),
                        telefono_contacto=inf_data.get("telefono_contacto"),
                        organizacion=inf_data.get("organizacion"),
                    ),
                    titular_afectado=TitularAfectado(
                        es_el_mismo_informante=tit_data.get("es_el_mismo_informante", True),
                        nombre_jefe_hogar=tit_data.get("nombre_jefe_hogar"),
                        documento_tipo=tit_data.get("documento_tipo", "CEDULA"),
                        documento_numero=tit_data.get("documento_numero"),
                        telefono_afectado=tit_data.get("telefono_afectado"),
                        estado_familia=tit_data.get("estado_familia", "EN_SITIO"),
                    ),
                    ubicacion=Ubicacion(
                        coordenadas=Coordenadas(
                            lat=float(coords.get("lat", 7.625)),
                            lng=float(coords.get("lng", -80.354)),
                        ),
                        provincia=item.get("ubicacion", {}).get("provincia", "Los Santos"),
                        distrito=item.get("ubicacion", {}).get("distrito", "Las Tablas"),
                        corregimiento=item.get("ubicacion", {}).get("corregimiento", ""),
                        comunidad_sector=item.get("ubicacion", {}).get("comunidad_sector", ""),
                        calle_o_direccion=item.get("ubicacion", {}).get("calle_o_direccion", ""),
                    ),
                    evaluacion_estructural=EvaluacionEstructural(
                        tipo_inmueble=TipoInmueble(est_data.get("tipo_inmueble", TipoInmueble.RESIDENCIAL_CASA.value)),
                        sistema_constructivo=SistemaConstructivo(est_data.get("sistema_constructivo", SistemaConstructivo.MAMPOSTERIA_BLOQUE.value)),
                        habitabilidad=NivelHabitabilidad(est_data.get("habitabilidad", NivelHabitabilidad.HABITABLE.value)),
                        riesgo_colapso_inminente=est_data.get("riesgo_colapso_inminente", False),
                        descripcion_dano=est_data.get("descripcion_dano"),
                    ),
                    servicios_vitales=ServiciosVitales(
                        agua_potable=ser_data.get("agua_potable", "NORMAL"),
                        electricidad=ser_data.get("electricidad", "NORMAL"),
                        fuga_gas=ser_data.get("fuga_gas", False),
                    ),
                    censo_demografico=CensoDemografico(
                        total_ocupantes=int(cen_data.get("total_ocupantes", 1)),
                        neonatos_0_2=int(cen_data.get("neonatos_0_2", 0)),
                        ninos_3_12=int(cen_data.get("ninos_3_12", 0)),
                        adolescentes_13_17=int(cen_data.get("adolescentes_13_17", 0)),
                        adultos_18_59=int(cen_data.get("adultos_18_59", 1)),
                        adultos_mayores_60=int(cen_data.get("adultos_mayores_60", 0)),
                        embarazadas=int(cen_data.get("embarazadas", 0)),
                        personas_discapacidad=int(cen_data.get("personas_discapacidad", 0)),
                    ),
                    necesidades_humanitarias=NecesidadesHumanitarias(
                        requiere_albergue_inmediato=nec_data.get("requiere_albergue_inmediato", False),
                        requiere_agua_alimentos=nec_data.get("requiere_agua_alimentos", False),
                        colchon_3_4_qty=int(nec_data.get("colchon_3_4_qty", 0)),
                        colchon_doble_qty=int(nec_data.get("colchon_doble_qty", 0)),
                        kit_limpieza_qty=int(nec_data.get("kit_limpieza_qty", 0)),
                        kit_bebe_qty=int(nec_data.get("kit_bebe_qty", 0)),
                        kit_higiene_familiar_qty=int(nec_data.get("kit_higiene_familiar_qty", 0)),
                        kit_cocina_qty=int(nec_data.get("kit_cocina_qty", 0)),
                        asistencia_extra_descripcion=nec_data.get("asistencia_extra_descripcion"),
                    ),
                    auditoria_kyc=AuditoriaDeviceKYC(installation_id=""),
                )

                esri_features.append(SinaprocSurvey123Adapter.to_esri_feature(assessment))
            except Exception as item_err:
                print(f"Error mapeando reporte a Esri: {item_err}")
                continue

        # Formato de respuesta compatible con ArcGIS FeatureServer Layer Query Results
        output = {
            "objectIdFieldName": "objectid",
            "globalIdFieldName": "globalid",
            "features": esri_features,
            "total_records": len(esri_features),
        }

        return build_response(200, output)

    except Exception as e:
        print(f"Error exportando datos para SINAPROC: {e}")
        return build_response(500, {"error": str(e)})
