/// Niveles de Habitabilidad según Norma Sísmica ATC-20
enum NivelHabitabilidad {
  habitable, // Verde: Seguro habitar
  accesoRestringido, // Amarillo: Ingreso restringido/peligro localizado
  inhabitable, // Rojo: Daño severo, prohibido habitar
  colapsoTotal, // Estructura destruida
}

extension NivelHabitabilidadExt on NivelHabitabilidad {
  String get value {
    switch (this) {
      case NivelHabitabilidad.habitable:
        return 'HABITABLE';
      case NivelHabitabilidad.accesoRestringido:
        return 'ACCESO_RESTRINGIDO';
      case NivelHabitabilidad.inhabitable:
        return 'INHABITABLE';
      case NivelHabitabilidad.colapsoTotal:
        return 'COLAPSO_TOTAL';
    }
  }

  String get label {
    switch (this) {
      case NivelHabitabilidad.habitable:
        return 'Habitable (Seguro)';
      case NivelHabitabilidad.accesoRestringido:
        return 'Acceso Restringido (Riesgo Parcial)';
      case NivelHabitabilidad.inhabitable:
        return 'Inhabitable (Peligro de Colapso)';
      case NivelHabitabilidad.colapsoTotal:
        return 'Colapso Total (Destruida)';
    }
  }
}

/// Rol del Informante
enum RolInformante {
  afectadoDirecto,
  vecinoOTercero,
  familiarNoResidente,
  voluntarioBrigadista,
  liderComunitario,
  funcionarioEstatal,
}

extension RolInformanteExt on RolInformante {
  String get value {
    switch (this) {
      case RolInformante.afectadoDirecto:
        return 'AFECTADO_DIRECTO';
      case RolInformante.vecinoOTercero:
        return 'VECINO_O_TERCERO';
      case RolInformante.familiarNoResidente:
        return 'FAMILIAR_NO_RESIDENTE';
      case RolInformante.voluntarioBrigadista:
        return 'VOLUNTARIO_BRIGADISTA';
      case RolInformante.liderComunitario:
        return 'LIDER_COMUNITARIO';
      case RolInformante.funcionarioEstatal:
        return 'FUNCIONARIO_ESTATAL';
    }
  }

  String get label {
    switch (this) {
      case RolInformante.afectadoDirecto:
        return 'Afectado Directo (Jefe o Miembro del Hogar)';
      case RolInformante.vecinoOTercero:
        return 'Vecino o Testigo en el Sitio';
      case RolInformante.familiarNoResidente:
        return 'Familiar que Reporta a Distancia';
      case RolInformante.voluntarioBrigadista:
        return 'Voluntario / Brigadista de Apoyo';
      case RolInformante.liderComunitario:
        return 'Líder Comunitario / Junta Local';
      case RolInformante.funcionarioEstatal:
        return 'Funcionario Estatal / Rescate';
    }
  }
}

/// Tipos de Eventos / Catástrofes (Arquitectura Multi-Evento Extensible)
enum TipoEvento {
  terremoto('TERREMOTO', 'Terremoto / Sismo'),
  inundacion('INUNDACION', 'Inundación / Crecida'),
  deslizamiento('DESLIZAMIENTO', 'Deslizamiento / Derrumbe'),
  vendavalHuracan('VENDAVAL_HURACAN', 'Vendaval / Huracán'),
  incendio('INCENDIO', 'Incendio Estructural / Forestal'),
  otro('OTRO', 'Otro Evento');

  final String value;
  final String label;
  const TipoEvento(this.value, this.label);
}

/// Clasificación de Evidencia Fotográfica
enum TipoFotoEvidencia {
  identificacion('IDENTIFICACION', 'Documento de Identidad'),
  estructuraDano('ESTRUCTURA_DANO', 'Estructura / Daño Visible'),
  otro('OTRO', 'Otra Evidencia');

  final String value;
  final String label;
  const TipoFotoEvidencia(this.value, this.label);
}

