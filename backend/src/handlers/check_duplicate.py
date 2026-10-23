"""
Lambda Handler: lse-check-duplicate
Verifica en tiempo real si ya existe una evaluación de daños registrada para una cédula
en la base de datos de la App (ReportsTable) o en las fichas oficiales de SINAPROC (ExternalReportsTable).
Adicionalmente, consulta si existe un expediente de trámite habitacional activo en MIVIOT.
"""

from datetime import datetime, timezone, timedelta
import json
import logging
import os
import boto3
from boto3.dynamodb.conditions import Key

from ..utils.cedula_normalizer import normalize_cedula, mask_cedula
from ..utils.geo_normalizer import (
    homologar_provincia,
    homologar_distrito,
    format_clean_name,
    homologar_evaluador,
)
from ..adapters.miviot_adapter import MiviotAdapter

logger = logging.getLogger(__name__)

REPORTS_TABLE_NAME = os.environ.get("REPORTS_TABLE_NAME", "lse-reports-table")
EXTERNAL_REPORTS_TABLE_NAME = os.environ.get("EXTERNAL_REPORTS_TABLE_NAME", "lse-external-reports-table")
MIVIOT_TRAMITES_TABLE_NAME = os.environ.get("MIVIOT_TRAMITES_TABLE_NAME", "lse-miviot-tramites-table")

dynamodb = boto3.resource("dynamodb")
reports_table = dynamodb.Table(REPORTS_TABLE_NAME)
external_table = dynamodb.Table(EXTERNAL_REPORTS_TABLE_NAME)
miviot_table = dynamodb.Table(MIVIOT_TRAMITES_TABLE_NAME)


