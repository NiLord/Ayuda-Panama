import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/disaster_report.dart';
import 'api_service.dart';

class LocalReportEntry {
  final DisasterReport report;
  final bool isSynced;

  LocalReportEntry({required this.report, required this.isSynced});
}

class OfflineQueueService {
  static const _keyQueue = 'lse_offline_reports_queue';
  static const _keyLocalCache = 'lse_local_reports_cache';

  /// Guarda o actualiza un reporte en el registro local del dispositivo
  static Future<void> saveLocalReport(DisasterReport report, {required bool isSynced}) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Guardar en caché histórico local
    final cacheMapRaw = prefs.getString(_keyLocalCache);
    Map<String, dynamic> cacheMap = {};
    if (cacheMapRaw != null && cacheMapRaw.isNotEmpty) {
      try {
        cacheMap = jsonDecode(cacheMapRaw) as Map<String, dynamic>;
      } catch (_) {}
    }

    cacheMap[report.reportId] = {
      'report': report.toJson(),
      'is_synced': isSynced,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    await prefs.setString(_keyLocalCache, jsonEncode(cacheMap));

    // 2. Gestionar la cola de sincronización pendiente
    final List<String> currentQueue = prefs.getStringList(_keyQueue) ?? [];
    // Remover versión previa si existía en cola
    currentQueue.removeWhere((itemStr) {
      try {
        final m = jsonDecode(itemStr) as Map<String, dynamic>;
        return m['report_id'] == report.reportId;
      } catch (_) {
        return false;
      }
    });

    if (!isSynced) {
      currentQueue.add(jsonEncode(report.toJson()));
    }

    await prefs.setStringList(_keyQueue, currentQueue);
  }

  /// Guarda un reporte directamente en la cola offline
  static Future<void> enqueueReport(DisasterReport report) async {
    await saveLocalReport(report, isSynced: false);
  }

  /// Obtiene todos los reportes creados en este dispositivo con su estado de sincronización
  static Future<List<LocalReportEntry>> getAllLocalReports() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheMapRaw = prefs.getString(_keyLocalCache);
    if (cacheMapRaw == null || cacheMapRaw.isEmpty) return [];

    try {
      final cacheMap = jsonDecode(cacheMapRaw) as Map<String, dynamic>;
      final List<LocalReportEntry> list = [];

      for (final entry in cacheMap.values) {
        if (entry is Map<String, dynamic> && entry['report'] != null) {
          final rep = DisasterReport.fromJson(entry['report'] as Map<String, dynamic>);
          final isSynced = entry['is_synced'] as bool? ?? false;
          list.add(LocalReportEntry(report: rep, isSynced: isSynced));
        }
      }

      list.sort((a, b) => b.report.timestamp.compareTo(a.report.timestamp));
      return list;
    } catch (_) {
      return [];
    }
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
          // Actualizar estado en el caché histórico local
          await saveLocalReport(report, isSynced: true);
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
