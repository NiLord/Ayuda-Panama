# Changelog

Todas las notas notables de los cambios en los componentes de este proyecto serán documentadas en este archivo.
El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

---

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
