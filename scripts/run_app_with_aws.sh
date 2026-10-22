#!/usr/bin/env bash
set -euo pipefail

# Script para compilar o ejecutar Ayuda Panamá apuntando a la infraestructura real de AWS
AWS_PROFILE="${AWS_PROFILE:-personal}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${1:-prod}"
STACK_NAME="lse-emergency-platform-${ENVIRONMENT}"
ACTION="${2:-run}" # 'run', 'build-ios', o 'install-ios'

echo "================================================================="
echo " Sincronizando con AWS (${ENVIRONMENT}) para ejecutar la App"
echo " Región:  ${AWS_REGION}"
echo " Perfil:  ${AWS_PROFILE}"
echo " Acción:  ${ACTION}"
echo "================================================================="

# 1. Obtener la URL del API Gateway desde CloudFormation
echo "==> 1. Obteniendo endpoint del API Gateway..."
API_BASE_URL=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='HttpApiUrl'].OutputValue" \
  --output text \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}")

echo "    - API URL: ${API_BASE_URL}"

# 2. Obtener las credenciales del Lambda Authorizer desde AWS SSM
echo "==> 2. Obteniendo credenciales de autorización desde AWS SSM..."
API_KEY=$(aws ssm get-parameter \
  --name "/ayuda-panama/${ENVIRONMENT}/api-key" \
  --query "Parameter.Value" \
  --output text \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}")

API_SECRET=$(aws ssm get-parameter \
  --name "/ayuda-panama/${ENVIRONMENT}/api-secret" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}")

echo "    - API Key: ${API_KEY:0:8}**************** (oculta)"
echo "    - Secret:  ******************************** (oculto)"

# 3. Sincronizar AppConfig
echo "==> 3. Sincronizando app_config.json..."
./scripts/fetch_app_config.sh "${ENVIRONMENT}"

# 4. Ejecutar la acción seleccionada
cd frontend

case "${ACTION}" in
  "run")
    echo "==> Iniciando app con Flutter..."
    flutter run \
      --dart-define=API_BASE_URL="${API_BASE_URL}" \
      --dart-define=API_KEY="${API_KEY}" \
      --dart-define=API_SECRET="${API_SECRET}"
    ;;
  "build-ios")
    echo "==> Compilando versión Release para iOS..."
    flutter build ios --release \
      --dart-define=API_BASE_URL="${API_BASE_URL}" \
      --dart-define=API_KEY="${API_KEY}" \
      --dart-define=API_SECRET="${API_SECRET}"
    ;;
  "install-ios")
    echo "==> Compilando e instalando en iPhone conectado..."
    flutter build ios --release \
      --dart-define=API_BASE_URL="${API_BASE_URL}" \
      --dart-define=API_KEY="${API_KEY}" \
      --dart-define=API_SECRET="${API_SECRET}"
    flutter install
    ;;
  *)
    echo "Acción desconocida: ${ACTION}. Usa 'run', 'build-ios' o 'install-ios'."
    exit 1
    ;;
esac

echo "✓ Proceso completado exitosamente."
