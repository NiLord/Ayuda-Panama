import unittest
from backend.src.utils.cedula_normalizer import (
    normalize_cedula,
    mask_cedula,
    mask_person_name,
)


class TestCedulaNormalizer(unittest.TestCase):
    def test_normalize_cedula_standard(self):
        self.assertEqual(normalize_cedula("7-71-1473"), "7-71-1473")
        self.assertEqual(normalize_cedula("7 71 1473"), "7-71-1473")
        self.assertEqual(normalize_cedula("07-0071-01473"), "7-71-1473")
        self.assertEqual(normalize_cedula("8-765-4321"), "8-765-4321")
        self.assertEqual(normalize_cedula("13-1-234"), "13-1-234")

    def test_normalize_cedula_special_prefixes(self):
        self.assertEqual(normalize_cedula("pe-1-1234"), "PE-1-1234")
        self.assertEqual(normalize_cedula("PE 1 1234"), "PE-1-1234")
        self.assertEqual(normalize_cedula("E-8-1234"), "E-8-1234")
        self.assertEqual(normalize_cedula("n-3-456"), "N-3-456")
        self.assertEqual(normalize_cedula("4pi-1-1234"), "4PI-1-1234")

    def test_normalize_cedula_invalid(self):
        self.assertIsNone(normalize_cedula(None))
        self.assertIsNone(normalize_cedula(""))
        self.assertIsNone(normalize_cedula("invalid"))
        self.assertIsNone(normalize_cedula("12345"))

    def test_mask_cedula(self):
        self.assertEqual(mask_cedula("7-708-417"), "7-*****417")
        self.assertEqual(mask_cedula("7 708 417"), "7-*****417")
        self.assertEqual(mask_cedula("PE-1-1234"), "PE-*****234")
        self.assertEqual(mask_cedula(None), "Censurado")

    def test_mask_person_name(self):
        self.assertEqual(mask_person_name("Juan Pérez"), "Juan P.")
        self.assertEqual(mask_person_name("Fernando Perez Secreto"), "Fernando P.")
        self.assertEqual(mask_person_name("María González Gómez"), "María G.")
        self.assertEqual(mask_person_name("Roberto"), "Roberto")
        self.assertEqual(mask_person_name(None), "Residente")
        self.assertEqual(mask_person_name(""), "Residente")
