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
  String get next => tr('next');
  String get back => tr('back');
  String get finishAndSend => tr('finish_and_send');
  String get updateAndSend => tr('update_and_send');
  String get camera => tr('camera');
  String get gallery => tr('gallery');
  String get begin => tr('begin');
  String get continueToReport => tr('continue_to_report');

  // Home Screen
  String get homeEmergencyBannerTitle => tr('home_emergency_banner_title');
  String get homeEmergencyBannerSubtitle => tr('home_emergency_banner_subtitle');
  String homeOfflineReportsCount(int count) =>
      tr('home_offline_reports_count', args: {'count': count});
  String get homeSyncBtn => tr('home_sync_btn');
  String get homeReportBtnTitle => tr('home_report_btn_title');
  String get homeReportBtnSubtitle => tr('home_report_btn_subtitle');
  String get homeMonitoringBtn => tr('home_monitoring_btn');
  String homeRoleBadge(String role) => tr('home_role_badge', args: {'role': role});
  String get homeEditProfileTooltip => tr('home_edit_profile_tooltip');

  // Profile
  String get profileTitleInitial => tr('profile_title_initial');
  String get profileTitleReporter => tr('profile_title_reporter');
  String get profileDescription => tr('profile_description');
  String get profileNameLabel => tr('profile_name_label');
  String get profileNameError => tr('profile_name_error');
  String get profileCedulaLabel => tr('profile_cedula_label');
  String get profileCedulaHelper => tr('profile_cedula_helper');
  String get profileCedulaError => tr('profile_cedula_error');
  String get profilePhoneLabel => tr('profile_phone_label');
  String get profilePhoneHelper => tr('profile_phone_helper');
  String get profilePhoneError => tr('profile_phone_error');
  String get profileRoleLabel => tr('profile_role_label');
  String get profileOrgLabel => tr('profile_org_label');
  String get profileOrgHelper => tr('profile_org_helper');

  // Wizard Steps
  String get stepTitular => tr('step_titular');
  String get stepSite => tr('step_site');
  String get stepDamages => tr('step_damages');
  String get stepCensus => tr('step_census');

  // Step 0: Titular
  String get titularReportingOwnHome => tr('titular_reporting_own_home');
  String get titularReportingOwnHomeSubTrue => tr('titular_reporting_own_home_sub_true');
  String get titularReportingOwnHomeSubFalse => tr('titular_reporting_own_home_sub_false');
  String get titularNameLabel => tr('titular_name_label');
  String get titularNameHelper => tr('titular_name_helper');
  String get titularCedulaLabel => tr('titular_cedula_label');
  String get titularCedulaHelper => tr('titular_cedula_helper');
  String get titularPhoneLabel => tr('titular_phone_label');
  String get titularPhoneHelper => tr('titular_phone_helper');
  String get titularIdPhotoTitle => tr('titular_id_photo_title');
  String titularIdPhotoCount(int count) => tr('titular_id_photo_count', args: {'count': count});
  String get titularIdPhotoMissing => tr('titular_id_photo_missing');
  String get titularIdPhotoInstruction => tr('titular_id_photo_instruction');

  // Step 1: Sitio
  String get siteGpsOnline => tr('site_gps_online');
  String get siteGpsOffline => tr('site_gps_offline');
  String get siteGpsSearching => tr('site_gps_searching');
  String get siteGpsRefresh => tr('site_gps_refresh');
  String get siteProvinceLabel => tr('site_province_label');
  String get siteDistrictLabel => tr('site_district_label');
  String get siteCorregimientoLabel => tr('site_corregimiento_label');
  String get sitePostalCodeLabel => tr('site_postal_code_label');
  String get sitePostalCodeHelper => tr('site_postal_code_helper');
  String get siteCommunityLabel => tr('site_community_label');
  String get siteCommunityHelper => tr('site_community_helper');
  String get siteStreetLabel => tr('site_street_label');
  String get siteReferenceLabel => tr('site_reference_label');
  String get siteReferenceHelper => tr('site_reference_helper');

  // Step 2: Daños
  String get damagesHabitabilityTitle => tr('damages_habitability_title');
  String get damagesPropertyTypeLabel => tr('damages_property_type_label');
  String get damagesConstructionLabel => tr('damages_construction_label');
  String get damagesCollapseRisk => tr('damages_collapse_risk');
  String get damagesGasLeak => tr('damages_gas_leak');
  String get damagesDescriptionLabel => tr('damages_description_label');
  String get damagesPhotosTitle => tr('damages_photos_title');
  String damagesPhotosCount(int count) => tr('damages_photos_count', args: {'count': count});
  String get damagesPhotosInstruction => tr('damages_photos_instruction');

  // Step 3: Censo & Asistencia & Consentimiento
  String get censusCriticalTrappedWarning => tr('census_critical_trapped_warning');
  String get censusFamilyBreakdownTitle => tr('census_family_breakdown_title');
  String get censusNeonatos => tr('census_neonatos');
  String get censusNinos => tr('census_ninos');
  String get censusAdolescentes => tr('census_adolescentes');
  String get censusAdultos => tr('census_adultos');
  String get censusAdultosMayores => tr('census_adultos_mayores');
  String get censusVulnerableTitle => tr('census_vulnerable_title');
  String get censusEmbarazadas => tr('census_embarazadas');
  String get censusDiscapacidad => tr('census_discapacidad');
  String get censusMedicalTitle => tr('census_medical_title');
  String get censusAtrapados => tr('census_atrapados');
  String get censusLesionados => tr('census_lesionados');
  String get censusShelterQuestion => tr('census_shelter_question');
  String get censusWaterFoodQuestion => tr('census_water_food_question');
  String get consentTitle => tr('consent_title');
  String get consentBody => tr('consent_body');

  // Validaciones
  String get valTitularNameReq => tr('val_titular_name_req');
  String get valTitularCedulaReq => tr('val_titular_cedula_req');
  String get valTitularPhoneReq => tr('val_titular_phone_req');
  String get valTitularPhotoReq => tr('val_titular_photo_req');
  String get valSiteCommunityReq => tr('val_site_community_req');
  String valStructurePhotosMin(int count) => tr('val_structure_photos_min', args: {'count': count});
  String get valCensusOccupantsMin => tr('val_census_occupants_min');
  String get valConsentReq => tr('val_consent_req');

  // Filtros y Monitoreo
  String get filterProvince => tr('filter_province');
  String get filterDistrict => tr('filter_district');
  String get filterAll => tr('filter_all');
  String get filterAllM => tr('filter_all_m');
  String get filterSyncStatus => tr('filter_sync_status');
  String get filterSynced => tr('filter_synced');
  String get filterPending => tr('filter_pending');
  String get filterMine => tr('filter_mine');
  String get emptyReportsTitle => tr('empty_reports_title');
  String get emptyReportsSubtitle => tr('empty_reports_subtitle');

  // Proceso de Envío
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

  String get duplicateCheckingCedula => tr('duplicate_checking_cedula');
  String get duplicateDetectedTitle => tr('duplicate_detected_title');
  String duplicateDetectedBody(String systems) =>
      tr('duplicate_detected_body', args: {'systems': systems});
  String get duplicateBlockAction => tr('duplicate_block_action');
  String get duplicateViewTramite => tr('duplicate_view_tramite');
  String get duplicateReenterCedula => tr('duplicate_reenter_cedula');

  String get miviotDialogTitle => tr('miviot_dialog_title');
  String miviotReportNumber(String number) =>
      tr('miviot_report_number', args: {'number': number});
  String miviotDateReceived(String date) =>
      tr('miviot_date_received', args: {'date': date});
  String miviotStepProgress(int current, String status) =>
      tr('miviot_step_progress', args: {'current': current, 'status': status});
  String get miviotNoTramite => tr('miviot_no_tramite');
  String get miviotConsultingBtn => tr('miviot_consulting_btn');
  String get miviotRefreshBtn => tr('miviot_refresh_btn');
  String get badgeSinaprocEdan => tr('badge_sinaproc_edan');

  /// Fallback integrado para garantizar respuestas seguras si el asset aún no carga
  static final Map<String, String> _defaultFallback = {
    'app_title': 'Ayuda Panamá',
    'understood': 'Entendido',
    'cancel': 'Cancelar',
    'accept': 'Aceptar',
    'save': 'Guardar',
    'edit': 'Editar',
    'close': 'Cerrar',
    'next': 'SIGUIENTE',
    'back': 'ATRÁS',
    'finish_and_send': 'FINALIZAR Y ENVIAR',
    'update_and_send': 'ACTUALIZAR Y ENVIAR',
    'camera': 'Cámara',
    'gallery': 'Galería',
    'begin': 'Comenzar',
    'continue_to_report': 'Continuar al Reporte',
    'home_emergency_banner_title': 'COBERTURA DE EMERGENCIA ACTIVA',
    'home_emergency_banner_subtitle': 'Tu reporte ayuda a SINAPROC y a los cuerpos de rescate a priorizar auxilio.',
    'home_offline_reports_count': '{count} reporte(s) guardado(s) offline.',
    'home_sync_btn': 'SINCRONIZAR',
    'home_report_btn_title': 'REPORTAR DAÑO O EMERGENCIA',
    'home_report_btn_subtitle': 'Funciona con o sin conexión a internet',
    'home_monitoring_btn': 'VER SITUACIÓN NACIONAL',
    'home_role_badge': 'Rol: {role}',
    'home_edit_profile_tooltip': 'Editar datos de contacto',
    'profile_title_initial': 'Configuración Inicial',
    'profile_title_reporter': 'Datos del Informante',
    'profile_description': 'Configura tus datos de contacto una sola vez. Se reutilizarán automáticamente en cada reporte para que no pierdas tiempo en emergencias.',
    'profile_name_label': 'Tu Nombre Completo *',
    'profile_name_error': 'Ingresa tu nombre',
    'profile_cedula_label': 'Tu Cédula de Identidad Personal *',
    'profile_cedula_helper': 'Ej. 7-123-456 o 8-123-4567',
    'profile_cedula_error': 'Ingresa tu número de cédula',
    'profile_phone_label': 'Teléfono de Contacto (+507...) *',
    'profile_phone_helper': 'Línea móvil para llamadas de rescate',
    'profile_phone_error': 'Ingresa un número telefónico válido',
    'profile_role_label': 'Tu Rol en el Sitio del Desastre',
    'profile_org_label': 'Organización / Institución (Opcional)',
    'profile_org_helper': 'Ej. Cruz Roja, Junta Comunal, Independiente',
    'step_titular': 'Titular',
    'step_site': 'Sitio',
    'step_damages': 'Daños',
    'step_census': 'Censo',
    'titular_reporting_own_home': '¿Estás reportando tu propia casa?',
    'titular_reporting_own_home_sub_true': 'Se usan tus datos guardados como jefe de familia',
    'titular_reporting_own_home_sub_false': 'Ingresa los datos del jefe de la familia afectada',
    'titular_name_label': 'Nombre Completo del Jefe/a de Familia *',
    'titular_name_helper': 'Obligatorio para el registro humanitario oficial',
    'titular_cedula_label': 'Cédula de Identidad del Jefe/a de Familia *',
    'titular_cedula_helper': 'Obligatorio. Ej. 7-123-456, 8-123-4567 o Pasaporte',
    'titular_phone_label': 'Teléfono de Contacto del Jefe/a de Familia *',
    'titular_phone_helper': 'Obligatorio para que los rescatistas coordinen auxilio',
    'titular_id_photo_title': 'Foto de la Cédula / Identificación *',
    'titular_id_photo_count': '{count} de 1 agregada',
    'titular_id_photo_missing': 'Falta foto',
    'titular_id_photo_instruction': 'Obligatorio: Fotografía legible de la cédula panameña o pasaporte del jefe/a de familia',
    'site_gps_online': 'GPS & Red Celular Activa',
    'site_gps_offline': 'Modo Offline: GPS Satelital Directo',
    'site_gps_searching': 'Buscando satélites GPS...',
    'site_gps_refresh': 'Actualizar GPS',
    'site_province_label': 'Provincia *',
    'site_district_label': 'Distrito *',
    'site_corregimiento_label': 'Corregimiento *',
    'site_postal_code_label': 'Código Postal Panameño',
    'site_postal_code_helper': 'Calculado automáticamente por el servicio postal de Panamá',
    'site_community_label': 'Comunidad / Barrio / Sector *',
    'site_community_helper': 'Ej. Barrio Santa Librada, Calle El Cocal',
    'site_street_label': 'Calle o Camino (Opcional)',
    'site_reference_label': 'Punto de Referencia (Opcional)',
    'site_reference_helper': 'Ej. Cerca de la iglesia, detrás del molino',
    'damages_habitability_title': 'Semáforo de Habitabilidad (ATC-20):',
    'damages_property_type_label': 'Tipo de Inmueble',
    'damages_construction_label': 'Material Predominante',
    'damages_collapse_risk': '⚠️ Riesgo de colapso inminente (Estructura cruje o cede)',
    'damages_gas_leak': '⚠️ Fuga de gas licuado o olor inflamable',
    'damages_description_label': 'Descripción de Daños Visibles',
    'damages_photos_title': 'Fotos de Daños de la Estructura *',
    'damages_photos_count': '{count} de 2 agregadas',
    'damages_photos_instruction': 'Obligatorio: Mínimo 2 fotos claras de los daños estructurales, paredes, techo o grietas',
    'census_critical_trapped_warning': '🚨 ALERTA ROJA: Personas atrapadas. Este reporte se marcará como Prioridad P1 para los equipos de búsqueda y rescate (INSARAG).',
    'census_family_breakdown_title': 'Desglose de Personas en la Vivienda (Censo Humanitario):',
    'census_neonatos': 'Bebés / Neonatos (0 a 2 años):',
    'census_ninos': 'Niños (3 a 12 años):',
    'census_adolescentes': 'Adolescentes (13 a 17 años):',
    'census_adultos': 'Adultos (18 a 59 años):',
    'census_adultos_mayores': 'Adultos Mayores (60+ años):',
    'census_vulnerable_title': 'Grupos Vulnerables Especiales:',
    'census_embarazadas': 'Mujeres embarazadas en el hogar:',
    'census_discapacidad': 'Personas con discapacidad o movilidad reducida:',
    'census_medical_title': 'Auxilio Médico y Rescate Inmediato:',
    'census_atrapados': 'Personas atrapadas o desaparecidas en la estructura:',
    'census_lesionados': 'Personas con lesiones que requieren hospital:',
    'census_shelter_question': '¿Requiere albergue temporal de inmediato?',
    'census_water_food_question': '¿Requiere agua potable y alimentos de auxilio?',
    'consent_title': 'Consentimiento Informado (Ley 81 de Panamá)',
    'consent_body': 'Autorizo que los datos de contacto y daños sean transmitidos exclusivamente a SINAPROC, Cruz Roja y autoridades para coordinar ayuda y rescate. El mapa público jamás mostrará nombres ni teléfonos.',
    'val_titular_name_req': 'El nombre del jefe/a de familia es obligatorio.',
    'val_titular_cedula_req': 'La cédula del jefe/a de familia es obligatoria.',
    'val_titular_phone_req': 'El teléfono de contacto del jefe/a de familia es obligatorio.',
    'val_titular_photo_req': 'Debes adjuntar al menos 1 foto de la cédula o identificación del jefe/a de familia.',
    'val_site_community_req': 'Por favor ingresa la Comunidad, Barrio o Sector (Obligatorio).',
    'val_structure_photos_min': 'Debes adjuntar al menos 2 fotos de la estructura afectada ({count}/2).',
    'val_census_occupants_min': 'El censo debe incluir al menos 1 persona en el hogar según el desglose.',
    'val_consent_req': 'Debes otorgar consentimiento para notificar a los cuerpos de auxilio.',
    'filter_province': 'Provincia',
    'filter_district': 'Distrito',
    'filter_all': 'TODAS',
    'filter_all_m': 'TODOS',
    'filter_sync_status': 'Sincronización',
    'filter_synced': 'Solo Sincronizados',
    'filter_pending': 'Solo Pendientes',
    'filter_mine': 'Solo Mis Reportes',
    'empty_reports_title': 'No se encontraron reportes',
    'empty_reports_subtitle': 'Ajusta los filtros o sincroniza los datos locales con la nube.',
    'sending_report_title': 'Enviando Reporte',
    'preparing_report': 'Preparando envío del reporte...',
    'optimizing_images': 'Optimizando imágenes...',
    'uploading_image': 'Subiendo imagen {current} de {total}...',
    'images_processed_success': 'Imágenes procesadas exitosamente.',
    'registering_emergency_report': 'Registrando reporte de emergencia...',
    'report_sent_success': '¡Reporte enviado exitosamente!',
    'report_sent_dialog_title': 'Reporte Enviado',
    'report_saved_offline_dialog_title': 'Guardado Offline',
    'report_sent_success_body': 'Tu reporte fue recibido exitosamente y está disponible para SINAPROC y los equipos de rescate.',
    'report_saved_offline_body': 'Sin conexión estable. Tu reporte quedó guardado localmente de forma segura y se enviará automáticamente en cuanto recuperes señal.',
    'background_upload_dialog_title': 'Subida en Segundo Plano',
    'background_upload_body': 'La conexión celular está lenta. Tu reporte y fotos se seguirán subiendo en segundo plano durante 1 minuto más. Si la conexión falla, el registro quedará seguro en tu cola pendiente.',
    'upload_overlay_notice': 'Por favor no cierres la app. Si la conexión tarda más de {seconds}s, el proceso continuará en segundo plano automáticamente.',
    'synced_reports_success': 'Se sincronizaron {count} reporte(s) exitosamente.',
    'no_pending_reports_to_sync': 'No hay reportes pendientes por sincronizar.',
    'sync_failed_check_connection': 'No fue posible sincronizar los reportes pendientes. Verifica tu conexión.',
    'sync_no_connection': 'Sin conexión para sincronizar los reportes pendientes.',
    'national_monitoring_title': 'Monitoreo Nacional de Daños',
    'no_synced_data': 'Sin datos sincronizados',
    'updated_seconds_ago': 'Actualizado hace {seconds} seg',
    'updated_minutes_ago': 'Actualizado hace {minutes} min',
    'updated_at_time': 'Actualizado a las {time}',
    'recent_data_wait_notice': 'Información reciente de hace {elapsed} seg. Podrás refrescar en {wait} seg.',
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
    'duplicate_checking_cedula': 'Verificando en registros oficiales...',
    'duplicate_detected_title': 'Vivienda ya Evaluada / Trámite Oficial',
    'duplicate_detected_body': 'Esta cédula ya cuenta con una evaluación o trámite en: {systems}. Por normativa de emergencia y para no duplicar recursos de auxilio, no se permite ingresar un nuevo reporte para esta vivienda.',
    'duplicate_block_action': 'Reporte Duplicado Bloqueado',
    'duplicate_view_tramite': 'Ver Trámite MIVIOT',
    'duplicate_reenter_cedula': 'Corregir Cédula',
    'miviot_dialog_title': 'Expediente de Vivienda MIVIOT',
    'miviot_report_number': 'Expediente: {number}',
    'miviot_date_received': 'Recibido: {date}',
    'miviot_step_progress': 'Fase {current} de 5: {status}',
    'miviot_no_tramite': 'No se localizó trámite de vivienda activo para esta cédula en MIVIOT.',
    'miviot_consulting_btn': 'Consultar MIVIOT',
    'miviot_refresh_btn': 'Actualizar MIVIOT',
    'badge_sinaproc_edan': 'SINAPROC EDAN',
  };
}
