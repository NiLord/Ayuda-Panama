import 'package:flutter/material.dart';
import '../l10n/app_messages.dart';
import '../services/offline_queue_service.dart';
import '../services/reporter_profile_service.dart';
import 'onboarding_profile_screen.dart';
import 'public_map_screen.dart';
import 'report_wizard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _pendingReports = 0;
  bool _sincronizando = false;
  ReporterProfile? _profile;

  @override
  void initState() {
    super.initState();
    _actualizarEstado();
  }

  Future<void> _actualizarEstado() async {
    final count = await OfflineQueueService.getPendingCount();
    final profile = await ReporterProfileService.getOrCreateProfile();
    setState(() {
      _pendingReports = count;
      _profile = profile;
    });
  }

  Future<void> _sincronizarCola() async {
    final pendientesAntes = _pendingReports;
    setState(() => _sincronizando = true);
    final count = await OfflineQueueService.flushQueue();
    await _actualizarEstado();
    setState(() => _sincronizando = false);

    if (mounted) {
      final msg = AppMessages.current;
      String mensaje;
      Color color;
      if (count > 0) {
        mensaje = msg.syncedReportsSuccess(count);
        color = Colors.green;
      } else if (pendientesAntes == 0) {
        mensaje = msg.noPendingReportsToSync;
        color = Colors.blue;
      } else {
        mensaje = msg.syncFailedCheckConnection;
        color = Colors.orange;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: color,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayuda Panamá'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Mi Perfil de Informante',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OnboardingProfileScreen()),
              );
              _actualizarEstado();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner de Emergencia Sísmica
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade800, size: 36),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergencia Sísmica Activa',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tu reporte ayuda a SINAPROC y a los cuerpos de rescate a priorizar auxilio.',
                          style: TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Banner de Cola Offline si hay reportes pendientes
            if (_pendingReports > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$_pendingReports reporte(s) guardado(s) offline.',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _sincronizando ? null : _sincronizarCola,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: _sincronizando
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('SINCRONIZAR'),
                    ),
                  ],
                ),
              ),

            // Botón Principal: CREAR REPORTE DE EMERGENCIA
            ElevatedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReportWizardScreen()),
                );
                _actualizarEstado();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
              ),
              child: const Column(
                children: [
                  Icon(Icons.add_location_alt, size: 36),
                  SizedBox(height: 8),
                  Text(
                    'REPORTAR DAÑO O EMERGENCIA',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Funciona con o sin conexión a internet',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Botón Secundario: VER SITUACIÓN NACIONAL
            OutlinedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PublicMapScreen()),
                );
                _actualizarEstado();
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(color: Colors.blueGrey.shade800, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(Icons.public, color: Colors.blueGrey.shade900),
              label: Text(
                'VER SITUACIÓN NACIONAL',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade900),
              ),
            ),
            const SizedBox(height: 24),

            // Tarjeta de Identidad del Informante
            if (_profile != null && _profile!.nombre.isNotEmpty)
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_user, color: Colors.green, size: 20),
                          const SizedBox(width: 6),
                          const Text(
                            'Informante Registrado',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Text(
                            _profile!.rol,
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Nombre: ${_profile!.nombre}'),
                      Text('Teléfono: ${_profile!.telefono}'),
                      if (_profile!.organizacion.isNotEmpty)
                        Text('Organización: ${_profile!.organizacion}'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
