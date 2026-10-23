"""
Geo Normalizer for Panamanian Administrative Divisions (DPA)
Homologa nombres de provincias, distritos, corregimientos y evaluadores
desde fuentes externas (ArcGIS SINAPROC snake_case) a nombres oficiales en Title Case.
"""

from typing import Optional
import unicodedata

PROVINCIAS_HOMOLOGADOS = {
    "los_santos": "Los Santos",
    "herrera": "Herrera",
    "cocle": "Coclé",
    "veraguas": "Veraguas",
    "colon": "Colón",
    "panama_oeste": "Panamá Oeste",
    "panama": "Panamá",
    "chiriqui": "Chiriquí",
    "bocas_del_toro": "Bocas del Toro",
    "c_ngabe_bugle": "Comarca Ngäbe Buglé",
    "ngabe_bugle": "Comarca Ngäbe Buglé",
    "darien": "Darién",
    "c_guna_yala": "Comarca Guna Yala",
    "guna_yala": "Comarca Guna Yala",
    "c_naso_tjer_di": "Comarca Naso Tjër Di",
    "naso_tjer_di": "Comarca Naso Tjër Di",
    "embera_wounaan": "Comarca Emberá Wounaan",
}

DISTRITOS_HOMOLOGADOS = {
    # Los Santos
    "las_tablas": "Las Tablas",
    "tonosi": "Tonosí",
    "los_santos": "Los Santos",
    "guarare": "Guararé",
    "macaracas": "Macaracas",
    "pedasi": "Pedasí",
    "pocri": "Pocrí",
    # Herrera
    "chitre": "Chitré",
    "las_minas": "Las Minas",
    "los_pozos": "Los Pozos",
    "ocu": "Ocú",
    "parita": "Parita",
    "pese": "Pesé",
    "santa_maria": "Santa María",
    # Coclé
    "aguadulce": "Aguadulce",
    "anton": "Antón",
    "la_pintada": "La Pintada",
    "nata": "Natá",
    "ola": "Olá",
    "penonome": "Penonomé",
    # Veraguas
    "santiago": "Santiago",
    "atalaya": "Atalaya",
    "calobre": "Calobre",
    "canazas": "Cañazas",
    "la_mesa": "La Mesa",
    "las_palmas": "Las Palmas",
    "montijo": "Montijo",
    "rio_de_jesus": "Río de Jesús",
    "san_francisco": "San Francisco",
    "santa_fe": "Santa Fe",
    "sona": "Soná",
    "mariato": "Mariato",
    # Panamá y Colón
    "panama": "Panamá",
    "san_miguelito": "San Miguelito",
    "chepo": "Chepo",
    "chiman": "Chimán",
    "taboga": "Taboga",
    "balboa": "Balboa",
    "colon": "Colón",
    "chagres": "Chagres",
    "donoso": "Donoso",
    "portobelo": "Portobelo",
    "santa_isabel": "Santa Isabel",
    # Panamá Oeste
    "la_chorrera": "La Chorrera",
    "arraijan": "Arraiján",
    "capira": "Capira",
    "chame": "Chame",
    "san_carlos": "San Carlos",
    # Chiriquí
    "david": "David",
    "alanje": "Alanje",
    "barqueta": "Barqueta",
    "baru": "Barú",
    "boqueron": "Boquerón",
    "boquete": "Boquete",
    "bugaba": "Bugaba",
    "dolega": "Dolega",
    "gualaca": "Gualaca",
    "remedio": "Remedios",
    "renacimiento": "Renacimiento",
    "san_felix": "San Félix",
    "san_lorenzo": "San Lorenzo",
    "tierras_altas": "Tierras Altas",
    "tolé": "Tolé",
    "tole": "Tolé",
}

PREPOSICIONES = {"de", "del", "y", "en", "a", "al", "la", "las", "el", "los"}
COMMON_ACCENT_WORDS = {
    "rio": "Río",
    "bahia": "Bahía",
    "rincon": "Rincón",
    "maria": "María",
    "jose": "José",
    "jesus": "Jesús",
    "martin": "Martín",
    "union": "Unión",
    "colon": "Colón",
    "panama": "Panamá",
    "chitre": "Chitré",
    "canazas": "Cañazas",
    "guarare": "Guararé",
    "tonosi": "Tonosí",
    "pocri": "Pocrí",
    "pedasi": "Pedasí",
    "ocu": "Ocú",
    "pese": "Pesé",
    "sona": "Soná",
}
IGNORED_PLACEHOLDERS = {
    "none", "null", "undefined", "0", "-", ".", "sin_dato", "desconocido", "n/a", "na"
}


def _strip_accents(s: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn"
    )


def format_clean_name(name: Optional[str]) -> str:
    """Limpia nombres con guiones bajos o formato crudo y aplica Title Case inteligente."""
    if not name:
        return ""
    val_str = str(name).strip().strip("_")
    if val_str.lower() in IGNORED_PLACEHOLDERS:
        return ""
    cleaned = val_str.replace("_", " ")
    words = cleaned.split()
    if not words:
        return ""

    result = []
    for i, w in enumerate(words):
        lw = w.lower()
        if i > 0 and lw in PREPOSICIONES:
            result.append(lw)
        elif lw in COMMON_ACCENT_WORDS:
            result.append(COMMON_ACCENT_WORDS[lw])
        else:
            result.append(w.capitalize())
    return " ".join(result)


def homologar_provincia(val: Optional[str]) -> str:
    """Homologa el identificador de provincia al nombre oficial con tildes y mayúsculas."""
    if not val:
        return "Los Santos"
    val_str = str(val).strip()
    if val_str.lower() in IGNORED_PLACEHOLDERS:
        return "Los Santos"
    key = val_str.lower().replace(" ", "_")
    key_no_accents = _strip_accents(key)
    return (
        PROVINCIAS_HOMOLOGADOS.get(key)
        or PROVINCIAS_HOMOLOGADOS.get(key_no_accents)
        or format_clean_name(val)
    )


def homologar_distrito(val: Optional[str]) -> str:
    """Homologa el identificador de distrito al nombre oficial con tildes y mayúsculas."""
    if not val:
        return ""
    val_str = str(val).strip()
    if val_str.lower() in IGNORED_PLACEHOLDERS:
        return ""
    key = val_str.lower().replace(" ", "_")
    key_no_accents = _strip_accents(key)
    return (
        DISTRITOS_HOMOLOGADOS.get(key)
        or DISTRITOS_HOMOLOGADOS.get(key_no_accents)
        or format_clean_name(val)
    )


def homologar_evaluador(name: Optional[str]) -> str:
    """Limpia y capitaliza nombres de evaluadores oficiales de SINAPROC."""
    if not name:
        return "Brigada SINAPROC"
    val_str = str(name).strip()
    if val_str.lower() in IGNORED_PLACEHOLDERS or val_str.lower() == "sinaproc":
        return "Brigada SINAPROC"
    cleaned = val_str.replace("_", " ")
    parts = cleaned.split()
    return " ".join(p.capitalize() for p in parts)
