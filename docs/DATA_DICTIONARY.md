# Diccionario de Datos: Modelo Canónico UDAM

El **Unified Disaster Assessment Model (UDAM)** es el estándar canónico de datos de la plataforma **Ayuda Los Santos**. Fue diseñado integrando **ATC-20** (evaluación post-sismo), **Normas Esfera / MIRA** (respuesta humanitaria y poblaciones prioritarias), **INSARAG** (búsqueda y rescate urbano) y la metodología centroamericana **EDAN (CEPREDENAC / SINAPROC Panamá)**.

---

## 1. Clasificación de Privacidad de Datos (Ley 81 de Panamá)

| Nivel de Privacidad | Descripción | Acceso | Ejemplos |
| :--- | :--- | :--- | :--- |
| 🟢 **Público (Anónimo)** | Agregaciones, semáforo de daño y ubicación general sin datos personales. | Cualquier ciudadano, prensa, donantes. | `habitabilidad`, `semaforo_color`, `lat`/`lng`, `requiere_albergue`. |
| 🔴 **Restringido (Rescate)** | PII y datos de contacto de víctimas e informantes. | Exclusivo SINAPROC, Cruz Roja, Bomberos. | `nombre_jefe_hogar`, `cedula`, `telefono`, `direccion_exacta`. |
| 🔒 **Forense (Auditoría)** | Metadatos técnicos de hardware, red e instalación. | Analistas de COE para prevenir falsas alarmas. | `installation_id`, `ip_origen`, `es_dispositivo_fisico`, `bateria`. |

---

## 2. Campos del Modelo Canónico

### A. Metadatos y Control de Emergencia
- `report_id` (String UUID): Identificador único del reporte en base64/hexadecimal.
- `timestamp` (ISO-8601 UTC): Fecha y hora exacta de registro.
- `prioridad` (Enum):
  - `P1_CRITICO_VIDA`: Personas atrapadas, lesionados graves, fuga de gas o riesgo inminente de colapso.
  - `P2_URGENTE_ALBERGUE`: Inmueble inhabitable, familias a la intemperie, sin agua o con personas vulnerables.
  - `P3_MONITOREO_ENSERES`: Daño menor en vivienda habitable, reposición de bienes.
- `consentimiento_informado` (Boolean): Aceptación explícita bajo Ley 81 para transferir PII a autoridades.

### B. Informante (Quien Reporta)
- `informante.reporter_id` (String UUID): Identificador persistente del dispositivo.
- `informante.rol` (Enum): `AFECTADO_DIRECTO`, `VECINO_O_TERCERO`, `FAMILIAR_NO_RESIDENTE`, `VOLUNTARIO_BRIGADISTA`, `LIDER_COMUNITARIO`, `FUNCIONARIO_ESTATAL`.
- `informante.nombre_completo` (String, Opcional): Nombre del informante.
- `informante.telefono_contacto` (String, Opcional): Teléfono para que los rescatistas coordinen la llegada.
- `informante.organizacion` (String, Opcional): Institución u ONG a la que pertenece.
- `informante.esta_presente_en_el_sitio` (Boolean): `true` si reporta desde el lugar de los hechos; `false` si reporta de forma remota.

### C. Titular Afectado (Jefe del Hogar Damnificado - PII)
- `titular_afectado.es_el_mismo_informante` (Boolean): Evita duplicar datos si reporta su propia casa.
- `titular_afectado.nombre_jefe_hogar` (String): Nombre del jefe de familia afectado.
- `titular_afectado.documento_tipo` (String): `CEDULA`, `PASAPORTE`, `OTRO`.
- `titular_afectado.documento_numero` (String): Número de cédula o identificación panameña.
- `titular_afectado.telefono_afectado` (String): Teléfono directo de la familia afectada.
- `titular_afectado.estado_familia` (Enum): `EN_SITIO`, `EVACUADOS_CALLE`, `EN_ALBERGUE`, `HOSPITALIZADOS`.

