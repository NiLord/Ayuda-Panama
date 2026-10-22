import 'package:flutter_test/flutter_test.dart';
import 'package:ayuda_los_santos/l10n/app_messages.dart';

void main() {
  group('AppMessages JSON & i18n Architecture Tests', () {
    test('Default in-memory fallback provides safe Spanish strings without rootBundle', () {
      final msg = AppMessages.current;
      expect(msg.appTitle, 'Ayuda Panamá');
      expect(msg.sendingReportTitle, 'Enviando Reporte');
      expect(msg.understood, 'Entendido');
      expect(msg.badgeReportApp, 'Reporte App');
      expect(msg.badgeSinaproc, 'SINAPROC');
      expect(msg.badgeMiviot, 'MIVIOT');
    });

    test('Interpolation replaces placeholders dynamically', () {
      final msg = AppMessages.current;
      expect(msg.uploadingImage(2, 5), 'Subiendo imagen 2 de 5...');
      expect(msg.syncedReportsSuccess(3), 'Se sincronizaron 3 reporte(s) exitosamente.');
      expect(msg.uploadOverlayNotice(15), contains('15s'));
      expect(msg.updatedSecondsAgo(20), 'Actualizado hace 20 seg');
      expect(msg.titularInfo('Fernando G.', '7-***-417'), 'Titular: Fernando G. • Cédula: 7-***-417');
    });

    test('Can load custom translations dynamically from JSON dictionary', () {
      final englishDictionary = {
        'app_title': 'Ayuda Panama',
        'sending_report_title': 'Submitting Report',
        'uploading_image': 'Uploading image {current} of {total}...',
        'synced_reports_success': 'Synced {count} report(s) successfully.',
      };

      AppMessages.loadFromMap(englishDictionary, language: 'en');
      final msg = AppMessages.current;

      expect(msg.currentLanguage, 'en');
      expect(msg.appTitle, 'Ayuda Panama');
      expect(msg.sendingReportTitle, 'Submitting Report');
      expect(msg.uploadingImage(1, 4), 'Uploading image 1 of 4...');
      expect(msg.syncedReportsSuccess(2), 'Synced 2 report(s) successfully.');

      // Restore Spanish for subsequent tests
      AppMessages.loadFromMap({}, language: 'es');
    });

    test('Gracefully returns key when translation key is missing', () {
      final msg = AppMessages.current;
      expect(msg.tr('non_existent_key'), 'non_existent_key');
    });
  });
}
