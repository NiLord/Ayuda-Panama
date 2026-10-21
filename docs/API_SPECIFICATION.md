# Especificación de API: Ayuda Los Santos

Base URL (Producción AWS): `https://lse-http-api.execute-api.us-east-1.amazonaws.com`

---

## 1. Endpoints

### `POST /api/v1/reports`
Registra un nuevo informe ciudadano o voluntario de evaluación de daños.

- **Autenticación**: Pública (con rate limit y Device KYC).
- **CORS**: Habilitado (`*`).
- **Headers**: `Content-Type: application/json`
- **Payload**: Objeto JSON conforme al estándar canónico UDAM.
- **Respuestas**:
  - `201 Created`:
    ```json
    {
      "success": true,
      "report_id": "rep_a1b2c3d4",
      "prioridad": "P1_CRITICO_VIDA",
      "mensaje": "Reporte registrado y encolado para auxilio oficial exitosamente"
    }
    ```
  - `400 Bad Request`: Payload malformado.
  - `500 Internal Server Error`.

---

### `GET /api/v1/reports/public`
Retorna las afectaciones ciudadanas en formato **GeoJSON FeatureCollection** seguro, con **0% de datos PII**.

- **Autenticación**: Pública.
- **CORS**: Habilitado (`*`).
- **Cache-Control**: `public, max-age=60`
- **Respuesta (200 OK)**:
  ```json
  {
    "type": "FeatureCollection",
    "features": [
      {
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [-80.3542, 7.6251]
        },
        "properties": {
          "id": "rep_a1b2c3d4",
          "timestamp": "2026-10-21T10:30:00Z",
          "prioridad": "P1_CRITICO_VIDA",
          "semaforo_color": "#E74C3C",
          "habitabilidad": "INHABITABLE",
          "riesgo_colapso": true,
          "tipo_inmueble": "RESIDENCIAL_CASA",
          "provincia": "Los Santos",
          "distrito": "Las Tablas",
          "corregimiento": "Las Tablas",
          "comunidad_sector": "Barrio Santa Librada",
          "total_ocupantes": 4,
          "necesidades_urgentes": {
            "albergue": true,
            "agua_alimentos": true,
            "rescate_medico": true
          }
        }
      }
    ]
  }
  ```

---

### `POST /api/v1/uploads/presign`
Genera una URL prefirmada de Amazon S3 (SigV4) con expiración de 5 minutos para subir fotografías de evidencia directamente desde el cliente.

- **Autenticación**: Pública.
- **Payload**:
  ```json
  {
    "report_id": "rep_a1b2c3d4",
    "extension": "jpg"
  }
  ```
- **Respuesta (200 OK)**:
  ```json
  {
    "upload_url": "https://lse-evidence-photos-xxx.s3.amazonaws.com/evidence/rep_a1b2c3d4/uuid.jpg?X-Amz-...",
    "s3_key": "evidence/rep_a1b2c3d4/uuid.jpg",
    "expires_in_seconds": 300,
    "final_resource_url": "https://lse-evidence-photos-xxx.s3.amazonaws.com/evidence/rep_a1b2c3d4/uuid.jpg"
  }
  ```

---

### `GET /api/v1/reports/export`
Exporta los reportes recopilados con PII completa en el formato exacto del **ArcGIS FeatureServer de SINAPROC** (`_3_de_formulario`).

- **Autenticación**: Requiere Header `X-Admin-Key` o `Authorization: Bearer <ADMIN_SECRET_KEY>`.
- **Respuesta (200 OK)**:
  ```json
  {
    "objectIdFieldName": "objectid",
    "globalIdFieldName": "globalid",
    "total_records": 1,
    "features": [
      {
        "geometry": {
          "x": -80.3542,
          "y": 7.6251,
          "spatialReference": { "wkid": 4326 }
        },
        "attributes": {
          "id_": "rep_a1b2c3d4",
          "f_h_registro": 1792578600000,
          "evaluador": "Carlos Méndez",
          "institucion": "Junta Comunal Las Tablas",
          "nombre_jefe": "Julia Ramos",
          "cedula": "7-111-222",
          "t_contacto": "+507 6555-4321",
          "t_d_infrestuctura": "INHABITABLE",
          "t_miembros": 4.0,
          "c_embarazadas": 1.0,
          "a_humanitaria": "Sí",
          "colchon_doble": 2.0,
          "k_bebe": 1.0
        }
      }
    ]
  }
  ```
- **Respuesta (401 Unauthorized)** si no se suministra la clave de rescatista autorizada.
