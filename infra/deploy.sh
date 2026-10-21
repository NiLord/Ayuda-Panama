#!/usr/bin/env bash
set -euo pipefail

# Configuración por defecto
AWS_PROFILE="${AWS_PROFILE:-personal}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${1:-prod}"
STACK_NAME="lse-emergency-platform-${ENVIRONMENT}"

echo "================================================================="
echo " Despliegue de Infraestructura: Ayuda Los Santos (${ENVIRONMENT})"
echo " Región:  ${AWS_REGION}"
echo " Perfil:  ${AWS_PROFILE}"
echo " Stack:   ${STACK_NAME}"
echo "================================================================="

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
  --parameter-overrides Environment="${ENVIRONMENT}" \
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
  "lse-submit-report-${ENVIRONMENT}"
  "lse-get-public-reports-${ENVIRONMENT}"
  "lse-get-upload-presign-${ENVIRONMENT}"
  "lse-export-edan-${ENVIRONMENT}"
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

echo "✓ Todo listo para conectar la app móvil en Flutter."
