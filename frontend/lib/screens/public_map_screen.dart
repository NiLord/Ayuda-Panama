import 'package:flutter/material.dart';
import '../models/disaster_report.dart';
import '../services/api_service.dart';
import '../services/offline_queue_service.dart';
import '../services/panama_dpa_service.dart';
import '../services/reporter_profile_service.dart';
import 'report_wizard_screen.dart';

class ReportViewModel {
  final String reportId;
  final String timestamp;
  final String provincia;
  final String distrito;
  final String corregimiento;
  final String comunidadSector;
  final String habitabilidad;
  final String semaforoColorHex;
  final String prioridad;
  final bool riesgoColapso;
  final bool requiereAlbergue;
  final bool isSynced;
  final bool isMyReport;
  final DisasterReport? fullReport;

  ReportViewModel({
    required this.reportId,
    required this.timestamp,
    required this.provincia,
    required this.distrito,
    required this.corregimiento,
    required this.comunidadSector,
    required this.habitabilidad,
    required this.semaforoColorHex,
    required this.prioridad,
    required this.riesgoColapso,
    required this.requiereAlbergue,
    required this.isSynced,
    required this.isMyReport,
    this.fullReport,
  });
}

class PublicMapScreen extends StatefulWidget {
  const PublicMapScreen({super.key});

  @override
  State<PublicMapScreen> createState() => _PublicMapScreenState();
}

class _PublicMapScreenState extends State<PublicMapScreen> {
  bool _cargando = true;
  bool _sincronizando = false;
  List<ReportViewModel> _reportes = [];

  // Filtros Nacionales
  String _filtroProvincia = 'TODAS';
  String _filtroDistrito = 'TODOS';
  String _filtroSincronizacion = 'TODOS'; // 'TODOS', 'SYNCED', 'PENDING', 'MINE'
  final String _filtroHabitabilidad = 'TODOS';

  ReporterProfile? _myProfile;

  @override
  void initState() {
    super.initState();
    _cargarReportes();
  }

  Future<void> _cargarReportes() async {
    setState(() => _cargando = true);

    _myProfile = await ReporterProfileService.getOrCreateProfile();
    final localEntries = await OfflineQueueService.getAllLocalReports();

    // Mapa para consolidar por ID
    final Map<String, ReportViewModel> itemsMap = {};

    // 1. Agregar reportes locales (creados en este dispositivo)
    for (final entry in localEntries) {
      final rep = entry.report;
      String colorHex;
      switch (rep.habitabilidad) {
        case 'HABITABLE':
          colorHex = '#2ECC71';
          break;
        case 'ACCESO_RESTRINGIDO':
          colorHex = '#F39C12';
          break;
        case 'INHABITABLE':
          colorHex = '#E74C3C';
          break;
        case 'COLAPSO_TOTAL':
          colorHex = '#8E44AD';
          break;
        default:
          colorHex = '#95A5A6';
      }

      final isCritico = rep.atrapadosDesaparecidos > 0 || rep.lesionadosGraves > 0;
      final prioridad = isCritico ? 'P1_CRITICO_VIDA' : 'P3';

      itemsMap[rep.reportId] = ReportViewModel(
        reportId: rep.reportId,
        timestamp: rep.timestamp,
        provincia: rep.provincia,
        distrito: rep.distrito,
        corregimiento: rep.corregimiento,
        comunidadSector: rep.comunidadSector,
        habitabilidad: rep.habitabilidad,
        semaforoColorHex: colorHex,
        prioridad: prioridad,
        riesgoColapso: rep.riesgoColapsoInminente,
        requiereAlbergue: rep.requiereAlbergue,
        isSynced: entry.isSynced,
        isMyReport: true,
        fullReport: rep,
      );
    }

    // 2. Consultar reportes remotos desde AWS
    final geojson = await ApiService.fetchPublicReports();
    if (geojson != null && geojson['features'] is List) {
      final features = geojson['features'] as List<dynamic>;
      for (final f in features) {
        final props = f['properties'] as Map<String, dynamic>? ?? {};
        final repId = props['report_id'] as String? ?? '';
        if (repId.isEmpty) continue;

        final isMine = _myProfile != null && props['reporter_id'] == _myProfile!.reporterId;

        // Si ya estaba en local, marcar como sincronizado
        if (itemsMap.containsKey(repId)) {
          final existing = itemsMap[repId]!;
          itemsMap[repId] = ReportViewModel(
            reportId: existing.reportId,
            timestamp: existing.timestamp,
            provincia: existing.provincia,
            distrito: existing.distrito,
            corregimiento: existing.corregimiento,
            comunidadSector: existing.comunidadSector,
            habitabilidad: existing.habitabilidad,
            semaforoColorHex: existing.semaforoColorHex,
            prioridad: existing.prioridad,
            riesgoColapso: existing.riesgoColapso,
            requiereAlbergue: existing.requiereAlbergue,
            isSynced: true, // Confirmado por AWS
            isMyReport: true,
            fullReport: existing.fullReport,
          );
        } else {
          // Reporte de otro informante en la nube
          itemsMap[repId] = ReportViewModel(
            reportId: repId,
            timestamp: props['timestamp'] ?? '',
            provincia: props['provincia'] ?? 'Panamá',
            distrito: props['distrito'] ?? '',
            corregimiento: props['corregimiento'] ?? '',
            comunidadSector: props['comunidad_sector'] ?? '',
            habitabilidad: props['habitabilidad'] ?? 'DESCONOCIDO',
            semaforoColorHex: props['semaforo_color'] ?? '#95A5A6',
            prioridad: props['prioridad'] ?? 'P3',
            riesgoColapso: props['riesgo_colapso'] ?? false,
            requiereAlbergue: props['necesidades_urgentes']?['albergue'] ?? false,
            isSynced: true,
            isMyReport: isMine,
          );
        }
      }
    }

    final sortedList = itemsMap.values.toList();
    sortedList.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (mounted) {
      setState(() {
        _reportes = sortedList;
        _cargando = false;
      });
    }
  }

