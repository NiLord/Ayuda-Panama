import 'dart:convert';
import 'package:flutter/services.dart';

/// Módulo centralizado de internacionalización (i18n) basado en JSON.
/// Permite que cualquier colaborador o traductor agregue o modifique idiomas
/// editando únicamente archivos JSON en `assets/i18n/<idioma>.json`.
class AppMessages {
  static final AppMessages _instance = AppMessages._();
  static AppMessages get current => _instance;

  String _currentLanguage = 'es';
  String get currentLanguage => _currentLanguage;

  Map<String, dynamic> _localizedStrings = {};

  AppMessages._();

  /// Carga asíncrona del archivo JSON correspondiente al idioma especificado
  static Future<void> load(String languageCode) async {
    _instance._currentLanguage = languageCode;
    try {
      final jsonString = await rootBundle.loadString('assets/i18n/$languageCode.json');
      _instance._localizedStrings = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      // Fallback a 'es' en caso de error o idioma inexistente
      if (languageCode != 'es') {
        try {
          final fallbackString = await rootBundle.loadString('assets/i18n/es.json');
          _instance._localizedStrings = jsonDecode(fallbackString) as Map<String, dynamic>;
        } catch (_) {}
      }
    }
  }

  /// Permite inyectar traducciones directamente (útil para pruebas unitarias)
  static void loadFromMap(Map<String, dynamic> map, {String language = 'es'}) {
    _instance._currentLanguage = language;
    _instance._localizedStrings = map;
  }

  /// Método genérico de traducción que reemplaza `{placeholder}` con sus argumentos
  String tr(String key, {Map<String, dynamic>? args}) {
    String value = _localizedStrings[key]?.toString() ?? _defaultFallback[key] ?? key;
    if (args != null && args.isNotEmpty) {
      args.forEach((k, v) {
        value = value.replaceAll('{$k}', v.toString());
      });
    }
    return value;
  }

  // -------------------------------------------------------------
  // Getters tipados para autocompletado y tipado fuerte
  // -------------------------------------------------------------
  String get appTitle => tr('app_title');
  String get understood => tr('understood');
  String get cancel => tr('cancel');
  String get accept => tr('accept');
  String get save => tr('save');
  String get edit => tr('edit');
  String get close => tr('close');

  String get sendingReportTitle => tr('sending_report_title');
  String get preparingReport => tr('preparing_report');
  String get optimizingImages => tr('optimizing_images');
  String uploadingImage(int current, int total) =>
      tr('uploading_image', args: {'current': current, 'total': total});
  String get imagesProcessedSuccess => tr('images_processed_success');
  String get registeringEmergencyReport => tr('registering_emergency_report');
  String get reportSentSuccess => tr('report_sent_success');

  String get reportSentDialogTitle => tr('report_sent_dialog_title');
  String get reportSavedOfflineDialogTitle => tr('report_saved_offline_dialog_title');
  String get reportSentSuccessBody => tr('report_sent_success_body');
  String get reportSavedOfflineBody => tr('report_saved_offline_body');
  String get backgroundUploadDialogTitle => tr('background_upload_dialog_title');
  String get backgroundUploadBody => tr('background_upload_body');
  String uploadOverlayNotice(int seconds) =>
      tr('upload_overlay_notice', args: {'seconds': seconds});

  String syncedReportsSuccess(int count) =>
      tr('synced_reports_success', args: {'count': count});
  String get noPendingReportsToSync => tr('no_pending_reports_to_sync');
  String get syncFailedCheckConnection => tr('sync_failed_check_connection');
  String get syncNoConnection => tr('sync_no_connection');

