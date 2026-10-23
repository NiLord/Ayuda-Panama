"""
Unit tests for DisasterAssessment canonical model and adapters
Uses standard library unittest for zero external dependencies.
"""

import unittest
from datetime import datetime, timezone
from backend.src.models.disaster_assessment import (
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
from backend.src.adapters.sinaproc_adapter import SinaprocSurvey123Adapter


def create_sample_assessment():
    censo = CensoDemografico(
        total_ocupantes=4,
        atrapados_o_desaparecidos=1, # Provokes P1 triage
        lesionados_graves=0,
        neonatos_0_2=1,
        ninos_3_12=1,
        adolescentes_13_17=0,
        adultos_18_59=2,
        adultos_mayores_60=0,
        embarazadas=1,
        personas_discapacidad=0,
    )
    servicios = ServiciosVitales(
        agua_potable="SIN_SERVICIO",
        electricidad="CORTE",
        saneamiento="COLAPSADO",
        fuga_gas=True,
    )
    estructural = EvaluacionEstructural(
        tipo_inmueble=TipoInmueble.RESIDENCIAL_CASA,
        sistema_constructivo=SistemaConstructivo.MAMPOSTERIA_BLOQUE,
        habitabilidad=NivelHabitabilidad.INHABITABLE,
        riesgo_colapso_inminente=True,
        danos_principales=["MUROS_AGRIETADOS", "COLAPSO_TECHO"],
        descripcion_dano="Paredes laterales con grietas profundas y caída de tejas",
    )
    necesidades = NecesidadesHumanitarias(
        requiere_albergue_inmediato=True,
        requiere_rescate_medico=True,
        requiere_agua_alimentos=True,
        colchon_doble_qty=2,
        kit_limpieza_qty=1,
        kit_bebe_qty=1,
        kit_higiene_familiar_qty=1,
    )
    prioridad = DisasterAssessment.calcular_prioridad(censo, servicios, estructural, necesidades)

    return DisasterAssessment(
        report_id="rep_test_001",
        timestamp=datetime.now(timezone.utc).isoformat(),
        prioridad=prioridad,
        consentimiento_informado=True,
        informante=Informante(
            reporter_id="device_uuid_123",
            rol=RolInformante.VECINO_O_TERCERO,
            nombre_completo="Carlos Méndez",
            telefono_contacto="+507 6789-0123",
            organizacion="Junta Comunal Las Tablas",
            esta_presente_en_el_sitio=True,
        ),
        titular_afectado=TitularAfectado(
            es_el_mismo_informante=False,
            nombre_jefe_hogar="Señora Julia Ramos",
            documento_tipo="CEDULA",
            documento_numero="7-111-222",
            telefono_afectado="+507 6555-4321",
            estado_familia="EVACUADOS_CALLE",
        ),
        ubicacion=Ubicacion(
            coordenadas=Coordenadas(lat=7.625, lng=-80.354, precision_metros=6.0),
            provincia="Los Santos",
            distrito="Las Tablas",
            corregimiento="Las Tablas",
            comunidad_sector="Barrio Santa Librada",
            calle_o_direccion="Calle 8va",
        ),
        evaluacion_estructural=estructural,
        servicios_vitales=servicios,
        censo_demografico=censo,
        necesidades_humanitarias=necesidades,
        auditoria_kyc=AuditoriaDeviceKYC(
            installation_id="inst_xyz",
            es_dispositivo_fisico=True,
            marca="Motorola",
            modelo="Edge 40",
            sistema_operativo="Android 14",
            nivel_bateria_pct=25,
            tipo_conexion="CELULAR",
            ip_origen="190.140.10.5",
        ),
    )


class TestDisasterAssessmentAndAdapters(unittest.TestCase):
    def setUp(self):
        self.assessment = create_sample_assessment()

    def test_triage_priority_calculation(self):
        """Verifica que atrapados o fuga de gas disparen P1_CRITICO_VIDA"""
        self.assertEqual(self.assessment.prioridad, PrioridadTriage.P1_CRITICO_VIDA)

    def test_sinaproc_adapter_mapping(self):
        """Verifica el mapeo a los campos oficiales de SINAPROC Survey123"""
        attrs = SinaprocSurvey123Adapter.to_sinaproc_attributes(self.assessment)
        self.assertEqual(attrs["id_"], "rep_test_001")
        self.assertEqual(attrs["provincia"], "Los Santos")
        self.assertEqual(attrs["distrito"], "Las Tablas")
        self.assertEqual(attrs["nombre_jefe"], "Señora Julia Ramos")
        self.assertEqual(attrs["cedula"], "7-111-222")
        self.assertEqual(attrs["evaluador"], "Carlos Méndez")
        self.assertEqual(attrs["c_embarazadas"], 1.0)
        self.assertEqual(attrs["k_bebe"], 1.0)
        self.assertEqual(attrs["t_miembros"], 4.0)


if __name__ == "__main__":
    unittest.main()
