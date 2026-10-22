import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../l10n/app_messages.dart';
import '../models/disaster_report.dart';
import '../services/api_service.dart';
import '../services/offline_queue_service.dart';
import '../services/panama_dpa_service.dart';
import '../services/reporter_profile_service.dart';
import 'report_wizard_screen.dart';
import '../widgets/miviot_tramite_dialog.dart';

class ReportViewModel {
  final String reportId;
  final String timestamp;
  final String fuente;
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
  final List<String> fotosUrls;
  final String nombreMascarado;
  final String cedulaMascarada;
  final List<String> sistemasVinculados;

  ReportViewModel({
    required this.reportId,
    required this.timestamp,
    this.fuente = 'APP',
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
    this.fotosUrls = const [],
    this.nombreMascarado = '',
    this.cedulaMascarada = '',
    this.sistemasVinculados = const ['APP'],
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
  DateTime? _ultimoRefresco;

  static const _keyPublicCache = 'lse_public_reports_cache';
  static const _keyLastFetch = 'lse_public_reports_last_fetch';

  // Filtros Nacionales
  String _filtroProvincia = 'TODAS';
  String _filtroDistrito = 'TODOS';
  String _filtroSincronizacion = 'TODOS'; // 'TODOS', 'SYNCED', 'PENDING', 'MINE'
  final String _filtroHabitabilidad = 'TODOS';

  ReporterProfile? _myProfile;

  String get _textoUltimaActualizacion {
    final msg = AppMessages.current;
    if (_ultimoRefresco == null) return msg.noSyncedData;
    final ahora = DateTime.now();
    final diff = ahora.difference(_ultimoRefresco!);
    if (diff.inSeconds < 60) {
      return msg.updatedSecondsAgo(diff.inSeconds);
    } else if (diff.inMinutes < 60) {
      return msg.updatedMinutesAgo(diff.inMinutes);
    } else {
      final hora = _ultimoRefresco!.hour.toString().padLeft(2, '0');
      final min = _ultimoRefresco!.minute.toString().padLeft(2, '0');
      return msg.updatedAtTime('$hora:$min');
    }
  }

  static String maskCedula(String? cedula) {
    if (cedula == null || cedula.trim().isEmpty) return '';
    final c = cedula.trim();
    if (c.length <= 4) return '${c.substring(0, 1)}***${c.substring(c.length - 1)}';
    final parts = c.split('-');
    if (parts.length >= 3) {
      return '${parts[0]}-***-${parts.last}';
    } else if (parts.length == 2) {
      final suffix = parts[1].length >= 3 ? parts[1].substring(parts[1].length - 3) : parts[1];
      return '${parts[0]}-***-$suffix';
    } else {
      return '${c.substring(0, 2)}***${c.substring(c.length - 3)}';
    }
  }

  static String maskName(String? name) {
    if (name == null || name.trim().isEmpty) return '';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    final first = parts[0][0].toUpperCase() + parts[0].substring(1).toLowerCase();
    if (parts.length > 1 && parts[1].isNotEmpty) {
      return '$first ${parts[1][0].toUpperCase()}.';
    }
    return first;
  }

  @override
  void initState() {
    super.initState();
    _cargarReportes();
  }

  Future<void> _solicitarRefrescoManual() async {
    final ahora = DateTime.now();
    if (_ultimoRefresco != null) {
      final diffSegundos = ahora.difference(_ultimoRefresco!).inSeconds;
      final segundosMinimos = AppConfig.publicMonitoringCacheMinutes * 60;
      if (diffSegundos < segundosMinimos) {
        final restan = segundosMinimos - diffSegundos;
        if (mounted) {
          final msg = AppMessages.current;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg.recentDataWaitNotice(diffSegundos, restan)),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    await _cargarReportes(esRefrescoManual: true);
  }

  Future<void> _cargarReportes({bool esRefrescoManual = false}) async {
    setState(() => _cargando = true);

    _myProfile = await ReporterProfileService.getOrCreateProfile();
    final localEntries = await OfflineQueueService.getAllLocalReports();
    final prefs = await SharedPreferences.getInstance();

    // 1. Cargar caché previo de SharedPreferences si existe
    final Map<String, dynamic> cachedFeaturesMap = {};
    final cachedRaw = prefs.getString(_keyPublicCache);
    if (cachedRaw != null && cachedRaw.isNotEmpty) {
      try {
        final list = jsonDecode(cachedRaw) as List<dynamic>;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final props = item['properties'] as Map<String, dynamic>? ?? {};
            final repId = (props['report_id'] ?? props['id'] ?? item['id']) as String? ?? '';
            if (repId.isNotEmpty) {
              cachedFeaturesMap[repId] = item;
            }
          }
        }
      } catch (_) {}
    }

    final lastFetchRaw = prefs.getString(_keyLastFetch);
    if (lastFetchRaw != null && lastFetchRaw.isNotEmpty && _ultimoRefresco == null) {
      try {
        _ultimoRefresco = DateTime.parse(lastFetchRaw).toLocal();
      } catch (_) {}
    }

    // 2. Determinar si se consulta a AWS (delta o carga inicial)
    bool debeConsultarAws = esRefrescoManual || cachedFeaturesMap.isEmpty;
    if (!debeConsultarAws && _ultimoRefresco != null) {
      final diffMinutos = DateTime.now().difference(_ultimoRefresco!).inMinutes;
      if (diffMinutos >= AppConfig.publicMonitoringCacheMinutes) {
        debeConsultarAws = true;
      }
    }

    if (debeConsultarAws) {
      final sinceParam = (cachedFeaturesMap.isNotEmpty && _ultimoRefresco != null)
          ? _ultimoRefresco!.toUtc().toIso8601String()
          : null;

      final geojson = await ApiService.fetchPublicReports(since: sinceParam);
      if (geojson != null && geojson['features'] is List) {
        final features = geojson['features'] as List<dynamic>;
        for (final f in features) {
          if (f is Map<String, dynamic>) {
            final props = f['properties'] as Map<String, dynamic>? ?? {};
            final repId = (props['report_id'] ?? props['id'] ?? f['id']) as String? ?? '';
            if (repId.isNotEmpty) {
              // Fusionar delta en el mapa del caché
              cachedFeaturesMap[repId] = f;
            }
          }
        }

        // Persistir caché consolidado en SharedPreferences
        _ultimoRefresco = DateTime.now();
        await prefs.setString(_keyPublicCache, jsonEncode(cachedFeaturesMap.values.toList()));
        await prefs.setString(_keyLastFetch, _ultimoRefresco!.toUtc().toIso8601String());
      }
    }

    // 3. Consolidar mapa en memoria para visualización
    final Map<String, ReportViewModel> itemsMap = {};

    // 3.1 Agregar reportes locales (creados en este dispositivo)
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
        fotosUrls: rep.fotosUrls,
        nombreMascarado: maskName(rep.afectadoNombre),
        cedulaMascarada: maskCedula(rep.documentoNumero),
        sistemasVinculados: entry.isSynced ? ['APP', 'SINAPROC'] : ['APP'],
      );
    }

    // 3.2 Agregar reportes remotos desde el caché consolidado
    for (final f in cachedFeaturesMap.values) {
      final props = f['properties'] as Map<String, dynamic>? ?? {};
      final repId = (props['report_id'] ?? props['id'] ?? f['id']) as String? ?? '';
      if (repId.isEmpty) continue;

      final isMine = _myProfile != null && (props['reporter_id'] == _myProfile!.reporterId);
      final fuente = (props['fuente'] as String?)?.toUpperCase() ?? 'APP';
      final remoteFotos = (props['fotos_urls'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final remoteSistemas = (props['sistemas_vinculados'] as List<dynamic>?)
              ?.map((e) => e.toString().toUpperCase())
              .toList() ??
          [fuente];

      final remoteNombre = (props['nombre_mascarado'] as String?) ?? '';
      final remoteCedula = (props['cedula_mascarada'] as String?) ?? '';

      if (itemsMap.containsKey(repId)) {
        final existing = itemsMap[repId]!;
        itemsMap[repId] = ReportViewModel(
          reportId: existing.reportId,
          timestamp: existing.timestamp,
          fuente: existing.fuente,
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
          fotosUrls: existing.fotosUrls.isNotEmpty ? existing.fotosUrls : remoteFotos,
          nombreMascarado: existing.nombreMascarado.isNotEmpty ? existing.nombreMascarado : remoteNombre,
          cedulaMascarada: existing.cedulaMascarada.isNotEmpty ? existing.cedulaMascarada : remoteCedula,
          sistemasVinculados: remoteSistemas,
        );
      } else {
        itemsMap[repId] = ReportViewModel(
          reportId: repId,
          timestamp: props['timestamp'] ?? '',
          fuente: fuente,
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
          fotosUrls: remoteFotos,
          nombreMascarado: remoteNombre,
          cedulaMascarada: remoteCedula,
          sistemasVinculados: remoteSistemas,
        );
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
    final pendientesAntes = await OfflineQueueService.getPendingCount();
    setState(() => _sincronizando = true);
    final count = await OfflineQueueService.flushQueue();
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
        mensaje = msg.syncNoConnection;
        color = Colors.orange;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: color,
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
            tooltip: 'Refrescar monitoreo',
            onPressed: _cargando ? null : _solicitarRefrescoManual,
          ),
        ],
      ),
      body: Column(
        children: [
          // Cintillo Informativo de Caché y Hora de Actualización
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: Colors.blueGrey.shade50,
            child: Row(
              children: [
                Icon(Icons.history_toggle_off, size: 16, color: Colors.blueGrey.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _textoUltimaActualizacion,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey.shade800,
                    ),
                  ),
                ),
                InkWell(
                  onTap: _cargando ? null : _solicitarRefrescoManual,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 14, color: Colors.blueGrey.shade800),
                        const SizedBox(width: 4),
                        Text(
                          'Refrescar',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                : RefreshIndicator(
                    onRefresh: _solicitarRefrescoManual,
                    child: filtered.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                              Icon(Icons.shield_outlined, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              const Center(
                                child: Text(
                                  'No hay reportes que coincidan con los filtros.',
                                  style: TextStyle(color: Colors.grey, fontSize: 16),
                                ),
                              ),
                            ],
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
                                  if (item.nombreMascarado.isNotEmpty || item.cedulaMascarada.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.blueGrey.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.badge_outlined, size: 15, color: Colors.blueGrey.shade700),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              AppMessages.current.titularInfo(item.nombreMascarado.isNotEmpty ? item.nombreMascarado : 'Afectado', item.cedulaMascarada.isNotEmpty ? item.cedulaMascarada : 'Registrada'),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.blueGrey.shade900,
                                             ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),

                                  // Estado Estructural y Peligros
                                  Row(
                                    children: [
                                      Text(
                                        AppMessages.current.damageHabitability(item.habitabilidad),
                                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                                      ),
                                      if (item.riesgoColapso) ...[
                                        const SizedBox(width: 8),
                                        Text(AppMessages.current.hazardCollapse, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                      if (item.requiereAlbergue) ...[
                                        const SizedBox(width: 8),
                                        Text(AppMessages.current.hazardShelter, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                    ],
                                  ),
                                  const Divider(height: 16),

                                  // Trazabilidad de Redes y Sistemas de Emergencia
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            AppMessages.current.traceabilityNetworksTitle,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.blueGrey,
                                            ),
                                          ),
                                          if (item.isMyReport && item.fullReport != null)
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                              onPressed: () async {
                                                await Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => ReportWizardScreen(initialReport: item.fullReport),
                                                  ),
                                                );
                                                _cargarReportes();
                                              },
                                              icon: const Icon(Icons.edit, size: 14),
                                              label: Text(AppMessages.current.edit, style: const TextStyle(fontSize: 11)),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          if (item.fuente == 'SINAPROC')
                                            _buildSystemBadge(
                                              label: AppMessages.current.badgeSinaprocEdan,
                                              icon: Icons.shield,
                                              active: true,
                                              color: Colors.orange.shade800,
                                            )
                                          else
                                            _buildSystemBadge(
                                              label: item.isSynced ? AppMessages.current.badgeReportApp : AppMessages.current.badgeReportAppLocal,
                                              icon: item.isSynced ? Icons.cloud_done : Icons.phone_android,
                                              active: true,
                                              color: item.isSynced ? Colors.teal : Colors.amber.shade800,
                                            ),
                                          if (item.sistemasVinculados.contains('MIVIOT'))
                                            _buildSystemBadge(
                                              label: AppMessages.current.badgeMiviot,
                                              icon: Icons.home_work,
                                              active: true,
                                              color: Colors.green.shade800,
                                            ),
                                          if (item.isMyReport)
                                            _buildSystemBadge(
                                              label: AppMessages.current.badgeMine,
                                              icon: Icons.person,
                                              active: true,
                                              color: Colors.blue.shade700,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.green.shade900,
                                              side: BorderSide(color: Colors.green.shade700),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              visualDensity: VisualDensity.compact,
                                            ),
                                            icon: const Icon(Icons.home_work, size: 14),
                                            label: Text(
                                              AppMessages.current.miviotConsultingBtn,
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                            onPressed: () => _mostrarDialogoMiviot(item),
                                          ),
                                        ],
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
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoMiviot(ReportViewModel item) {
    String cedulaInicial = '';
    if (item.isMyReport && item.fullReport?.documentoNumero != null) {
      cedulaInicial = item.fullReport!.documentoNumero!;
    } else if (_myProfile != null && _myProfile!.cedula.isNotEmpty) {
      cedulaInicial = _myProfile!.cedula;
    }

    if (cedulaInicial.isNotEmpty) {
      MiviotTramiteDialog.show(context, cedula: cedulaInicial);
      return;
    }

    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.home_work, color: Colors.green.shade800),
            const SizedBox(width: 8),
            const Text('Consultar Trámite MIVIOT', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa tu número de cédula para consultar el avance del expediente oficial en MIVIOT (Fases 1 a 5):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Cédula Panameña',
                hintText: 'Ej. 7-71-1473',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.credit_card),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppMessages.current.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800, foregroundColor: Colors.white),
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                Navigator.of(ctx).pop();
                MiviotTramiteDialog.show(context, cedula: val);
              }
            },
            child: Text(AppMessages.current.accept),
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

  Widget _buildSystemBadge({
    required String label,
    required IconData icon,
    required bool active,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.08) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? color.withValues(alpha: 0.5) : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? icon : Icons.radio_button_unchecked,
            size: 13,
            color: active ? color : Colors.grey.shade400,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? color : Colors.grey.shade500,
            ),
          ),
          if (active) ...[
            const SizedBox(width: 3),
            Icon(Icons.check, size: 11, color: color),
          ],
        ],
      ),
    );
  }
}
