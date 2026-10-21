"""
Unified Disaster Assessment Model (UDAM)
Modelo Canónico Unificado de Evaluación de Desastres

Basado en:
- ATC-20 (Post-Earthquake Safety Evaluation of Buildings)
- Normas Esfera (The Sphere Handbook)
- MIRA (UN OCHA Multi-Cluster Initial Rapid Assessment)
- INSARAG (International Search and Rescue Advisory Group)
- Metodología EDAN (CEPREDENAC / SINAPROC Panamá)
"""

from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from enum import Enum
from typing import List, Optional, Dict, Any
import uuid


class RolInformante(str, Enum):
    AFECTADO_DIRECTO = "AFECTADO_DIRECTO"
    VECINO_O_TERCERO = "VECINO_O_TERCERO"
    FAMILIAR_NO_RESIDENTE = "FAMILIAR_NO_RESIDENTE"
    VOLUNTARIO_BRIGADISTA = "VOLUNTARIO_BRIGADISTA"
    LIDER_COMUNITARIO = "LIDER_COMUNITARIO"
    FUNCIONARIO_ESTATAL = "FUNCIONARIO_ESTATAL"


class NivelHabitabilidad(str, Enum):
    """Clasificación según norma sísmica ATC-20"""
    HABITABLE = "HABITABLE"                      # Verde: Estructura segura, daños leves/nulos
    ACCESO_RESTRINGIDO = "ACCESO_RESTRINGIDO"    # Amarillo: Peligro localizado, solo ingreso temporal
    INHABITABLE = "INHABITABLE"                  # Rojo: Daño severo, riesgo de colapso, prohibido habitar
    COLAPSO_TOTAL = "COLAPSO_TOTAL"              # Estructura destruida


class PrioridadTriage(str, Enum):
    """Prioridad operativa de respuesta humanitaria"""
    P1_CRITICO_VIDA = "P1_CRITICO_VIDA"          # Personas atrapadas, lesionados graves, fuga de gas
    P2_URGENTE_ALBERGUE = "P2_URGENTE_ALBERGUE"  # Inhabitable, familias a la intemperie, sin agua
    P3_MONITOREO_ENSERES = "P3_MONITOREO_ENSERES"# Daños menores, habitable, reposición de bienes


class TipoInmueble(str, Enum):
    RESIDENCIAL_CASA = "RESIDENCIAL_CASA"
    RESIDENCIAL_EDIFICIO = "RESIDENCIAL_EDIFICIO"
    COMERCIAL = "COMERCIAL"
    ESCUELA_O_EDUCATIVO = "ESCUELA_O_EDUCATIVO"
    CENTRO_SALUD = "CENTRO_SALUD"
    OTRO = "OTRO"


class SistemaConstructivo(str, Enum):
    MAMPOSTERIA_BLOQUE = "MAMPOSTERIA_BLOQUE"
    HORMIGON_ARMADO = "HORMIGON_ARMADO"
    MADERA = "MADERA"
    ZINC_LAMINA = "ZINC_LAMINA"
    QUINCHA_ADOBE = "QUINCHA_ADOBE"
    MIXTO_OTRO = "MIXTO_OTRO"


@dataclass
class Informante:
    reporter_id: str
    rol: RolInformante
    nombre_completo: Optional[str] = None
    telefono_contacto: Optional[str] = None
    organizacion: Optional[str] = None
    esta_presente_en_el_sitio: bool = True
    relacion_con_afectado: Optional[str] = None


@dataclass
class TitularAfectado:
    es_el_mismo_informante: bool = True
    nombre_jefe_hogar: Optional[str] = None
    documento_tipo: str = "CEDULA"               # CEDULA, PASAPORTE, OTRO
    documento_numero: Optional[str] = None
    telefono_afectado: Optional[str] = None
    estado_familia: str = "EN_SITIO"             # EN_SITIO, EVACUADOS_CALLE, EN_ALBERGUE, HOSPITALIZADOS


@dataclass
class Coordenadas:
    lat: float
    lng: float
    precision_metros: Optional[float] = None
    altitud_metros: Optional[float] = None


@dataclass
class Ubicacion:
    coordenadas: Coordenadas
    provincia: str = "Los Santos"
    distrito: str = "Las Tablas"
    corregimiento: str = ""
    comunidad_sector: str = ""
    calle_o_direccion: str = ""
    punto_referencia: Optional[str] = None
    accesibilidad_vial: str = "TRANSITABLE"       # TRANSITABLE, BLOQUEADO_ESCOMBROS, SOLO_A_PIE, INUNDADO


