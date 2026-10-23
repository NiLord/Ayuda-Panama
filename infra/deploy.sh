#!/usr/bin/env bash
set -euo pipefail

# Configuración por defecto
AWS_PROFILE="${AWS_PROFILE:-personal}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${1:-prod}"
STACK_NAME="lse-emergency-platform-${ENVIRONMENT}"

echo "================================================================="
echo " Despliegue de Infraestructura: Ayuda Panamá (${ENVIRONMENT})"
echo " Región:  ${AWS_REGION}"
echo " Perfil:  ${AWS_PROFILE}"
echo " Stack:   ${STACK_NAME}"
echo "================================================================="

# 0. Generación criptográfica aleatoria de API Key, Secret y Admin Key en memoria
APP_API_KEY="${APP_API_KEY:-$(openssl rand -hex 24)}"
APP_API_SECRET="${APP_API_SECRET:-$(openssl rand -hex 32)}"
echo "==> Generando / verificando credenciales seguras de aplicación..."
echo "    - API Key:    ${APP_API_KEY:0:8}**************** (oculta)"
echo "    - API Secret: ******************************** (oculto)"

# Registrar secretos en AWS SSM Parameter Store como SecureString cifrado con KMS
echo "==> Guardando secretos en AWS SSM Parameter Store (SecureString cifrado)..."
aws ssm put-parameter \
  --name "/ayuda-panama/${ENVIRONMENT}/api-secret" \
  --type "SecureString" \
  --value "${APP_API_SECRET}" \
  --overwrite \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" > /dev/null || echo "    (Aviso: SSM put-parameter omitido o no autorizado)"

# 1. Validar plantilla de CloudFormation
echo "==> 1. Validando plantilla de CloudFormation..."
aws cloudformation validate-template \
  --template-body file://cloudformation.yaml \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" > /dev/null
echo "✓ Plantilla válida."

# 2. Desplegar o actualizar el stack de CloudFormation
echo "==> 2. Desplegando stack con CloudFormation..."
aws cloudformation deploy \
  --template-file cloudformation.yaml \
  --stack-name "${STACK_NAME}" \
  --parameter-overrides \
      Environment="${ENVIRONMENT}" \
      AppApiKey="${APP_API_KEY}" \
      AppApiSecret="${APP_API_SECRET}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}"

# 3. Empaquetar y actualizar código de las funciones Lambda
echo "==> 3. Empaquetando código del backend (Python 3.13)..."
TMP_DIR=$(mktemp -d)
cp -r ../backend "${TMP_DIR}/"
cd "${TMP_DIR}"
zip -rq lambda_code.zip backend/
cd - > /dev/null

echo "==> 4. Actualizando código de las Lambdas..."
FUNCTIONS=(
  "lse-authorizer-${ENVIRONMENT}"
  "lse-submit-report-${ENVIRONMENT}"
  "lse-check-duplicate-${ENVIRONMENT}"
  "lse-get-miviot-tramite-${ENVIRONMENT}"
  "lse-sync-sinaproc-${ENVIRONMENT}"
  "lse-get-upload-presign-${ENVIRONMENT}"
  "lse-national-dashboard-${ENVIRONMENT}"
)

for FN in "${FUNCTIONS[@]}"; do
  echo "    - Actualizando ${FN}..."
  aws lambda update-function-code \
    --function-name "${FN}" \
    --zip-file "fileb://${TMP_DIR}/lambda_code.zip" \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}" > /dev/null
done

rm -rf "${TMP_DIR}"

# 5. Obtener Outputs
echo "==> 5. Despliegue exitoso. Información de la infraestructura:"
aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs" \
  --output table \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}"

HTTP_API_URL=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='HttpApiUrl'].OutputValue" \
  --output text \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}")

echo ""
echo "================================================================="
echo " COMANDOS DE COMPILACIÓN FLUTTER (Sin archivos de texto en disco)"
echo "================================================================="
echo "Para compilar o ejecutar la app inyectando las claves en memoria:"
echo ""
echo "  flutter run \\"
echo "    --dart-define=API_BASE_URL=\"${HTTP_API_URL}\" \\"
echo "    --dart-define=API_KEY=\"${APP_API_KEY}\" \\"
echo "    --dart-define=API_SECRET=\"${APP_API_SECRET}\""
echo ""
echo "O para compilar iOS en Release:"
echo "  flutter build ios --release \\"
echo "    --dart-define=API_BASE_URL=\"${HTTP_API_URL}\" \\"
echo "    --dart-define=API_KEY=\"${APP_API_KEY}\" \\"
echo "    --dart-define=API_SECRET=\"${APP_API_SECRET}\""
echo "================================================================="