### D. Ubicación Geográfica
- `ubicacion.coordenadas.lat` (Float): Latitud WGS-84 (EPSG:4326).
- `ubicacion.coordenadas.lng` (Float): Longitud WGS-84 (EPSG:4326).
- `ubicacion.coordenadas.precision_metros` (Float): Precisión del GPS del teléfono.
- `ubicacion.provincia` (String): Default `"Los Santos"`.
- `ubicacion.distrito` (String): Las Tablas, Guararé, Los Santos, Macaracas, Pedasí, Pocrí, Tonosí.
- `ubicacion.corregimiento` (String): Corregimiento político-administrativo.
- `ubicacion.comunidad_sector` (String): Barrio, poblado o comunidad.
- `ubicacion.calle_o_direccion` (String): Dirección y número de vivienda.
- `ubicacion.punto_referencia` (String): Referencia visual para rescatistas (ej. *"frente a la iglesia vieja"*).
- `ubicacion.accesibilidad_vial` (Enum): `TRANSITABLE`, `BLOQUEADO_ESCOMBROS`, `SOLO_A_PIE`, `INUNDADO`.

### E. Evaluación Estructural y Habitabilidad (ATC-20)
- `evaluacion_estructural.tipo_inmueble` (Enum): `RESIDENCIAL_CASA`, `RESIDENCIAL_EDIFICIO`, `COMERCIAL`, `ESCUELA_O_EDUCATIVO`, `CENTRO_SALUD`, `OTRO`.
- `evaluacion_estructural.sistema_constructivo` (Enum): `MAMPOSTERIA_BLOQUE`, `HORMIGON_ARMADO`, `MADERA`, `ZINC_LAMINA`, `QUINCHA_ADOBE`, `MIXTO_OTRO`.
- `evaluacion_estructural.habitabilidad` (Enum ATC-20):
  - `HABITABLE` (Verde `#2ECC71`): Estructura segura. Daños superficiales o nulos.
  - `ACCESO_RESTRINGIDO` (Amarillo `#F1C40F`): Daño localizado; solo ingreso temporal delimitado.
  - `INHABITABLE` (Rojo `#E74C3C`): Daño estructural grave. Peligro de colapso por réplicas.
  - `COLAPSO_TOTAL` (Púrpura `#8E44AD`): Estructura colapsada o destruida.
- `evaluacion_estructural.riesgo_colapso_inminente` (Boolean): Peligro visible de desprendimiento o derrumbe.
- `evaluacion_estructural.danos_principales` (List[String]): `MUROS_AGRIETADOS`, `COLAPSO_TECHO`, `DANOS_CIMIENTOS`, `VIDRIOS_ROTOS`, etc.
- `evaluacion_estructural.descripcion_dano` (String): Detalle cualitativo de la afectación.

### F. Servicios Vitales (Lifelines)
- `servicios_vitales.agua_potable` (Enum): `NORMAL`, `CONTAMINADA`, `SIN_SERVICIO`.
- `servicios_vitales.electricidad` (Enum): `NORMAL`, `CORTE`, `CABLES_CAIDOS_PELIGRO`.
- `servicios_vitales.saneamiento` (Enum): `FUNCIONAL`, `COLAPSADO`.
- `servicios_vitales.fuga_gas` (Boolean): Presencia de olor o fuga en tanques de gas.

### G. Censo Demográfico y Poblaciones Prioritarias (Sphere / MIRA / INSARAG)
- `censo_demografico.total_ocupantes` (Integer): Total de personas que habitan la vivienda.
- `censo_demografico.atrapados_o_desaparecidos` (Integer): **ALERTA INSARAG**: Personas bajo escombros.
- `censo_demografico.lesionados_graves` (Integer): Personas que requieren traslado en ambulancia.
- `censo_demografico.neonatos_0_2` (Integer): Bebés y lactantes.
- `censo_demografico.ninos_3_12` (Integer): Niños en edad escolar.
- `censo_demografico.adolescentes_13_17` (Integer): Adolescentes.
- `censo_demografico.adultos_18_59` (Integer): Adultos.
- `censo_demografico.adultos_mayores_60` (Integer): Adultos mayores.
- `censo_demografico.embarazadas` (Integer): Mujeres en estado de gestación.
- `censo_demografico.personas_discapacidad` (Integer): Personas con limitaciones motoras o cognitivas.

