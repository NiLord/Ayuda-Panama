import 'package:flutter/material.dart';
import '../l10n/app_messages.dart';
import '../models/miviot_tramite_result.dart';
import '../services/duplicate_check_service.dart';

class MiviotTramiteDialog extends StatefulWidget {
  final String cedula;
  final MiviotTramiteResult? initialResult;

  const MiviotTramiteDialog({
    super.key,
    required this.cedula,
    this.initialResult,
  });

  static Future<void> show(
    BuildContext context, {
    required String cedula,
    MiviotTramiteResult? initialResult,
  }) {
    return showDialog(
      context: context,
      builder: (_) => MiviotTramiteDialog(
        cedula: cedula,
        initialResult: initialResult,
      ),
    );
  }

  @override
  State<MiviotTramiteDialog> createState() => _MiviotTramiteDialogState();
}

class _MiviotTramiteDialogState extends State<MiviotTramiteDialog> {
  late MiviotTramiteResult? _result;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    if (_result == null) {
      _consultar(force: false);
    }
  }

  Future<void> _consultar({bool force = false}) async {
    setState(() => _cargando = true);
    final res = await DuplicateCheckService.consultarTramiteMiviot(
      widget.cedula,
      force: force,
    );
    if (mounted) {
      setState(() {
        _result = res;
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final msg = AppMessages.current;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade700, width: 1.5),
            ),
            child: Icon(Icons.home_work, color: Colors.green.shade800, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.miviotDialogTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Cédula: ${widget.cedula}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _cargando
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.green),
                    SizedBox(height: 16),
                    Text(
                      'Consultando portal oficial de MIVIOT...',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ],
                ),
              )
            : _result == null || !_result!.encontrado
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline, size: 48, color: Colors.amber.shade800),
                        const SizedBox(height: 12),
                        Text(
                          _result?.mensaje ?? msg.miviotNoTramite,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tarjeta de Resumen
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    msg.miviotReportNumber(_result!.reporte ?? 'Sin asignar'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade900,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade700,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'ACTIVO',
                                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              if (_result!.fechaRecibido != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  msg.miviotDateReceived(_result!.fechaRecibido!),
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Etapas del Proceso de Vivienda:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 10),

                        // Stepper de las 5 Etapas del MIVIOT
                        ...List.generate(5, (index) {
                          final stepNumber = index + 1;
                          final currentStep = _result!.pasoActual ?? 1;
                          final isCompleted = stepNumber < currentStep;
                          final isActive = stepNumber == currentStep;
                          final etapaNombre = MiviotTramiteResult.etapasOficiales[index];

                          Color circleColor;
                          Color textColor;
                          FontWeight fontWeight;
                          Widget iconChild;

                          if (isCompleted) {
                            circleColor = Colors.green.shade700;
                            textColor = Colors.black87;
                            fontWeight = FontWeight.normal;
                            iconChild = const Icon(Icons.check, size: 14, color: Colors.white);
                          } else if (isActive) {
                            circleColor = const Color(0xFF2E7D32); // Verde oficial MIVIOT
                            textColor = Colors.green.shade900;
                            fontWeight = FontWeight.bold;
                            iconChild = Text(
                              '$stepNumber',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            );
                          } else {
                            circleColor = Colors.grey.shade400;
                            textColor = Colors.grey.shade600;
                            fontWeight = FontWeight.normal;
                            iconChild = Text(
                              '$stepNumber',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            );
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: circleColor,
                                  child: iconChild,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        etapaNombre,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: fontWeight,
                                          color: textColor,
                                        ),
                                      ),
                                      if (isActive)
                                        Container(
                                          margin: const EdgeInsets.only(top: 2),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade100,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Fase actual en ejecución',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.green.shade900,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
      ),
      actions: [
        if (_result != null && !_cargando)
          TextButton.icon(
            onPressed: () => _consultar(force: true),
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(msg.miviotRefreshBtn),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(msg.close),
        ),
      ],
    );
  }
}