/// Evidencia Fotográfica con Metadata y Clasificación
class FotoEvidencia {
  final String id;
  final String tipo; // IDENTIFICACION, ESTRUCTURA_DANO, OTRO
  final String rutaLocal;
  final String? urlRemota;
  final String timestamp;
  final String? descripcion;

  FotoEvidencia({
    required this.id,
    required this.tipo,
    required this.rutaLocal,
    this.urlRemota,
    required this.timestamp,
    this.descripcion,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tipo': tipo,
      'ruta_local': rutaLocal,
      'url_remota': urlRemota,
      'timestamp': timestamp,
      if (descripcion != null) 'descripcion': descripcion,
    };
  }

  factory FotoEvidencia.fromJson(Map<String, dynamic> json) {
    return FotoEvidencia(
      id: json['id'] ?? '',
      tipo: json['tipo'] ?? 'OTRO',
      rutaLocal: json['ruta_local'] ?? '',
      urlRemota: json['url_remota'],
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
      descripcion: json['descripcion'],
    );
  }
}

/// Modelo Canónico de Reporte de Emergencia
class DisasterReport {
  final String reportId;
  final String timestamp;
  final bool consentimientoInformado;

  // Multi-Evento Extensible
  final String tipoEvento;
  final String codigoEvento;
  final Map<String, dynamic> metadatosEvento;

  // Informante
  final String reporterId;
  final String rolInformante;
  final String? informanteNombre;
  final String? informanteTelefono;
  final String? informanteOrganizacion;
  final bool estaPresenteEnSitio;

  // Titular Afectado (PII)
  final bool esElMismoInformante;
  final String? afectadoNombre;
  final String documentoTipo;
  final String? documentoNumero;
  final String? afectadoTelefono;
  final String estadoFamilia;

  // Ubicación
  final double latitud;
  final double longitud;
  final double? precisionMetros;
  final String provincia;
  final String distrito;
  final String corregimiento;
  final String comunidadSector;
  final String calleDireccion;
  final String? puntoReferencia;
  final String accesibilidadVial;

  // Evaluación Estructural
  final String tipoInmueble;
  final String sistemaConstructivo;
  final String habitabilidad;
  final bool riesgoColapsoInminente;
  final List<String> danosPrincipales;
  final String? descripcionDano;

  // Servicios Vitales
  final String aguaPotable;
  final String electricidad;
  final String saneamiento;
  final bool fugaGas;

  // Censo Demográfico
  final int totalOcupantes;
  final int atrapadosDesaparecidos;
  final int lesionadosGraves;
  final int neonatos;
  final int ninos;
  final int adolescentes;
  final int adultos;
  final int adultosMayores;
  final int embarazadas;
  final int personasDiscapacidad;

  // Necesidades Humanitarias
  final bool requiereAlbergue;
  final bool requiereRescateMedico;
  final bool requiereAguaAlimentos;
  final int colchon34Qty;
  final int colchonDobleQty;
  final int kitLimpiezaQty;
  final int kitBebeQty;
  final int kitHigieneQty;
  final int kitCocinaQty;
  final String? asistenciaExtra;

  // Telemetría KYC
  final String installationId;
  final bool esDispositivoFisico;
  final String marcaDispositivo;
  final String modeloDispositivo;
  final String sistemaOperativo;
  final int? nivelBateria;
  final String tipoConexion;
  final List<FotoEvidencia> evidencias;
  final List<String> fotosUrls;

