"""
Lambda Handler: lse-check-duplicate
Verifica en tiempo real si ya existe una evaluación de daños registrada para una cédula
en la base de datos de la App (ReportsTable) o en las fichas oficiales de SINAPROC (ExternalReportsTable).
Adicionalmente, consulta si existe un expediente de trámite habitacional activo en MIVIOT.
"""

from datetime import datetime, timezone
import json
import logging
import os
import boto3
from boto3.dynamodb.conditions import Key

from ..utils.cedula_normalizer import normalize_cedula, mask_cedula
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
            "Content-Type": "application/json",
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
                    detalles_reportes.append({
                        "fuente": "APP",
                        "report_id": it.get("report_id"),
                        "fecha": it.get("timestamp"),
                        "habitabilidad": it.get("evaluacion_estructural", {}).get("habitabilidad") or it.get("habitabilidad"),
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
                    detalles_reportes.append({
                        "fuente": "SINAPROC",
                        "external_id": it.get("external_id"),
                        "fecha": it.get("timestamp"),
                        "habitabilidad": it.get("habitabilidad"),
                        "estado": f"Evaluación oficial de campo realizada por {it.get('evaluador', 'SINAPROC')}",
                    })
        except Exception as e:
            logger.warning("Error consultando GSI_Cedula en ExternalReportsTable: %s", str(e))

        # 3. Consultar estado del trámite en MIVIOT (Cache en MiviotTramitesTable o Scraper)
        tramite_miviot = None
        try:
            resp_miviot = miviot_table.get_item(Key={"PK": f"CEDULA#{norm_cedula}"})
            cached_item = resp_miviot.get("Item")

            if cached_item and cached_item.get("encontrado"):
                tramite_miviot = {
                    "reporte": cached_item.get("reporte"),
                    "fecha_recibido": cached_item.get("fecha_recibido"),
                    "paso_actual": cached_item.get("paso_actual"),
                    "estado_actual": cached_item.get("estado_actual"),
                }
                if "MIVIOT" not in sistemas_encontrados:
                    sistemas_encontrados.append("MIVIOT")
            elif not cached_item:
                # Si no está en caché de DynamoDB, ejecutar consulta al MIVIOT
                adapter = MiviotAdapter(timeout_seconds=8)
                res_miviot = adapter.consultar_cedula(norm_cedula)
                if res_miviot.encontrado:
                    tramite_miviot = {
                        "reporte": res_miviot.reporte,
                        "fecha_recibido": res_miviot.fecha_recibido,
                        "paso_actual": res_miviot.paso_actual,
                        "estado_actual": res_miviot.estado_actual,
                    }
                    if "MIVIOT" not in sistemas_encontrados:
                        sistemas_encontrados.append("MIVIOT")
                    # Guardar en MiviotTramitesTable
                    miviot_table.put_item(Item={
                        "PK": f"CEDULA#{norm_cedula}",
                        "encontrado": True,
                        "reporte": res_miviot.reporte,
                        "fecha_recibido": res_miviot.fecha_recibido,
                        "paso_actual": res_miviot.paso_actual,
                        "estado_actual": res_miviot.estado_actual,
                        "ultima_actualizacion": datetime.now(timezone.utc).isoformat(),
                    })
        except Exception as e:
            logger.warning("Error consultando trámite en MIVIOT: %s", str(e))

        # Si tiene trámite en MIVIOT, también se considera vivienda ya registrada oficialmente
        if tramite_miviot:
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
