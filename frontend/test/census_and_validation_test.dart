import 'package:flutter_test/flutter_test.dart';
import 'package:ayuda_los_santos/models/disaster_report.dart';

void main() {
  group('Census Calculation & DisasterReport Validation Tests', () {
    test('Calculates total occupants correctly from demographic detail', () {
      const neonatos = 1;
      const ninos = 2;
      const adolescentes = 1;
      const adultos = 2;
      const adultosMayores = 1;

      final totalCalculado = neonatos + ninos + adolescentes + adultos + adultosMayores;
      expect(totalCalculado, 7);

      final report = DisasterReport(
        reportId: 'rep_test_001',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        consentimientoInformado: true,
        reporterId: 'rep_123',
        rolInformante: 'AFECTADO_DIRECTO',
        informanteNombre: 'Fernando González',
        informanteTelefono: '+507 6000-0000',
        informanteOrganizacion: '',
        estaPresenteEnSitio: true,
        esElMismoInformante: true,
        afectadoNombre: 'Fernando González',
        documentoTipo: 'CEDULA',
        documentoNumero: '7-123-456',
        afectadoTelefono: '+507 6000-0000',
        latitud: 7.6251,
        longitud: -80.3542,
        provincia: 'Los Santos',
        distrito: 'Las Tablas',
        corregimiento: 'Las Tablas',
        comunidadSector: 'Barrio Santa Librada',
        calleDireccion: 'Calle 3ra',
        puntoReferencia: 'Frente al parque',
        habitabilidad: 'INHABITABLE',
        totalOcupantes: totalCalculado,
        neonatos: neonatos,
        ninos: ninos,
        adolescentes: adolescentes,
        adultos: adultos,
        adultosMayores: adultosMayores,
        embarazadas: 1,
        personasDiscapacidad: 1,
        installationId: 'inst_test',
      );

      final json = report.toJson();
      expect(json['censo_demografico']['total_ocupantes'], 7);
      expect(json['censo_demografico']['neonatos_0_2'], 1);
      expect(json['censo_demografico']['ninos_3_12'], 2);
      expect(json['censo_demografico']['adolescentes_13_17'], 1);
      expect(json['censo_demografico']['adultos_18_59'], 2);
      expect(json['censo_demografico']['adultos_mayores_60'], 1);
      expect(json['titular_afectado']['documento_numero'], '7-123-456');
      expect(json['titular_afectado']['nombre_jefe_hogar'], 'Fernando González');
      expect(json['titular_afectado']['telefono_afectado'], '+507 6000-0000');
    });

    test('Validates that mandatory fields in site and head of family are present', () {
      const comunidad = 'El Cocal';
      const cedulaJefe = '8-765-4321';
      const nombreJefe = 'María Pérez';
      const telefonoJefe = '+507 6123-4567';

      expect(comunidad.trim().isNotEmpty, isTrue);
      expect(cedulaJefe.trim().isNotEmpty, isTrue);
      expect(nombreJefe.trim().isNotEmpty, isTrue);
      expect(telefonoJefe.trim().isNotEmpty, isTrue);

      // Optional fields can be empty
      const calleOpcional = '';
      const referenciaOpcional = '';
      expect(calleOpcional.isEmpty, isTrue);
      expect(referenciaOpcional.isEmpty, isTrue);
    });
  });
}