def build_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json; charset=utf-8",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,X-Api-Key,X-App-Secret,Authorization",
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
        cedula_input = payload.get("cedula")

        if not cedula_input:
            return build_response(400, {
                "success": False,
                "error": "PARAMETRO_REQUERIDO",
                "mensaje": "Se requiere el parámetro 'cedula' para realizar la validación.",
            })

        norm_cedula = normalize_cedula(str(cedula_input))
        if not norm_cedula:
            return build_response(400, {
                "success": False,
                "error": "FORMATO_INVALIDO",
                "mensaje": "El formato de cédula no es válido para Panamá (ej. 7-71-1473).",
            })

        sistemas_encontrados = []
        detalles_reportes = []
        existe_duplicado = False

        # 1. Consultar en ReportsTable (App) vía GSI2_Cedula
        try:
            resp_app = reports_table.query(
                IndexName="GSI2_Cedula",
                KeyConditionExpression=Key("GSI2PK").eq(f"CEDULA#{norm_cedula}"),
                Limit=5
            )
            app_items = resp_app.get("Items", [])
            if app_items:
                existe_duplicado = True
                sistemas_encontrados.append("APP")
                for it in app_items:
                    ubic = it.get("ubicacion") or {}
                    detalles_reportes.append({
                        "fuente": "APP",
                        "report_id": str(it.get("report_id") or ""),
                        "fecha": str(it.get("timestamp") or ""),
                        "habitabilidad": str(it.get("evaluacion_estructural", {}).get("habitabilidad") or it.get("habitabilidad") or "HABITABLE"),
                        "provincia": homologar_provincia(ubic.get("provincia")),
                        "distrito": homologar_distrito(ubic.get("distrito")),
                        "corregimiento": format_clean_name(ubic.get("corregimiento")),
                        "comunidad_sector": format_clean_name(ubic.get("comunidad_sector")),
                        "estado": "Reporte ciudadano registrado en la aplicación",
                    })
        except Exception as e:
            logger.warning("Error consultando GSI2_Cedula en ReportsTable: %s", str(e))

        # 2. Consultar en ExternalReportsTable (SINAPROC EDAN) vía GSI_Cedula
        try:
            resp_ext = external_table.query(
                IndexName="GSI_Cedula",
                KeyConditionExpression=Key("GSI_CedulaPK").eq(f"CEDULA#{norm_cedula}"),
                Limit=5
            )
            ext_items = resp_ext.get("Items", [])
            if ext_items:
                existe_duplicado = True
                if "SINAPROC" not in sistemas_encontrados:
                    sistemas_encontrados.append("SINAPROC")
                for it in ext_items:
                    eval_name = homologar_evaluador(it.get("evaluador"))
                    ubic = it.get("ubicacion") or {}
                    detalles_reportes.append({
                        "fuente": "SINAPROC",
                        "external_id": str(it.get("external_id") or ""),
                        "fecha": str(it.get("timestamp") or ""),
                        "habitabilidad": str(it.get("habitabilidad") or "DESCONOCIDO"),
                        "evaluador": eval_name,
                        "dano_descripcion": str(it.get("dano_descripcion") or "Evaluación oficial de campo"),
                        "tipo_vivienda": format_clean_name(it.get("tipo_vivienda")) or "Casa",
                        "tipo_construccion": format_clean_name(it.get("tipo_construccion")) or "Bloque",
                        "total_afectados": int(it.get("total_afectados") or 1) if str(it.get("total_afectados") or "").isdigit() else 1,
                        "titular": str(it.get("nombre_titular_censurado") or "Residente"),
                        "provincia": homologar_provincia(ubic.get("provincia")),
                        "distrito": homologar_distrito(ubic.get("distrito")),
                        "corregimiento": format_clean_name(ubic.get("corregimiento")),
                        "comunidad_sector": format_clean_name(ubic.get("comunidad_sector")),
                        "calle_o_direccion": str(ubic.get("calle_o_direccion") or ""),
                        "estado": f"Evaluación oficial de campo realizada por {eval_name}",
                    })
        except Exception as e:
            logger.warning("Error consultando GSI_Cedula en ExternalReportsTable: %s", str(e))

        # 3. Consultar estado del trámite en MIVIOT (Cache en MiviotTramitesTable o Scraper)
        tramite_miviot = None
        now_iso = datetime.now(timezone.utc).isoformat()
        try:
            resp_miviot = miviot_table.get_item(Key={"PK": f"CEDULA#{norm_cedula}"})
            cached_item = resp_miviot.get("Item")

            if cached_item and cached_item.get("encontrado"):
                paso_val = cached_item.get("paso_actual", 1)
                tramite_miviot = {
                    "reporte": cached_item.get("reporte"),
                    "fecha_recibido": cached_item.get("fecha_recibido"),
                    "paso_actual": int(paso_val) if str(paso_val).isdigit() else 1,
                    "estado_actual": cached_item.get("estado_actual"),
                    "encontrado": True,
                    "verificado_inexistente": False,
                    "es_timeout": False,
                    "error": None,
                    "ultima_actualizacion": cached_item.get("ultima_actualizacion") or now_iso,
                }
                if "MIVIOT" not in sistemas_encontrados:
                    sistemas_encontrados.append("MIVIOT")
            elif cached_item and cached_item.get("verificado_inexistente"):
                tramite_miviot = {
                    "encontrado": False,
                    "verificado_inexistente": True,
                    "es_timeout": False,
                    "error": None,
                    "ultima_actualizacion": cached_item.get("ultima_actualizacion") or now_iso,
                    "mensaje": "El MIVIOT certificó que no hay expediente para esta cédula.",
                }
            else:
                # Si no está en caché o la entrada previa no era concluyente, consultar MIVIOT
                adapter = MiviotAdapter(timeout_seconds=12)
                res_miviot = adapter.consultar_cedula(norm_cedula)
                if res_miviot.encontrado:
                    tramite_miviot = {
                        "reporte": res_miviot.reporte,
                        "fecha_recibido": res_miviot.fecha_recibido,
                        "paso_actual": res_miviot.paso_actual,
                        "estado_actual": res_miviot.estado_actual,
                        "encontrado": True,
                        "verificado_inexistente": False,
                        "es_timeout": False,
                        "error": None,
                        "ultima_actualizacion": now_iso,
                    }
                    if "MIVIOT" not in sistemas_encontrados:
                        sistemas_encontrados.append("MIVIOT")
                    # Guardar en MiviotTramitesTable
                    miviot_table.put_item(Item={
                        "PK": f"CEDULA#{norm_cedula}",
                        "encontrado": True,
                        "verificado_inexistente": False,
                        "reporte": res_miviot.reporte,
                        "fecha_recibido": res_miviot.fecha_recibido,
                        "paso_actual": res_miviot.paso_actual,
                        "estado_actual": res_miviot.estado_actual,
                        "ultima_actualizacion": now_iso,
                    })
                elif res_miviot.error:
                    # Ocurrió error o timeout: NO guardar como 'inexistente'
                    tramite_miviot = {
                        "encontrado": False,
                        "verificado_inexistente": False,
                        "es_timeout": res_miviot.es_timeout,
                        "error": res_miviot.error,
                        "puede_reintentar": True,
                        "ultima_actualizacion": res_miviot.timestamp_consulta or now_iso,
                        "mensaje": res_miviot.mensaje,
                    }
                else:
                    # Portal confirmó literalmente que NO existe registro
                    tramite_miviot = {
                        "encontrado": False,
                        "verificado_inexistente": True,
                        "es_timeout": False,
                        "error": None,
                        "puede_reintentar": False,
                        "ultima_actualizacion": now_iso,
                        "mensaje": res_miviot.mensaje or "Sin expediente registrado en MIVIOT",
                    }
                    miviot_table.put_item(Item={
                        "PK": f"CEDULA#{norm_cedula}",
                        "encontrado": False,
                        "verificado_inexistente": True,
                        "ultima_actualizacion": now_iso,
                        "ttl_expiration": int((datetime.now(timezone.utc) + timedelta(hours=4)).timestamp()),
                    })
        except Exception as e:
            logger.warning("Error consultando trámite en MIVIOT: %s", str(e))
            tramite_miviot = {
                "encontrado": False,
                "verificado_inexistente": False,
                "es_timeout": "timeout" in str(e).lower(),
                "error": "EXCEPTION",
                "puede_reintentar": True,
                "mensaje": f"No se pudo consultar MIVIOT: {str(e)}",
            }

        # Si tiene trámite confirmado en MIVIOT, se considera vivienda ya registrada oficialmente
        if tramite_miviot and tramite_miviot.get("encontrado"):
            existe_duplicado = True
            detalles_reportes.append({
                "fuente": "MIVIOT",
                "reporte": tramite_miviot.get("reporte"),
                "fecha": tramite_miviot.get("fecha_recibido"),
                "paso_actual": tramite_miviot.get("paso_actual"),
                "estado": f"Expediente de vivienda activo: {tramite_miviot.get('estado_actual')}",
            })

        censored = mask_cedula(norm_cedula)
        if existe_duplicado:
            mensaje = (
                f"La vivienda con cédula {censored} ya cuenta con evaluación o trámite registrado "
                f"en: {', '.join(sistemas_encontrados)}. No se permite ingresar un reporte duplicado."
            )
        else:
            mensaje = f"Cédula {censored} sin reportes previos registrados. Puede continuar con el formulario."

        return build_response(200, {
            "success": True,
            "cedula": norm_cedula,
            "cedula_censurada": censored,
            "existe_duplicado": existe_duplicado,
            "sistemas": sistemas_encontrados,
            "detalles": detalles_reportes,
            "tramite_miviot": tramite_miviot,
            "mensaje": mensaje,
        })

    except Exception as e:
        logger.exception("Error en check_duplicate: %s", str(e))
        return build_response(500, {
            "success": False,
            "error": "INTERNAL_ERROR",
            "mensaje": f"Error procesando verificación de cédula: {str(e)}",
        })