  String get nationalMonitoringTitle => tr('national_monitoring_title');
  String get noSyncedData => tr('no_synced_data');
  String updatedSecondsAgo(int seconds) =>
      tr('updated_seconds_ago', args: {'seconds': seconds});
  String updatedMinutesAgo(int minutes) =>
      tr('updated_minutes_ago', args: {'minutes': minutes});
  String updatedAtTime(String time) =>
      tr('updated_at_time', args: {'time': time});
  String recentDataWaitNotice(int elapsed, int wait) =>
      tr('recent_data_wait_notice', args: {'elapsed': elapsed, 'wait': wait});
  String get traceabilityNetworksTitle => tr('traceability_networks_title');
  String get badgeReportApp => tr('badge_report_app');
  String get badgeReportAppLocal => tr('badge_report_app_local');
  String get badgeSinaproc => tr('badge_sinaproc');
  String get badgeMiviot => tr('badge_miviot');
  String get badgeMine => tr('badge_mine');
  String titularInfo(String name, String cedula) =>
      tr('titular_info', args: {'name': name, 'cedula': cedula});
  String damageHabitability(String habitability) =>
      tr('damage_habitability', args: {'habitability': habitability});
  String get hazardCollapse => tr('hazard_collapse');
  String get hazardShelter => tr('hazard_shelter');

  /// Fallback integrado para garantizar respuestas seguras si el asset aún no carga
  static final Map<String, String> _defaultFallback = {
    'app_title': 'Ayuda Panamá',
    'understood': 'Entendido',
    'cancel': 'Cancelar',
    'accept': 'Aceptar',
    'save': 'Guardar',
    'edit': 'Editar',
    'close': 'Cerrar',
    'sending_report_title': 'Enviando Reporte',
    'preparing_report': 'Preparando envío del reporte...',
    'optimizing_images': 'Optimizando imágenes...',
    'uploading_image': 'Subiendo imagen {current} de {total}...',
    'images_processed_success': 'Imágenes procesadas exitosamente.',
    'registering_emergency_report': 'Registrando reporte de emergencia...',
    'report_sent_success': '¡Reporte enviado exitosamente!',
    'report_sent_dialog_title': 'Reporte Enviado',
    'report_saved_offline_dialog_title': 'Guardado Offline',
    'report_sent_success_body':
        'Tu reporte fue recibido exitosamente y está disponible para SINAPROC y los equipos de rescate.',
    'report_saved_offline_body':
        'Sin conexión estable. Tu reporte quedó guardado localmente de forma segura y se enviará automáticamente en cuanto recuperes señal.',
    'background_upload_dialog_title': 'Subida en Segundo Plano',
    'background_upload_body':
        'La conexión celular está lenta. Tu reporte y fotos se seguirán subiendo en segundo plano durante 1 minuto más. Si la conexión falla, el registro quedará seguro en tu cola pendiente.',
    'upload_overlay_notice':
        'Por favor no cierres la app. Si la conexión tarda más de {seconds}s, el proceso continuará en segundo plano automáticamente.',
    'synced_reports_success': 'Se sincronizaron {count} reporte(s) exitosamente.',
    'no_pending_reports_to_sync': 'No hay reportes pendientes por sincronizar.',
    'sync_failed_check_connection':
        'No fue posible sincronizar los reportes pendientes. Verifica tu conexión.',
    'sync_no_connection': 'Sin conexión para sincronizar los reportes pendientes.',
    'national_monitoring_title': 'Monitoreo Nacional de Daños',
    'no_synced_data': 'Sin datos sincronizados',
    'updated_seconds_ago': 'Actualizado hace {seconds} seg',
    'updated_minutes_ago': 'Actualizado hace {minutes} min',
    'updated_at_time': 'Actualizado a las {time}',
    'recent_data_wait_notice':
        'Información reciente de hace {elapsed} seg. Podrás refrescar en {wait} seg.',
    'traceability_networks_title': 'Trazabilidad / Redes:',
    'badge_report_app': 'Reporte App',
    'badge_report_app_local': 'Reporte App (Local)',
    'badge_sinaproc': 'SINAPROC',
    'badge_miviot': 'MIVIOT',
    'badge_mine': 'Mío',
    'titular_info': 'Titular: {name} • Cédula: {cedula}',
    'damage_habitability': 'Daño: {habitability}',
    'hazard_collapse': '⚠️ Colapso',
    'hazard_shelter': '⛺ Albergue',
  };
}
