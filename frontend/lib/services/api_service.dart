import 'dart:convert';
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

  /// Consulta los reportes públicos verificados desde AWS
  static Future<Map<String, dynamic>?> fetchPublicReports() async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/reports/public');
      final response = await http
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 6));

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
    required String fileName,
    required String contentType,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/uploads/presign');
      final response = await http
          .post(
            url,
            headers: _authHeaders,
            body: jsonEncode({
              'file_name': fileName,
              'content_type': contentType,
            }),
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
}
