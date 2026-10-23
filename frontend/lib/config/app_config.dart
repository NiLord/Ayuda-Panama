import 'dart:convert';
import 'package:flutter/services.dart';

/// Modelo para los eventos o desastres soportados por la plataforma
class DisasterEvent {
  final String codigo;
  final String nombre;
  final String tipo;
  final String descripcion;
  final bool activo;

  const DisasterEvent({
    required this.codigo,
    required this.nombre,
    required this.tipo,
    required this.descripcion,
    this.activo = true,
  });

  factory DisasterEvent.fromJson(Map<String, dynamic> json) {
    return DisasterEvent(
      codigo: json['codigo'] ?? '',
      nombre: json['nombre'] ?? '',
      tipo: json['tipo'] ?? 'TERREMOTO',
      descripcion: json['descripcion'] ?? '',
      activo: json['activo'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'codigo': codigo,
    'nombre': nombre,
    'tipo': tipo,
    'descripcion': descripcion,
    'activo': activo,
  };
}

/// Gestión centralizada de configuración de la aplicación
/// Las credenciales de acceso se inyectan estrictamente en tiempo de compilación (--dart-define)
class AppConfig {
  static const String _defaultApiUrl = '';
  static const String _defaultRawApiUrl = '';
  static const String _defaultPostalUrl = 'https://codigospostalespanama.gob.pa/api/location';
  static const String _defaultEventCode = 'SISMO_OCTUBRE_2026';
  // Credenciales inyectadas en tiempo de compilación vía --dart-define
  static const String apiKey = String.fromEnvironment('API_KEY', defaultValue: '');
  static const String apiSecret = String.fromEnvironment('API_SECRET', defaultValue: '');

  // Configuración cargada en memoria
  static String environment = 'prod';
  static String apiBaseUrl = _defaultApiUrl;
  static String httpApiRawEndpoint = _defaultRawApiUrl;
  static String postalCodeServiceUrl = _defaultPostalUrl;
  static String defaultEventCode = _defaultEventCode;
  static List<DisasterEvent> availableEvents = [
    const DisasterEvent(
      codigo: 'SISMO_OCTUBRE_2026',
      nombre: 'Sismo Octubre 2026',
      tipo: 'TERREMOTO',
      descripcion: 'Evaluación rápida de daños y necesidades por sismo regional en Panamá.',
      activo: true,
    ),
  ];
  static Map<String, String> emergencyContacts = {
    'sinaproc': '*335',
    'cruzRoja': '119',
    'policia': '104',
    'bomberos': '103',
  };
  static bool requireIdPhoto = true;
  static int minDamagePhotos = 2;
  static int uploadTimeoutSeconds = 15;
  static int backgroundUploadMaxDurationSeconds = 60;
  static int publicMonitoringCacheMinutes = 1;

  static bool _initialized = false;

  /// Retorna la lista de eventos actualmente habilitados para selección
  static List<DisasterEvent> get activeEvents =>
      availableEvents.where((e) => e.activo).toList();

  /// Retorna el evento seleccionado por defecto en la aplicación
  static DisasterEvent get defaultEvent {
    for (final ev in availableEvents) {
      if (ev.codigo == defaultEventCode) {
        return ev;
      }
    }
    return availableEvents.isNotEmpty
        ? availableEvents.first
        : const DisasterEvent(
            codigo: 'SISMO_OCTUBRE_2026',
            nombre: 'Sismo Octubre 2026',
            tipo: 'TERREMOTO',
            descripcion: 'Evento por defecto',
            activo: true,
          );
  }

  /// Inicializa la configuración leyendo el archivo JSON local/embebido
  /// y aplicando sobreescrituras en tiempo de compilación (--dart-define)
  static Future<void> init() async {
    if (_initialized) return;

    try {
      final jsonString = await rootBundle.loadString('assets/config/app_config.json');
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      environment = data['environment'] ?? environment;
      apiBaseUrl = data['apiBaseUrl'] ?? apiBaseUrl;
      httpApiRawEndpoint = data['httpApiRawEndpoint'] ?? httpApiRawEndpoint;
      postalCodeServiceUrl = data['postalCodeServiceUrl'] ?? postalCodeServiceUrl;
      defaultEventCode = data['defaultEventCode'] ?? defaultEventCode;

      if (data['events'] is List) {
        availableEvents = (data['events'] as List)
            .map((e) => DisasterEvent.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      if (data['emergencyContacts'] is Map) {
        emergencyContacts = (data['emergencyContacts'] as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString()));
      }

      final rules = data['rules'] as Map<String, dynamic>?;
      if (rules != null) {
        requireIdPhoto = rules['requireIdPhoto'] ?? requireIdPhoto;
        minDamagePhotos = (rules['minDamagePhotos'] as num?)?.toInt() ?? minDamagePhotos;
        uploadTimeoutSeconds = (rules['uploadTimeoutSeconds'] as num?)?.toInt() ?? uploadTimeoutSeconds;
        backgroundUploadMaxDurationSeconds = (rules['backgroundUploadMaxDurationSeconds'] as num?)?.toInt() ?? backgroundUploadMaxDurationSeconds;
        publicMonitoringCacheMinutes = (rules['publicMonitoringCacheMinutes'] as num?)?.toInt() ?? publicMonitoringCacheMinutes;
      }
    } catch (_) {
      // Si el asset no está disponible (ej. en ciertos tests unitarios), se mantienen los valores por defecto seguros
    }

    // Sobreescrituras prioritarias en tiempo de compilación con --dart-define
    const envApi = String.fromEnvironment('API_BASE_URL');
    if (envApi.isNotEmpty) apiBaseUrl = envApi;

    const envEvent = String.fromEnvironment('DEFAULT_EVENT_CODE');
    if (envEvent.isNotEmpty) defaultEventCode = envEvent;

    const envTimeout = String.fromEnvironment('UPLOAD_TIMEOUT_SECONDS');
    if (envTimeout.isNotEmpty) {
      final parsed = int.tryParse(envTimeout);
      if (parsed != null) uploadTimeoutSeconds = parsed;
    }

    _initialized = true;
  }
}