@dataclass
class EvaluacionEstructural:
    tipo_inmueble: TipoInmueble = TipoInmueble.RESIDENCIAL_CASA
    sistema_constructivo: SistemaConstructivo = SistemaConstructivo.MAMPOSTERIA_BLOQUE
    habitabilidad: NivelHabitabilidad = NivelHabitabilidad.HABITABLE
    riesgo_colapso_inminente: bool = False
    danos_principales: List[str] = field(default_factory=list)
    descripcion_dano: Optional[str] = None


@dataclass
class ServiciosVitales:
    agua_potable: str = "NORMAL"                 # NORMAL, CONTAMINADA, SIN_SERVICIO
    electricidad: str = "NORMAL"                 # NORMAL, CORTE, CABLES_CAIDOS_PELIGRO
    saneamiento: str = "FUNCIONAL"               # FUNCIONAL, COLAPSADO
    fuga_gas: bool = False


@dataclass
class CensoDemografico:
    total_ocupantes: int = 1
    atrapados_o_desaparecidos: int = 0           # INSARAG P1 Search & Rescue
    lesionados_graves: int = 0
    neonatos_0_2: int = 0
    ninos_3_12: int = 0
    adolescentes_13_17: int = 0
    adultos_18_59: int = 1
    adultos_mayores_60: int = 0
    embarazadas: int = 0
    personas_discapacidad: int = 0


@dataclass
class NecesidadesHumanitarias:
    requiere_albergue_inmediato: bool = False
    requiere_rescate_medico: bool = False
    requiere_agua_alimentos: bool = False
    colchon_3_4_qty: int = 0
    colchon_doble_qty: int = 0
    kit_limpieza_qty: int = 0
    kit_bebe_qty: int = 0
    kit_higiene_familiar_qty: int = 0
    kit_cocina_qty: int = 0
    asistencia_extra_descripcion: Optional[str] = None


@dataclass
class AuditoriaDeviceKYC:
    installation_id: str
    es_dispositivo_fisico: bool = True
    marca: str = "Desconocido"
    modelo: str = "Desconocido"
    sistema_operativo: str = "Desconocido"
    app_version: str = "1.0.0"
    nivel_bateria_pct: Optional[int] = None
    esta_cargando: Optional[bool] = None
    tipo_conexion: str = "CELULAR"               # CELULAR, WIFI, OFFLINE_SYNC
    ip_origen: Optional[str] = None
    timestamp_creacion_local: Optional[str] = None
    timestamp_recepcion_aws: Optional[str] = None


@dataclass
class DisasterAssessment:
    report_id: str
    timestamp: str
    prioridad: PrioridadTriage
    consentimiento_informado: bool
    informante: Informante
    titular_afectado: TitularAfectado
    ubicacion: Ubicacion
    evaluacion_estructural: EvaluacionEstructural
    servicios_vitales: ServiciosVitales
    censo_demografico: CensoDemografico
    necesidades_humanitarias: NecesidadesHumanitarias
    auditoria_kyc: AuditoriaDeviceKYC
    fotos_urls: List[str] = field(default_factory=list)

    @classmethod
    def calcular_prioridad(
        cls,
        censo: CensoDemografico,
        servicios: ServiciosVitales,
        estructural: EvaluacionEstructural,
        necesidades: NecesidadesHumanitarias,
    ) -> PrioridadTriage:
        """Determina automáticamente el nivel de triage humanitario"""
        if (
            censo.atrapados_o_desaparecidos > 0
            or censo.lesionados_graves > 0
            or servicios.fuga_gas
            or estructural.riesgo_colapso_inminente
        ):
            return PrioridadTriage.P1_CRITICO_VIDA

        if (
            estructural.habitabilidad in (NivelHabitabilidad.INHABITABLE, NivelHabitabilidad.COLAPSO_TOTAL)
            or necesidades.requiere_albergue_inmediato
            or servicios.agua_potable == "SIN_SERVICIO"
            or censo.embarazadas > 0
            or censo.personas_discapacidad > 0
            or censo.neonatos_0_2 > 0
        ):
            return PrioridadTriage.P2_URGENTE_ALBERGUE

        return PrioridadTriage.P3_MONITOREO_ENSERES

    def to_dict(self) -> Dict[str, Any]:
        """Serializa el objeto completo a diccionario estándar (snake_case)"""
        data = asdict(self)
        data["prioridad"] = self.prioridad.value
        data["informante"]["rol"] = self.informante.rol.value
        data["evaluacion_estructural"]["tipo_inmueble"] = self.evaluacion_estructural.tipo_inmueble.value
        data["evaluacion_estructural"]["sistema_constructivo"] = self.evaluacion_estructural.sistema_constructivo.value
        data["evaluacion_estructural"]["habitabilidad"] = self.evaluacion_estructural.habitabilidad.value
        return data
