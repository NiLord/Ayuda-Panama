import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PublicMapScreen extends StatefulWidget {
  const PublicMapScreen({super.key});

  @override
  State<PublicMapScreen> createState() => _PublicMapScreenState();
}

class _PublicMapScreenState extends State<PublicMapScreen> {
  bool _cargando = true;
  List<dynamic> _features = [];
  String _filtroDistrito = 'TODOS';

  @override
  void initState() {
    super.initState();
    _cargarReportesPublicos();
  }

  Future<void> _cargarReportesPublicos() async {
    setState(() => _cargando = true);
    final geojson = await ApiService.fetchPublicReports();
    if (geojson != null && geojson['features'] is List) {
      setState(() {
        _features = geojson['features'] as List<dynamic>;
      });
    }
    setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    final filteredFeatures = _features.where((f) {
      if (_filtroDistrito == 'TODOS') return true;
      final props = f['properties'] as Map<String, dynamic>? ?? {};
      return props['distrito'] == _filtroDistrito;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Situación Ciudadana'),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarReportesPublicos,
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de filtros y leyenda ATC-20
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                const Text('Distrito:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _filtroDistrito,
                  underline: const SizedBox(),
                  items: ['TODOS', 'Las Tablas', 'Guararé', 'Los Santos', 'Macaracas', 'Pedasí', 'Pocrí', 'Tonosí']
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (val) => setState(() => _filtroDistrito = val ?? 'TODOS'),
                ),
                const Spacer(),
                Text(
                  '${filteredFeatures.length} reportes',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
              ],
            ),
          ),

          // Leyenda de colores ATC-20
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 12,
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

          // Lista de Afectaciones
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : filteredFeatures.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'No hay reportes cargados en este distrito',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredFeatures.length,
                        padding: const EdgeInsets.all(12),
                        itemBuilder: (context, idx) {
                          final f = filteredFeatures[idx];
                          final props = f['properties'] as Map<String, dynamic>? ?? {};
                          final colorHex = props['semaforo_color'] as String? ?? '#95A5A6';
                          final habitabilidad = props['habitabilidad'] ?? 'DESCONOCIDO';
                          final comunidad = props['comunidad_sector'] ?? '';
                          final distrito = props['distrito'] ?? '';
                          final prioridad = props['prioridad'] ?? 'P3';
                          final albergue = props['necesidades_urgentes']?['albergue'] ?? false;
                          final colapso = props['riesgo_colapso'] ?? false;

                          Color statusColor;
                          try {
                            statusColor = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
                          } catch (_) {
                            statusColor = Colors.grey;
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              side: BorderSide(color: statusColor, width: 2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(radius: 6, backgroundColor: statusColor),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '$distrito - $comunidad',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                      ),
                                      if (prioridad == 'P1_CRITICO_VIDA')
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                  const SizedBox(height: 6),
                                  Text('Estado Estructural: $habitabilidad', style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
                                  if (colapso)
                                    const Text('⚠️ Riesgo inminente de colapso', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                  if (albergue)
                                    const Text('⛺ Requiere albergue urgente', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
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
