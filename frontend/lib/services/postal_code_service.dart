import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../utils/panama_text_normalizer.dart';

class PostalLocationResult {
  final String provincia;
  final String distrito;
  final String corregimiento;
  final String? poblado;
  final String? barrio;
  final String? codigoPostal;
  final String? codigoCompleto;

  PostalLocationResult({
    required this.provincia,
    required this.distrito,
    required this.corregimiento,
    this.poblado,
    this.barrio,
    this.codigoPostal,
    this.codigoCompleto,
  });

  /// Retorna el nombre de la comunidad o barrio preferido
  String get sectorOBarrio {
    if (barrio != null && barrio!.isNotEmpty) {
      return barrio!;
    }
    if (poblado != null && poblado!.isNotEmpty) {
      return poblado!;
    }
    return '';
  }
}

class PostalCodeService {
  static String get _baseUrl => AppConfig.postalCodeServiceUrl;

  /// Realiza la consulta de geocodificación inversa oficial a la API de Códigos Postales de Panamá.
  /// Retorna null si no hay conexión o si la consulta falla, permitiendo el fallback offline inmediato.
  static Future<PostalLocationResult?> lookup({
    required double lat,
    required double lng,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl?lat=$lat&lng=$lng');
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'User-Agent': 'Mozilla/5.0 (AyudaLosSantos Emergency App; Android/iOS)',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final provRaw = data['provincia']?['nombre'] as String?;
      final distRaw = data['distrito']?['nombre'] as String?;
      final corrRaw = data['corregimiento']?['nombre'] as String?;
      final poblRaw = data['poblado']?['nombre'] as String?;
      final barrRaw = data['barrio']?['nombre'] as String?;
      final postCode = data['postal']?['codigo'] as String?;
      final postFull = data['postal']?['codigo_completo'] as String?;

      if (provRaw == null || distRaw == null || corrRaw == null) {
        return null;
      }

      return PostalLocationResult(
        provincia: PanamaTextNormalizer.normalize(provRaw),
        distrito: PanamaTextNormalizer.normalize(distRaw),
        corregimiento: PanamaTextNormalizer.normalize(corrRaw),
        poblado: poblRaw != null ? PanamaTextNormalizer.normalize(poblRaw) : null,
        barrio: barrRaw != null ? PanamaTextNormalizer.normalize(barrRaw) : null,
        codigoPostal: postCode,
        codigoCompleto: postFull,
      );
    } catch (_) {
      // Captura TimeoutException, SocketException o caída de red sin bloquear la UI
      return null;
    }
  }
}
