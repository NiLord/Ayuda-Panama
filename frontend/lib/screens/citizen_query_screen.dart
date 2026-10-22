import 'package:flutter/material.dart';
import '../models/duplicate_check_result.dart';
import '../models/miviot_tramite_result.dart';
import '../services/duplicate_check_service.dart';
import '../services/reporter_profile_service.dart';
import 'report_wizard_screen.dart';

class CitizenQueryScreen extends StatefulWidget {
  final String? initialCedula;

  const CitizenQueryScreen({super.key, this.initialCedula});

  @override
  State<CitizenQueryScreen> createState() => _CitizenQueryScreenState();
}

class _CitizenQueryScreenState extends State<CitizenQueryScreen> {
  final TextEditingController _cedulaController = TextEditingController();
  bool _consultando = false;
  bool _reintentandoMiviot = false;
  DuplicateCheckResult? _checkResult;
  MiviotTramiteResult? _miviotResult;
  bool _yaConsulto = false;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    if (widget.initialCedula != null && widget.initialCedula!.isNotEmpty) {
      _cedulaController.text = widget.initialCedula!;
      _ejecutarConsulta();
    } else {
      final profile = await ReporterProfileService.getOrCreateProfile();
      if (profile.cedula.isNotEmpty) {
        _cedulaController.text = profile.cedula;
        _ejecutarConsulta();
      }
    }
  }

  @override
  void dispose() {
    _cedulaController.dispose();
    super.dispose();
  }

  Future<void> _ejecutarConsulta({bool force = true}) async {
    final cedula = _cedulaController.text.trim();
    if (cedula.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingrese su número de cédula panameña.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _consultando = true;
      _yaConsulto = true;
      _checkResult = null;
      _miviotResult = null;
    });

    try {
      final dupRes = await DuplicateCheckService.verificarCedula(cedula, force: force);
      MiviotTramiteResult? mivRes;

      if (dupRes.tramiteMiviot != null && dupRes.tramiteMiviot!['reporte'] != null) {
        mivRes = MiviotTramiteResult(
          success: true,
          encontrado: true,
          cedula: cedula,
          cedulaCensurada: dupRes.cedulaCensurada,
          reporte: dupRes.tramiteMiviot!['reporte'] as String?,
          fechaRecibido: dupRes.tramiteMiviot!['fecha_recibido'] as String?,
          pasoActual: dupRes.tramiteMiviot!['paso_actual'] as int?,
          estadoActual: dupRes.tramiteMiviot!['estado_actual'] as String?,
          mensaje: 'Trámite oficial recuperado',
        );
      } else if (dupRes.tramiteMiviot != null && dupRes.tramiteMiviot!['es_timeout'] == true) {
        mivRes = MiviotTramiteResult(
          success: false,
          encontrado: false,
          esTimeout: true,
          verificadoInexistente: false,
          error: 'TIMEOUT',
          puedeReintentar: true,
          cedula: cedula,
          cedulaCensurada: dupRes.cedulaCensurada,
          mensaje: dupRes.tramiteMiviot!['mensaje'] as String? ?? 'Tiempo de espera agotado al consultar MIVIOT.',
        );
      } else if (dupRes.tramiteMiviot != null && dupRes.tramiteMiviot!['verificado_inexistente'] == true) {
        mivRes = MiviotTramiteResult(
          success: true,
          encontrado: false,
          esTimeout: false,
          verificadoInexistente: true,
          error: null,
          puedeReintentar: false,
          cedula: cedula,
          cedulaCensurada: dupRes.cedulaCensurada,
          mensaje: dupRes.tramiteMiviot!['mensaje'] as String? ?? 'Sin expediente en MIVIOT.',
        );
      } else {
        // Consultar MIVIOT directamente como respaldo con reintentos
        mivRes = await DuplicateCheckService.consultarTramiteMiviot(cedula, force: force);
      }

      if (mounted) {
        setState(() {
          _checkResult = dupRes;
          _miviotResult = mivRes;
          _consultando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _consultando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al realizar la consulta: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _reintentarSoloMiviot() async {
    final cedula = _cedulaController.text.trim();
    if (cedula.isEmpty) return;

    setState(() => _reintentandoMiviot = true);

    try {
      final res = await DuplicateCheckService.consultarTramiteMiviot(cedula, force: true);
      if (mounted) {
        setState(() {
          _miviotResult = res;
          _reintentandoMiviot = false;
        });

        if (res != null && res.encontrado) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('¡Expediente ${res.reporte} localizado en MIVIOT!'),
              backgroundColor: const Color(0xFF1B5E20),
            ),
          );
        } else if (res != null && res.tieneError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.mensaje),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _reintentandoMiviot = false);
      }
    }
  }

  Color _obtenerColorSemaforo(String habitabilidad) {
    switch (habitabilidad.toUpperCase()) {
      case 'HABITABLE':
        return const Color(0xFF2ECC71);
      case 'ACCESO_RESTRINGIDO':
        return const Color(0xFFF1C40F);
      case 'INHABITABLE':
        return const Color(0xFFE74C3C);
      case 'COLAPSO_TOTAL':
        return const Color(0xFF8E44AD);
      default:
        return const Color(0xFF95A5A6);
    }
  }

  String _traducirHabitabilidad(String hab) {
    switch (hab.toUpperCase()) {
      case 'HABITABLE':
        return 'Habitable (Verde)';
      case 'ACCESO_RESTRINGIDO':
        return 'Acceso Restringido (Amarillo)';
      case 'INHABITABLE':
        return 'Inhabitable (Rojo)';
      case 'COLAPSO_TOTAL':
        return 'Colapso Total (Púrpura)';
      default:
        return hab;
    }
  }

  String _formatearFecha(String? raw) {
    if (raw == null || raw.isEmpty) return 'No registrada';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final dia = dt.day.toString().padLeft(2, '0');
      final mes = dt.month.toString().padLeft(2, '0');
      final anio = dt.year;
      final hora = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$dia/$mes/$anio $hora:$min';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Estado de mi Solicitud'),
        backgroundColor: const Color(0xFF1B5E20), // Verde oficial
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Caja de Búsqueda por Cédula
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Búsqueda de Expediente por Cédula',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Consulte el estado unificado de su vivienda en SINAPROC (EDAN de campo) y MIVIOT (Trámite habitacional).',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _cedulaController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: 'Cédula de Identidad',
                              hintText: 'Ej. 7-71-1473 o PE-12-345',
                              prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFF1B5E20)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onSubmitted: (_) => _ejecutarConsulta(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _consultando ? null : () => _ejecutarConsulta(force: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: _consultando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text('Consultar', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Contenido del Resultado
            if (_consultando)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF1B5E20)),
                    const SizedBox(height: 16),
                    Text(
                      'Consultando bases de datos de SINAPROC y MIVIOT...',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              )
            else if (_yaConsulto)
              _buildResultadoConsolidado()
            else
              _buildGuiaInicial(),
          ],
        ),
      ),
    );
  }

  Widget _buildGuiaInicial() {
    return Card(
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.manage_search_rounded, size: 56, color: Colors.green.shade700),
            const SizedBox(height: 14),
            const Text(
              'Consulta Nacional Unificada',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Al consultar su cédula, el sistema verificará automáticamente si su vivienda ya cuenta con inspección de daños por SINAPROC y el estado de su trámite en el MIVIOT.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultadoConsolidado() {
    final result = _checkResult;
    if (result == null || !result.success) {
      final esTimeoutGlobal = result?.esTimeout == true;
      return Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: esTimeoutGlobal ? Colors.amber.shade400 : Colors.red.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                esTimeoutGlobal ? Icons.timer_off_outlined : Icons.error_outline_rounded,
                size: 48,
                color: esTimeoutGlobal ? Colors.amber.shade800 : Colors.red.shade700,
              ),
              const SizedBox(height: 12),
              Text(
                esTimeoutGlobal
                    ? 'Tiempo de espera agotado al consultar'
                    : 'No fue posible consultar el expediente',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                result?.mensaje ?? 'Error de conexión con los servicios de consulta.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _consultando ? null : () => _ejecutarConsulta(force: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar Consulta Ahora'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final sinaprocDetalle = result.detalles.firstWhere(
      (d) => d['fuente'] == 'SINAPROC',
      orElse: () => <String, dynamic>{},
    );

    final tieneSinaproc = sinaprocDetalle.isNotEmpty;
    final tieneMiviot = _miviotResult != null && _miviotResult!.encontrado;
    final tieneApp = result.detalles.any((d) => d['fuente'] == 'APP');
    final miviotDioTimeout = (_miviotResult != null && _miviotResult!.esTimeout) || result.esTimeout;
    final miviotDioError = _miviotResult != null && _miviotResult!.tieneError;

    // Caso: No se encontró en ninguna fuente
    if (!tieneSinaproc && !tieneMiviot && !tieneApp) {
      if (miviotDioTimeout || miviotDioError) {
        return Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.amber.shade400, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.timer_off_outlined, size: 48, color: Colors.amber.shade800),
                ),
                const SizedBox(height: 14),
                Text(
                  'El portal de MIVIOT tardó en responder',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'La consulta para la cédula ${result.cedula} no pudo completarse debido a que el portal externo del MIVIOT excedió el tiempo límite de espera.\n\n⚠️ Esto NO significa que su expediente no exista. Por favor presione el botón de abajo para reintentar la consulta.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade800, height: 1.4),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _consultando ? null : () => _ejecutarConsulta(force: true),
                    icon: _consultando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.refresh_rounded),
                    label: Text(_consultando ? 'Reintentando...' : 'Reintentar Consulta de MIVIOT'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ReportWizardScreen()),
                    );
                  },
                  icon: const Icon(Icons.add_location_alt, size: 18),
                  label: const Text('Crear Reporte de Emergencia'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // SOLO si ambas entidades confirmaron de forma concluyente que NO existe:
      return Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.search_off_rounded, size: 54, color: Colors.blueGrey.shade600),
              const SizedBox(height: 14),
              Text(
                'Sin registros para ${result.cedula}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Los sistemas oficiales de SINAPROC y MIVIOT certificaron que no existe una evaluación de daños ni expediente habitacional registrado para esta cédula.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportWizardScreen()),
                  );
                },
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Crear Reporte de Emergencia Ahora'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Caso: Sí se encontró información (Visión de Un Solo Registro)
    final titular = sinaprocDetalle['titular'] as String? ?? 'Residente';
    final provincia = sinaprocDetalle['provincia'] as String? ?? 'Los Santos';
    final distrito = sinaprocDetalle['distrito'] as String? ?? '';
    final corregimiento = sinaprocDetalle['corregimiento'] as String? ?? '';
    final sector = sinaprocDetalle['comunidad_sector'] as String? ?? '';

    final habitabilidad = sinaprocDetalle['habitabilidad'] as String? ?? 'HABITABLE';
    final semaforoColor = _obtenerColorSemaforo(habitabilidad);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tarjeta Principal Unificada (Encabezado)
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [const Color(0xFF003882), const Color(0xFF1B5E20)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified, size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'EXPEDIENTE OFICIAL UNIFICADO',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      result.cedulaCensurada.isNotEmpty ? result.cedulaCensurada : result.cedula,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  titular,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '$provincia • $distrito ${corregimiento.isNotEmpty ? "• $corregimiento" : ""} ${sector.isNotEmpty ? "($sector)" : ""}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    if (tieneSinaproc)
                      _buildChipFuente('SINAPROC EDAN', Colors.orange.shade700),
                    if (tieneMiviot)
                      _buildChipFuente('MIVIOT ODOO', Colors.green.shade600),
                    if (tieneApp)
                      _buildChipFuente('APP CIUDADANA', Colors.blue.shade600),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 1. Sección: Ficha de Inspección de Campo (SINAPROC EDAN)
        if (tieneSinaproc)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Icon(Icons.shield_outlined, color: Colors.orange.shade900, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Evaluación de Campo SINAPROC',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: semaforoColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: semaforoColor, width: 1.5),
                        ),
                        child: Text(
                          _traducirHabitabilidad(habitabilidad),
                          style: TextStyle(color: semaforoColor, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildFilaDato('Ficha de Inspección:', '#${sinaprocDetalle["external_id"]}'),
                  _buildFilaDato('Evaluador Oficial:', sinaprocDetalle['evaluador'] ?? 'Brigada SINAPROC'),
                  _buildFilaDato('Fecha de Inspección:', _formatearFecha(sinaprocDetalle['fecha'])),
                  _buildFilaDato('Tipo de Inmueble:', '${sinaprocDetalle["tipo_vivienda"]} de ${sinaprocDetalle["tipo_construccion"]}'),
                  _buildFilaDato('Daños en Infraestructura:', sinaprocDetalle['dano_descripcion'] == 'si' ? 'Daños reportados en estructura' : sinaprocDetalle['dano_descripcion'] ?? 'Sin daños'),
                  if ((sinaprocDetalle['calle_o_direccion'] as String?)?.isNotEmpty ?? false)
                    _buildFilaDato('Dirección Detallada:', sinaprocDetalle['calle_o_direccion']),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),

        // 2. Sección: Expediente Habitacional MIVIOT
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade700),
                      ),
                      child: Icon(Icons.home_work_outlined, color: Colors.green.shade800, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Expediente Habitacional MIVIOT',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (tieneMiviot)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.shade700),
                        ),
                        child: const Text(
                          'EN TRÁMITE',
                          style: TextStyle(color: Color(0xFF1B5E20), fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                  ],
                ),
                const Divider(height: 24),
                if (tieneMiviot) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        'Reporte ${_miviotResult!.reporte ?? "AFV"}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      if (_miviotResult!.fechaRecibido != null)
                        Text(
                          'Recibido el ${_miviotResult!.fechaRecibido}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildStepperMiviot(_miviotResult!.pasoActual ?? 1),
                ] else if (_miviotResult != null && _miviotResult!.tieneError) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.timer_off_outlined, color: Colors.amber.shade900, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _miviotResult!.esTimeout
                                    ? 'Consulta externa MIVIOT en espera (Timeout)'
                                    : 'Fallo al conectar con MIVIOT',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'El portal externo de MIVIOT tardó demasiado en responder. No se ha confirmado la inexistencia de su trámite.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _reintentandoMiviot ? null : _reintentarSoloMiviot,
                            icon: _reintentandoMiviot
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.refresh, size: 16),
                            label: Text(_reintentandoMiviot ? 'Reintentando...' : 'Reintentar consulta de MIVIOT'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'El MIVIOT certifica que no registra expediente formal para esta cédula.',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tieneSinaproc
                              ? 'Con su ficha de inspección de SINAPROC (#${sinaprocDetalle["external_id"]}), puede acudir a la sede provincial del MIVIOT para agilizar la apertura de su expediente.'
                              : 'Para iniciar la solicitud de ayuda habitacional, primero debe contar con la evaluación de daños.',
                          style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 3. Sección: Dictamen y Próximos Pasos
        Card(
          color: Colors.blue.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.blue.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_rounded, color: Colors.blue.shade800, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Orientación Oficial al Ciudadano',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue.shade900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tieneSinaproc && tieneMiviot
                            ? 'Su vivienda cuenta con evaluación de campo realizada por SINAPROC y un expediente habitacional en trámite ante el MIVIOT. Ambas entidades están vinculadas a su caso.'
                            : tieneSinaproc
                                ? 'La inspección de SINAPROC ya certificó el estado de habitabilidad de su hogar. Si requiere asistencia de reconstrucción, este dictamen es válido ante el MIVIOT.'
                                : 'Su trámite se encuentra registrado ante el MIVIOT.',
                        style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChipFuente(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildFilaDato(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 155,
            child: Text(
              etiqueta,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperMiviot(int pasoActual) {
    final pasos = MiviotTramiteResult.etapasOficiales;

    return Column(
      children: List.generate(pasos.length, (index) {
        final pasoNumero = index + 1;
        final isActual = pasoNumero == pasoActual;

        // Círculo verde #2e7d32 para la etapa actual, gris/azulado #8FA0AC para las demás
        final circleColor = isActual ? const Color(0xFF2E7D32) : const Color(0xFF8FA0AC);

        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Círculo numerado oficial
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: circleColor,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$pasoNumero',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Descripción oficial de la etapa
                Expanded(
                  child: Text(
                    pasos[index],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActual ? FontWeight.bold : FontWeight.normal,
                      color: isActual ? Colors.black87 : const Color(0xFF4B5563),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            // Flecha vertical conectando etapas
            if (index < pasos.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Center(
                        child: Icon(
                          Icons.arrow_downward_rounded,
                          size: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}
