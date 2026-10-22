#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-personal}"
TARGET_FILE="frontend/assets/config/app_config.json"
SSM_PARAM="/ayuda-panama/${ENVIRONMENT}/app-config"

echo "==> Sincronizando configuración remota de Ayuda Panamá desde AWS SSM..."
echo "    - Parámetro: ${SSM_PARAM}"
echo "    - Región:    ${AWS_REGION}"
echo "    - Destino:   ${TARGET_FILE}"

mkdir -p "frontend/assets/config"

# Consultar AWS SSM Parameter Store
CONFIG_JSON=$(aws ssm get-parameter \
  --name "${SSM_PARAM}" \
  --query "Parameter.Value" \
  --output text \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" 2>/dev/null || true)

if [ -z "${CONFIG_JSON}" ]; then
  echo "⚠️  No se pudo leer ${SSM_PARAM} desde AWS SSM (¿sin sesión activa o parámetro no desplegado aún?)."
  echo "    Se conservará la configuración local actual en ${TARGET_FILE}."
  exit 0
fi

# Guardar en el asset de configuración de Flutter
echo "${CONFIG_JSON}" > "${TARGET_FILE}"
echo "✓ Configuración de la aplicación sincronizada exitosamente con AWS SSM."