### H. Asistencia Humanitaria (Sphere Standards / EDAN)
- `necesidades_humanitarias.requiere_albergue_inmediato` (Boolean)
- `necesidades_humanitarias.requiere_rescate_medico` (Boolean)
- `necesidades_humanitarias.requiere_agua_alimentos` (Boolean)
- `necesidades_humanitarias.colchon_3_4_qty` (Integer)
- `necesidades_humanitarias.colchon_doble_qty` (Integer)
- `necesidades_humanitarias.kit_limpieza_qty` (Integer)
- `necesidades_humanitarias.kit_bebe_qty` (Integer)
- `necesidades_humanitarias.kit_higiene_familiar_qty` (Integer)
- `necesidades_humanitarias.kit_cocina_qty` (Integer)
- `necesidades_humanitarias.asistencia_extra_descripcion` (String)

### I. Device KYC y Trazabilidad Forense
- `auditoria_kyc.installation_id` (String UUID): ID generado en la primera apertura de la app.
- `auditoria_kyc.es_dispositivo_fisico` (Boolean): Filtra emuladores y bots de PC.
- `auditoria_kyc.marca` / `modelo` (String): Hardware del celular (ej. Samsung Galaxy A54).
- `auditoria_kyc.sistema_operativo` (String): Versión de Android o iOS.
- `auditoria_kyc.nivel_bateria_pct` (Integer): Porcentaje de batería al enviar (alerta si está por apagarse).
- `auditoria_kyc.tipo_conexion` (Enum): `CELULAR`, `WIFI`, `OFFLINE_SYNC`.
- `auditoria_kyc.ip_origen` (String): Dirección IP capturada por AWS API Gateway.

---

## 3. Matriz de Equivalencias con SINAPROC ArcGIS FeatureServer

| Campo UDAM Canónico | Campo SINAPROC Survey123 | Tipo ArcGIS |
| :--- | :--- | :--- |
| `report_id` | `id_` | `esriFieldTypeString` |
| `timestamp` | `f_h_registro` / `fecha_de_situacion` | `esriFieldTypeDate` (Epoch ms) |
| `informante.nombre_completo` | `evaluador` | `esriFieldTypeString` |
| `informante.organizacion` | `institucion` | `esriFieldTypeString` |
| `ubicacion.coordenadas.lat` | `latitud` | `esriFieldTypeString` |
| `ubicacion.coordenadas.lng` | `longitud` | `esriFieldTypeString` |
| `ubicacion.provincia` | `provincia` | `esriFieldTypeString` |
| `ubicacion.distrito` | `distrito` | `esriFieldTypeString` |
| `ubicacion.corregimiento` | `corregimiento` | `esriFieldTypeString` |
| `ubicacion.calle_o_direccion` | `calle` | `esriFieldTypeString` |
| `titular_afectado.nombre_jefe_hogar` | `nombre_jefe` | `esriFieldTypeString` |
| `titular_afectado.documento_numero` | `cedula` / `pasaporte` | `esriFieldTypeString` |
| `titular_afectado.telefono_afectado` | `t_contacto` | `esriFieldTypeString` |
| `evaluacion_estructural.habitabilidad` | `t_d_infrestuctura` | `esriFieldTypeString` |
| `censo_demografico.total_ocupantes` | `t_miembros` | `esriFieldTypeDouble` |
| `censo_demografico.neonatos_0_2` | `t_neonatos` | `esriFieldTypeDouble` |
| `censo_demografico.ninos_3_12` | `t_ninos` | `esriFieldTypeDouble` |
| `censo_demografico.adultos_18_59` | `t_adultos` | `esriFieldTypeDouble` |
| `censo_demografico.adultos_mayores_60` | `t_a_mayores` | `esriFieldTypeDouble` |
| `censo_demografico.embarazadas` | `c_embarazadas` | `esriFieldTypeDouble` |
| `censo_demografico.personas_discapacidad` | `c_discapacitados` | `esriFieldTypeDouble` |
| `necesidades_humanitarias.colchon_doble_qty` | `colchon_doble` | `esriFieldTypeDouble` |
| `necesidades_humanitarias.kit_bebe_qty` | `k_bebe` | `esriFieldTypeDouble` |
| `necesidades_humanitarias.kit_limpieza_qty` | `k_limpieza` | `esriFieldTypeDouble` |
| `necesidades_humanitarias.kit_higiene_familiar_qty` | `h_familiar` | `esriFieldTypeDouble` |
| `necesidades_humanitarias.kit_cocina_qty` | `k_cocina` | `esriFieldTypeDouble` |
