/// Modelo de resultado de verificación de duplicados de cédula en múltiples fuentes
class DuplicateCheckResult {
  final bool success;
  final bool existeDuplicado;
  final bool esTimeout;
  final String cedula;
  final String cedulaCensurada;
  final List<String> sistemas;
  final List<Map<String, dynamic>> detalles;
  final Map<String, dynamic>? tramiteMiviot;
  final String mensaje;
  final String? error;

  const DuplicateCheckResult({
    required this.success,
    required this.existeDuplicado,
    this.esTimeout = false,
    required this.cedula,
    required this.cedulaCensurada,
    required this.sistemas,
    required this.detalles,
    this.tramiteMiviot,
    required this.mensaje,
    this.error,
  });

  bool get tieneError => esTimeout || (error != null && error!.isNotEmpty);

  factory DuplicateCheckResult.fromJson(Map<String, dynamic> json) {
    final tramite = json['tramite_miviot'] as Map<String, dynamic>?;
    final esTimeout = json['es_timeout'] as bool? ?? (tramite != null && tramite['es_timeout'] == true);

    return DuplicateCheckResult(
      success: json['success'] as bool? ?? false,
      existeDuplicado: json['existe_duplicado'] as bool? ?? false,
      esTimeout: esTimeout,
      cedula: json['cedula'] as String? ?? '',
      cedulaCensurada: json['cedula_censurada'] as String? ?? '',
      sistemas: (json['sistemas'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      detalles: (json['detalles'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      tramiteMiviot: tramite,
      mensaje: json['mensaje'] as String? ?? '',
      error: json['error'] as String?,
    );
  }

  factory DuplicateCheckResult.empty() {
    return const DuplicateCheckResult(
      success: true,
      existeDuplicado: false,
      cedula: '',
      cedulaCensurada: '',
      sistemas: [],
      detalles: [],
      mensaje: '',
    );
  }
}
