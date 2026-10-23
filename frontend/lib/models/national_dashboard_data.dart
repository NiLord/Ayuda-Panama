/// Modelos tipados para el Dashboard Nacional (COEN y Severidad Habitacional)
/// Refleja fielmente la información oficial agregada de SINAPROC y la Plataforma de Emergencia.
library;

class NationalDashboardData {
  final CensoCoen censoCoen;
  final SeveridadHabitacional severidadHabitacional;
  final String ultimaActualizacionIso;
  final String ultimaActualizacionTexto;
  final int totalRegistrosEvaluados;

  NationalDashboardData({
    required this.censoCoen,
    required this.severidadHabitacional,
    required this.ultimaActualizacionIso,
    required this.ultimaActualizacionTexto,
    required this.totalRegistrosEvaluados,
  });

  factory NationalDashboardData.fromJson(Map<String, dynamic> json) {
    final meta = json['metadatos'] as Map<String, dynamic>? ?? {};
    return NationalDashboardData(
      censoCoen: CensoCoen.fromJson(json['censo_coen'] as Map<String, dynamic>? ?? {}),
      severidadHabitacional: SeveridadHabitacional.fromJson(
        json['severidad_habitacional'] as Map<String, dynamic>? ?? {},
      ),
      ultimaActualizacionIso: meta['ultima_actualizacion_iso']?.toString() ?? '',
      ultimaActualizacionTexto: meta['ultima_actualizacion_texto']?.toString() ?? '',
      totalRegistrosEvaluados: _asInt(meta['total_registros_evaluados']),
    );
  }

  static int _asInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    return int.tryParse(val.toString()) ?? 0;
  }

  static double _asDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }
}

class CensoCoen {
  final int familiasAfectadas;
  final int personasAfectadas;
  final int conDiscapacidad;
  final int embarazadas;
  final GeneroStats genero;
  final List<GrupoEtarioItem> gruposEtarios;

  CensoCoen({
    required this.familiasAfectadas,
    required this.personasAfectadas,
    required this.conDiscapacidad,
    required this.embarazadas,
    required this.genero,
    required this.gruposEtarios,
  });

