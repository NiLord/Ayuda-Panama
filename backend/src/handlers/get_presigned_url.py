"""
Lambda Handler: lse-get-upload-presign
Genera URLs prefirmadas de Amazon S3 seguras con expiración corta (5 minutos)
para permitir la subida directa de fotografías de daños desde la aplicación móvil.
"""

import json
import os
import uuid
import boto3
from botocore.config import Config

EVIDENCE_BUCKET_NAME = os.environ.get("EVIDENCE_BUCKET_NAME", "lse-evidence-photos")

# Configurar firma SigV4 explícita para S3
s3_client = boto3.client("s3", config=Config(signature_version="s3v4"))


def build_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,Authorization",
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

        file_extension = payload.get("extension", "jpg").lower().replace(".", "")
        if file_extension not in ["jpg", "jpeg", "png", "webp"]:
            return build_response(400, {"error": "Formato no permitido. Solo se aceptan jpg, jpeg, png o webp"})

        report_id = payload.get("report_id", "temp")
        unique_id = uuid.uuid4().hex
        s3_key = f"evidence/{report_id}/{unique_id}.{file_extension}"
        content_type = f"image/{'jpeg' if file_extension in ['jpg', 'jpeg'] else file_extension}"

        presigned_url = s3_client.generate_presigned_url(
            ClientMethod="put_object",
            Params={
                "Bucket": EVIDENCE_BUCKET_NAME,
                "Key": s3_key,
                "ContentType": content_type,
            },
            ExpiresIn=300, # 5 minutos
        )

        return build_response(200, {
            "upload_url": presigned_url,
            "s3_key": s3_key,
            "expires_in_seconds": 300,
            "final_resource_url": f"https://{EVIDENCE_BUCKET_NAME}.s3.amazonaws.com/{s3_key}",
        })

    except Exception as e:
        print(f"Error generando URL prefirmada: {e}")
        return build_response(500, {"error": str(e)})
