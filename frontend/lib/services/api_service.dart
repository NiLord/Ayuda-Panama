import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/disaster_report.dart';
import '../models/duplicate_check_result.dart';
import '../models/miviot_tramite_result.dart';

class ApiService {
  /// URL base dinámica resuelta desde AppConfig (centralizada en AWS SSM)
  static String get baseUrl => AppConfig.apiBaseUrl;

  static String get apiKey {
    const envKey = String.fromEnvironment('API_KEY', defaultValue: '');
    if (envKey.isNotEmpty) return envKey;
    return AppConfig.apiKey;
  }

  static String get apiSecret {
    const envSec = String.fromEnvironment('API_SECRET', defaultValue: '');
    if (envSec.isNotEmpty) return envSec;
    return AppConfig.apiSecret;
  }

  /// Cabeceras de autenticación requeridas por el Lambda Authorizer de API Gateway
  static Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    if (apiKey.isNotEmpty) 'x-api-key': apiKey,
    if (apiSecret.isNotEmpty) 'x-app-secret': apiSecret,
  };

  /// Helper para decodificar respuestas HTTP en UTF-8 garantizando la visualización correcta de tildes y caracteres especiales
  static String _decodeBody(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes);
    } catch (_) {
      return response.body;
    }
  }

  /// Ejecuta GET con fallback automático a AWS API Gateway si el dominio personalizado falla o da error
  static Future<http.Response> _getWithFallback(
    String pathAndQuery, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final primaryUri = Uri.parse('${AppConfig.apiBaseUrl}$pathAndQuery');
    final fallbackUri = Uri.parse('${AppConfig.httpApiRawEndpoint}$pathAndQuery');

    if (primaryUri != fallbackUri) {
      debugPrint('🌐 [API GET] Intentando: $primaryUri');
      try {
        final res = await http.get(primaryUri, headers: headers).timeout(const Duration(seconds: 3));
        debugPrint('📡 [API GET] Código devuelto por $primaryUri: ${res.statusCode}');
        if (res.statusCode == 200 || res.statusCode == 201) {
          return res;
        }
        debugPrint('⚠️ [API GET] Código no exitoso (${res.statusCode}) desde dominio principal. Activando fallback a AWS...');
      } catch (e) {
        debugPrint('⚠️ [API GET] Error en endpoint principal: $e');
      }
    }

    debugPrint('🔄 [API GET FALLBACK] Consultando endpoint directo: $fallbackUri');
    try {
      final fallbackRes = await http.get(fallbackUri, headers: headers).timeout(timeout);
      debugPrint('✅ [API GET FALLBACK] Código recibido: ${fallbackRes.statusCode} (${fallbackRes.body.length} bytes)');
      return fallbackRes;
    } catch (e) {
      debugPrint('💥 [API GET FALLBACK ERROR]: $e');
      rethrow;
    }
  }

  /// Ejecuta POST con fallback automático a AWS API Gateway si el dominio personalizado falla o da error
  static Future<http.Response> _postWithFallback(
    String pathAndQuery, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final primaryUri = Uri.parse('${AppConfig.apiBaseUrl}$pathAndQuery');
    try {
      final res = await http.post(primaryUri, headers: headers, body: body).timeout(timeout);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return res;
      }
    } catch (_) {}

    final fallbackUri = Uri.parse('${AppConfig.httpApiRawEndpoint}$pathAndQuery');
    return await http.post(fallbackUri, headers: headers, body: body).timeout(timeout);
  }

  /// Envía un reporte de desastre a AWS API Gateway
  static Future<bool> submitReport(DisasterReport report) async {
    try {
      final response = await _postWithFallback(
        '/api/v1/reports',
        headers: _authHeaders,
        body: jsonEncode(report.toJson()),
        timeout: const Duration(seconds: 8),
      );

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Consulta los reportes públicos verificados desde AWS (soporta paginación por lotes de 20 y cursor next_token)
  static Future<Map<String, dynamic>?> fetchPublicReports({
    String? since,
    int limit = 20,
    String? nextToken,
  }) async {
    try {
      final queryParams = <String>['limit=$limit'];
      if (since != null && since.isNotEmpty) {
        queryParams.add('since=${Uri.encodeComponent(since)}');
      }
      if (nextToken != null && nextToken.isNotEmpty) {
        queryParams.add('next_token=${Uri.encodeComponent(nextToken)}');
      }
      final queryString = '?${queryParams.join('&')}';

      final response = await _getWithFallback(
        '/api/v1/reports/public$queryString',
        headers: _authHeaders,
        timeout: const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        return jsonDecode(_decodeBody(response)) as Map<String, dynamic>;
      }
      debugPrint('⚠️ [API fetchPublicReports] Status code: ${response.statusCode}');
      return null;
    } catch (e, st) {
      debugPrint('💥 [API fetchPublicReports Error]: $e\n$st');
      return null;
    }
  }

  /// Solicita una URL presignada para subir una foto de evidencia a S3
  static Future<Map<String, dynamic>?> getPresignedUploadUrl({
    required String reportId,
    required String category, // 'danos' o 'identificacion'
    String extension = 'jpg',
    String? photoId,
    String? fileName,
  }) async {
    try {
      final ext = extension.replaceAll('.', '').toLowerCase();
      final Map<String, dynamic> bodyData = {
        'report_id': reportId,
        'category': category,
        'extension': ext,
      };
      if (photoId != null) bodyData['photo_id'] = photoId;
      if (fileName != null) bodyData['file_name'] = fileName;

      final response = await _postWithFallback(
        '/api/v1/uploads/presign',
        headers: _authHeaders,
        body: jsonEncode(bodyData),
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode == 200) {
        return jsonDecode(_decodeBody(response)) as Map<String, dynamic>;
      }
      debugPrint('⚠️ [API fetchPublicReports] Status code: ${response.statusCode}');
      return null;
    } catch (e, st) {
      debugPrint('💥 [API fetchPublicReports Error]: $e\n$st');
      return null;
    }
  }

  /// Sube un archivo local directamente a S3 usando la URL presignada
  /// Retorna la URL pública final de la imagen en S3, o null si falla
  static Future<String?> uploadPhotoToS3({
    required String reportId,
    required String localPath,
    required String category,
    String? photoId,
  }) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) return null;

      final extension = localPath.split('.').last.toLowerCase().replaceAll('.', '');
      final presignData = await getPresignedUploadUrl(
        reportId: reportId,
        category: category,
        extension: extension,
        photoId: photoId,
      );

      if (presignData == null) return null;

      final uploadUrl = presignData['upload_url'] as String?;
      final finalResourceUrl = presignData['final_resource_url'] as String?;
      if (uploadUrl == null) return null;

      final bytes = await file.readAsBytes();
      final mimeType = (extension == 'png')
          ? 'image/png'
          : (extension == 'webp')
              ? 'image/webp'
              : 'image/jpeg';

      final uploadResponse = await http
          .put(
            Uri.parse(uploadUrl),
            headers: {
              'Content-Type': mimeType,
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 30));

      if (uploadResponse.statusCode == 200) {
        return finalResourceUrl;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Verifica en tiempo real si ya existe una evaluación previa para la cédula en la App o SINAPROC
  static Future<DuplicateCheckResult> checkCedulaDuplicate(String cedula) async {
    try {
      final response = await _postWithFallback(
        '/api/v1/reports/check-duplicate',
        headers: _authHeaders,
        body: jsonEncode({'cedula': cedula}),
        timeout: const Duration(seconds: 12),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(_decodeBody(response)) as Map<String, dynamic>;
        return DuplicateCheckResult.fromJson(data);
      } else {
        final data = jsonDecode(_decodeBody(response)) as Map<String, dynamic>;
        return DuplicateCheckResult(
          success: false,
          existeDuplicado: false,
          cedula: cedula,
          cedulaCensurada: '',
          sistemas: [],
          detalles: [],
          mensaje: data['mensaje'] as String? ?? 'Error verificando cédula',
          error: data['error'] as String?,
        );
      }
    } catch (e) {
      return DuplicateCheckResult(
        success: false,
        existeDuplicado: false,
        cedula: cedula,
        cedulaCensurada: '',
        sistemas: [],
        detalles: [],
        mensaje: 'No fue posible validar la cédula por problemas de conexión.',
        error: e.toString(),
      );
    }
  }

  /// Consulta el expediente y avance en las 5 etapas del MIVIOT para una cédula
  static Future<MiviotTramiteResult?> fetchMiviotTramite(
    String cedula, {
    bool force = false,
  }) async {
    try {
      final forceParam = force ? '&force=true' : '';
      final response = await _getWithFallback(
        '/api/v1/tramites/miviot?cedula=${Uri.encodeComponent(cedula)}$forceParam',
        headers: _authHeaders,
        timeout: const Duration(seconds: 12),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(_decodeBody(response)) as Map<String, dynamic>;
        return MiviotTramiteResult.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
