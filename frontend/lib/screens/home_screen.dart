import 'package:flutter/material.dart';
import '../l10n/app_messages.dart';
import '../services/offline_queue_service.dart';
import '../services/reporter_profile_service.dart';
import 'citizen_query_screen.dart';
import 'national_dashboard_screen.dart';
import 'onboarding_profile_screen.dart';
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
    final msg = AppMessages.current;
    return Scaffold(
      appBar: AppBar(
        title: Text(msg.appTitle),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: msg.homeEditProfileTooltip,
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
            // Tarjeta de Bienvenida y Guía
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.volunteer_activism_rounded, color: Colors.red.shade800, size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bienvenido a Ayuda Panamá',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Plataforma ciudadana de asistencia y evaluación de daños. Consulta el estado de tu solicitud con tu cédula o registra un nuevo reporte de afectación.',
                          style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.35),
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
                        msg.homeOfflineReportsCount(_pendingReports),
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
                          : Text(msg.homeSyncBtn),
                    ),
                  ],
                ),
              ),

            // Botón Principal Verde (De Primero): CONSULTA ESTADO DE MI SOLICITUD
            ElevatedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CitizenQueryScreen()),
                );
                _actualizarEstado();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20), // Verde oficial
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
              ),
              child: const Column(
                children: [
                  Icon(Icons.assignment_turned_in_rounded, size: 36),
                  SizedBox(height: 8),
                  Text(
                    'CONSULTA ESTADO DE MI SOLICITUD',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Búsqueda unificada en SINAPROC y MIVIOT por cédula',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Botón Secundario Rojo: CREAR REPORTE DE EMERGENCIA
            ElevatedButton(
              onPressed: () async {
                final isConfigured = await ReporterProfileService.isProfileConfigured();
                if (!isConfigured) {
                  if (!context.mounted) return;
                  final completed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const OnboardingProfileScreen(isFirstReportFlow: true),
                    ),
                  );
                  if (completed != true) return;
                }
                if (!context.mounted) return;
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
              child: Column(
                children: [
                  const Icon(Icons.add_location_alt, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    msg.homeReportBtnTitle,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    msg.homeReportBtnSubtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Botón Secundario: ESTADÍSTICA NACIONAL
            OutlinedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NationalDashboardScreen()),
                );
                _actualizarEstado();
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(color: Colors.blueGrey.shade800, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(Icons.analytics_rounded, color: Colors.blueGrey.shade900),
              label: Text(
                'ESTADÍSTICA NACIONAL',
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
