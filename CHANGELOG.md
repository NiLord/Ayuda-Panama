# Changelog

Todas las notas notables de los cambios en los componentes de este proyecto serán documentadas en este archivo.
El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

---

## [1.2.1] - 2026-10-23

### Added
- **Módulo Agnóstico de Alertas y Notificaciones SQS (`send_alert`)**:
  - Nuevo módulo utilitario `backend/src/utils/notifier.py` para publicación de eventos y errores en colas SQS.
  - Resolución determinista bidireccional (soporta ARN o URL directa de SQS).
  - Integración en `lse-sync-sinaproc`:
    - Notificación de sincronización exitosa con conteo de registros inyectados, indexados y modo de ejecución (Full/Delta).
    - Reporte automático de excepciones no controladas.
  - Integración de reporte de excepciones no controladas en `submit_report`, `check_duplicate` y `national_dashboard`.
  - Configuración dinámica en CloudFormation mediante parámetro único `AlertsQueueArn` y política condicional IAM `SqsAlertsPublishPolicy` (sin valores ni cuentas fijas quemadas).

### Changed
- **Optimización de Memoria en AWS Lambdas (Cost & Compute Right-Sizing)**:
  - Análisis empírico de consumo real en CloudWatch Logs Insights (perfil `personal`):
    - `lse-submit-report-prod`: Reducido de 256 MB a **128 MB** (pico real 95 MB, 50% ahorro).
    - `lse-get-upload-presign-prod`: Reducido de 256 MB a **128 MB** (pico real 96 MB, 50% ahorro).
    - `lse-check-duplicate-prod`: Reducido de 256 MB a **128 MB** (pico real 103 MB, 50% ahorro).
    - `lse-national-dashboard-prod`: Reducido de 256 MB a **128 MB** (pico real 104 MB, 50% ahorro).
    - `lse-get-miviot-tramite-prod`: Reducido de 256 MB a **160 MB** (pico real 105 MB, 37.5% ahorro, con margen para parsing HTML).
    - `lse-sync-sinaproc-prod`: Reducido de 512 MB a **256 MB** (pico real 206 MB en ingesta masiva de 5K+ registros, 50% ahorro).
    - `lse-authorizer-prod`: Mantenido en **128 MB** (mínimo absoluto de AWS Lambda, pico real 42 MB).

## [1.2.0] - 2026-10-22

### Added
- **Dashboard de Estadísticas Nacionales**:
  - Nuevo handler `lse-national-dashboard-prod` para lectura instantánea O(1) de totales nacionales, censo demográfico y severidad habitacional por provincia/distrito.
  - Sincronizador de SINAPROC con filtro oficial de evento (`f_h_registro >= '2026-10-09'`), homologando con precisión los totales oficiales.
- **Mejoras UX/UI en Flutter**:
  - Pantalla de consulta ciudadana con campo de cédula en blanco por defecto y ocultamiento automático de teclado al consultar.
  - Validación de cédula en reporte mediante evento `out-of-focus` para optimizar llamados a la red.
  - Footer fijo para fecha de última actualización en estadísticas nacionales.
  - Carga automática de perfil existente al editar desde el icono superior.
  - Tarjeta de bienvenida en pantalla de inicio.

### Security
- Erradicación total de credenciales y endpoints en código estático; inyección de credenciales estrictamente en tiempo de compilación con `--dart-define`.

## [1.1.0] - 2026-10-22

### Added
- **Integración y Deduplicación Multi-Fuente (SINAPROC, MIVIOT y App)**:
  - Repositorio desacoplado de 3 tablas en DynamoDB: `lse-reports-table` (App), `lse-external-reports-table` (SINAPROC EDAN) y `lse-miviot-tramites-table` (Expedientes y etapas MIVIOT).
  - Normalizador de Cédulas de Panamá (`normalize_cedula`, `mask_cedula`, `mask_person_name`) compatible con Ley 81.
  - Adaptador Scraper para portal Odoo de MIVIOT (`MiviotAdapter`) con handshake de 2 fases (CSRF + cookies) y detección de 5 etapas habitacionales.
  - Sincronizador de FeatureServer ArcGIS de SINAPROC (`sinaproc_sync.py` y Lambda `lse-sync-sinaproc`).
  - Endpoint de validación de duplicados en tiempo real (`POST /api/v1/reports/check-duplicate`).
  - Endpoint de consulta de expedientes MIVIOT (`GET /api/v1/tramites/miviot`).
  - Bloqueo estricto e infranqueable de duplicados en Paso 0 de la App (botón "Siguiente" deshabilitado con alerta roja) y en el backend (HTTP 409 Conflict).
  - Tarjetas de Monitoreo Nacional con badges distintivos `[Reporte App]`, `[SINAPROC EDAN]` y `[MIVIOT]` y botón de consulta de expediente MIVIOT (`MiviotTramiteDialog`).
  - 100% de cadenas internacionalizadas en diccionarios JSON (`es.json`, `en.json`).
- Suite completa de pruebas unitarias (`pytest` 35/35 passing, `flutter test` 25/25 passing).

## [1.0.0]

### Added
- Inicialización del Monorepo con versionamiento semántico independiente (`app-v*`, `api-v*`, `infra-v*`).
- Definición del **Modelo Canónico Unificado de Evaluación de Desastres (UDAM)** integrando ATC-20, Normas Esfera/MIRA, INSARAG y EDAN SINAPROC.
- Implementación de adaptadores para interoperabilidad:
  - `SinaprocSurvey123Adapter` (Mapeo bidireccional con FeatureServer oficial).
  - `PublicMapAdapter` (Filtrado estricto de PII y semáforo de habitabilidad).
- Módulo de **Device KYC y Telemetría** para autenticación forense, anti-spam y aviso de batería baja.
- Infraestructura Serverless en AWS mediante **CloudFormation** (DynamoDB On-Demand, S3 cifrado con SSE-S3 y CORS, HTTP API Gateway v2, Lambdas en Python 3.13).
- Aplicación móvil en **Flutter** (Android e iOS) con arquitectura offline-first, persistencia local y sincronización en cola.