  DisasterReport({
    required this.reportId,
    required this.timestamp,
    required this.consentimientoInformado,
    this.tipoEvento = 'TERREMOTO',
    this.codigoEvento = 'SISMO_OCTUBRE_2026',
    this.metadatosEvento = const {},
    required this.reporterId,
    required this.rolInformante,
    this.informanteNombre,
    this.informanteTelefono,
    this.informanteOrganizacion,
    this.estaPresenteEnSitio = true,
    this.esElMismoInformante = true,
    this.afectadoNombre,
    this.documentoTipo = 'CEDULA',
    this.documentoNumero,
    this.afectadoTelefono,
    this.estadoFamilia = 'EN_SITIO',
    required this.latitud,
    required this.longitud,
    this.precisionMetros,
    this.provincia = 'Los Santos',
    this.distrito = 'Las Tablas',
    required this.corregimiento,
    required this.comunidadSector,
    required this.calleDireccion,
    this.puntoReferencia,
    this.accesibilidadVial = 'TRANSITABLE',
    this.tipoInmueble = 'RESIDENCIAL_CASA',
    this.sistemaConstructivo = 'MAMPOSTERIA_BLOQUE',
    required this.habitabilidad,
    this.riesgoColapsoInminente = false,
    this.danosPrincipales = const [],
    this.descripcionDano,
    this.aguaPotable = 'NORMAL',
    this.electricidad = 'NORMAL',
    this.saneamiento = 'FUNCIONAL',
    this.fugaGas = false,
    this.totalOcupantes = 1,
    this.atrapadosDesaparecidos = 0,
    this.lesionadosGraves = 0,
    this.neonatos = 0,
    this.ninos = 0,
    this.adolescentes = 0,
    this.adultos = 1,
    this.adultosMayores = 0,
    this.embarazadas = 0,
    this.personasDiscapacidad = 0,
    this.requiereAlbergue = false,
    this.requiereRescateMedico = false,
    this.requiereAguaAlimentos = false,
    this.colchon34Qty = 0,
    this.colchonDobleQty = 0,
    this.kitLimpiezaQty = 0,
    this.kitBebeQty = 0,
    this.kitHigieneQty = 0,
    this.kitCocinaQty = 0,
    this.asistenciaExtra,
    required this.installationId,
    this.esDispositivoFisico = true,
    this.marcaDispositivo = 'Desconocido',
    this.modeloDispositivo = 'Desconocido',
    this.sistemaOperativo = 'Desconocido',
    this.nivelBateria,
    this.tipoConexion = 'CELULAR',
    this.evidencias = const [],
    this.fotosUrls = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'report_id': reportId,
      'timestamp': timestamp,
      'consentimiento_informado': consentimientoInformado,
      'evento': {
        'tipo': tipoEvento,
        'codigo_evento': codigoEvento,
        'metadatos_evento': metadatosEvento,
      },
      'evidencias_fotograficas': evidencias.map((e) => e.toJson()).toList(),
      'informante': {
        'reporter_id': reporterId,
        'rol': rolInformante,
        'nombre_completo': informanteNombre,
        'telefono_contacto': informanteTelefono,
        'organizacion': informanteOrganizacion,
        'esta_presente_en_el_sitio': estaPresenteEnSitio,
      },
      'titular_afectado': {
        'es_el_mismo_informante': esElMismoInformante,
        'nombre_jefe_hogar': afectadoNombre,
        'documento_tipo': documentoTipo,
        'documento_numero': documentoNumero,
        'telefono_afectado': afectadoTelefono,
        'estado_familia': estadoFamilia,
      },
      'ubicacion': {
        'coordenadas': {
          'lat': latitud,
          'lng': longitud,
          'precision_metros': precisionMetros,
        },
        'provincia': provincia,
        'distrito': distrito,
        'corregimiento': corregimiento,
        'comunidad_sector': comunidadSector,
        'calle_o_direccion': calleDireccion,
        'punto_referencia': puntoReferencia,
        'accesibilidad_vial': accesibilidadVial,
      },
      'evaluacion_estructural': {
        'tipo_inmueble': tipoInmueble,
        'sistema_constructivo': sistemaConstructivo,
        'habitabilidad': habitabilidad,
        'riesgo_colapso_inminente': riesgoColapsoInminente,
        'danos_principales': danosPrincipales,
        'descripcion_dano': descripcionDano,
      },
      'servicios_vitales': {
        'agua_potable': aguaPotable,
        'electricidad': electricidad,
        'saneamiento': saneamiento,
        'fuga_gas': fugaGas,
      },
      'censo_demografico': {
        'total_ocupantes': totalOcupantes,
        'atrapados_o_desaparecidos': atrapadosDesaparecidos,
        'lesionados_graves': lesionadosGraves,
        'neonatos_0_2': neonatos,
        'ninos_3_12': ninos,
        'adolescentes_13_17': adolescentes,
        'adultos_18_59': adultos,
        'adultos_mayores_60': adultosMayores,
        'embarazadas': embarazadas,
        'personas_discapacidad': personasDiscapacidad,
      },
      'necesidades_humanitarias': {
        'requiere_albergue_inmediato': requiereAlbergue,
        'requiere_rescate_medico': requiereRescateMedico,
        'requiere_agua_alimentos': requiereAguaAlimentos,
        'colchon_3_4_qty': colchon34Qty,
        'colchon_doble_qty': colchonDobleQty,
        'kit_limpieza_qty': kitLimpiezaQty,
        'kit_bebe_qty': kitBebeQty,
        'kit_higiene_familiar_qty': kitHigieneQty,
        'kit_cocina_qty': kitCocinaQty,
        'asistencia_extra_descripcion': asistenciaExtra,
      },
      'auditoria_kyc': {
        'installation_id': installationId,
        'es_dispositivo_fisico': esDispositivoFisico,
        'marca': marcaDispositivo,
        'modelo': modeloDispositivo,
        'sistema_operativo': sistemaOperativo,
        'nivel_bateria_pct': nivelBateria,
        'tipo_conexion': tipoConexion,
        'timestamp_creacion_local': timestamp,
      },
      'fotos_urls': fotosUrls,
    };
  }

