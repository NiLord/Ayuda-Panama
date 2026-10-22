import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_messages.dart';
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

  /// Sube las evidencias pendientes a S3 y persiste el reporte en AWS API Gateway / DynamoDB.
  /// Si se proporciona [onProgress], emite el valor (0.0 a 1.0) y el mensaje de estado.
  static Future<bool> uploadReportWithEvidences(
    DisasterReport report, {
    void Function(double progress, String message)? onProgress,
  }) async {
    try {
      final msg = AppMessages.current;
      onProgress?.call(0.05, msg.preparingReport);

      // 1. Identificar evidencias que requieren subida
      final pendientesSubir = report.evidencias
          .where((e) => (e.urlRemota == null || e.urlRemota!.isEmpty) && e.rutaLocal.isNotEmpty)
          .toList();

      final totalFotos = pendientesSubir.length;
      final evidenciasActualizadas = <FotoEvidencia>[];
      int fotosSubidas = 0;

      for (final ev in report.evidencias) {
        if ((ev.urlRemota == null || ev.urlRemota!.isEmpty) && ev.rutaLocal.isNotEmpty) {
          final category = ev.tipo == TipoFotoEvidencia.identificacion.value
              ? 'identificacion'
              : 'danos';

          onProgress?.call(
            0.1 + (0.75 * fotosSubidas / (totalFotos > 0 ? totalFotos : 1)),
            msg.uploadingImage(fotosSubidas + 1, totalFotos),
          );

          final remoteUrl = await ApiService.uploadPhotoToS3(
            reportId: report.reportId,
            localPath: ev.rutaLocal,
            category: category,
            photoId: ev.id,
          );

          if (remoteUrl != null) {
            evidenciasActualizadas.add(ev.copyWith(urlRemota: remoteUrl));
          } else {
            evidenciasActualizadas.add(ev);
          }
          fotosSubidas++;
        } else {
          evidenciasActualizadas.add(ev);
        }
      }

      onProgress?.call(0.85, msg.imagesProcessedSuccess);

      // 2. Armar lista final de URLs remotas disponibles
      final fotosUrls = evidenciasActualizadas
          .map((e) => (e.urlRemota != null && e.urlRemota!.isEmpty) ? e.urlRemota! : e.rutaLocal)
          .toList();

      final reportFinal = report.copyWith(
        evidencias: evidenciasActualizadas,
        fotosUrls: fotosUrls,
      );

      // Guardar incrementalmente localmente para no perder las URLs ya obtenidas
      await saveLocalReport(reportFinal, isSynced: false);

      // 3. Registrar el reporte en el sistema central
      onProgress?.call(0.90, msg.registeringEmergencyReport);
      final success = await ApiService.submitReport(reportFinal);

      if (success) {
        onProgress?.call(1.0, msg.reportSentSuccess);
        await saveLocalReport(reportFinal, isSynced: true);
        return true;
      } else {
        await saveLocalReport(reportFinal, isSynced: false);
        return false;
      }
    } catch (_) {
      await saveLocalReport(report, isSynced: false);
      return false;
    }
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

        final success = await uploadReportWithEvidences(report);
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
