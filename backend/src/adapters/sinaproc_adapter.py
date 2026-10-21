"""
SINAPROC Survey123 Adapter
Transforma bidireccionalmente entre el Modelo Canónico (UDAM) y el esquema
oficial de SINAPROC ArcGIS FeatureServer (_3_de_formulario).
"""

from typing import Dict, Any
from datetime import datetime, timezone
from ..models.disaster_assessment import (
    DisasterAssessment,
    Informante,
    TitularAfectado,
    Ubicacion,
    Coordenadas,
    EvaluacionEstructural,
    ServiciosVitales,
    CensoDemografico,
    NecesidadesHumanitarias,
    AuditoriaDeviceKYC,
    RolInformante,
    NivelHabitabilidad,
    TipoInmueble,
    SistemaConstructivo,
    PrioridadTriage,
)


class SinaprocSurvey123Adapter:
    """Adaptador para exportación e ingesta compatible con SINAPROC ArcGIS Survey123"""

    @staticmethod
    def to_sinaproc_attributes(assessment: DisasterAssessment) -> Dict[str, Any]:
        """Convierte una evaluación canónica a los atributos exactos esperados por SINAPROC"""
        # Mapeo de fecha a milisegundos Epoch que usa ArcGIS
        try:
            dt = datetime.fromisoformat(assessment.timestamp.replace("Z", "+00:00"))
            epoch_ms = int(dt.timestamp() * 1000)
        except Exception:
            epoch_ms = int(datetime.now(timezone.utc).timestamp() * 1000)

        # Mapeo de habitabilidad a texto de daño de infraestructura
        tiene_dano = "No" if assessment.evaluacion_estructural.habitabilidad == NivelHabitabilidad.HABITABLE else "Sí"
        tipo_dano = assessment.evaluacion_estructural.habitabilidad.value

        # Identificación del evaluador
        evaluador_nombre = assessment.informante.nombre_completo or "Reporte Ciudadano Anónimo"
        institucion = assessment.informante.organizacion or f"Ciudadano ({assessment.informante.rol.value})"

        # Documento del jefe de hogar
        cedula = ""
        pasaporte = ""
        if assessment.titular_afectado.documento_tipo == "CEDULA":
            cedula = assessment.titular_afectado.documento_numero or ""
        elif assessment.titular_afectado.documento_tipo == "PASAPORTE":
            pasaporte = assessment.titular_afectado.documento_numero or ""

        return {
            "f_h_registro": epoch_ms,
            "evaluador": evaluador_nombre,
            "institucion": institucion,
            "id_": assessment.report_id,
            "situacion": "TERREMOTO / SISMO",
            "fecha_de_situacion": epoch_ms,
            "longitud": str(assessment.ubicacion.coordenadas.lng),
            "latitud": str(assessment.ubicacion.coordenadas.lat),
            "concordancia": "ALTA",
            "provincia": assessment.ubicacion.provincia,
            "distrito": assessment.ubicacion.distrito,
            "corregimiento": assessment.ubicacion.corregimiento,
            "comunidad": assessment.ubicacion.comunidad_sector,
            "sector_barrio": assessment.ubicacion.comunidad_sector,
            "calle": assessment.ubicacion.calle_o_direccion,
            "tipo_vivienda": assessment.evaluacion_estructural.tipo_inmueble.value,
            "t_afectacion": "SISMO",
            "tipo_construcion": assessment.evaluacion_estructural.sistema_constructivo.value,
            "d_infrestuctura": tiene_dano,
            "t_d_infrestuctura": tipo_dano,
            "descripcion_dano": assessment.evaluacion_estructural.descripcion_dano or "",
            "nombre_jefe": assessment.titular_afectado.nombre_jefe_hogar or "No especificado",
            "t_nip": assessment.titular_afectado.documento_tipo,
            "cedula": cedula,
            "pasaporte": pasaporte,
            "t_contacto": assessment.titular_afectado.telefono_afectado or assessment.informante.telefono_contacto or "",
            "t_neonatos": float(assessment.censo_demografico.neonatos_0_2),
            "t_ninos": float(assessment.censo_demografico.ninos_3_12),
            "t_adolescentes": float(assessment.censo_demografico.adolescentes_13_17),
            "t_adultos": float(assessment.censo_demografico.adultos_18_59),
            "t_a_mayores": float(assessment.censo_demografico.adultos_mayores_60),
            "t_miembros": float(assessment.censo_demografico.total_ocupantes),
            "embarazadas": "Sí" if assessment.censo_demografico.embarazadas > 0 else "No",
            "c_embarazadas": float(assessment.censo_demografico.embarazadas),
            "hay_discapacidad": "Sí" if assessment.censo_demografico.personas_discapacidad > 0 else "No",
            "c_discapacitados": float(assessment.censo_demografico.personas_discapacidad),
            "a_humanitaria": "Sí" if assessment.necesidades_humanitarias.requiere_albergue_inmediato or assessment.necesidades_humanitarias.requiere_agua_alimentos else "No",
            "colchon_3_4": float(assessment.necesidades_humanitarias.colchon_3_4_qty),
            "colchon_doble": float(assessment.necesidades_humanitarias.colchon_doble_qty),
            "k_limpieza": float(assessment.necesidades_humanitarias.kit_limpieza_qty),
            "k_bebe": float(assessment.necesidades_humanitarias.kit_bebe_qty),
            "h_familiar": float(assessment.necesidades_humanitarias.kit_higiene_familiar_qty),
            "k_cocina": float(assessment.necesidades_humanitarias.kit_cocina_qty),
            "a_extra": assessment.necesidades_humanitarias.asistencia_extra_descripcion or "",
            "comentario": f"Prioridad: {assessment.prioridad.value}. Habitabilidad: {assessment.evaluacion_estructural.habitabilidad.value}.",
        }

    @staticmethod
    def to_esri_feature(assessment: DisasterAssessment) -> Dict[str, Any]:
        """Produce un GeoJSON Feature compatible con Esri ArcGIS FeatureServer"""
        return {
            "geometry": {
                "x": assessment.ubicacion.coordenadas.lng,
                "y": assessment.ubicacion.coordenadas.lat,
                "spatialReference": {"wkid": 4326},
            },
            "attributes": SinaprocSurvey123Adapter.to_sinaproc_attributes(assessment),
        }