  Future<void> _sincronizarPendientes() async {
    setState(() => _sincronizando = true);
    final count = await OfflineQueueService.flushQueue();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count > 0
              ? 'Se sincronizaron $count reporte(s) con AWS exitosamente.'
              : 'Sin conexión para sincronizar en este momento.'),
          backgroundColor: count > 0 ? Colors.green : Colors.orange,
        ),
      );
      setState(() => _sincronizando = false);
      await _cargarReportes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendientesCount = _reportes.where((r) => !r.isSynced).length;
    final provincias = ['TODAS', ...PanamaDpaService.getProvincias()];

    List<String> distritos = ['TODOS'];
    if (_filtroProvincia != 'TODAS') {
      distritos = ['TODOS', ...PanamaDpaService.getDistritos(_filtroProvincia)];
    }

    final filtered = _reportes.where((r) {
      if (_filtroProvincia != 'TODAS' && r.provincia != _filtroProvincia) return false;
      if (_filtroDistrito != 'TODOS' && r.distrito != _filtroDistrito) return false;
      if (_filtroSincronizacion == 'SYNCED' && !r.isSynced) return false;
      if (_filtroSincronizacion == 'PENDING' && r.isSynced) return false;
      if (_filtroSincronizacion == 'MINE' && !r.isMyReport) return false;
      if (_filtroHabitabilidad != 'TODOS' && r.habitabilidad != _filtroHabitabilidad) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoreo Nacional'),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: [
          if (pendientesCount > 0)
            IconButton(
              icon: _sincronizando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.sync, color: Colors.amberAccent),
              tooltip: 'Sincronizar reportes pendientes ($pendientesCount)',
              onPressed: _sincronizando ? null : _sincronizarPendientes,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargarReportes,
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de Alerta si hay reportes pendientes
          if (pendientesCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.amber.shade100,
              child: Row(
                children: [
                  const Icon(Icons.cloud_queue, size: 20, color: Colors.brown),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tienes $pendientesCount reporte(s) guardados localmente.',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.brown.shade900),
                    ),
                  ),
                  TextButton(
                    onPressed: _sincronizando ? null : _sincronizarPendientes,
                    child: const Text('SUBIR AHORA'),
                  ),
                ],
              ),
            ),

          // Filtros de Provincia y Distrito a Nivel Nacional
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _filtroProvincia,
                    decoration: const InputDecoration(
                      labelText: 'Provincia',
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      border: OutlineInputBorder(),
                    ),
                    items: provincias.map((p) => DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (val) {
                      setState(() {
                        _filtroProvincia = val ?? 'TODAS';
                        _filtroDistrito = 'TODOS';
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: distritos.contains(_filtroDistrito) ? _filtroDistrito : 'TODOS',
                    decoration: const InputDecoration(
                      labelText: 'Distrito',
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      border: OutlineInputBorder(),
                    ),
                    items: distritos.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (val) => setState(() => _filtroDistrito = val ?? 'TODOS'),
                  ),
                ),
              ],
            ),
          ),

          // Filtros rápidos por Estado / Mis Reportes
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('Todos (${_reportes.length})'),
                  selected: _filtroSincronizacion == 'TODOS',
                  onSelected: (_) => setState(() => _filtroSincronizacion = 'TODOS'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  avatar: const Icon(Icons.person, size: 16),
                  label: Text('Mis Reportes (${_reportes.where((r) => r.isMyReport).length})'),
                  selected: _filtroSincronizacion == 'MINE',
                  onSelected: (_) => setState(() => _filtroSincronizacion = 'MINE'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  avatar: const Icon(Icons.cloud_done, size: 16, color: Colors.green),
                  label: Text('En Nube (${_reportes.where((r) => r.isSynced).length})'),
                  selected: _filtroSincronizacion == 'SYNCED',
                  onSelected: (_) => setState(() => _filtroSincronizacion = 'SYNCED'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  avatar: const Icon(Icons.cloud_upload_outlined, size: 16, color: Colors.orange),
                  label: Text('Pendientes ($pendientesCount)'),
                  selected: _filtroSincronizacion == 'PENDING',
                  onSelected: (_) => setState(() => _filtroSincronizacion = 'PENDING'),
                ),
              ],
            ),
          ),

          // Leyenda de Habitabilidad ATC-20
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildBadge(Colors.green, 'Habitable'),
                _buildBadge(Colors.amber.shade700, 'Restringido'),
                _buildBadge(Colors.red, 'Inhabitable'),
                _buildBadge(Colors.purple.shade800, 'Colapso'),
              ],
            ),
          ),
          const Divider(height: 1),

          // Lista de Reportes
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'No hay reportes que coincidan con los filtros.',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        padding: const EdgeInsets.all(12),
                        itemBuilder: (context, idx) {
                          final item = filtered[idx];
                          Color statusColor;
                          try {
                            statusColor = Color(int.parse(item.semaforoColorHex.replaceFirst('#', '0xFF')));
                          } catch (_) {
                            statusColor = Colors.grey;
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              side: BorderSide(color: statusColor, width: 2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Encabezado con Ubicación y Badges de Sincronización
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(radius: 6, backgroundColor: statusColor),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${item.distrito} - ${item.comunidadSector.isNotEmpty ? item.comunidadSector : item.corregimiento}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                            ),
                                            Text(
                                              '${item.provincia} • ${item.corregimiento}',
                                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (item.prioridad == 'P1_CRITICO_VIDA')
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          margin: const EdgeInsets.only(left: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'P1 RESCATE',
                                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Estado Estructural y Peligros
                                  Row(
                                    children: [
                                      Text(
                                        'Daño: ${item.habitabilidad}',
                                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                                      ),
                                      if (item.riesgoColapso) ...[
                                        const SizedBox(width: 8),
                                        const Text('⚠️ Colapso', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                      if (item.requiereAlbergue) ...[
                                        const SizedBox(width: 8),
                                        const Text('⛺ Albergue', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                    ],
                                  ),
                                  const Divider(height: 16),

                                  // Barra inferior: Badges de Estado (Nube vs Local) + Botón Editar
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          // Badge de Sincronización Visual
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: item.isSynced ? Colors.green.shade50 : Colors.amber.shade50,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: item.isSynced ? Colors.green.shade600 : Colors.orange.shade700,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  item.isSynced ? Icons.cloud_done : Icons.cloud_upload_outlined,
                                                  size: 14,
                                                  color: item.isSynced ? Colors.green.shade700 : Colors.orange.shade800,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  item.isSynced ? 'En la Nube (AWS)' : 'Pendiente Local',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: item.isSynced ? Colors.green.shade800 : Colors.orange.shade900,
                                                 ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (item.isMyReport) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.blue.shade600),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.person, size: 12, color: Colors.blue),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    'Mío',
                                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),

                                      // Acción de Edición (Habilitada para reportes creados por el usuario)
                                      if (item.isMyReport && item.fullReport != null)
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                          onPressed: () async {
                                            await Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => ReportWizardScreen(initialReport: item.fullReport),
                                              ),
                                            );
                                            // Recargar datos tras regresar de la edición
                                            _cargarReportes();
                                          },
                                          icon: const Icon(Icons.edit, size: 15),
                                          label: const Text('Editar', style: TextStyle(fontSize: 12)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 5, backgroundColor: color),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
