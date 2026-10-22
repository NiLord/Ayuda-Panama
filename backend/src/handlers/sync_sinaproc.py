"""
Lambda Handler: lse-sync-sinaproc
Sincroniza los registros de evaluación de daños de SINAPROC (FeatureServer ArcGIS)
hacia la tabla de reportes externos (ExternalReportsTable) en DynamoDB.
Puede ser invocado de forma programada por EventBridge o a demanda por API.
"""

from datetime import datetime, timezone
from decimal import Decimal
import json
import logging
import os
import boto3

from ..adapters.sinaproc_sync import (
    DEFAULT_FEATURE_SERVER_URL,
    fetch_sinaproc_features,
    transform_sinaproc_to_dynamo_item,
)

logger = logging.getLogger(__name__)

EXTERNAL_REPORTS_TABLE_NAME = os.environ.get("EXTERNAL_REPORTS_TABLE_NAME", "lse-external-reports-table")
FEATURE_SERVER_URL = os.environ.get("FEATURE_SERVER_URL", DEFAULT_FEATURE_SERVER_URL)

dynamodb = boto3.resource("dynamodb")
external_table = dynamodb.Table(EXTERNAL_REPORTS_TABLE_NAME)


def build_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def lambda_handler(event: dict, context) -> dict:
    try:
        query_params = event.get("queryStringParameters") or {}
        max_records = int(query_params.get("limit", 200))
        last_sync_ms = int(query_params.get("since_ms", 0))

        # Si no se pasó since_ms explícito (ej. invocado por EventBridge), buscar checkpoint en DynamoDB
        if last_sync_ms == 0:
            try:
                state_resp = external_table.get_item(
                    Key={"PK": "CONFIG#SYNC_STATE", "SK": "SINAPROC"}
                )
                if "Item" in state_resp:
                    last_sync_ms = int(state_resp["Item"].get("last_sync_ms", 0))
                    logger.info("Recuperado checkpoint de sincronización previo: since_ms=%d", last_sync_ms)
            except Exception as st_err:
                logger.warning("No se pudo leer checkpoint de sincronización previo: %s", str(st_err))

        logger.info("Iniciando sincronización SINAPROC desde %s (since_ms=%d)", FEATURE_SERVER_URL, last_sync_ms)
        features = fetch_sinaproc_features(
            feature_server_url=FEATURE_SERVER_URL,
            last_edited_ms=last_sync_ms,
            max_records=max_records,
        )

        logger.info("Recuperados %d registros de SINAPROC", len(features))
        items_procesados = 0
        items_con_cedula = 0
        max_timestamp_visto = last_sync_ms

        with external_table.batch_writer() as batch:
            for feat in features:
                item = transform_sinaproc_to_dynamo_item(feat)
                if item:
                    # DynamoDB batch_writer
                    batch.put_item(Item=item)
                    items_procesados += 1
                    if "cedula_normalizada" in item:
                        items_con_cedula += 1

                # Seguir el timestamp más reciente para el checkpoint
                feat_ts = feat.get("last_edited_date") or feat.get("created_date") or 0
                if isinstance(feat_ts, (int, float)) and feat_ts > max_timestamp_visto:
                    max_timestamp_visto = int(feat_ts)

        # Actualizar checkpoint de sincronización en DynamoDB
        if max_timestamp_visto > last_sync_ms:
            try:
                external_table.put_item(Item={
                    "PK": "CONFIG#SYNC_STATE",
                    "SK": "SINAPROC",
                    "last_sync_ms": max_timestamp_visto,
                    "last_sync_iso": datetime.now(timezone.utc).isoformat(),
                    "total_items_procesados": items_procesados,
                })
                logger.info("Checkpoint de sincronización actualizado a %d", max_timestamp_visto)
            except Exception as upd_err:
                logger.warning("Error guardando checkpoint de sincronización: %s", str(upd_err))

        resultado = {
            "success": True,
            "total_recuperados": len(features),
            "items_guardados": items_procesados,
            "items_con_cedula_indexada": items_con_cedula,
            "checkpoint_ms": max_timestamp_visto,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        logger.info("Sincronización SINAPROC finalizada con éxito: %s", json.dumps(resultado))
        return build_response(200, resultado)

    except Exception as e:
        logger.exception("Error en sincronización de SINAPROC: %s", str(e))
        return build_response(500, {
            "success": False,
            "error": "SYNC_ERROR",
            "mensaje": f"Error ejecutando sincronización SINAPROC: {str(e)}",
        })
