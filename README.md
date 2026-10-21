# Ayuda Los Santos (Plataforma de Emergencia Ciudadana e Interoperabilidad)

Plataforma serverless de reporte ciudadano, evaluación de daños e interoperabilidad de emergencias ante eventos sísmicos en Los Santos, Panamá.

Desarrollada bajo principios de:
- **Offline-First**: Funciona sin conectividad y sincroniza en cola cuando se restablece la red.
- **Privacy by Design**: Cumple con la Ley 81 de Panamá, separando PII para uso exclusivo de rescatistas y publicando únicamente agregaciones y mapas de semáforo de habitabilidad.
- **Modelo Canónico Unificado**: Basado en **ATC-20** (evaluación post-sismo), **Normas Esfera / MIRA** (necesidades humanitarias y poblaciones vulnerables) e **INSARAG** (alerta de rescate urbano).
- **Adaptadores de Interoperabilidad**: Capacidad de transformar y exportar datos bidireccionalmente hacia **SINAPROC (ArcGIS Survey123)**, **Cruz Roja** y **Contraloría**.
- **Device KYC y Trazabilidad**: Telemetría técnica para verificación de autenticidad, prevención de alertas falsas y detección de batería crítica de los informantes.

---

## Estructura del Monorepo

```text
.
├── backend/            # Lambdas en Python 3.13 con Modelo Canónico y Adaptadores
│   ├── src/
│   │   ├── models/     # Definición del modelo canónico (UDAM)
│   │   ├── adapters/   # Transformadores (SINAPROC, Mapa Público, Cruz Roja)
│   │   └── handlers/   # Handlers de Lambda (submit, public, presign, export)
│   └── tests/          # Pruebas unitarias de esquemas y adaptadores
├── infra/              # Plantilla CloudFormation (DynamoDB, S3, API Gateway, IAM)
├── frontend/           # App Flutter (Android e iOS) con almacenamiento local
└── .github/workflows/  # CI/CD independiente por rutas
```

---

## Versionamiento Semántico Independiente

- **Frontend (App Móvil)**: Tags `app-vX.Y.Z` (ej. `app-v1.0.0`)
- **Backend & API**: Tags `api-vX.Y.Z` (ej. `api-v1.0.0`)
- **Infraestructura**: Tags `infra-vX.Y.Z` (ej. `infra-v1.0.0`)
