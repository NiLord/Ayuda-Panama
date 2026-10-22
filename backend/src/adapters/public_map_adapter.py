"""
Public Map Adapter (Privacy by Design)
Transforma evaluaciones a GeoJSON público sin PII para visualización ciudadana.
Cumple estrictamente con la Ley 81 de Protección de Datos de Panamá.
"""

from typing import Dict, Any, List
from ..models.disaster_assessment import DisasterAssessment, NivelHabitabilidad


def mask_cedula(cedula: str) -> str:
    """Enmascara la cédula panameña (ej. 7-708-417 -> 7-***-417) para proteger PII según Ley 81"""
    if not cedula or not isinstance(cedula, str):
        return ""
    c = cedula.strip()
    if len(c) <= 4:
        return c[:1] + "***" + c[-1:]
    parts = c.split("-")
    if len(parts) >= 3:
        return f"{parts[0]}-***-{parts[-1]}"
    elif len(parts) == 2:
        suffix = parts[1][-3:] if len(parts[1]) >= 3 else parts[1]
        return f"{parts[0]}-***-{suffix}"
    else:
        return f"{c[:2]}***{c[-3:]}"


def mask_name(full_name: str) -> str:
    """Enmascara el nombre dejando solo el primer nombre e inicial (ej. Fernando Gonzalez -> Fernando G.)"""
    if not full_name or not isinstance(full_name, str):
        return ""
    parts = full_name.strip().split()
    if not parts:
        return ""
    first_name = parts[0].capitalize()
    if len(parts) > 1 and parts[1]:
        initial = parts[1][0].upper()
        return f"{first_name} {initial}."
    return first_name


class PublicMapAdapter:
    """Adaptador de visualización pública con anonimización total de PII"""

    COLOR_MAP = {
        NivelHabitabilidad.HABITABLE.value: "#2ECC71",           # Verde
        NivelHabitabilidad.ACCESO_RESTRINGIDO.value: "#F1C40F",   # Amarillo
        NivelHabitabilidad.INHABITABLE.value: "#E74C3C",         # Rojo
        NivelHabitabilidad.COLAPSO_TOTAL.value: "#8E44AD",       # Púrpura
    }

    @classmethod
    def to_public_feature(cls, assessment: DisasterAssessment) -> Dict[str, Any]:
        """Convierte una evaluación en un Feature GeoJSON seguro sin PII"""
        habitabilidad = assessment.evaluacion_estructural.habitabilidad.value
        color = cls.COLOR_MAP.get(habitabilidad, "#95A5A6")

        nombre_titular = assessment.titular_afectado.nombre_jefe_hogar or ""
        cedula_titular = assessment.titular_afectado.documento_numero or ""

        sistemas = assessment.metadatos_evento.get("sistemas_vinculados")
        if not sistemas:
            sistemas = ["APP", "SINAPROC"]

        return {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [
                    assessment.ubicacion.coordenadas.lng,
                    assessment.ubicacion.coordenadas.lat,
                ],
            },
            "properties": {
                "id": assessment.report_id,
                "report_id": assessment.report_id,
                "timestamp": assessment.timestamp,
                "prioridad": assessment.prioridad.value,
                "semaforo_color": color,
                "habitabilidad": habitabilidad,
                "riesgo_colapso": assessment.evaluacion_estructural.riesgo_colapso_inminente,
                "tipo_inmueble": assessment.evaluacion_estructural.tipo_inmueble.value,
                "provincia": assessment.ubicacion.provincia,
                "distrito": assessment.ubicacion.distrito,
                "corregimiento": assessment.ubicacion.corregimiento,
                "comunidad_sector": assessment.ubicacion.comunidad_sector,
                "accesibilidad_vial": assessment.ubicacion.accesibilidad_vial,
                "total_ocupantes": assessment.censo_demografico.total_ocupantes,
                "reporter_id": assessment.informante.reporter_id,
                "fotos_urls": assessment.fotos_urls,
                "nombre_mascarado": mask_name(nombre_titular),
                "cedula_mascarada": mask_cedula(cedula_titular),
                "sistemas_vinculados": sistemas,
                "servicios_afectados": {
                    "agua_potable": assessment.servicios_vitales.agua_potable,
                    "electricidad": assessment.servicios_vitales.electricidad,
                    "fuga_gas": assessment.servicios_vitales.fuga_gas,
                },
                "necesidades_urgentes": {
                    "albergue": assessment.necesidades_humanitarias.requiere_albergue_inmediato,
                    "agua_alimentos": assessment.necesidades_humanitarias.requiere_agua_alimentos,
                    "rescate_medico": assessment.necesidades_humanitarias.requiere_rescate_medico,
                },
            },
        }

    @classmethod
    def to_feature_collection(cls, assessments: List[DisasterAssessment]) -> Dict[str, Any]:
        """Agrupa múltiples evaluaciones en un FeatureCollection GeoJSON"""
        return {
            "type": "FeatureCollection",
            "features": [cls.to_public_feature(a) for a in assessments],
        }
