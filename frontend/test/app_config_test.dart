import 'package:flutter_test/flutter_test.dart';
import 'package:ayuda_los_santos/config/app_config.dart';

void main() {
  group('AppConfig & Multi-Event Vector Tests', () {
    test('Has default event code and default disaster event configured', () {
      expect(AppConfig.defaultEventCode, 'SISMO_OCTUBRE_2026');
      final defEvt = AppConfig.defaultEvent;
      expect(defEvt.codigo, 'SISMO_OCTUBRE_2026');
      expect(defEvt.tipo, 'TERREMOTO');
      expect(defEvt.nombre, contains('Sismo Octubre 2026'));
      expect(defEvt.activo, isTrue);
    });

    test('Available events vector supports extensible disaster types', () {
      expect(AppConfig.availableEvents, isNotEmpty);
      expect(AppConfig.availableEvents.length, greaterThanOrEqualTo(1));

      final activeEvents = AppConfig.activeEvents;
      expect(activeEvents.any((e) => e.codigo == 'SISMO_OCTUBRE_2026'), isTrue);
    });

    test('DisasterEvent serialization and deserialization works cleanly', () {
      final customEvent = DisasterEvent(
        codigo: 'HURACAN_CARIBE_2026',
        nombre: 'Huracán Caribe 2026',
        tipo: 'HURACAN',
        descripcion: 'Vientos sostenidos y lluvias en la vertiente atlántica',
        activo: true,
      );

      final json = customEvent.toJson();
      expect(json['codigo'], 'HURACAN_CARIBE_2026');
      expect(json['tipo'], 'HURACAN');

      final parsed = DisasterEvent.fromJson(json);
      expect(parsed.codigo, customEvent.codigo);
      expect(parsed.nombre, customEvent.nombre);
      expect(parsed.tipo, customEvent.tipo);
      expect(parsed.activo, isTrue);
    });

    test('Environment is configured properly', () {
      expect(AppConfig.environment, 'prod');
    });
  });
}
