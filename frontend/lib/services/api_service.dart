import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/disaster_report.dart';

class ApiService {
  // En producción se sobreescribe con el output de CloudFormation
  static String baseUrl = 'https://lse-api-placeholder.execute-api.us-east-1.amazonaws.com';

  static Future<bool> submitReport(DisasterReport report) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/reports');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(report.toJson()),
          )
          .timeout(const Duration(seconds: 8));

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> fetchPublicReports() async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/reports/public');
      final response = await http.get(url).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
