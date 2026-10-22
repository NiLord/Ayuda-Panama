/// Normalizador inteligente de direcciones y barrios para Panamá.
/// Limpia espacios, expande abreviaturas comunes y aplica formato Title Case
/// respetando las reglas toponímicas de Panamá y preposiciones en español.
class PanamaTextNormalizer {
  static const Set<String> _preposiciones = {
    'de',
    'del',
    'y',
    'en',
    'a',
    'al',
  };

  static const Set<String> _articulos = {
    'el',
    'la',
    'los',
    'las',
  };

  /// Diccionario de abreviaturas panameñas comunes y su forma canónica
  static final Map<RegExp, String> _abreviaturas = {
    RegExp(r'\b(urb|urbanizacion)\b\.?', caseSensitive: false): 'Urbanización',
    RegExp(r'\b(res|residencial)\b\.?', caseSensitive: false): 'Residencial',
    RegExp(r'\b(brio|barrio|bda|barriada)\b\.?', caseSensitive: false): 'Barriada',
    RegExp(r'\b(clle|calle)\b\.?', caseSensitive: false): 'Calle',
    RegExp(r'\b(ave|avenida)\b\.?', caseSensitive: false): 'Avenida',
    RegExp(r'\b(ph|p\.h\.)\b\.?', caseSensitive: false): 'P.H.',
    RegExp(r'\b(apto|apt|apartamento)\b\.?', caseSensitive: false): 'Apartamento',
    RegExp(r'\b(km)\b\.?', caseSensitive: false): 'Km',
    RegExp(r'\b(no|num)\b\.?', caseSensitive: false): '#',
  };

  /// Normaliza una cadena de texto (barrio, comunidad, calle o dirección)
  static String normalize(String? input) {
    if (input == null || input.trim().isEmpty) return '';

    // 1. Eliminar espacios iniciales, finales y duplicados
    String text = input.trim().replaceAll(RegExp(r'\s+'), ' ');

    // 2. Expandir abreviaturas comunes
    for (final entry in _abreviaturas.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    // 3. Aplicar Title Case inteligente
    final words = text.split(' ');
    final normalizedWords = <String>[];

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.isEmpty) continue;

      // Limpiar puntuación para comparar
      final cleanWord = word.replaceAll(RegExp(r'[,.]'), '').toLowerCase();

      // Caso especial P.H.
      if (word.toUpperCase() == 'P.H.' || word.toUpperCase() == 'PH' || word.toUpperCase() == 'P.H') {
        normalizedWords.add('P.H.');
        continue;
      }

      // Preposiciones puras ('de', 'del', 'y', 'en') en minúscula si no es la primera palabra
      if (i > 0 && _preposiciones.contains(cleanWord)) {
        normalizedWords.add(cleanWord + (word.endsWith(',') ? ',' : ''));
        continue;
      }

      // Artículos ('el', 'la', 'los', 'las'): en minúscula solo si van precedidos de una preposición (ej. "de la Paz")
      if (i > 0 && _articulos.contains(cleanWord)) {
        final prevClean = words[i - 1].replaceAll(RegExp(r'[,.]'), '').toLowerCase();
        if (_preposiciones.contains(prevClean)) {
          normalizedWords.add(cleanWord + (word.endsWith(',') ? ',' : ''));
          continue;
        }
      }

      // Capitalizar primera letra para nombres propios y topónimos
      final lower = word.toLowerCase();
      final capitalized = lower[0].toUpperCase() + lower.substring(1);
      normalizedWords.add(capitalized);
    }

    return normalizedWords.join(' ');
  }
}
