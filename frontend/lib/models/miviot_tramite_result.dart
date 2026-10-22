/// Modelo que representa el expediente y estado de trámite de vivienda en MIVIOT
class MiviotTramiteResult {
  final bool success;
  final bool encontrado;
  final bool esTimeout;
  final bool verificadoInexistente;
  final String? error;
  final bool puedeReintentar;
  final String origen;
  final String cedula;
  final String cedulaCensurada;
  final String? reporte;
  final String? fechaRecibido;
  final int? pasoActual;
  final String? estadoActual;
  final String? ultimaActualizacion;
  final String mensaje;

  const MiviotTramiteResult({
    required this.success,
    required this.encontrado,
    this.esTimeout = false,
    this.verificadoInexistente = false,
    this.error,
    this.puedeReintentar = false,
    this.origen = 'MIVIOT',
    required this.cedula,
    required this.cedulaCensurada,
    this.reporte,
    this.fechaRecibido,
    this.pasoActual,
    this.estadoActual,
    this.ultimaActualizacion,
    required this.mensaje,
  });

  bool get tieneError => esTimeout || (error != null && error!.isNotEmpty);

  factory MiviotTramiteResult.fromJson(Map<String, dynamic> json) {
    final esTimeout = json['es_timeout'] as bool? ?? false;
    final errorStr = json['error'] as String?;
    final encontrado = json['encontrado'] as bool? ?? false;
    final verificado = json['verificado_inexistente'] as bool? ?? (!encontrado && errorStr == null && !esTimeout);

    return MiviotTramiteResult(
      success: json['success'] as bool? ?? false,
      encontrado: encontrado,
      esTimeout: esTimeout,
      verificadoInexistente: verificado,
      error: errorStr,
      puedeReintentar: (json['puede_reintentar'] as bool?) ?? (esTimeout || errorStr != null),
      origen: json['origen'] as String? ?? 'MIVIOT',
      cedula: json['cedula'] as String? ?? '',
      cedulaCensurada: json['cedula_censurada'] as String? ?? '',
      reporte: json['reporte'] as String?,
      fechaRecibido: json['fecha_recibido'] as String?,
      pasoActual: json['paso_actual'] as int?,
      estadoActual: json['estado_actual'] as String?,
      ultimaActualizacion: json['ultima_actualizacion'] as String?,
      mensaje: json['mensaje'] as String? ?? '',
    );
  }

  /// Nombres oficiales literales de las 5 etapas del MIVIOT (según el portal oficial de afectaciones)
  static const List<String> etapasOficiales = [
    'Reporte de afectación de vivienda registrado. Pendiente evaluación técnica.',
    'Vivienda evaluada. Pendiente asignación de programa.',
    'Programa asignado. Pendiente construcción.',
    'Construcción en proceso.',
    'Vivienda entregada.',
  ];
}
