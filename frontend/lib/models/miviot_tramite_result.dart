/// Modelo que representa el expediente y estado de trámite de vivienda en MIVIOT
class MiviotTramiteResult {
  final bool success;
  final bool encontrado;
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

  factory MiviotTramiteResult.fromJson(Map<String, dynamic> json) {
    return MiviotTramiteResult(
      success: json['success'] as bool? ?? false,
      encontrado: json['encontrado'] as bool? ?? false,
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

  /// Nombres oficiales de las 5 etapas del MIVIOT
  static const List<String> etapasOficiales = [
    'Recepción y Registro de Solicitud',
    'Evaluación Técnica en Sitio',
    'Validación Socioeconómica',
    'Asignación de Solución Habitacional',
    'Entrega de Ayuda o Vivienda Finalizada',
  ];
}
