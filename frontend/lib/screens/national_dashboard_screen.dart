import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/national_dashboard_data.dart';
import '../services/api_service.dart';

class NationalDashboardScreen extends StatefulWidget {
  const NationalDashboardScreen({super.key});

  @override
  State<NationalDashboardScreen> createState() => _NationalDashboardScreenState();
}

class _NationalDashboardScreenState extends State<NationalDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  NationalDashboardData? _data;
  bool _isLoading = true;
  String? _errorMessage;

  // Filtro por provincia: null significa "Todas"
  String? _selectedProvincia;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  int _territorialViewMode = 0; // 0: Por Distritos, 1: Ranking General
  final Set<String> _expandedDistricts = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargarDatos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Lee el registro horario precalculado sin disparar ningún cálculo pesado
  Future<void> _cargarDatos() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.fetchNationalDashboard();
      if (mounted) {
        setState(() {
          _data = res;
          _isLoading = false;
          if (res == null) {
            _errorMessage = 'No se pudo cargar la información del dashboard nacional.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error de conexión al consultar el dashboard.';
        });
      }
    }
  }

  String _formatNumber(int number) {
    final str = number.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return str.replaceAllMapped(reg, (Match m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    const bgDark = Color(0xFF0F172A); // Slate 900
    const cardDark = Color(0xFF1E293B); // Slate 800
    const borderDark = Color(0xFF334155); // Slate 700

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ESTADÍSTICA NACIONAL',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'Afectación y Evaluación de Daños',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Consultar datos actualizados',
            onPressed: _isLoading ? null : () => _cargarDatos(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF38BDF8),
          indicatorWeight: 3,
          labelColor: const Color(0xFF38BDF8),
          unselectedLabelColor: const Color(0xFF94A3B8),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'POBLACIÓN', icon: Icon(Icons.groups_rounded, size: 20)),
            Tab(text: 'SEVERIDAD Y PROVINCIAS', icon: Icon(Icons.location_city_rounded, size: 20)),
          ],
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF38BDF8)),
                  SizedBox(height: 16),
                  Text(
                    'Consultando información consolidada...',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  ),
                ],
              ),
            )
          : _errorMessage != null || _data == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage ?? 'Error inesperado',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _cargarDatos(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF38BDF8),
                            foregroundColor: bgDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Barra de última actualización (GMT-5 Panamá, sin "EN VIVO")
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFF38BDF8)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Última actualización: ${_data!.ultimaActualizacionTexto}',
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Selector Global de Provincias (afecta a Población y Severidad)
                    _buildGlobalProvinceSelector(
                      _data!.severidadHabitacional.provincias,
                      cardDark,
                      borderDark,
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPoblacionTab(
                            _data!.censoCoen,
                            _data!.severidadHabitacional,
                            cardDark,
                            borderDark,
                          ),
                          _buildSeveridadYProvinciasTab(
                            _data!.severidadHabitacional,
                            cardDark,
                            borderDark,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  // ===========================================================================
  // SELECTOR GLOBAL DE PROVINCIAS
  // ===========================================================================
  Widget _buildGlobalProvinceSelector(
    List<ProvinciaSeveridadItem> provincias,
    Color cardBg,
    Color border,
  ) {
    return Container(
      width: double.infinity,
      color: cardBg.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded, color: Color(0xFF38BDF8), size: 15),
              const SizedBox(width: 6),
              Text(
                _selectedProvincia == null
                    ? 'Ámbito: República de Panamá (Nacional)'
                    : 'Provincia: ${_selectedProvincia!.toUpperCase()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_selectedProvincia != null)
                InkWell(
                  onTap: () {
                    setState(() {
                      _selectedProvincia = null;
                      _searchQuery = '';
                      _searchController.clear();
                      _expandedDistricts.clear();
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Ver Nacional',
                      style: TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ChoiceChip(
                    label: const Text('Todas'),
                    selected: _selectedProvincia == null,
                    selectedColor: const Color(0xFF38BDF8),
                    backgroundColor: const Color(0xFF0F172A),
                    visualDensity: VisualDensity.compact,
                    labelStyle: TextStyle(
                      color: _selectedProvincia == null ? const Color(0xFF0F172A) : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedProvincia = null;
                          _searchQuery = '';
                          _searchController.clear();
                          _expandedDistricts.clear();
                        });
                      }
                    },
                  ),
                ),
                ...provincias.map((p) {
                  final isSelected =
                      _selectedProvincia?.toLowerCase() == p.provincia.toLowerCase();
                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ChoiceChip(
                      label: Text(p.provincia),
                      selected: isSelected,
                      selectedColor: const Color(0xFF38BDF8),
                      backgroundColor: const Color(0xFF0F172A),
                      visualDensity: VisualDensity.compact,
                      labelStyle: TextStyle(
                        color: isSelected ? const Color(0xFF0F172A) : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      onSelected: (selected) {
                        setState(() {
                          _selectedProvincia = selected ? p.provincia : null;
                          _searchQuery = '';
                          _searchController.clear();
                          _expandedDistricts.clear();
                        });
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // DISCLAIMER INSTITUCIONAL REQUERIDO
  // ===========================================================================
  Widget _buildInstitutionalDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Aviso: Esta información se brinda con fines preliminares y de visualización en desarrollo. La única fuente oficial de la verdad son las autoridades competentes como el SINAPROC. Esta aplicación busca apoyar y brindar visibilidad a la labor de las instituciones en campo.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: POBLACIÓN (NÚMEROS GRANDES Y DESTACADOS)
  // ===========================================================================
  Widget _buildPoblacionTab(
    CensoCoen censo,
    SeveridadHabitacional sev,
    Color cardBg,
    Color border,
  ) {
    ProvinciaSeveridadItem? selectedItem;
    if (_selectedProvincia != null) {
      for (final p in sev.provincias) {
        if (p.provincia.toLowerCase() == _selectedProvincia!.toLowerCase()) {
          selectedItem = p;
          break;
        }
      }
    }

    final int familias = selectedItem != null ? selectedItem.total : censo.familiasAfectadas;
    final int personas = selectedItem != null ? selectedItem.totalPersonas : censo.personasAfectadas;
    final int discapacidad = selectedItem != null ? selectedItem.conDiscapacidad : censo.conDiscapacidad;
    final int embarazadas = selectedItem != null ? selectedItem.embarazadas : censo.embarazadas;
    final int colapsos = selectedItem != null ? selectedItem.colapsosEstructurales : sev.colapsosEstructurales;
    final int inundaciones = selectedItem != null ? selectedItem.inundaciones : sev.inundaciones;

    final GeneroStats genero = (selectedItem != null && selectedItem.genero != null)
        ? selectedItem.genero!
        : censo.genero;

    final List<GrupoEtarioItem> gruposEtarios =
        (selectedItem != null && selectedItem.gruposEtarios.isNotEmpty)
            ? selectedItem.gruposEtarios
            : censo.gruposEtarios;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInstitutionalDisclaimer(),

        if (selectedItem != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded, color: Color(0xFF38BDF8), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Población Afectada: ${selectedItem.provincia.toUpperCase()}',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // 4 KPI Cards en Grid 2x2 con Números Grandes (fontSize: 26)
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.25,
          children: [
            _buildLargeKpiCard(
              title: 'Familias Afectadas',
              value: _formatNumber(familias),
              icon: Icons.family_restroom_rounded,
              color: const Color(0xFF38BDF8),
              cardBg: cardBg,
              border: border,
            ),
            _buildLargeKpiCard(
              title: 'Total Personas',
              value: _formatNumber(personas),
              icon: Icons.groups_rounded,
              color: const Color(0xFF6366F1),
              cardBg: cardBg,
              border: border,
            ),
            _buildLargeKpiCard(
              title: 'Con Discapacidad',
              value: _formatNumber(discapacidad),
              icon: Icons.accessible_forward_rounded,
              color: const Color(0xFFF59E0B),
              cardBg: cardBg,
              border: border,
            ),
            _buildLargeKpiCard(
              title: 'Embarazadas',
              value: _formatNumber(embarazadas),
              icon: Icons.pregnant_woman_rounded,
              color: const Color(0xFFEC4899),
              cardBg: cardBg,
              border: border,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Situaciones de Emergencia (Colapsos e Inundaciones)
        Row(
          children: [
            Expanded(
              child: _buildLargeKpiCard(
                title: 'Colapso de Estructura',
                value: _formatNumber(colapsos),
                icon: Icons.foundation_rounded,
                color: const Color(0xFFE11D48),
                cardBg: cardBg,
                border: border,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildLargeKpiCard(
                title: 'Inundaciones',
                value: _formatNumber(inundaciones),
                icon: Icons.water_damage_rounded,
                color: const Color(0xFF0284C7),
                cardBg: cardBg,
                border: border,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Género (Masculino / Femenino)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.wc_rounded, color: Color(0xFF38BDF8), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Distribución por Género',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildGenderCard(
                      label: 'Masculino',
                      count: _formatNumber(genero.masculinoTotal),
                      percentage: genero.masculinoPorcentaje,
                      color: const Color(0xFF38BDF8),
                      icon: Icons.male_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildGenderCard(
                      label: 'Femenino',
                      count: _formatNumber(genero.femeninoTotal),
                      percentage: genero.femeninoPorcentaje,
                      color: const Color(0xFFEC4899),
                      icon: Icons.female_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    children: [
                      Expanded(
                        flex: (genero.masculinoPorcentaje * 10).toInt(),
                        child: Container(color: const Color(0xFF38BDF8)),
                      ),
                      Expanded(
                        flex: (genero.femeninoPorcentaje * 10).toInt(),
                        child: Container(color: const Color(0xFFEC4899)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Demografía por Grupo Etario (5 rangos)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.cake_rounded, color: Color(0xFFF59E0B), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Demografía por Rango Etario',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...gruposEtarios.map((item) => _buildAgeGroupRow(item)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Donut Chart "Proporcional por Edad"
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.donut_large_rounded, color: Color(0xFF10B981), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Proporción por Edad',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: SizedBox(
                  width: 170,
                  height: 170,
                  child: CustomPaint(
                    painter: _DonutChartPainter(
                      grupos: gruposEtarios,
                      total: personas,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatNumber(personas),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Text(
                            'Personas',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: gruposEtarios.map((item) {
                  final color = _hexToColor(item.colorHex);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${item.label} (${item.porcentaje}%)',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 2: SEVERIDAD Y FILTRO POR PROVINCIA (CON DISTRITOS)
  // ===========================================================================
  Widget _buildSeveridadYProvinciasTab(
    SeveridadHabitacional sev,
    Color cardBg,
    Color border,
  ) {
    // Si hay una provincia seleccionada, buscamos sus datos específicos
    ProvinciaSeveridadItem? selectedItem;
    if (_selectedProvincia != null) {
      for (final p in sev.provincias) {
        if (p.provincia.toLowerCase() == _selectedProvincia!.toLowerCase()) {
          selectedItem = p;
          break;
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInstitutionalDisclaimer(),

        // SECCIÓN ESPECÍFICA DE LA PROVINCIA SELECCIONADA
        if (selectedItem != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1E293B),
                  const Color(0xFF38BDF8).withValues(alpha: 0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      selectedItem.provincia.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_formatNumber(selectedItem.total)} Viviendas',
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (selectedItem.totalPersonas > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_formatNumber(selectedItem.totalPersonas)} Personas',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 4 Tarjetas de Severidad para esta provincia
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.5,
                  children: [
                    _buildProvinceSeverityTile(
                      label: 'Pérdida Total',
                      sublabel: 'Inhabitables',
                      count: selectedItem.perdidaTotal,
                      color: const Color(0xFFEF4444),
                    ),
                    _buildProvinceSeverityTile(
                      label: 'Daño Parcial',
                      sublabel: 'Techos / Muros',
                      count: selectedItem.danoParcial,
                      color: const Color(0xFFF97316),
                    ),
                    _buildProvinceSeverityTile(
                      label: 'Moderado',
                      sublabel: 'Fisuras Menores',
                      count: selectedItem.moderado,
                      color: const Color(0xFFF59E0B),
                    ),
                    _buildProvinceSeverityTile(
                      label: 'Leve / Menor',
                      sublabel: 'Habitables',
                      count: selectedItem.leveMenor,
                      color: const Color(0xFF10B981),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 2 Situaciones de Emergencia para la provincia
                Row(
                  children: [
                    Expanded(
                      child: _buildProvinceSeverityTile(
                        label: 'Colapso Estructura',
                        sublabel: 'Reportes de campo',
                        count: selectedItem.colapsosEstructurales,
                        color: const Color(0xFFE11D48),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildProvinceSeverityTile(
                        label: 'Inundaciones',
                        sublabel: 'Viviendas anegadas',
                        count: selectedItem.inundaciones,
                        color: const Color(0xFF0284C7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // JERARQUÍA TERRITORIAL: DISTRITOS Y CORREGIMIENTOS
          _buildProvinceTerritorialHierarchy(selectedItem, cardBg, border),
          const SizedBox(height: 20),
        ] else ...[
          // SECCIÓN GENERAL NACIONAL (4 TARJETAS CON NÚMEROS GRANDES)
          const Text(
            'Severidad a Nivel Nacional',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: [
              _buildLargeSeverityCard(
                cat: sev.perdidaTotal,
                icon: Icons.cancel_rounded,
                color: const Color(0xFFEF4444),
                cardBg: cardBg,
                border: border,
              ),
              _buildLargeSeverityCard(
                cat: sev.danoParcial,
                icon: Icons.warning_rounded,
                color: const Color(0xFFF97316),
                cardBg: cardBg,
                border: border,
              ),
              _buildLargeSeverityCard(
                cat: sev.moderado,
                icon: Icons.report_problem_rounded,
                color: const Color(0xFFF59E0B),
                cardBg: cardBg,
                border: border,
              ),
              _buildLargeSeverityCard(
                cat: sev.leveMenor,
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF10B981),
                cardBg: cardBg,
                border: border,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Situaciones de Emergencia Nacionales
          Row(
            children: [
              Expanded(
                child: _buildLargeKpiCard(
                  title: 'Colapso de Estructura',
                  value: _formatNumber(sev.colapsosEstructurales),
                  icon: Icons.foundation_rounded,
                  color: const Color(0xFFE11D48),
                  cardBg: cardBg,
                  border: border,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildLargeKpiCard(
                  title: 'Inundaciones',
                  value: _formatNumber(sev.inundaciones),
                  icon: Icons.water_damage_rounded,
                  color: const Color(0xFF0284C7),
                  cardBg: cardBg,
                  border: border,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Gráfico de Barras Apiladas por Provincia
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bar_chart_rounded, color: Color(0xFF38BDF8), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Distribución por Provincia (Toque para filtrar)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildLegendItem('Pérdida Total', const Color(0xFFEF4444)),
                    const SizedBox(width: 12),
                    _buildLegendItem('Parcial/Mod', const Color(0xFFF97316)),
                    const SizedBox(width: 12),
                    _buildLegendItem('Leve/Menor', const Color(0xFF10B981)),
                  ],
                ),
                const SizedBox(height: 16),
                ...sev.provincias.map((p) => _buildProvinceStackedBar(p)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProvinceSeverityTile({
    required String label,
    required String sublabel,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _formatNumber(count),
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            sublabel,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildProvinceStackedBar(ProvinciaSeveridadItem p) {
    final int parcialMod = p.danoParcial + p.moderado;
    final int total = p.total > 0 ? p.total : 1;

    return InkWell(
      onTap: () {
        setState(() => _selectedProvincia = p.provincia);
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      p.provincia,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Color(0xFF38BDF8)),
                  ],
                ),
                Text(
                  _formatNumber(p.total),
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    if (p.perdidaTotal > 0)
                      Expanded(
                        flex: (p.perdidaTotal / total * 1000).toInt(),
                        child: Container(color: const Color(0xFFEF4444)),
                      ),
                    if (parcialMod > 0)
                      Expanded(
                        flex: (parcialMod / total * 1000).toInt(),
                        child: Container(color: const Color(0xFFF97316)),
                      ),
                    if (p.leveMenor > 0)
                      Expanded(
                        flex: (p.leveMenor / total * 1000).toInt(),
                        child: Container(color: const Color(0xFF10B981)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // JERARQUÍA TERRITORIAL: DISTRITOS Y CORREGIMIENTOS (ESTILO REFERENCIA COEN)
  // ===========================================================================
  Widget _buildProvinceTerritorialHierarchy(
    ProvinciaSeveridadItem province,
    Color cardBg,
    Color border,
  ) {
    final query = _searchQuery.trim().toLowerCase();

    // Filtro por búsqueda de distritos o corregimientos
    final matchingDistricts = province.distritos.where((d) {
      if (query.isEmpty) return true;
      if (d.nombre.toLowerCase().contains(query)) return true;
      return d.corregimientos.any((c) => c.nombre.toLowerCase().contains(query));
    }).toList();

    // Filtro para ranking general
    final matchingRanking = province.rankingCorregimientos.where((c) {
      if (query.isEmpty) return true;
      return c.nombre.toLowerCase().contains(query) || c.distrito.toLowerCase().contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Controles de Búsqueda y Segmented Control
        _buildHierarchyControls(province, cardBg, border),
        const SizedBox(height: 14),

        if (_territorialViewMode == 0) ...[
          // MODO 0: POR DISTRITOS
          if (matchingDistricts.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Text(
                query.isNotEmpty
                    ? 'No se encontraron distritos o corregimientos con "$query"'
                    : 'No hay datos territoriales disponibles.',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            )
          else
            ...matchingDistricts.map((d) {
              final isExpanded = query.isNotEmpty ||
                  _expandedDistricts.contains(d.nombre) ||
                  (_expandedDistricts.isEmpty && d == matchingDistricts.first);

              return _buildDistrictAccordionItem(
                d,
                isExpanded: isExpanded,
                onToggle: () {
                  setState(() {
                    if (_expandedDistricts.contains(d.nombre)) {
                      _expandedDistricts.remove(d.nombre);
                    } else {
                      _expandedDistricts.add(d.nombre);
                    }
                  });
                },
                query: query,
              );
            }),
        ] else ...[
          // MODO 1: RANKING GENERAL DE CORREGIMIENTOS
          if (matchingRanking.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Text(
                query.isNotEmpty
                    ? 'No se encontraron corregimientos con "$query"'
                    : 'No hay corregimientos registrados para esta provincia.',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            )
          else
            ...matchingRanking.asMap().entries.map((entry) {
              return _buildCorregimientoCard(entry.value, rank: entry.key + 1);
            }),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildHierarchyControls(
    ProvinciaSeveridadItem province,
    Color cardBg,
    Color border,
  ) {
    return Column(
      children: [
        // Buscador estilizado con icono y clear
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Buscar corregimiento o distrito...',
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8), size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (val) {
              setState(() => _searchQuery = val);
            },
          ),
        ),
        const SizedBox(height: 12),

        // Tabs de visualización y botones Expandir / Colapsar
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Segmented control [ Por Distritos | Ranking General ]
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSegmentButton(
                    title: 'Por Distritos',
                    icon: Icons.groups_rounded,
                    isSelected: _territorialViewMode == 0,
                    onTap: () => setState(() => _territorialViewMode = 0),
                  ),
                  const SizedBox(width: 4),
                  _buildSegmentButton(
                    title: 'Ranking General',
                    icon: Icons.format_list_numbered_rounded,
                    isSelected: _territorialViewMode == 1,
                    onTap: () => setState(() => _territorialViewMode = 1),
                  ),
                ],
              ),
            ),

            if (_territorialViewMode == 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _expandedDistricts.addAll(province.distritos.map((d) => d.nombre));
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        'Expandir todos',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const Text(
                    '•',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _expandedDistricts.clear();
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        'Colapsar todos',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSegmentButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF38BDF8) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 5),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistrictAccordionItem(
    DistritoTerritorialItem d, {
    required bool isExpanded,
    required VoidCallback onToggle,
    required String query,
  }) {
    final corregs = query.isEmpty
        ? d.corregimientos
        : d.corregimientos.where((c) {
            return c.nombre.toLowerCase().contains(query) ||
                d.nombre.toLowerCase().contains(query);
          }).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpanded
              ? const Color(0xFF38BDF8).withValues(alpha: 0.6)
              : const Color(0xFF334155),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.account_balance_rounded,
                      color: Color(0xFF38BDF8),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.nombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 12),
                            children: [
                              const TextSpan(
                                text: '🔴 ',
                                style: TextStyle(fontSize: 10),
                              ),
                              TextSpan(
                                text: '${d.perdidaTotal} colapsos',
                                style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const TextSpan(
                                text: ' • ',
                                style: TextStyle(color: Color(0xFF64748B)),
                              ),
                              TextSpan(
                                text: '${_formatNumber(d.totalViviendas)} viv.',
                                style: const TextStyle(
                                  color: Color(0xFFCBD5E1),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(
                                text: ' • ',
                                style: TextStyle(color: Color(0xFF64748B)),
                              ),
                              TextSpan(
                                text: '${d.totalCorregimientos} correg.',
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: isExpanded ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: Color(0xFF334155)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(
                children: corregs.map((c) => _buildCorregimientoCard(c)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCorregimientoCard(
    CorregimientoTerritorialItem c, {
    int? rank,
  }) {
    final totalViv = c.totalViviendas > 0 ? c.totalViviendas : 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF131E31),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.7)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Color(0xFFEF4444),
                width: 4.5,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (rank != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      margin: const EdgeInsets.only(right: 8, top: 1),
                      decoration: BoxDecoration(
                        color: rank <= 3
                            ? const Color(0xFFEF4444).withValues(alpha: 0.25)
                            : const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$rank',
                        style: TextStyle(
                          color: rank <= 3 ? const Color(0xFFFCA5A5) : const Color(0xFF94A3B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.nombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          c.distrito,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                    ),
                    child: RichText(
                      text: TextSpan(
                        children: [
                          const TextSpan(
                            text: '🔴 ',
                            style: TextStyle(fontSize: 10),
                          ),
                          TextSpan(
                            text: '${c.perdidaTotal} totales',
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const TextSpan(
                            text: ' | ',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                          ),
                          TextSpan(
                            text: 'Total: ${_formatNumber(c.totalViviendas)} viv.',
                            style: const TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Barra de colores apilada (4 severidades)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      if (c.perdidaTotal > 0)
                        Expanded(
                          flex: (c.perdidaTotal / totalViv * 1000).toInt(),
                          child: Container(color: const Color(0xFFEF4444)),
                        ),
                      if (c.danoParcial > 0)
                        Expanded(
                          flex: (c.danoParcial / totalViv * 1000).toInt(),
                          child: Container(color: const Color(0xFFF97316)),
                        ),
                      if (c.moderado > 0)
                        Expanded(
                          flex: (c.moderado / totalViv * 1000).toInt(),
                          child: Container(color: const Color(0xFFF59E0B)),
                        ),
                      if (c.leveMenor > 0)
                        Expanded(
                          flex: (c.leveMenor / totalViv * 1000).toInt(),
                          child: Container(color: const Color(0xFF10B981)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Puntos de métricas
              Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildMetricDot(
                    dotColor: const Color(0xFFEF4444),
                    count: c.perdidaTotal,
                    label: 'pt',
                  ),
                  _buildMetricDot(
                    dotColor: const Color(0xFFF97316),
                    count: c.danoParcial,
                    label: 'parcial',
                  ),
                  _buildMetricDot(
                    dotColor: const Color(0xFFF59E0B),
                    count: c.moderado,
                    label: 'mod',
                  ),
                  _buildMetricDot(
                    dotColor: const Color(0xFF10B981),
                    count: c.leveMenor,
                    label: 'leve',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricDot({
    required Color dotColor,
    required int count,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          _formatNumber(count),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // WIDGET HELPERS: NÚMEROS GRANDES (fontSize: 26)
  // ===========================================================================
  Widget _buildLargeKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color cardBg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeSeverityCard({
    required SeveridadCategoria cat,
    required IconData icon,
    required Color color,
    required Color cardBg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              Text(
                cat.subetiqueta,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatNumber(cat.total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                cat.etiqueta,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGenderCard({
    required String label,
    required String count,
    required double percentage,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              Icon(icon, color: color, size: 16),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            count,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$percentage%',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgeGroupRow(GrupoEtarioItem item) {
    final color = _hexToColor(item.colorHex);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(item.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${_formatNumber(item.count)} (${item.porcentaje}%)',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (item.porcentaje / 100.0).clamp(0.0, 1.0),
              backgroundColor: const Color(0xFF0F172A),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Color _hexToColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}

// =============================================================================
// PAINTER PARA EL DONUT CHART
// =============================================================================
class _DonutChartPainter extends CustomPainter {
  final List<GrupoEtarioItem> grupos;
  final int total;

  _DonutChartPainter({required this.grupos, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 24.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    double startAngle = -math.pi / 2;

    for (final g in grupos) {
      final sweepAngle = (g.porcentaje / 100.0) * (2 * math.pi);
      paint.color = _hexToColor(g.colorHex);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  Color _hexToColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return const Color(0xFF38BDF8);
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.grupos != grupos || oldDelegate.total != total;
  }
}
