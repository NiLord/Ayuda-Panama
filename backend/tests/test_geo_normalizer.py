import unittest
from backend.src.utils.geo_normalizer import (
    homologar_provincia,
    homologar_distrito,
    format_clean_name,
    homologar_evaluador,
)


class TestGeoNormalizer(unittest.TestCase):
    def test_homologar_provincia(self):
        self.assertEqual(homologar_provincia("los_santos"), "Los Santos")
        self.assertEqual(homologar_provincia("cocle"), "Coclé")
        self.assertEqual(homologar_provincia("herrera"), "Herrera")
        self.assertEqual(homologar_provincia("panama_oeste"), "Panamá Oeste")
        self.assertEqual(homologar_provincia(None), "Los Santos")
        self.assertEqual(homologar_provincia(""), "Los Santos")

    def test_homologar_distrito(self):
        self.assertEqual(homologar_distrito("las_tablas"), "Las Tablas")
        self.assertEqual(homologar_distrito("tonosi"), "Tonosí")
        self.assertEqual(homologar_distrito("guarare"), "Guararé")
        self.assertEqual(homologar_distrito("chitre"), "Chitré")
        self.assertEqual(homologar_distrito("pese"), "Pesé")
        self.assertEqual(homologar_distrito(None), "")

    def test_format_clean_name(self):
        self.assertEqual(format_clean_name("el_cocal"), "El Cocal")
        self.assertEqual(format_clean_name("las_palmitas"), "Las Palmitas")
        self.assertEqual(format_clean_name("villa_de_los_santos"), "Villa de los Santos")
        self.assertEqual(format_clean_name("rio_hondo"), "Río Hondo")  # retains accents if present
        self.assertEqual(format_clean_name(""), "")
        self.assertEqual(format_clean_name("sin_dato"), "")

    def test_homologar_evaluador(self):
        self.assertEqual(homologar_evaluador("brigada_central"), "Brigada Central")
        self.assertEqual(homologar_evaluador("juan perez"), "Juan Perez")
        self.assertEqual(homologar_evaluador("sinaproc"), "Brigada SINAPROC")
        self.assertEqual(homologar_evaluador(""), "Brigada SINAPROC")
        self.assertEqual(homologar_evaluador(None), "Brigada SINAPROC")


if __name__ == "__main__":
    unittest.main()
