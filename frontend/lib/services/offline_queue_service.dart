import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/disaster_report.dart';
import 'api_service.dart';

class OfflineQueueService {
  static const _keyQueue = 'lse_offline_reports_queue';

  /// Guarda un reporte en la cola local
  static Future<void> enqueueReport(DisasterReport report) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> currentQueue = prefs.getStringList(_keyQueue) ?? [];

    final reportJsonStr = jsonEncode(report.toJson());
    currentQueue.add(reportJsonStr);

    await prefs.setStringList(_keyQueue, currentQueue);
  }

  /// Retorna la cantidad de reportes pendientes de sincronizar
  static Future<int> getPendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyQueue) ?? [];
    return list.length;
  }

  /// Intenta sincronizar todos los reportes pendientes con el backend en AWS
  static Future<int> flushQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> currentQueue = prefs.getStringList(_keyQueue) ?? [];

    if (currentQueue.isEmpty) return 0;

    final List<String> remainingQueue = [];
    int syncedCount = 0;

    for (final itemStr in currentQueue) {
      try {
        final map = jsonDecode(itemStr) as Map<String, dynamic>;
        final report = DisasterReport.fromJson(map);

        final success = await ApiService.submitReport(report);
        if (success) {
          syncedCount++;
        } else {
          remainingQueue.add(itemStr);
        }
      } catch (_) {
        remainingQueue.add(itemStr);
      }
    }

    await prefs.setStringList(_keyQueue, remainingQueue);
    return syncedCount;
  }
}
