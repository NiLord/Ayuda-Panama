import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/disaster_report.dart';

class ApiService {
  /// URL base dinámica resuelta desde AppConfig (centralizada en AWS SSM)
  static String get baseUrl => AppConfig.apiBaseUrl;

  static const String apiKey = String.fromEnvironment(
    'API_KEY',
    defaultValue: '',
  );

  static const String apiSecret = String.fromEnvironment(
    'API_SECRET',
    defaultValue: '',
  );

  /// Cabeceras de autenticación requeridas por el Lambda Authorizer de API Gateway
  static Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    if (apiKey.isNotEmpty) 'x-api-key': apiKey,
    if (apiSecret.isNotEmpty) 'x-app-secret': apiSecret,
  };

  /// Envía un reporte de desastre a AWS API Gateway
  static Future<bool> submitReport(DisasterReport report) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/reports');
      final response = await http
          .post(
            url,
            headers: _authHeaders,
            body: jsonEncode(report.toJson()),
          )
          .timeout(const Duration(seconds: 8));

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Consulta los reportes públicos verificados desde AWS (soporta delta con since)
  static Future<Map<String, dynamic>?> fetchPublicReports({String? since}) async {
    try {
      final queryParam = (since != null && since.isNotEmpty)
          ? '?since=${Uri.encodeComponent(since)}'
          : '';
      final url = Uri.parse('$baseUrl/api/v1/reports/public$queryParam');
      final response = await http
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
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
      final url = Uri.parse('$baseUrl/api/v1/uploads/presign');
      final Map<String, dynamic> bodyData = {
        'report_id': reportId,
        'category': category,
        'extension': ext,
      };
      if (photoId != null) bodyData['photo_id'] = photoId;
      if (fileName != null) bodyData['file_name'] = fileName;

      final response = await http
          .post(
            url,
            headers: _authHeaders,
            body: jsonEncode(bodyData),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
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
}
