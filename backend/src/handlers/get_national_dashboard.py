"""
Lambda Handler: lse-national-dashboard
Sirve las estadísticas consolidadas del Dashboard Nacional (COEN y Severidad Habitacional)
calculadas de forma horaria y persistidas en DynamoDB (ExternalReportsTable).
Reutiliza la arquitectura de agregación de sinaproc_sync sin duplicidad de código.
"""

from decimal import Decimal
import json
import logging
import os
import boto3

from ..adapters.sinaproc_sync import (
    calculate_national_dashboard_stats,
    save_national_dashboard,
    DEFAULT_FEATURE_SERVER_URL,
)
from ..utils.notifier import send_alert

logger = logging.getLogger(__name__)

EXTERNAL_REPORTS_TABLE_NAME = os.environ.get("EXTERNAL_REPORTS_TABLE_NAME", "lse-external-reports-table")
REPORTS_TABLE_NAME = os.environ.get("REPORTS_TABLE_NAME", "lse-reports-table")
FEATURE_SERVER_URL = os.environ.get("FEATURE_SERVER_URL", DEFAULT_FEATURE_SERVER_URL)

dynamodb = boto3.resource("dynamodb")
external_table = dynamodb.Table(EXTERNAL_REPORTS_TABLE_NAME)


def _decimal_to_native(obj):
    """Convierte tipos Decimal de DynamoDB a tipos estándar de Python/JSON (int/float)."""
    if isinstance(obj, Decimal):
        return int(obj) if obj % 1 == 0 else float(obj)
    if isinstance(obj, dict):
        return {k: _decimal_to_native(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_decimal_to_native(item) for item in obj]
    return obj


def build_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json; charset=utf-8",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,X-Api-Key,X-App-Secret,Authorization",
            "Access-Control-Allow-Methods": "GET,OPTIONS",
            "Cache-Control": "public, max-age=180",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def lambda_handler(event: dict, context) -> dict:
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return build_response(200, {"message": "OK"})

    try:
        # 1. Siempre leer el registro horario precalculado desde DynamoDB
        # El recálculo sólo es ejecutado por el evento horario de sincronización, nunca desde la App
        try:
            resp = external_table.get_item(
                Key={"PK": "CONFIG#HOURLY_DASHBOARD", "SK": "HOURLY"}
            )
            if "Item" in resp and "payload" in resp["Item"]:
                payload = _decimal_to_native(resp["Item"]["payload"])
                return build_response(200, {
                    "success": True,
                    "data": payload,
                    "cached": True,
                    "updated_at": resp["Item"].get("updated_at"),
                })
        except Exception as read_err:
            logger.warning("No se pudo leer registro de dashboard horario: %s", str(read_err))

        # 2. Respaldo exclusivo de inicialización si la tabla está completamente vacía
        logger.info("Registro de dashboard no encontrado en DynamoDB. Inicializando cálculo inicial...")
        dashboard_payload = calculate_national_dashboard_stats(
            feature_server_url=FEATURE_SERVER_URL,
            reports_table_name=REPORTS_TABLE_NAME,
        )
        save_national_dashboard(dashboard_payload, EXTERNAL_REPORTS_TABLE_NAME)

        return build_response(200, {
            "success": True,
            "data": dashboard_payload,
            "cached": False,
            "updated_at": dashboard_payload.get("metadatos", {}).get("ultima_actualizacion_iso"),
        })

    except Exception as e:
        logger.exception("Error recuperando dashboard nacional: %s", str(e))
        send_alert(
            f"🚨 *ERROR en National Dashboard*\n"
            f"• *Función:* `lse-national-dashboard`\n"
            f"• *Error:* `{str(e)}`\n"
        )
        return build_response(500, {
            "success": False,
            "error": "DASHBOARD_ERROR",
            "mensaje": f"Error recuperando datos del dashboard nacional: {str(e)}",
        })
