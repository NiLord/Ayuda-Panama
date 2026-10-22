import 'package:flutter_test/flutter_test.dart';
import 'package:ayuda_los_santos/utils/panama_text_normalizer.dart';
import 'package:ayuda_los_santos/services/postal_code_service.dart';

void main() {
  group('PanamaTextNormalizer Tests', () {
    test('Expands abbreviations and normalizes whitespace', () {
      const raw = '  urb.   bosques   de la paz  ';
      final cleaned = PanamaTextNormalizer.normalize(raw);
      expect(cleaned, 'Urbanización Bosques de la Paz');
    });

    test('Normalizes street and avenue abbreviations', () {
      const raw = 'clle. 3ra, ave. central, brio. el carate';
      final cleaned = PanamaTextNormalizer.normalize(raw);
      expect(cleaned, 'Calle 3ra, Avenida Central, Barriada El Carate');
    });

    test('Preserves special abbreviations like P.H.', () {
      const raw = 'p.h. torres de cantabria, apto. 4b';
      final cleaned = PanamaTextNormalizer.normalize(raw);
      expect(cleaned, 'P.H. Torres de Cantabria, Apartamento 4b');
    });

    test('Handles empty and null inputs safely', () {
      expect(PanamaTextNormalizer.normalize(''), '');
      expect(PanamaTextNormalizer.normalize('   '), '');
      expect(PanamaTextNormalizer.normalize(null), '');
    });
  });

  group('PostalLocationResult Tests', () {
    test('Prioritizes barrio over poblado', () {
      final res = PostalLocationResult(
        provincia: 'Los Santos',
        distrito: 'Las Tablas',
        corregimiento: 'Valle Rico',
        poblado: 'Valle Rico Centro',
        barrio: 'Barrio Santa Librada',
        codigoPostal: 'J4199',
      );
      expect(res.sectorOBarrio, 'Barrio Santa Librada');
    });

    test('Falls back to poblado when barrio is empty', () {
      final res = PostalLocationResult(
        provincia: 'Los Santos',
        distrito: 'Las Tablas',
        corregimiento: 'Valle Rico',
        poblado: 'Valle Rico Centro',
        barrio: null,
      );
      expect(res.sectorOBarrio, 'Valle Rico Centro');
    });
  });
}
