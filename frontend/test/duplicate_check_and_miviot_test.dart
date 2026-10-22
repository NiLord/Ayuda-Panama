import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ayuda_los_santos/models/duplicate_check_result.dart';
import 'package:ayuda_los_santos/models/miviot_tramite_result.dart';
import 'package:ayuda_los_santos/services/duplicate_check_service.dart';
import 'package:ayuda_los_santos/widgets/miviot_tramite_dialog.dart';

void main() {
  group('DuplicateCheckResult Tests', () {
    test('Correctly parses positive duplicate check response', () {
      final json = {
        'success': true,
        'existe_duplicado': true,
        'cedula': '7-71-1473',
        'cedula_censurada': '7-*****473',
        'sistemas': ['SINAPROC', 'MIVIOT'],
        'detalles': [
          {
            'fuente': 'SINAPROC',
            'external_id': '10492',
            'estado': 'Evaluación oficial realizada',
          },
          {
            'fuente': 'MIVIOT',
            'reporte': 'AFV/07877',
            'estado': 'Evaluación Técnica en Sitio',
          }
        ],
        'tramite_miviot': {
          'reporte': 'AFV/07877',
          'paso_actual': 2,
          'estado_actual': 'Evaluación Técnica en Sitio',
        },
        'mensaje': 'Vivienda ya evaluada',
      };

      final result = DuplicateCheckResult.fromJson(json);
      expect(result.success, isTrue);
      expect(result.existeDuplicado, isTrue);
      expect(result.cedula, equals('7-71-1473'));
      expect(result.cedulaCensurada, equals('7-*****473'));
      expect(result.sistemas, contains('SINAPROC'));
      expect(result.sistemas, contains('MIVIOT'));
      expect(result.detalles.length, equals(2));
      expect(result.tramiteMiviot, isNotNull);
      expect(result.tramiteMiviot!['reporte'], equals('AFV/07877'));
    });

    test('Parses negative (no duplicate) response', () {
      final json = {
        'success': true,
        'existe_duplicado': false,
        'cedula': '8-123-4567',
        'cedula_censurada': '8-*****567',
        'sistemas': [],
        'detalles': [],
        'mensaje': 'Sin reportes previos',
      };

      final result = DuplicateCheckResult.fromJson(json);
      expect(result.success, isTrue);
      expect(result.existeDuplicado, isFalse);
      expect(result.sistemas, isEmpty);
      expect(result.tramiteMiviot, isNull);
    });

    test('DuplicateCheckResult.empty() provides safe non-blocking default', () {
      final empty = DuplicateCheckResult.empty();
      expect(empty.success, isTrue);
      expect(empty.existeDuplicado, isFalse);
      expect(empty.sistemas, isEmpty);
      expect(empty.cedula, isEmpty);
    });
  });

  group('MiviotTramiteResult Tests', () {
    test('Correctly parses active housing case with stages', () {
      final json = {
        'success': true,
        'encontrado': true,
        'origen': 'CACHE',
        'cedula': '7-71-1473',
        'cedula_censurada': '7-*****473',
        'reporte': 'AFV/07877',
        'fecha_recibido': '12/10/2026',
        'paso_actual': 2,
        'estado_actual': 'Evaluación Técnica en Sitio',
        'ultima_actualizacion': '2026-10-22T10:00:00Z',
        'mensaje': 'Localizado en MIVIOT',
      };

      final result = MiviotTramiteResult.fromJson(json);
      expect(result.success, isTrue);
      expect(result.encontrado, isTrue);
      expect(result.reporte, equals('AFV/07877'));
      expect(result.pasoActual, equals(2));
      expect(result.estadoActual, equals('Evaluación Técnica en Sitio'));
      expect(MiviotTramiteResult.etapasOficiales.length, equals(5));
      expect(MiviotTramiteResult.etapasOficiales[1], equals('Evaluación Técnica en Sitio'));
    });

    test('Handles non-found case gracefully', () {
      final json = {
        'success': true,
        'encontrado': false,
        'cedula': '8-999-999',
        'cedula_censurada': '8-*****999',
        'mensaje': 'No encontramos un reporte con esa cédula',
      };

      final result = MiviotTramiteResult.fromJson(json);
      expect(result.success, isTrue);
      expect(result.encontrado, isFalse);
      expect(result.reporte, isNull);
      expect(result.pasoActual, isNull);
    });
  });

  group('MiviotTramiteDialog Widget Tests', () {
    testWidgets('Renders MIVIOT dossier details and 5 steps', (tester) async {
      const result = MiviotTramiteResult(
        success: true,
        encontrado: true,
        cedula: '7-71-1473',
        cedulaCensurada: '7-*****473',
        reporte: 'AFV/07877',
        fechaRecibido: '12/10/2026',
        pasoActual: 2,
        estadoActual: 'Evaluación Técnica en Sitio',
        mensaje: 'Trámite activo',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MiviotTramiteDialog(
              cedula: '7-71-1473',
              initialResult: result,
            ),
          ),
        ),
      );

      expect(find.textContaining('AFV/07877'), findsWidgets);
      expect(find.text('Evaluación Técnica en Sitio'), findsWidgets);
      expect(find.text('Fase actual en ejecución'), findsOneWidget);
      expect(find.text('Recepción y Registro de Solicitud'), findsOneWidget);
      expect(find.text('Entrega de Ayuda o Vivienda Finalizada'), findsOneWidget);
    });
  });
}
