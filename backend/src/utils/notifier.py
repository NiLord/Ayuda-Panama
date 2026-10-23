"""
Módulo de Notificaciones y Alertas del Sistema.
Publica eventos, resúmenes operativos y reportes de error a una cola SQS configurada.
Es completamente agnóstico al consumidor final de la cola (Telegram, Slack, Email, PagerDuty, etc.).
"""

import logging
import os
import boto3

logger = logging.getLogger(__name__)


def _resolve_queue_url(queue_target: str) -> tuple[str, str | None]:
    """
    Convierte de forma determinista un ARN de SQS o valida una URL de SQS existente.
    Retorna una tupla (queue_url, region_name).
    Ejemplo de ARN: arn:aws:sqs:us-east-1:430118856212:telegram-bot-stack-queue
    URL resultante: https://sqs.us-east-1.amazonaws.com/430118856212/telegram-bot-stack-queue
    """
    target = queue_target.strip()
    if target.startswith("http://") or target.startswith("https://"):
        return target, None

    if target.startswith("arn:aws:sqs:"):
        parts = target.split(":")
        if len(parts) >= 6:
            region = parts[3]
            account_id = parts[4]
            queue_name = parts[5]
            url = f"https://sqs.{region}.amazonaws.com/{account_id}/{queue_name}"
            return url, region

    return target, None


def send_alert(message: str, queue_target: str | None = None) -> bool:
    """
    Publica un mensaje de alerta o notificación a una cola SQS.
    Acepta tanto el ARN de la cola como su URL directamente.
    Si la cola no está configurada, no realiza ninguna acción.
    Atrapa cualquier excepción para garantizar que fallos en la cola nunca
    afecten ni bloqueen el flujo principal de ejecución.
    """
    target = queue_target or os.environ.get("ALERTS_QUEUE", "").strip()
    if not target:
        logger.debug("send_alert: ALERTS_QUEUE no configurada. Omitiendo publicación.")
        return False

    queue_url, region = _resolve_queue_url(target)
    if not queue_url:
        return False

    try:
        sqs = boto3.client("sqs", region_name=region) if region else boto3.client("sqs")
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=message,
        )
        logger.info("send_alert: Mensaje publicado exitosamente en la cola SQS (%s).", queue_url)
        return True
    except Exception as e:
        logger.warning("send_alert: No se pudo publicar el mensaje en la cola SQS: %s", str(e))
        return False
