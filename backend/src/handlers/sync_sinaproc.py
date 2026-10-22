"""
Lambda Handler: lse-sync-sinaproc
Sincroniza los registros de evaluación de daños de SINAPROC (FeatureServer ArcGIS)
hacia la tabla de reportes externos (ExternalReportsTable) en DynamoDB.
Soporta:
1. Carga inicial completa paralelizada (19k+ registros con ThreadPoolExecutor).
2. Sincronización delta incremental por fecha de última modificación (last_edited_date).
Puede ser invocado de forma programada por EventBridge o a demanda por API.
"""

from datetime import datetime, timezone
import json
import logging
import os
import boto3

from ..adapters.sinaproc_sync import (
    DEFAULT_FEATURE_SERVER_URL,
    build_where_clause,
    fetch_sinaproc_object_ids,
    fetch_sinaproc_chunk,
    transform_sinaproc_to_dynamo_item,
)
from concurrent.futures import ThreadPoolExecutor, as_completed

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
        is_full_mode = event.get("full") is True or query_params.get("mode") == "full"
        last_sync_ms = 0 if is_full_mode else int(query_params.get("since_ms", 0))

        # Si no se pasó since_ms explícito ni modo full, buscar checkpoint en DynamoDB
        if not is_full_mode and last_sync_ms == 0:
            try:
                state_resp = external_table.get_item(
                    Key={"PK": "CONFIG#SYNC_STATE", "SK": "SINAPROC"}
                )
                if "Item" in state_resp:
                    last_sync_ms = int(state_resp["Item"].get("last_sync_ms", 0))
                    logger.info("Recuperado checkpoint de sincronización previo: since_ms=%d", last_sync_ms)
            except Exception as st_err:
                logger.warning("No se pudo leer checkpoint de sincronización previo: %s", str(st_err))

        since_dt = None
        if last_sync_ms > 0:
            since_dt = datetime.fromtimestamp(last_sync_ms / 1000.0, tz=timezone.utc)

        where_clause = build_where_clause(since_dt)
        logger.info("Iniciando sincronización SINAPROC con condición: %s", where_clause)

        # 1. Obtener lista completa de ObjectIDs para la condición
        all_ids = fetch_sinaproc_object_ids(FEATURE_SERVER_URL, where_clause=where_clause)
        total_ids = len(all_ids)
        logger.info("Total de registros a sincronizar desde SINAPROC: %d", total_ids)

        if total_ids == 0:
            return build_response(200, {
                "success": True,
                "modo": "full" if last_sync_ms == 0 else "delta",
                "total_recuperados": 0,
                "items_guardados": 0,
                "items_con_cedula_indexada": 0,
                "checkpoint_ms": last_sync_ms,
                "mensaje": "Al día. No hay nuevos registros en SINAPROC para sincronizar.",
                "timestamp": datetime.now(timezone.utc).isoformat(),
            })

        # 2. Dividir en lotes de 1000 IDs y procesar concurrentemente
        chunk_size = 1000
        chunks = [all_ids[i:i + chunk_size] for i in range(0, total_ids, chunk_size)]
        items_procesados = 0
        items_con_cedula = 0
        max_timestamp_visto = last_sync_ms
        max_workers = 6

        logger.info("Descargando e insertando %d lotes de IDs concurrentemente...", len(chunks))

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_chunk = {
                executor.submit(fetch_sinaproc_chunk, FEATURE_SERVER_URL, ch): idx
                for idx, ch in enumerate(chunks)
            }

            # Escribir en DynamoDB con batch_writer a medida que llega cada lote
            with external_table.batch_writer() as batch:
                for future in as_completed(future_to_chunk):
                    chunk_idx = future_to_chunk[future]
                    features = future.result()
                    for feat in features:
                        item = transform_sinaproc_to_dynamo_item(feat)
                        if item:
                            batch.put_item(Item=item)
                            items_procesados += 1
                            if "cedula_normalizada" in item:
                                items_con_cedula += 1

                        feat_ts = feat.get("last_edited_date") or feat.get("created_date") or 0
                        if isinstance(feat_ts, (int, float)) and feat_ts > max_timestamp_visto:
                            max_timestamp_visto = int(feat_ts)

                    logger.info("Lote %d procesado: %d registros guardados (acumulado: %d)", chunk_idx, len(features), items_procesados)

        # 3. Actualizar checkpoint de sincronización en DynamoDB
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
            "modo": "full" if last_sync_ms == 0 else "delta",
            "total_recuperados": total_ids,
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
