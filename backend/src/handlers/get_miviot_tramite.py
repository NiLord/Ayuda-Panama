"""
Lambda Handler: lse-get-miviot-tramite
Consulta el estado de trámite habitacional de una cédula en MIVIOT (portal Odoo).
Verifica primero en la tabla de caché de trámites (MiviotTramitesTable) y si no existe
o han pasado más de 24 horas, realiza la consulta en vivo al portal y actualiza la tabla.
"""

from datetime import datetime, timezone, timedelta
import json
import logging
import os
import boto3

from ..utils.cedula_normalizer import normalize_cedula, mask_cedula
from ..adapters.miviot_adapter import MiviotAdapter

logger = logging.getLogger(__name__)

MIVIOT_TRAMITES_TABLE_NAME = os.environ.get("MIVIOT_TRAMITES_TABLE_NAME", "lse-miviot-tramites-table")
dynamodb = boto3.resource("dynamodb")
miviot_table = dynamodb.Table(MIVIOT_TRAMITES_TABLE_NAME)


def build_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,X-Api-Key,X-App-Secret,Authorization",
            "Access-Control-Allow-Methods": "GET,OPTIONS",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def lambda_handler(event: dict, context) -> dict:
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return build_response(200, {"message": "OK"})

    try:
        query_params = event.get("queryStringParameters") or {}
        cedula_raw = query_params.get("cedula")

        if not cedula_raw:
            return build_response(400, {
                "success": False,
                "error": "PARAMETRO_REQUERIDO",
                "mensaje": "Parámetro 'cedula' requerido en la consulta.",
            })

        norm_cedula = normalize_cedula(cedula_raw)
        if not norm_cedula:
            return build_response(400, {
                "success": False,
                "error": "FORMATO_INVALIDO",
                "mensaje": "Formato de cédula panameña no válido (ej. 7-71-1473).",
            })

        # 1. Verificar si existe en la tabla de trámites
        now = datetime.now(timezone.utc)
        cached_item = None
        try:
            resp = miviot_table.get_item(Key={"PK": f"CEDULA#{norm_cedula}"})
            cached_item = resp.get("Item")
        except Exception as e:
            logger.warning("No se pudo leer de MiviotTramitesTable: %s", str(e))

        force_refresh = query_params.get("force") == "true"
        necesita_consulta_en_vivo = force_refresh or cached_item is None

        # Si tenemos caché previo, evaluar si expiró la ventana de 24 horas
        if cached_item and not force_refresh:
            updated_at_str = cached_item.get("ultima_actualizacion")
            if updated_at_str:
                try:
                    updated_at = datetime.fromisoformat(updated_at_str.replace("Z", "+00:00"))
                    if now - updated_at > timedelta(hours=24):
                        necesita_consulta_en_vivo = True
                except Exception:
                    necesita_consulta_en_vivo = True

        if not necesita_consulta_en_vivo and cached_item:
            return build_response(200, {
                "success": True,
                "origen": "CACHE",
                "encontrado": cached_item.get("encontrado", False),
                "verificado_inexistente": cached_item.get("verificado_inexistente", not cached_item.get("encontrado", False)),
                "es_timeout": False,
                "error": None,
                "puede_reintentar": False,
                "cedula": norm_cedula,
                "cedula_censurada": mask_cedula(norm_cedula),
                "reporte": cached_item.get("reporte"),
                "fecha_recibido": cached_item.get("fecha_recibido"),
                "paso_actual": cached_item.get("paso_actual"),
                "estado_actual": cached_item.get("estado_actual"),
                "ultima_actualizacion": cached_item.get("ultima_actualizacion"),
                "mensaje": "Trámite obtenido desde el registro del sistema",
            })

        # 2. Consulta en vivo al portal Odoo de MIVIOT
        adapter = MiviotAdapter(timeout_seconds=15)
        resultado = adapter.consultar_cedula(norm_cedula)

        # Si ocurrió un error o timeout en la conexión externa:
        # NUNCA persistir en DynamoDB como 'no encontrado' y advertir claramente el fallo
        if resultado.error:
            logger.warning("Fallo en consulta externa MIVIOT para %s: %s (timeout: %s)", norm_cedula, resultado.error, resultado.es_timeout)
            return build_response(200, {
                "success": False,
                "origen": "MIVIOT_LIVE",
                "encontrado": False,
                "verificado_inexistente": False,
                "es_timeout": resultado.es_timeout,
                "error": resultado.error,
                "puede_reintentar": True,
                "cedula": norm_cedula,
                "cedula_censurada": mask_cedula(norm_cedula),
                "reporte": None,
                "fecha_recibido": None,
                "paso_actual": None,
                "estado_actual": None,
                "ultima_actualizacion": now.isoformat(),
                "mensaje": resultado.mensaje or "El servicio de MIVIOT no respondió a tiempo",
            })

        # 3. Guardar en tabla MiviotTramitesTable SOLO si la consulta fue exitosa o confirmada inexistente
        item_to_save = {
            "PK": f"CEDULA#{norm_cedula}",
            "encontrado": resultado.encontrado,
            "verificado_inexistente": resultado.verificado_inexistente,
            "cedula": norm_cedula,
            "reporte": resultado.reporte,
            "fecha_recibido": resultado.fecha_recibido,
            "paso_actual": resultado.paso_actual,
            "estado_actual": resultado.estado_actual,
            "ultima_actualizacion": now.isoformat(),
        }

        # Si fue verificado que no existe, colocar TTL de 4 horas para reintentar más adelante
        if not resultado.encontrado:
            item_to_save["ttl_expiration"] = int((now + timedelta(hours=4)).timestamp())

        try:
            miviot_table.put_item(Item=item_to_save)
        except Exception as e:
            logger.warning("Error al guardar en MiviotTramitesTable: %s", str(e))

        return build_response(200, {
            "success": True,
            "origen": "MIVIOT_LIVE",
            "encontrado": resultado.encontrado,
            "verificado_inexistente": resultado.verificado_inexistente,
            "es_timeout": False,
            "error": None,
            "puede_reintentar": False,
            "cedula": norm_cedula,
            "cedula_censurada": mask_cedula(norm_cedula),
            "reporte": resultado.reporte,
            "fecha_recibido": resultado.fecha_recibido,
            "paso_actual": resultado.paso_actual,
            "estado_actual": resultado.estado_actual,
            "ultima_actualizacion": now.isoformat(),
            "mensaje": resultado.mensaje or "Consulta realizada en MIVIOT",
        })

    except Exception as e:
        logger.exception("Error en get_miviot_tramite: %s", str(e))
        return build_response(500, {
            "success": False,
            "error": "INTERNAL_ERROR",
            "mensaje": f"Error consultando trámite en MIVIOT: {str(e)}",
        })
