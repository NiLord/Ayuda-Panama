# Changelog

Todas las notas notables de los cambios en los componentes de este proyecto serán documentadas en este archivo.
El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

---

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

## [Unreleased]

### Added
- Inicialización del Monorepo con versionamiento semántico independiente (`app-v*`, `api-v*`, `infra-v*`).
- Definición del **Modelo Canónico Unificado de Evaluación de Desastres (UDAM)** integrando ATC-20, Normas Esfera/MIRA, INSARAG y EDAN SINAPROC.
- Implementación de adaptadores para interoperabilidad:
  - `SinaprocSurvey123Adapter` (Mapeo bidireccional con FeatureServer oficial).
  - `PublicMapAdapter` (Filtrado estricto de PII y semáforo de habitabilidad).
- Módulo de **Device KYC y Telemetría** para autenticación forense, anti-spam y aviso de batería baja.
- Infraestructura Serverless en AWS mediante **CloudFormation** (DynamoDB On-Demand, S3 cifrado con SSE-S3 y CORS, HTTP API Gateway v2, Lambdas en Python 3.13).
- Aplicación móvil en **Flutter** (Android e iOS) con arquitectura offline-first, persistencia local y sincronización en cola.
