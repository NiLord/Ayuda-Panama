import pytest
from backend.src.utils.cedula_normalizer import (
    normalize_cedula,
    mask_cedula,
    mask_person_name,
)


def test_normalize_cedula_standard():
    assert normalize_cedula("7-71-1473") == "7-71-1473"
    assert normalize_cedula("7 71 1473") == "7-71-1473"
    assert normalize_cedula("07-0071-01473") == "7-71-1473"
    assert normalize_cedula("8-765-4321") == "8-765-4321"
    assert normalize_cedula("13-1-234") == "13-1-234"


def test_normalize_cedula_special_prefixes():
    assert normalize_cedula("pe-1-1234") == "PE-1-1234"
    assert normalize_cedula("PE 1 1234") == "PE-1-1234"
    assert normalize_cedula("E-8-1234") == "E-8-1234"
    assert normalize_cedula("n-3-456") == "N-3-456"
    assert normalize_cedula("4pi-1-1234") == "4PI-1-1234"


def test_normalize_cedula_invalid():
    assert normalize_cedula(None) is None
    assert normalize_cedula("") is None
    assert normalize_cedula("invalid") is None
    assert normalize_cedula("12345") is None


def test_mask_cedula():
    assert mask_cedula("7-708-417") == "7-*****417"
    assert mask_cedula("7 708 417") == "7-*****417"
    assert mask_cedula("PE-1-1234") == "PE-*****234"
    assert mask_cedula(None) == "Censurado"


def test_mask_person_name():
    assert mask_person_name("Juan Pérez") == "Juan P."
    assert mask_person_name("Fernando Perez Secreto") == "Fernando P."
    assert mask_person_name("María González Gómez") == "María G."
    assert mask_person_name("Roberto") == "Roberto"
    assert mask_person_name(None) == "Residente"
    assert mask_person_name("") == "Residente"