  factory CensoCoen.fromJson(Map<String, dynamic> json) {
    final rawGrupos = json['grupos_etarios'] as List<dynamic>? ?? [];
    return CensoCoen(
      familiasAfectadas: NationalDashboardData._asInt(json['familias_afectadas']),
      personasAfectadas: NationalDashboardData._asInt(json['personas_afectadas']),
      conDiscapacidad: NationalDashboardData._asInt(json['con_discapacidad']),
      embarazadas: NationalDashboardData._asInt(json['embarazadas']),
      genero: GeneroStats.fromJson(json['genero'] as Map<String, dynamic>? ?? {}),
      gruposEtarios: rawGrupos.map((e) => GrupoEtarioItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class GeneroStats {
  final int masculinoTotal;
  final double masculinoPorcentaje;
  final int femeninoTotal;
  final double femeninoPorcentaje;

  GeneroStats({
    required this.masculinoTotal,
    required this.masculinoPorcentaje,
    required this.femeninoTotal,
    required this.femeninoPorcentaje,
  });

  factory GeneroStats.fromJson(Map<String, dynamic> json) {
    final m = json['masculino'] as Map<String, dynamic>? ?? {};
    final f = json['femenino'] as Map<String, dynamic>? ?? {};
    return GeneroStats(
      masculinoTotal: NationalDashboardData._asInt(m['total']),
      masculinoPorcentaje: NationalDashboardData._asDouble(m['porcentaje']),
      femeninoTotal: NationalDashboardData._asInt(f['total']),
      femeninoPorcentaje: NationalDashboardData._asDouble(f['porcentaje']),
    );
  }
}

class GrupoEtarioItem {
  final String id;
  final String emoji;
  final String label;
  final int count;
  final double porcentaje;
  final String colorHex;

  GrupoEtarioItem({
    required this.id,
    required this.emoji,
    required this.label,
    required this.count,
    required this.porcentaje,
    required this.colorHex,
  });

  factory GrupoEtarioItem.fromJson(Map<String, dynamic> json) {
    return GrupoEtarioItem(
      id: json['id']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      count: NationalDashboardData._asInt(json['count']),
      porcentaje: NationalDashboardData._asDouble(json['porcentaje']),
      colorHex: json['color']?.toString() ?? '#38BDF8',
    );
  }
}

class SeveridadHabitacional {
  final int colapsosEstructurales;
  final int inundaciones;
  final SeveridadCategoria perdidaTotal;
  final SeveridadCategoria danoParcial;
  final SeveridadCategoria moderado;
  final SeveridadCategoria leveMenor;
  final List<ProvinciaSeveridadItem> provincias;

  SeveridadHabitacional({
    required this.colapsosEstructurales,
    this.inundaciones = 0,
    required this.perdidaTotal,
    required this.danoParcial,
    required this.moderado,
    required this.leveMenor,
    required this.provincias,
  });

  factory SeveridadHabitacional.fromJson(Map<String, dynamic> json) {
    final cat = json['categorias'] as Map<String, dynamic>? ?? {};
    final rawProvs = json['provincias'] as List<dynamic>? ?? [];

    return SeveridadHabitacional(
      colapsosEstructurales: NationalDashboardData._asInt(json['colapsos_estructurales']),
      inundaciones: NationalDashboardData._asInt(json['inundaciones']),
      perdidaTotal: SeveridadCategoria.fromJson(cat['perdida_total'] as Map<String, dynamic>? ?? {}),
      danoParcial: SeveridadCategoria.fromJson(cat['dano_parcial'] as Map<String, dynamic>? ?? {}),
      moderado: SeveridadCategoria.fromJson(cat['moderado'] as Map<String, dynamic>? ?? {}),
      leveMenor: SeveridadCategoria.fromJson(cat['leve_menor'] as Map<String, dynamic>? ?? {}),
      provincias: rawProvs.map((e) => ProvinciaSeveridadItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class SeveridadCategoria {
  final int total;
  final String etiqueta;
  final String subetiqueta;
  final String colorHex;

  SeveridadCategoria({
    required this.total,
    required this.etiqueta,
    required this.subetiqueta,
    required this.colorHex,
  });

  factory SeveridadCategoria.fromJson(Map<String, dynamic> json) {
    return SeveridadCategoria(
      total: NationalDashboardData._asInt(json['total']),
      etiqueta: json['etiqueta']?.toString() ?? '',
      subetiqueta: json['subetiqueta']?.toString() ?? '',
      colorHex: json['color']?.toString() ?? '#94A3B8',
    );
  }
}

class ProvinciaSeveridadItem {
  final String provincia;
  final int perdidaTotal;
  final int danoParcial;
  final int moderado;
  final int leveMenor;
  final int total;
  final int totalPersonas;
  final int conDiscapacidad;
  final int embarazadas;
  final int colapsosEstructurales;
  final int inundaciones;
  final GeneroStats? genero;
  final List<GrupoEtarioItem> gruposEtarios;
  final List<DistritoAfectadoItem> distritosMasAfectados;
  final List<DistritoTerritorialItem> distritos;
  final List<CorregimientoTerritorialItem> rankingCorregimientos;

  ProvinciaSeveridadItem({
    required this.provincia,
    required this.perdidaTotal,
    required this.danoParcial,
    required this.moderado,
    required this.leveMenor,
    required this.total,
    this.totalPersonas = 0,
    this.conDiscapacidad = 0,
    this.embarazadas = 0,
    this.colapsosEstructurales = 0,
    this.inundaciones = 0,
    this.genero,
    this.gruposEtarios = const [],
    this.distritosMasAfectados = const [],
    this.distritos = const [],
    this.rankingCorregimientos = const [],
  });

  factory ProvinciaSeveridadItem.fromJson(Map<String, dynamic> json) {
    final rawDists = json['distritos_mas_afectados'] as List<dynamic>? ?? [];
    final rawTerritorialDists = json['distritos'] as List<dynamic>? ?? [];
    final rawRanking = json['ranking_corregimientos'] as List<dynamic>? ?? [];
    final rawGrupos = json['grupos_etarios'] as List<dynamic>? ?? [];

    return ProvinciaSeveridadItem(
      provincia: json['provincia']?.toString() ?? 'Panamá',
      perdidaTotal: NationalDashboardData._asInt(json['perdida_total']),
      danoParcial: NationalDashboardData._asInt(json['dano_parcial']),
      moderado: NationalDashboardData._asInt(json['moderado']),
      leveMenor: NationalDashboardData._asInt(json['leve_menor']),
      total: NationalDashboardData._asInt(json['total']),
      totalPersonas: NationalDashboardData._asInt(json['total_personas']),
      conDiscapacidad: NationalDashboardData._asInt(json['con_discapacidad']),
      embarazadas: NationalDashboardData._asInt(json['embarazadas']),
      colapsosEstructurales: NationalDashboardData._asInt(json['colapsos_estructurales']),
      inundaciones: NationalDashboardData._asInt(json['inundaciones']),
      genero: json['genero'] != null ? GeneroStats.fromJson(json['genero'] as Map<String, dynamic>) : null,
      gruposEtarios: rawGrupos.map((e) => GrupoEtarioItem.fromJson(e as Map<String, dynamic>)).toList(),
      distritosMasAfectados: rawDists.map((d) => DistritoAfectadoItem.fromJson(d as Map<String, dynamic>)).toList(),
      distritos: rawTerritorialDists.map((d) => DistritoTerritorialItem.fromJson(d as Map<String, dynamic>)).toList(),
      rankingCorregimientos: rawRanking.map((c) => CorregimientoTerritorialItem.fromJson(c as Map<String, dynamic>)).toList(),
    );
  }
}

class DistritoTerritorialItem {
  final String nombre;
  final String slug;
  final int perdidaTotal;
  final int danoParcial;
  final int moderado;
  final int leveMenor;
  final int totalViviendas;
  final int totalPersonas;
  final int totalCorregimientos;
  final List<CorregimientoTerritorialItem> corregimientos;

  DistritoTerritorialItem({
    required this.nombre,
    required this.slug,
    required this.perdidaTotal,
    required this.danoParcial,
    required this.moderado,
    required this.leveMenor,
    required this.totalViviendas,
    required this.totalPersonas,
    required this.totalCorregimientos,
    required this.corregimientos,
  });

  factory DistritoTerritorialItem.fromJson(Map<String, dynamic> json) {
    final rawCorregs = json['corregimientos'] as List<dynamic>? ?? [];
    return DistritoTerritorialItem(
      nombre: json['nombre']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      perdidaTotal: NationalDashboardData._asInt(json['perdida_total']),
      danoParcial: NationalDashboardData._asInt(json['dano_parcial']),
      moderado: NationalDashboardData._asInt(json['moderado']),
      leveMenor: NationalDashboardData._asInt(json['leve_menor']),
      totalViviendas: NationalDashboardData._asInt(json['total_viviendas']),
      totalPersonas: NationalDashboardData._asInt(json['total_personas']),
      totalCorregimientos: NationalDashboardData._asInt(json['total_corregimientos']),
      corregimientos: rawCorregs
          .map((c) => CorregimientoTerritorialItem.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CorregimientoTerritorialItem {
  final String nombre;
  final String distrito;
  final int perdidaTotal;
  final int danoParcial;
  final int moderado;
  final int leveMenor;
  final int totalViviendas;
  final int totalPersonas;

  CorregimientoTerritorialItem({
    required this.nombre,
    required this.distrito,
    required this.perdidaTotal,
    required this.danoParcial,
    required this.moderado,
    required this.leveMenor,
    required this.totalViviendas,
    required this.totalPersonas,
  });

  factory CorregimientoTerritorialItem.fromJson(Map<String, dynamic> json) {
    return CorregimientoTerritorialItem(
      nombre: json['nombre']?.toString() ?? '',
      distrito: json['distrito']?.toString() ?? '',
      perdidaTotal: NationalDashboardData._asInt(json['perdida_total']),
      danoParcial: NationalDashboardData._asInt(json['dano_parcial']),
      moderado: NationalDashboardData._asInt(json['moderado']),
      leveMenor: NationalDashboardData._asInt(json['leve_menor']),
      totalViviendas: NationalDashboardData._asInt(json['total_viviendas']),
      totalPersonas: NationalDashboardData._asInt(json['total_personas']),
    );
  }
}

class DistritoAfectadoItem {
  final String distrito;
  final int totalFamilias;
  final int totalPersonas;

  DistritoAfectadoItem({
    required this.distrito,
    required this.totalFamilias,
    required this.totalPersonas,
  });

  factory DistritoAfectadoItem.fromJson(Map<String, dynamic> json) {
    return DistritoAfectadoItem(
      distrito: json['distrito']?.toString() ?? '',
      totalFamilias: NationalDashboardData._asInt(json['total_familias']),
      totalPersonas: NationalDashboardData._asInt(json['total_personas']),
    );
  }
}