  factory DisasterReport.fromJson(Map<String, dynamic> json) {
    final evt = json['evento'] as Map<String, dynamic>? ?? {};
    final inf = json['informante'] as Map<String, dynamic>? ?? {};
    final tit = json['titular_afectado'] as Map<String, dynamic>? ?? {};
    final ubi = json['ubicacion'] as Map<String, dynamic>? ?? {};
    final coords = ubi['coordenadas'] as Map<String, dynamic>? ?? {};
    final est = json['evaluacion_estructural'] as Map<String, dynamic>? ?? {};
    final ser = json['servicios_vitales'] as Map<String, dynamic>? ?? {};
    final cen = json['censo_demografico'] as Map<String, dynamic>? ?? {};
    final nec = json['necesidades_humanitarias'] as Map<String, dynamic>? ?? {};
    final kyc = json['auditoria_kyc'] as Map<String, dynamic>? ?? {};

    return DisasterReport(
      reportId: json['report_id'] ?? '',
      timestamp: json['timestamp'] ?? '',
      consentimientoInformado: json['consentimiento_informado'] ?? true,
      tipoEvento: evt['tipo'] ?? json['tipo_evento'] ?? 'TERREMOTO',
      codigoEvento: evt['codigo_evento'] ?? json['codigo_evento'] ?? 'SISMO_OCTUBRE_2026',
      metadatosEvento: evt['metadatos_evento'] as Map<String, dynamic>? ?? {},
      evidencias: (json['evidencias_fotograficas'] as List<dynamic>?)
              ?.map((e) => FotoEvidencia.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      reporterId: inf['reporter_id'] ?? '',
      rolInformante: inf['rol'] ?? 'AFECTADO_DIRECTO',
      informanteNombre: inf['nombre_completo'],
      informanteTelefono: inf['telefono_contacto'],
      informanteOrganizacion: inf['organizacion'],
      estaPresenteEnSitio: inf['esta_presente_en_el_sitio'] ?? true,
      esElMismoInformante: tit['es_el_mismo_informante'] ?? true,
      afectadoNombre: tit['nombre_jefe_hogar'],
      documentoTipo: tit['documento_tipo'] ?? 'CEDULA',
      documentoNumero: tit['documento_numero'],
      afectadoTelefono: tit['telefono_afectado'],
      estadoFamilia: tit['estado_familia'] ?? 'EN_SITIO',
      latitud: (coords['lat'] as num?)?.toDouble() ?? 7.625,
      longitud: (coords['lng'] as num?)?.toDouble() ?? -80.354,
      precisionMetros: (coords['precision_metros'] as num?)?.toDouble(),
      provincia: ubi['provincia'] ?? 'Los Santos',
      distrito: ubi['distrito'] ?? 'Las Tablas',
      corregimiento: ubi['corregimiento'] ?? '',
      comunidadSector: ubi['comunidad_sector'] ?? '',
      calleDireccion: ubi['calle_o_direccion'] ?? '',
      puntoReferencia: ubi['punto_referencia'],
      accesibilidadVial: ubi['accesibilidad_vial'] ?? 'TRANSITABLE',
      tipoInmueble: est['tipo_inmueble'] ?? 'RESIDENCIAL_CASA',
      sistemaConstructivo: est['sistema_constructivo'] ?? 'MAMPOSTERIA_BLOQUE',
      habitabilidad: est['habitabilidad'] ?? 'HABITABLE',
      riesgoColapsoInminente: est['riesgo_colapso_inminente'] ?? false,
      danosPrincipales: (est['danos_principales'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      descripcionDano: est['descripcion_dano'],
      aguaPotable: ser['agua_potable'] ?? 'NORMAL',
      electricidad: ser['electricidad'] ?? 'NORMAL',
      saneamiento: ser['saneamiento'] ?? 'FUNCIONAL',
      fugaGas: ser['fuga_gas'] ?? false,
      totalOcupantes: (cen['total_ocupantes'] as num?)?.toInt() ?? 1,
      atrapadosDesaparecidos:
          (cen['atrapados_o_desaparecidos'] as num?)?.toInt() ?? 0,
      lesionadosGraves: (cen['lesionados_graves'] as num?)?.toInt() ?? 0,
      neonatos: (cen['neonatos_0_2'] as num?)?.toInt() ?? 0,
      ninos: (cen['ninos_3_12'] as num?)?.toInt() ?? 0,
      adolescentes: (cen['adolescentes_13_17'] as num?)?.toInt() ?? 0,
      adultos: (cen['adultos_18_59'] as num?)?.toInt() ?? 1,
      adultosMayores: (cen['adultos_mayores_60'] as num?)?.toInt() ?? 0,
      embarazadas: (cen['embarazadas'] as num?)?.toInt() ?? 0,
      personasDiscapacidad:
          (cen['personas_discapacidad'] as num?)?.toInt() ?? 0,
      requiereAlbergue: nec['requiere_albergue_inmediato'] ?? false,
      requiereRescateMedico: nec['requiere_rescate_medico'] ?? false,
      requiereAguaAlimentos: nec['requiere_agua_alimentos'] ?? false,
      colchon34Qty: (nec['colchon_3_4_qty'] as num?)?.toInt() ?? 0,
      colchonDobleQty: (nec['colchon_doble_qty'] as num?)?.toInt() ?? 0,
      kitLimpiezaQty: (nec['kit_limpieza_qty'] as num?)?.toInt() ?? 0,
      kitBebeQty: (nec['kit_bebe_qty'] as num?)?.toInt() ?? 0,
      kitHigieneQty: (nec['kit_higiene_familiar_qty'] as num?)?.toInt() ?? 0,
      kitCocinaQty: (nec['kit_cocina_qty'] as num?)?.toInt() ?? 0,
      asistenciaExtra: nec['asistencia_extra_descripcion'],
      installationId: kyc['installation_id'] ?? '',
      esDispositivoFisico: kyc['es_dispositivo_fisico'] ?? true,
      marcaDispositivo: kyc['marca'] ?? 'Desconocido',
      modeloDispositivo: kyc['modelo'] ?? 'Desconocido',
      sistemaOperativo: kyc['sistema_operativo'] ?? 'Desconocido',
      nivelBateria: (kyc['nivel_bateria_pct'] as num?)?.toInt(),
      tipoConexion: kyc['tipo_conexion'] ?? 'CELULAR',
      fotosUrls: (json['fotos_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}
