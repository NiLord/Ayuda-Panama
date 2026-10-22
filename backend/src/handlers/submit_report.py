"""
Lambda Handler: lse-submit-report
Recibe y valida un reporte de emergencia ciudadano, procesa la telemetría KYC,
asigna prioridad de triage humanitario, actualiza la reputación del informante
y persiste el reporte completo en Amazon DynamoDB.
"""

import json
import os
import uuid
from datetime import datetime, timezone
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
)

REPORTS_TABLE_NAME = os.environ.get("REPORTS_TABLE_NAME", "lse-reports-table")
REPORTERS_TABLE_NAME = os.environ.get("REPORTERS_TABLE_NAME", "lse-reporters-table")

dynamodb = boto3.resource("dynamodb")
reports_table = dynamodb.Table(REPORTS_TABLE_NAME)
reporters_table = dynamodb.Table(REPORTERS_TABLE_NAME)


def build_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,X-Api-Key,Authorization",
            "Access-Control-Allow-Methods": "POST,OPTIONS",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def lambda_handler(event: dict, context) -> dict:
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return build_response(200, {"message": "OK"})

    try:
        raw_body = event.get("body", "{}")
        if event.get("isBase64Encoded", False):
            import base64
            raw_body = base64.b64decode(raw_body).decode("utf-8")

        payload = json.loads(raw_body) if isinstance(raw_body, str) else raw_body

        # Extraer telemetría técnica desde el request de API Gateway
        http_ctx = event.get("requestContext", {}).get("http", {})
        ip_origen = http_ctx.get("sourceIp", "0.0.0.0")
        user_agent = http_ctx.get("userAgent", "Unknown")

        # Parsear objetos anidados
        inf_data = payload.get("informante", {})
        informante = Informante(
            reporter_id=inf_data.get("reporter_id", f"anon_{uuid.uuid4().hex[:8]}"),
            rol=RolInformante(inf_data.get("rol", RolInformante.AFECTADO_DIRECTO.value)),
            nombre_completo=inf_data.get("nombre_completo"),
            telefono_contacto=inf_data.get("telefono_contacto"),
            organizacion=inf_data.get("organizacion"),
            esta_presente_en_el_sitio=inf_data.get("esta_presente_en_el_sitio", True),
            relacion_con_afectado=inf_data.get("relacion_con_afectado"),
        )

        tit_data = payload.get("titular_afectado", {})
        titular = TitularAfectado(
            es_el_mismo_informante=tit_data.get("es_el_mismo_informante", True),
            nombre_jefe_hogar=tit_data.get("nombre_jefe_hogar"),
            documento_tipo=tit_data.get("documento_tipo", "CEDULA"),
            documento_numero=tit_data.get("documento_numero"),
            telefono_afectado=tit_data.get("telefono_afectado"),
            estado_familia=tit_data.get("estado_familia", "EN_SITIO"),
        )

        ubi_data = payload.get("ubicacion", {})
        coords_data = ubi_data.get("coordenadas", {})
        ubicacion = Ubicacion(
            coordenadas=Coordenadas(
                lat=float(coords_data.get("lat", 7.625)),
                lng=float(coords_data.get("lng", -80.354)),
                precision_metros=coords_data.get("precision_metros"),
                altitud_metros=coords_data.get("altitud_metros"),
            ),
            provincia=ubi_data.get("provincia", "Los Santos"),
            distrito=ubi_data.get("distrito", "Las Tablas"),
            corregimiento=ubi_data.get("corregimiento", ""),
            comunidad_sector=ubi_data.get("comunidad_sector", ""),
            calle_o_direccion=ubi_data.get("calle_o_direccion", ""),
            punto_referencia=ubi_data.get("punto_referencia"),
            accesibilidad_vial=ubi_data.get("accesibilidad_vial", "TRANSITABLE"),
        )

        est_data = payload.get("evaluacion_estructural", {})
        estructural = EvaluacionEstructural(
            tipo_inmueble=TipoInmueble(est_data.get("tipo_inmueble", TipoInmueble.RESIDENCIAL_CASA.value)),
            sistema_constructivo=SistemaConstructivo(est_data.get("sistema_constructivo", SistemaConstructivo.MAMPOSTERIA_BLOQUE.value)),
            habitabilidad=NivelHabitabilidad(est_data.get("habitabilidad", NivelHabitabilidad.HABITABLE.value)),
            riesgo_colapso_inminente=est_data.get("riesgo_colapso_inminente", False),
            danos_principales=est_data.get("danos_principales", []),
            descripcion_dano=est_data.get("descripcion_dano"),
        )

        ser_data = payload.get("servicios_vitales", {})
        servicios = ServiciosVitales(
            agua_potable=ser_data.get("agua_potable", "NORMAL"),
            electricidad=ser_data.get("electricidad", "NORMAL"),
            saneamiento=ser_data.get("saneamiento", "FUNCIONAL"),
            fuga_gas=ser_data.get("fuga_gas", False),
        )

        cen_data = payload.get("censo_demografico", {})
        censo = CensoDemografico(
            total_ocupantes=int(cen_data.get("total_ocupantes", 1)),
            atrapados_o_desaparecidos=int(cen_data.get("atrapados_o_desaparecidos", 0)),
            lesionados_graves=int(cen_data.get("lesionados_graves", 0)),
            neonatos_0_2=int(cen_data.get("neonatos_0_2", 0)),
            ninos_3_12=int(cen_data.get("ninos_3_12", 0)),
            adolescentes_13_17=int(cen_data.get("adolescentes_13_17", 0)),
            adultos_18_59=int(cen_data.get("adultos_18_59", 1)),
            adultos_mayores_60=int(cen_data.get("adultos_mayores_60", 0)),
            embarazadas=int(cen_data.get("embarazadas", 0)),
            personas_discapacidad=int(cen_data.get("personas_discapacidad", 0)),
        )

        nec_data = payload.get("necesidades_humanitarias", {})
        necesidades = NecesidadesHumanitarias(
            requiere_albergue_inmediato=nec_data.get("requiere_albergue_inmediato", False),
            requiere_rescate_medico=nec_data.get("requiere_rescate_medico", False),
            requiere_agua_alimentos=nec_data.get("requiere_agua_alimentos", False),
            colchon_3_4_qty=int(nec_data.get("colchon_3_4_qty", 0)),
            colchon_doble_qty=int(nec_data.get("colchon_doble_qty", 0)),
            kit_limpieza_qty=int(nec_data.get("kit_limpieza_qty", 0)),
            kit_bebe_qty=int(nec_data.get("kit_bebe_qty", 0)),
            kit_higiene_familiar_qty=int(nec_data.get("kit_higiene_familiar_qty", 0)),
            kit_cocina_qty=int(nec_data.get("kit_cocina_qty", 0)),
            asistencia_extra_descripcion=nec_data.get("asistencia_extra_descripcion"),
        )

        kyc_data = payload.get("auditoria_kyc", {})
        auditoria_kyc = AuditoriaDeviceKYC(
            installation_id=kyc_data.get("installation_id", f"inst_{uuid.uuid4().hex[:8]}"),
            es_dispositivo_fisico=kyc_data.get("es_dispositivo_fisico", True),
            marca=kyc_data.get("marca", "Desconocido"),
            modelo=kyc_data.get("modelo", "Desconocido"),
            sistema_operativo=kyc_data.get("sistema_operativo", user_agent),
            app_version=kyc_data.get("app_version", "1.0.0"),
            nivel_bateria_pct=kyc_data.get("nivel_bateria_pct"),
            esta_cargando=kyc_data.get("esta_cargando"),
            tipo_conexion=kyc_data.get("tipo_conexion", "CELULAR"),
            ip_origen=ip_origen,
            timestamp_creacion_local=kyc_data.get("timestamp_creacion_local"),
            timestamp_recepcion_aws=datetime.now(timezone.utc).isoformat(),
        )

        # Calcular prioridad automática
        prioridad = DisasterAssessment.calcular_prioridad(censo, servicios, estructural, necesidades)
        report_id = payload.get("report_id") or f"rep_{uuid.uuid4().hex}"
        timestamp = payload.get("timestamp") or datetime.now(timezone.utc).isoformat()

        # Parsear evento extensible y evidencias fotográficas
        evento_data = payload.get("evento", {})
        tipo_evento = evento_data.get("tipo", payload.get("tipo_evento", "TERREMOTO"))
        codigo_evento = evento_data.get("codigo_evento", payload.get("codigo_evento", "TERREMOTO_LOS_SANTOS_2026"))
        metadatos_evento = evento_data.get("metadatos_evento", payload.get("metadatos_evento", {}))

        evidencias_data = payload.get("evidencias_fotograficas", [])
        fotos_urls = payload.get("fotos_urls", [])
        if not fotos_urls and evidencias_data:
            fotos_urls = [ev.get("url") or ev.get("ruta_local") for ev in evidencias_data if ev.get("url") or ev.get("ruta_local")]

        assessment = DisasterAssessment(
            report_id=report_id,
            timestamp=timestamp,
            prioridad=prioridad,
            consentimiento_informado=payload.get("consentimiento_informado", True),
            informante=informante,
            titular_afectado=titular,
            ubicacion=ubicacion,
            evaluacion_estructural=estructural,
            servicios_vitales=servicios,
            censo_demografico=censo,
            necesidades_humanitarias=necesidades,
            auditoria_kyc=auditoria_kyc,
            tipo_evento=tipo_evento,
            codigo_evento=codigo_evento,
            metadatos_evento=metadatos_evento,
            evidencias_fotograficas=evidencias_data,
            fotos_urls=fotos_urls,
        )

        # 1. Guardar reporte completo en DynamoDB
        report_dict = assessment.to_dict()
        # Asegurar clave de partición para DynamoDB
        report_dict["PK"] = f"REPORT#{report_id}"
        report_dict["SK"] = f"METADATA#{timestamp}"
        report_dict["GSI1PK"] = f"PROVINCIA#{ubicacion.provincia}#DISTRITO#{ubicacion.distrito}"
        report_dict["GSI1SK"] = f"PRIORIDAD#{prioridad.value}#{timestamp}"
        reports_table.put_item(Item=report_dict)

        # 2. Actualizar contador atómico de reputación del informante
        try:
            reporters_table.update_item(
                Key={"PK": f"REPORTER#{informante.reporter_id}", "SK": "PROFILE"},
                UpdateExpression="ADD total_reportes :inc SET ultimo_reporte = :now, nombre = if_not_exists(nombre, :name), organizacion = if_not_exists(organizacion, :org)",
                ExpressionAttributeValues={
                    ":inc": 1,
                    ":now": timestamp,
                    ":name": informante.nombre_completo or "Anónimo",
                    ":org": informante.organizacion or "Independiente",
                },
            )
        except Exception as rep_err:
            print(f"Error actualizando reputación de reporter: {rep_err}")

        return build_response(201, {
            "success": True,
            "report_id": report_id,
            "prioridad": prioridad.value,
            "mensaje": "Reporte registrado y encolado para auxilio oficial exitosamente",
        })

    except Exception as e:
        print(f"Error procesando reporte: {e}")
        return build_response(500, {
            "success": False,
            "error": str(e),
        })
