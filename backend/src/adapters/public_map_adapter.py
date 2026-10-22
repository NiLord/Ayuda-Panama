"""
Public Map Adapter (Privacy by Design)
Transforma evaluaciones y reportes externos a GeoJSON público sin PII para visualización ciudadana.
Cumple estrictamente con la Ley 81 de Protección de Datos de Panamá.
"""

from decimal import Decimal
from typing import Dict, Any, List, Optional
from ..models.disaster_assessment import DisasterAssessment, NivelHabitabilidad
from ..utils.cedula_normalizer import mask_cedula as normalizer_mask_cedula, mask_person_name as normalizer_mask_name
from ..utils.geo_normalizer import (
    homologar_provincia,
    homologar_distrito,
    format_clean_name,
    homologar_evaluador,
)


def mask_cedula(cedula: str) -> str:
    """Enmascara la cédula panameña (ej. 7-708-417 -> 7-*****417) para proteger PII según Ley 81"""
    return normalizer_mask_cedula(cedula)


def mask_name(full_name: str) -> str:
    """Enmascara el nombre dejando solo el primer nombre e inicial (ej. Fernando Gonzalez -> Fernando G.)"""
    return normalizer_mask_name(full_name)


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
        """Convierte una evaluación de la App en un Feature GeoJSON seguro sin PII"""
        habitabilidad = assessment.evaluacion_estructural.habitabilidad.value
        color = cls.COLOR_MAP.get(habitabilidad, "#95A5A6")

        nombre_titular = assessment.titular_afectado.nombre_jefe_hogar or ""
        cedula_titular = assessment.titular_afectado.documento_numero or ""

        sistemas = assessment.metadatos_evento.get("sistemas_vinculados")
        if not sistemas:
            sistemas = ["APP"]

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
                "fuente": "APP",
                "timestamp": assessment.timestamp,
                "prioridad": assessment.prioridad.value,
                "semaforo_color": color,
                "habitabilidad": habitabilidad,
                "riesgo_colapso": assessment.evaluacion_estructural.riesgo_colapso_inminente,
                "tipo_inmueble": assessment.evaluacion_estructural.tipo_inmueble.value,
                "provincia": homologar_provincia(assessment.ubicacion.provincia),
                "distrito": homologar_distrito(assessment.ubicacion.distrito),
                "corregimiento": format_clean_name(assessment.ubicacion.corregimiento),
                "comunidad_sector": format_clean_name(assessment.ubicacion.comunidad_sector),
                "accesibilidad_vial": assessment.ubicacion.accesibilidad_vial,
                "total_ocupantes": assessment.censo_demografico.total_ocupantes,
                "reporter_id": homologar_evaluador(assessment.informante.reporter_id) if assessment.informante.reporter_id else "Residente",
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
    def to_public_feature_from_external(cls, item: Dict[str, Any]) -> Dict[str, Any]:
        """Convierte un ítem de ExternalReportsTable (SINAPROC EDAN) en Feature GeoJSON"""
        habitabilidad = item.get("habitabilidad", "HABITABLE")
        color = cls.COLOR_MAP.get(habitabilidad, "#95A5A6")

        coords = item.get("ubicacion", {}).get("coordenadas", {})
        lat = float(coords.get("lat", 7.625)) if coords.get("lat") is not None else 7.625
        lng = float(coords.get("lng", -80.354)) if coords.get("lng") is not None else -80.354

        ext_id = item.get("external_id") or item.get("PK", "").replace("SINAPROC#", "")
        fuente = item.get("fuente", "SINAPROC")

        ubicacion = item.get("ubicacion") or {}
        provincia = homologar_provincia(ubicacion.get("provincia", "Los Santos"))
        distrito = homologar_distrito(ubicacion.get("distrito", "Las Tablas"))
        corregimiento = format_clean_name(ubicacion.get("corregimiento", ""))
        comunidad_sector = format_clean_name(ubicacion.get("comunidad_sector", ""))
        evaluador = homologar_evaluador(item.get("evaluador", "SINAPROC"))

        total_ocupantes = item.get("total_afectados")
        if total_ocupantes is None or not str(total_ocupantes).isdigit():
            total_ocupantes = 1
        else:
            total_ocupantes = int(total_ocupantes)

        return {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [lng, lat],
            },
            "properties": {
                "id": f"{fuente}_{ext_id}",
                "report_id": f"sinaproc_{ext_id}",
                "external_id": ext_id,
                "fuente": fuente,
                "timestamp": item.get("timestamp", ""),
                "prioridad": "P2_URGENTE_ALBERGUE" if habitabilidad in ["INHABITABLE", "COLAPSO_TOTAL"] else "P3_MONITOREO_ENSERES",
                "semaforo_color": color,
                "habitabilidad": habitabilidad,
                "riesgo_colapso": habitabilidad in ["INHABITABLE", "COLAPSO_TOTAL"],
                "tipo_inmueble": "RESIDENCIAL_CASA",
                "provincia": provincia,
                "distrito": distrito,
                "corregimiento": corregimiento,
                "comunidad_sector": comunidad_sector,
                "accesibilidad_vial": "TRANSITABLE",
                "total_ocupantes": total_ocupantes,
                "reporter_id": evaluador,
                "fotos_urls": [],
                "nombre_mascarado": item.get("nombre_titular_censurado") or "Residente",
                "cedula_mascarada": item.get("cedula_censurada") or "7-*****000",
                "sistemas_vinculados": [fuente],
                "servicios_afectados": {
                    "agua_potable": "NORMAL",
                    "electricidad": "NORMAL",
                    "fuga_gas": False,
                },
                "necesidades_urgentes": {
                    "albergue": habitabilidad in ["INHABITABLE", "COLAPSO_TOTAL"],
                    "agua_alimentos": False,
                    "rescate_medico": False,
                },
            },
        }

    @classmethod
    def to_feature_collection(
        cls,
        assessments: Optional[List[DisasterAssessment]] = None,
        external_items: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        """Agrupa evaluaciones de la App y reportes externos en un FeatureCollection GeoJSON consolidado"""
        features = []
        if assessments:
            features.extend([cls.to_public_feature(a) for a in assessments])
        if external_items:
            features.extend([cls.to_public_feature_from_external(it) for it in external_items])

        return {
            "type": "FeatureCollection",
            "features": features,
        }
