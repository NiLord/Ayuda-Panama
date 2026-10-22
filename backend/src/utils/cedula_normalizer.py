"""
Utilidades de validación, normalización y anonimización de Cédulas de Identidad Personal
de la República de Panamá, conforme a los formatos del Tribunal Electoral y Ley 81 de Protección de Datos.
"""

import re
from typing import Optional, Tuple


# Regex para formatos de cédula panameña:
# 1. Regulares: 1 a 13 (con o sin cero a la izquierda) seguido de tomo y asiento
# 2. Especiales: E, PE, N, AV, 1PI..4PI
CEDULA_PATTERN = re.compile(
    r'^(?:'
    r'(?P<prefijo>PE|E|N|AV|\d{1,2}PI|0?[1-9]|1[0-3])'
    r'[- ]+'
    r'(?P<tomo>\d{1,6})'
    r'[- ]+'
    r'(?P<asiento>\d{1,7})'
    r')$',
    re.IGNORECASE
)


def normalize_cedula(cedula_raw: Optional[str]) -> Optional[str]:
    """
    Normaliza una cédula panameña al formato estándar con guiones.
    Ejemplos:
      '7-71-1473'   -> '7-71-1473'
      '7 71 1473'   -> '7-71-1473'
      '07-0071-01473' -> '7-71-1473'
      'pe-1-1234'   -> 'PE-1-1234'
      'e-8-1234'    -> 'E-8-1234'
    Retorna None si la cédula no cumple con un formato válido.
    """
    if not cedula_raw or not isinstance(cedula_raw, str):
        return None

    cleaned = cedula_raw.strip().upper()
    # Reemplazar múltiples espacios o puntos por un único guion
    cleaned = re.sub(r'[\.\s_]+', '-', cleaned)

    match = CEDULA_PATTERN.match(cleaned)
    if not match:
        # Intentar rescatar si los números vienen sin ceros a la izquierda
        parts = [p for p in cleaned.split('-') if p]
        if len(parts) == 3:
            prefijo, tomo, asiento = parts
            prefijo = prefijo.upper()
            try:
                # Si el tomo y asiento son dígitos, quitar ceros no significativos
                tomo_clean = str(int(tomo))
                asiento_clean = str(int(asiento))
                candidate = f"{prefijo}-{tomo_clean}-{asiento_clean}"
                if CEDULA_PATTERN.match(candidate):
                    return candidate
            except ValueError:
                pass
        return None

    prefijo = match.group('prefijo').upper()
    tomo = str(int(match.group('tomo')))
    asiento = str(int(match.group('asiento')))

    # Si el prefijo es numérico con cero al inicio (ej: 07), limpiarlo
    if prefijo.isdigit():
        prefijo = str(int(prefijo))

    return f"{prefijo}-{tomo}-{asiento}"


def mask_cedula(cedula: Optional[str]) -> str:
    """
    Aplica censura de seguridad Ley 81 a una cédula panameña.
    Muestra solo el primer segmento y los últimos dígitos:
    Ejemplo: '7-708-417' -> '7-*****417'
             'PE-1-1234' -> 'PE-*****234'
    """
    if not cedula or not isinstance(cedula, str):
        return "Censurado"

    norm = normalize_cedula(cedula) or cedula.strip()
    parts = norm.split('-')
    if len(parts) >= 3:
        prefijo = parts[0]
        asiento = parts[-1]
        last_digits = asiento[-3:] if len(asiento) >= 3 else asiento
        return f"{prefijo}-*****{last_digits}"
    
    # Fallback si no tiene guiones
    if len(norm) > 4:
        return f"{norm[:2]}*****{norm[-3:]}"
    return "*****"


def mask_person_name(name: Optional[str]) -> str:
    """
    Censura un nombre según Ley 81, dejando el primer nombre y la inicial del primer apellido:
    Ejemplo: 'Juan Carlos Pérez' -> 'Juan P.'
             'María' -> 'María'
    """
    if not name or not isinstance(name, str):
        return "Residente"

    tokens = [t.strip().capitalize() for t in name.split() if t.strip()]
    if not tokens:
        return "Residente"
    if len(tokens) == 1:
        return tokens[0]
    
    primer_nombre = tokens[0]
    segundo_token_inicial = tokens[1][0].upper()
    return f"{primer_nombre} {segundo_token_inicial}."
