import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';
import '../models/disaster_report.dart';
import '../services/api_service.dart';
import '../services/offline_queue_service.dart';
import '../services/panama_dpa_service.dart';
import '../services/postal_code_service.dart';
import '../services/reporter_profile_service.dart';
import '../services/telemetry_service.dart';
import '../utils/panama_text_normalizer.dart';

class ReportWizardScreen extends StatefulWidget {
  final DisasterReport? initialReport;
  const ReportWizardScreen({super.key, this.initialReport});

  @override
  State<ReportWizardScreen> createState() => _ReportWizardScreenState();
}

class _ReportWizardScreenState extends State<ReportWizardScreen> {
  int _currentStep = 0;
  bool _enviando = false;

  // Evento activo dinámico resuelto desde AppConfig (vector de eventos en AWS SSM)
  String get _tipoEvento => AppConfig.defaultEvent.tipo;
  String get _codigoEvento => AppConfig.defaultEvent.codigo;
  String get _nombreEvento => AppConfig.defaultEvent.nombre;

  // Evidencias Fotográficas
  final ImagePicker _picker = ImagePicker();
  FotoEvidencia? _fotoIdentificacion; // Mínimo 1 obligatoria
  final List<FotoEvidencia> _fotosEstructura = []; // Mínimo 2 obligatorias

  // Paso 1: Ubicación Nacional & Códigos Postales
  String _provincia = 'Los Santos';
  String _distrito = 'Las Tablas';
  String _corregimiento = 'Las Tablas';
  String? _codigoPostal;
  bool _autocompletadoOnline = false;
  String _estadoGeolocalizacion = 'Detectando ubicación...';

  final _comunidadCtrl = TextEditingController();
  final _calleCtrl = TextEditingController();
  final _referenciaCtrl = TextEditingController();
  double _lat = 7.6251;
  double _lng = -80.3542;
  double? _precisionMetros;
  bool _obteniendoGps = false;

  // Paso 2: Estructura & Habitabilidad (ATC-20)
  NivelHabitabilidad _habitabilidad = NivelHabitabilidad.inhabitable;
  String _tipoInmueble = 'RESIDENCIAL_CASA';
  String _sistemaConstructivo = 'MAMPOSTERIA_BLOQUE';
  bool _riesgoColapso = false;
  bool _fugaGas = false;
  bool _cablesCaidos = false;
  String _aguaPotable = 'NORMAL';
  final _descripcionDanoCtrl = TextEditingController();

  // Paso 3: Censo y Necesidades Humanitarias (Sphere / INSARAG)
  int _atrapados = 0;
  int _lesionados = 0;
  int _neonatos = 0;
  int _ninos = 0;
  int _adolescentes = 0;
  int _adultos = 1;
  int _adultosMayores = 0;
  int _embarazadas = 0;
  int _discapacitados = 0;
  bool _requiereAlbergue = false;
  bool _requiereAguaAlimentos = false;
  final int _colchonesDoble = 1;
  final int _kitsHigiene = 1;
  final int _kitsBebe = 0;

  // Total calculado automáticamente basado en el desglose del detalle
  int get _totalOcupantes =>
      _neonatos + _ninos + _adolescentes + _adultos + _adultosMayores;

  // Paso 4: Afectado y Consentimiento
  bool _esElMismoInformante = true;
  ReporterProfile? _reporterProfile;
  final _afectadoNombreCtrl = TextEditingController();
  final _afectadoCedulaCtrl = TextEditingController();
  final _afectadoTelefonoCtrl = TextEditingController();
  bool _consentimientoDado = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialReport != null) {
      final rep = widget.initialReport!;
      _provincia = rep.provincia;
      _distrito = rep.distrito;
      _corregimiento = rep.corregimiento;
      _comunidadCtrl.text = rep.comunidadSector;
      _calleCtrl.text = rep.calleDireccion;
      _referenciaCtrl.text = rep.puntoReferencia ?? '';
      _lat = rep.latitud;
      _lng = rep.longitud;
      _precisionMetros = rep.precisionMetros;
      _estadoGeolocalizacion = 'Ubicación cargada del reporte existente';

      _habitabilidad = NivelHabitabilidad.values.firstWhere(
        (n) => n.value == rep.habitabilidad,
        orElse: () => NivelHabitabilidad.inhabitable,
      );
      _tipoInmueble = rep.tipoInmueble;
      _sistemaConstructivo = rep.sistemaConstructivo;
      _riesgoColapso = rep.riesgoColapsoInminente;
      _fugaGas = rep.fugaGas;
      _cablesCaidos = rep.electricidad.contains('CABLES');
      _aguaPotable = rep.aguaPotable;
      _descripcionDanoCtrl.text = rep.descripcionDano ?? '';

      _atrapados = rep.atrapadosDesaparecidos;
      _lesionados = rep.lesionadosGraves;
      _neonatos = rep.neonatos;
      _ninos = rep.ninos;
      _adolescentes = rep.adolescentes;
      _adultos = rep.adultos;
      _adultosMayores = rep.adultosMayores;
      _embarazadas = rep.embarazadas;
      _discapacitados = rep.personasDiscapacidad;
      _requiereAlbergue = rep.requiereAlbergue;
      _requiereAguaAlimentos = rep.requiereAguaAlimentos;

      _esElMismoInformante = rep.esElMismoInformante;
      _afectadoNombreCtrl.text = rep.afectadoNombre ?? '';
      _afectadoCedulaCtrl.text = rep.documentoNumero ?? '';
      _afectadoTelefonoCtrl.text = rep.afectadoTelefono ?? '';
      _consentimientoDado = rep.consentimientoInformado;

      // Cargar fotos previas si existían
      for (final ev in rep.evidencias) {
        if (ev.tipo == TipoFotoEvidencia.identificacion.value && _fotoIdentificacion == null) {
          _fotoIdentificacion = ev;
        } else if (ev.tipo == TipoFotoEvidencia.estructuraDano.value) {
          _fotosEstructura.add(ev);
        }
      }
      _clampearCondicionesEspeciales();
    } else {
      _cargarPerfilInformante();
      _capturarGpsInicial();
    }
  }

  void _clampearCondicionesEspeciales() {
    final maxTotal = _totalOcupantes;
    if (_embarazadas > maxTotal) _embarazadas = maxTotal;
    if (_discapacitados > maxTotal) _discapacitados = maxTotal;
    if (_atrapados > maxTotal) _atrapados = maxTotal;
    if (_lesionados > maxTotal) _lesionados = maxTotal;
  }

  Future<void> _cargarPerfilInformante() async {
    final profile = await ReporterProfileService.getOrCreateProfile();
    if (mounted) {
      setState(() {
        _reporterProfile = profile;
        if (_esElMismoInformante) {
          if (_afectadoNombreCtrl.text.isEmpty) _afectadoNombreCtrl.text = profile.nombre;
          if (_afectadoCedulaCtrl.text.isEmpty) _afectadoCedulaCtrl.text = profile.cedula;
          if (_afectadoTelefonoCtrl.text.isEmpty) _afectadoTelefonoCtrl.text = profile.telefono;
        }
      });
    }
  }

  Future<void> _capturarFotoIdentificacion(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(source: source, imageQuality: 85);
      if (file != null) {
        setState(() {
          _fotoIdentificacion = FotoEvidencia(
            id: 'id_${const Uuid().v4()}',
            tipo: TipoFotoEvidencia.identificacion.value,
            rutaLocal: file.path,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            descripcion: 'Cédula o Documento de Identidad',
          );
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al capturar foto de identificación: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _capturarFotoEstructura(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(source: source, imageQuality: 85);
      if (file != null) {
        setState(() {
          _fotosEstructura.add(FotoEvidencia(
            id: 'est_${const Uuid().v4()}',
            tipo: TipoFotoEvidencia.estructuraDano.value,
            rutaLocal: file.path,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            descripcion: 'Foto #${_fotosEstructura.length + 1} daño estructural',
          ));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al capturar foto de la estructura: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _comunidadCtrl.dispose();
    _calleCtrl.dispose();
    _referenciaCtrl.dispose();
    _descripcionDanoCtrl.dispose();
    _afectadoNombreCtrl.dispose();
    _afectadoCedulaCtrl.dispose();
    _afectadoTelefonoCtrl.dispose();
    super.dispose();
  }

  Future<void> _capturarGpsInicial() async {
    setState(() {
      _obteniendoGps = true;
      _estadoGeolocalizacion = 'Obteniendo coordenadas GPS...';
    });

    final telemetry = await TelemetryService.captureTelemetry();
    if (telemetry.posicionGps != null) {
      _lat = telemetry.posicionGps!.latitude;
      _lng = telemetry.posicionGps!.longitude;
      _precisionMetros = telemetry.posicionGps!.accuracy;
    }

    // Consulta en vivo a la API nacional de Códigos Postales
    setState(() => _estadoGeolocalizacion = 'Consultando Códigos Postales Panamá...');
    final result = await PostalCodeService.lookup(lat: _lat, lng: _lng);

    if (result != null) {
      setState(() {
        final provs = PanamaDpaService.getProvincias();
        // Buscar provincia coincidente
        final matchedProv = provs.firstWhere(
          (p) => p.toLowerCase() == result.provincia.toLowerCase(),
          orElse: () => _provincia,
        );
        _provincia = matchedProv;

        final distritos = PanamaDpaService.getDistritos(_provincia);
        final matchedDist = distritos.firstWhere(
          (d) => d.toLowerCase() == result.distrito.toLowerCase(),
          orElse: () => distritos.isNotEmpty ? distritos.first : _distrito,
        );
        _distrito = matchedDist;

        final corrs = PanamaDpaService.getCorregimientos(_provincia, _distrito);
        final matchedCorr = corrs.firstWhere(
          (c) => c.toLowerCase().contains(result.corregimiento.toLowerCase()) ||
                 result.corregimiento.toLowerCase().contains(c.toLowerCase()),
          orElse: () => corrs.isNotEmpty ? corrs.first : result.corregimiento,
        );
        _corregimiento = matchedCorr;

        if (result.sectorOBarrio.isNotEmpty) {
          _comunidadCtrl.text = result.sectorOBarrio;
        }
        _codigoPostal = result.codigoPostal;
        _autocompletadoOnline = true;
        _estadoGeolocalizacion = 'Identificado por Códigos Postales Panamá (C.P. ${_codigoPostal ?? ""})';
      });
    } else {
      setState(() {
        _autocompletadoOnline = false;
        _estadoGeolocalizacion = 'Modo sin conexión. Usando Catálogo Oficial Nacional.';
      });
    }

    setState(() => _obteniendoGps = false);
  }

  Future<void> _enviarReporte() async {
    // 1. Validar Sitio
    if (_comunidadCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa la Comunidad, Barrio o Sector (Obligatorio).'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _currentStep = 0);
      return;
    }

    // 2. Validar Censo
    if (_totalOcupantes < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El hogar debe tener al menos 1 ocupante en el censo.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _currentStep = 2);
      return;
    }

    // 3. Validar Jefe de Familia
    if (_afectadoNombreCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El nombre del jefe/a de familia es obligatorio.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _currentStep = 3);
      return;
    }

    if (_afectadoCedulaCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La cédula del jefe/a de familia es obligatoria.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _currentStep = 3);
      return;
    }

    if (_afectadoTelefonoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El teléfono de contacto del jefe/a de familia es obligatorio.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _currentStep = 3);
      return;
    }

    // 4. Validar Foto de Identificación (Mínimo 1 obligatoria)
    if (_fotoIdentificacion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes adjuntar al menos 1 foto de la cédula o identificación del jefe/a de familia.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _currentStep = 3);
      return;
    }

    // 5. Validar Fotos de la Estructura Afectada (Mínimo 2 obligatorias)
    if (_fotosEstructura.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Debes adjuntar al menos 2 fotos de la estructura afectada (${_fotosEstructura.length}/2).'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _currentStep = 1);
      return;
    }

    if (!_consentimientoDado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes otorgar consentimiento para notificar a los cuerpos de auxilio.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _enviando = true);

    try {
      final profile = await ReporterProfileService.getOrCreateProfile();
      final telemetry = await TelemetryService.captureTelemetry();

      // Guardar cédula en el perfil local si reporta su propia casa
      if (_esElMismoInformante && profile.cedula != _afectadoCedulaCtrl.text.trim()) {
        await ReporterProfileService.saveProfile(
          nombre: _afectadoNombreCtrl.text.trim(),
          cedula: _afectadoCedulaCtrl.text.trim(),
          telefono: _afectadoTelefonoCtrl.text.trim(),
          rol: profile.rol,
          organizacion: profile.organizacion,
        );
      }

      // Normalización inteligente de texto para evitar typos en la data
      final comunidadNormalizada = PanamaTextNormalizer.normalize(_comunidadCtrl.text);
      final calleNormalizada = PanamaTextNormalizer.normalize(_calleCtrl.text);
      final referenciaNormalizada = PanamaTextNormalizer.normalize(_referenciaCtrl.text);
      final descripcionDanoNormalizada = PanamaTextNormalizer.normalize(_descripcionDanoCtrl.text);

      // Consolidar evidencias fotográficas estructuradas
      final todasLasEvidencias = <FotoEvidencia>[];
      if (_fotoIdentificacion != null) todasLasEvidencias.add(_fotoIdentificacion!);
      todasLasEvidencias.addAll(_fotosEstructura);
      final fotosUrls = todasLasEvidencias.map((e) => e.rutaLocal).toList();

      final report = DisasterReport(
        reportId: widget.initialReport?.reportId ?? 'rep_${const Uuid().v4()}',
        timestamp: widget.initialReport?.timestamp ?? DateTime.now().toUtc().toIso8601String(),
        consentimientoInformado: _consentimientoDado,
        tipoEvento: _tipoEvento,
        codigoEvento: _codigoEvento,
        metadatosEvento: {
          'nombre_evento': _nombreEvento,
          'sistema_constructivo': _sistemaConstructivo,
          'tipo_inmueble': _tipoInmueble,
          'fuga_gas': _fugaGas,
          'riesgo_colapso': _riesgoColapso,
        },
        evidencias: todasLasEvidencias,
        fotosUrls: fotosUrls,
        reporterId: profile.reporterId,
        rolInformante: profile.rol,
        informanteNombre: profile.nombre,
        informanteTelefono: profile.telefono,
        informanteOrganizacion: profile.organizacion,
        estaPresenteEnSitio: true,
        esElMismoInformante: _esElMismoInformante,
        afectadoNombre: _afectadoNombreCtrl.text.trim(),
        documentoTipo: 'CEDULA',
        documentoNumero: _afectadoCedulaCtrl.text.trim(),
        afectadoTelefono: _afectadoTelefonoCtrl.text.trim(),
        latitud: _lat,
        longitud: _lng,
        precisionMetros: _precisionMetros,
        provincia: _provincia,
        distrito: _distrito,
        corregimiento: _corregimiento,
        comunidadSector: comunidadNormalizada,
        calleDireccion: calleNormalizada,
        puntoReferencia: referenciaNormalizada,
        tipoInmueble: _tipoInmueble,
        sistemaConstructivo: _sistemaConstructivo,
        habitabilidad: _habitabilidad.value,
        riesgoColapsoInminente: _riesgoColapso,
        descripcionDano: descripcionDanoNormalizada,
        aguaPotable: _aguaPotable,
        electricidad: _cablesCaidos ? 'CABLES_CAIDOS_PELIGRO' : 'NORMAL',
        fugaGas: _fugaGas,
        totalOcupantes: _totalOcupantes,
        atrapadosDesaparecidos: _atrapados,
        lesionadosGraves: _lesionados,
        neonatos: _neonatos,
        ninos: _ninos,
        adolescentes: _adolescentes,
        adultos: _adultos,
        adultosMayores: _adultosMayores,
        embarazadas: _embarazadas,
        personasDiscapacidad: _discapacitados,
        requiereAlbergue: _requiereAlbergue,
        requiereAguaAlimentos: _requiereAguaAlimentos,
        requiereRescateMedico: _atrapados > 0 || _lesionados > 0,
        colchonDobleQty: _colchonesDoble,
        kitHigieneQty: _kitsHigiene,
        kitBebeQty: _kitsBebe,
        installationId: profile.installationId,
        esDispositivoFisico: telemetry.esFisico,
        marcaDispositivo: telemetry.marca,
        modeloDispositivo: telemetry.modelo,
        sistemaOperativo: telemetry.sistemaOperativo,
        nivelBateria: telemetry.nivelBateria,
        tipoConexion: telemetry.tipoConexion,
      );

      // Intentar enviar a AWS
      final exito = await ApiService.submitReport(report);

      // Guardar o actualizar siempre en el registro local histórico (marcando si está sincronizado o pendiente)
      await OfflineQueueService.saveLocalReport(report, isSynced: exito);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  exito ? Icons.check_circle : Icons.cloud_queue,
                  color: exito ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(exito ? 'Reporte Enviado' : 'Guardado Offline'),
              ],
            ),
            content: Text(
              exito
                  ? 'Tu reporte fue recibido en AWS y está disponible para SINAPROC y los cuerpos de rescate.'
                  : 'Sin conexión estable. Tu reporte quedó guardado localmente de forma segura y se enviará automáticamente en cuanto recuperes señal.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop(); // Volver al home
                },
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialReport != null ? 'Editar Reporte de Emergencia' : 'Nuevo Reporte de Emergencia'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: Stepper(
        type: StepperType.horizontal,
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep == 0) {
            if (_comunidadCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Por favor ingresa la Comunidad, Barrio o Sector (Obligatorio).'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
          } else if (_currentStep == 1) {
            if (_fotosEstructura.length < 2) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Debes adjuntar al menos 2 fotos de la estructura afectada (${_fotosEstructura.length}/2).'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
          } else if (_currentStep == 2) {
            if (_totalOcupantes < 1) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('El censo debe incluir al menos 1 persona en el hogar según el desglose.'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
          } else if (_currentStep == 3) {
            if (_fotoIdentificacion == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Debes adjuntar al menos 1 foto de la cédula o identificación del jefe/a de familia.'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
          }
          if (_currentStep < 3) {
            setState(() => _currentStep++);
          } else {
            _enviarReporte();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep--);
          } else {
            Navigator.of(context).pop();
          }
        },
        controlsBuilder: (context, details) {
          final isLast = _currentStep == 3;
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Botón ATRÁS o CANCELAR a la IZQUIERDA
                if (_currentStep > 0)
                  OutlinedButton(
                    onPressed: details.onStepCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    child: const Text('ATRÁS'),
                  )
                else
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    child: const Text('CANCELAR'),
                  ),
                const SizedBox(width: 12),
                // Botón SIGUIENTE o FINALIZAR a la DERECHA
                Expanded(
                  child: ElevatedButton(
                    onPressed: _enviando ? null : details.onStepContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLast ? Colors.green.shade700 : Colors.red.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _enviando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(isLast ? (widget.initialReport != null ? 'ACTUALIZAR Y ENVIAR' : 'FINALIZAR Y ENVIAR') : 'SIGUIENTE'),
                  ),
                ),
              ],
            ),
          );
        },
        steps: [
          // ---------------------------------------------------------------
          // PASO 1: UBICACIÓN
          // ---------------------------------------------------------------
          Step(
            title: const Text('Sitio'),
            isActive: _currentStep >= 0,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Banner de Estado GPS y Geocodificación
                Card(
                  color: _autocompletadoOnline ? Colors.green.shade50 : Colors.amber.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: _autocompletadoOnline ? Colors.green.shade300 : Colors.amber.shade300,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _autocompletadoOnline ? Icons.check_circle_outline : Icons.gps_fixed,
                              color: _autocompletadoOnline ? Colors.green.shade800 : Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'GPS: ${_lat.toStringAsFixed(4)}, ${_lng.toStringAsFixed(4)} (±${_precisionMetros?.toStringAsFixed(0) ?? "?"}m)',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: _obteniendoGps
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.refresh),
                              onPressed: _capturarGpsInicial,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _estadoGeolocalizacion,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _autocompletadoOnline ? Colors.green.shade900 : Colors.brown.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Selector de Provincia (Nivel Nacional)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _provincia,
                  decoration: const InputDecoration(labelText: 'Provincia / Comarca', border: OutlineInputBorder()),
                  items: PanamaDpaService.getProvincias()
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _provincia = val;
                        final dists = PanamaDpaService.getDistritos(_provincia);
                        _distrito = dists.isNotEmpty ? dists.first : '';
                        final corrs = PanamaDpaService.getCorregimientos(_provincia, _distrito);
                        _corregimiento = corrs.isNotEmpty ? corrs.first : '';
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Selector de Distrito (Filtrado por Provincia)
                DropdownButtonFormField<String>(
                  key: ValueKey('dist_$_provincia'),
                  isExpanded: true,
                  initialValue: PanamaDpaService.getDistritos(_provincia).contains(_distrito)
                      ? _distrito
                      : (PanamaDpaService.getDistritos(_provincia).isNotEmpty ? PanamaDpaService.getDistritos(_provincia).first : null),
                  decoration: const InputDecoration(labelText: 'Distrito', border: OutlineInputBorder()),
                  items: PanamaDpaService.getDistritos(_provincia)
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _distrito = val;
                        final corrs = PanamaDpaService.getCorregimientos(_provincia, _distrito);
                        _corregimiento = corrs.isNotEmpty ? corrs.first : '';
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Selector de Corregimiento (Filtrado por Distrito)
                DropdownButtonFormField<String>(
                  key: ValueKey('corr_${_provincia}_$_distrito'),
                  isExpanded: true,
                  initialValue: PanamaDpaService.getCorregimientos(_provincia, _distrito).contains(_corregimiento)
                      ? _corregimiento
                      : (PanamaDpaService.getCorregimientos(_provincia, _distrito).isNotEmpty ? PanamaDpaService.getCorregimientos(_provincia, _distrito).first : null),
                  decoration: const InputDecoration(labelText: 'Corregimiento', border: OutlineInputBorder()),
                  items: PanamaDpaService.getCorregimientos(_provincia, _distrito)
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _corregimiento = val);
                  },
                ),
                const SizedBox(height: 12),

                // Texto Libre para Comunidad / Barrio con auto-normalización (Obligatorio)
                TextField(
                  controller: _comunidadCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Comunidad / Barrio / Urbanización *',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    helperText: 'Obligatorio. Se normaliza automáticamente sin errores de tipeo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Calle / Dirección con auto-normalización (Opcional)
                TextField(
                  controller: _calleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Calle / Número de Vivienda (Opcional)',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    helperText: 'Ej. Calle 3ra, Casa #45, Edificio Mirador',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Punto de Referencia (Opcional)
                TextField(
                  controller: _referenciaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Punto de referencia',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    helperText: 'Opcional. Ej. Frente a la tienda, al lado del parque',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),

          // ---------------------------------------------------------------
          // PASO 2: ESTRUCTURA & HABITABILIDAD (ATC-20)
          // ---------------------------------------------------------------
          Step(
            title: const Text('Daños'),
            isActive: _currentStep >= 1,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Semáforo de Habitabilidad (ATC-20):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                RadioGroup<NivelHabitabilidad>(
                  groupValue: _habitabilidad,
                  onChanged: (val) {
                    if (val != null) setState(() => _habitabilidad = val);
                  },
                  child: Column(
                    children: NivelHabitabilidad.values.map((nivel) {
                      Color color;
                      switch (nivel) {
                        case NivelHabitabilidad.habitable:
                          color = Colors.green;
                          break;
                        case NivelHabitabilidad.accesoRestringido:
                          color = Colors.amber.shade700;
                          break;
                        case NivelHabitabilidad.inhabitable:
                          color = Colors.red;
                          break;
                        case NivelHabitabilidad.colapsoTotal:
                          color = Colors.purple.shade800;
                          break;
                      }
                      return RadioListTile<NivelHabitabilidad>(
                        value: nivel,
                        secondary: CircleAvatar(backgroundColor: color, radius: 10),
                        title: Text(nivel.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('¿Hay riesgo inminente de colapso por réplicas?'),
                  value: _riesgoColapso,
                  activeThumbColor: Colors.red,
                  onChanged: (val) => setState(() => _riesgoColapso = val),
                ),
                SwitchListTile(
                  title: const Text('¿Hay fuga de gas inflamable?'),
                  value: _fugaGas,
                  activeThumbColor: Colors.red,
                  onChanged: (val) => setState(() => _fugaGas = val),
                ),
                SwitchListTile(
                  title: const Text('¿Hay cables eléctricos caídos con peligro?'),
                  value: _cablesCaidos,
                  activeThumbColor: Colors.orange,
                  onChanged: (val) => setState(() => _cablesCaidos = val),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descripcionDanoCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Breve descripción de los daños visibles',
                    helperText: 'Ej. Pared rajada, caída de techo, vidrios rotos',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Sección de Fotos de la Estructura Afectada (Mínimo 2 requeridas)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _fotosEstructura.length >= 2 ? Colors.green.shade400 : Colors.red.shade300,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Fotos de la Estructura *',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _fotosEstructura.length >= 2 ? Colors.green.shade100 : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_fotosEstructura.length} de 2 mínimas',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _fotosEstructura.length >= 2 ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Obligatorio: Adjunta al menos 2 fotos de la estructura (fachada, grietas, columnas o techo)',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _capturarFotoEstructura(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Cámara'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _capturarFotoEstructura(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Galería'),
                            ),
                          ),
                        ],
                      ),
                      if (_fotosEstructura.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 95,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _fotosEstructura.length,
                            itemBuilder: (ctx, idx) {
                              final foto = _fotosEstructura[idx];
                              return Stack(
                                children: [
                                  Container(
                                    width: 95,
                                    height: 95,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade400),
                                      image: DecorationImage(
                                        image: FileImage(File(foto.rutaLocal)),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 2,
                                    right: 10,
                                    child: GestureDetector(
                                      onTap: () => setState(() => _fotosEstructura.removeAt(idx)),
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ---------------------------------------------------------------
          // PASO 3: PERSONAS Y ASISTENCIA (SPHERE / INSARAG)
          // ---------------------------------------------------------------
          Step(
            title: const Text('Censo'),
            isActive: _currentStep >= 2,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_atrapados > 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ALERTA P1: Se activará protocolo urgente de Búsqueda y Rescate (USAR) para SINAPROC y Bomberos.',
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Total de personas calculado automáticamente
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total de personas en el hogar:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Calculado automáticamente a partir del detalle inferior',
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      CircleAvatar(
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        radius: 18,
                        child: Text(
                          '$_totalOcupantes',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),

                const Text(
                  'Desglose por edad (determina el total de ocupantes):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                ),
                const SizedBox(height: 4),
                _buildCounter('Bebés (0 a 2 años):', _neonatos, (v) {
                  setState(() {
                    _neonatos = v;
                    _clampearCondicionesEspeciales();
                  });
                }),
                _buildCounter('Niños (3 a 12 años):', _ninos, (v) {
                  setState(() {
                    _ninos = v;
                    _clampearCondicionesEspeciales();
                  });
                }),
                _buildCounter('Adolescentes (13 a 17 años):', _adolescentes, (v) {
                  setState(() {
                    _adolescentes = v;
                    _clampearCondicionesEspeciales();
                  });
                }),
                _buildCounter('Adultos (18 a 59 años):', _adultos, (v) {
                  setState(() {
                    _adultos = v;
                    _clampearCondicionesEspeciales();
                  });
                }),
                _buildCounter('Adultos mayores (60+ años):', _adultosMayores, (v) {
                  setState(() {
                    _adultosMayores = v;
                    _clampearCondicionesEspeciales();
                  });
                }),

                const Divider(height: 24),
                const Text(
                  'Condiciones de vulnerabilidad específicas:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                ),
                const SizedBox(height: 4),
                _buildCounter(
                  'Mujeres embarazadas:',
                  _embarazadas,
                  (v) => setState(() => _embarazadas = v),
                  maxVal: _totalOcupantes,
                  helperSubtitle: '(Máx. $_totalOcupantes según total del hogar)',
                ),
                _buildCounter(
                  'Personas con discapacidad:',
                  _discapacitados,
                  (v) => setState(() => _discapacitados = v),
                  maxVal: _totalOcupantes,
                  helperSubtitle: '(Máx. $_totalOcupantes según total del hogar)',
                ),

                const Divider(height: 24),
                const Text(
                  'Emergencias de rescate y auxilio médico inmediato:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                ),
                const SizedBox(height: 4),
                _buildCounter(
                  'Personas atrapadas o desaparecidas:',
                  _atrapados,
                  (v) => setState(() => _atrapados = v),
                  isCritical: true,
                  maxVal: _totalOcupantes,
                  helperSubtitle: '(Máx. $_totalOcupantes según total del hogar)',
                ),
                _buildCounter(
                  'Personas con lesiones que requieren hospital:',
                  _lesionados,
                  (v) => setState(() => _lesionados = v),
                  maxVal: _totalOcupantes,
                  helperSubtitle: '(Máx. $_totalOcupantes según total del hogar)',
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('¿Requiere albergue temporal de inmediato?'),
                  value: _requiereAlbergue,
                  onChanged: (val) => setState(() => _requiereAlbergue = val),
                ),
                SwitchListTile(
                  title: const Text('¿Requiere agua potable y alimentos de auxilio?'),
                  value: _requiereAguaAlimentos,
                  onChanged: (val) => setState(() => _requiereAguaAlimentos = val),
                ),
              ],
            ),
          ),

          // ---------------------------------------------------------------
          // PASO 4: TITULAR AFECTADO & CONSENTIMIENTO (LEY 81)
          // ---------------------------------------------------------------
          Step(
            title: const Text('Fin'),
            isActive: _currentStep >= 3,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  title: const Text('¿Estás reportando tu propia casa?'),
                  subtitle: Text(_esElMismoInformante
                      ? 'Se usan tus datos guardados como jefe de familia'
                      : 'Ingresa los datos del jefe de la familia afectada'),
                  value: _esElMismoInformante,
                  onChanged: (val) {
                    setState(() {
                      _esElMismoInformante = val;
                      if (_esElMismoInformante && _reporterProfile != null) {
                        _afectadoNombreCtrl.text = _reporterProfile!.nombre;
                        _afectadoCedulaCtrl.text = _reporterProfile!.cedula;
                        _afectadoTelefonoCtrl.text = _reporterProfile!.telefono;
                      } else if (!_esElMismoInformante) {
                        _afectadoNombreCtrl.clear();
                        _afectadoCedulaCtrl.clear();
                        _afectadoTelefonoCtrl.clear();
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _afectadoNombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo del Jefe/a de Familia *',
                    helperText: 'Obligatorio para el registro humanitario oficial',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _afectadoCedulaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cédula de Identidad del Jefe/a de Familia *',
                    helperText: 'Obligatorio. Ej. 7-123-456, 8-123-4567 o Pasaporte',
                    prefixIcon: Icon(Icons.credit_card),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _afectadoTelefonoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono de Contacto del Jefe/a de Familia *',
                    helperText: 'Obligatorio para que los rescatistas coordinen auxilio',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Sección Foto de Identificación (Mínimo 1 obligatoria)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _fotoIdentificacion != null ? Colors.green.shade400 : Colors.red.shade300,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Foto de la Cédula / Identificación *',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _fotoIdentificacion != null ? Colors.green.shade100 : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _fotoIdentificacion != null ? '1 de 1 agregada' : 'Falta foto',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _fotoIdentificacion != null ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Obligatorio: Fotografía legible de la cédula panameña o pasaporte del jefe/a de familia',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _capturarFotoIdentificacion(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Cámara'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _capturarFotoIdentificacion(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Galería'),
                            ),
                          ),
                        ],
                      ),
                      if (_fotoIdentificacion != null) ...[
                        const SizedBox(height: 12),
                        Stack(
                          alignment: Alignment.topRight,
                          children: [
                            Container(
                              height: 140,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.shade400),
                                image: DecorationImage(
                                  image: FileImage(File(_fotoIdentificacion!.rutaLocal)),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: GestureDetector(
                                onTap: () => setState(() => _fotoIdentificacion = null),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: CheckboxListTile(
                    value: _consentimientoDado,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Consentimiento Informado (Ley 81 de Panamá)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Autorizo que los datos de contacto y daños sean transmitidos exclusivamente a SINAPROC, Cruz Roja y autoridades para coordinar ayuda y rescate. El mapa público jamás mostrará nombres ni teléfonos.',
                      style: TextStyle(fontSize: 12),
                    ),
                    onChanged: (val) => setState(() => _consentimientoDado = val ?? true),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCounter(
    String title,
    int val,
    Function(int) onChanged, {
    bool isCritical = false,
    int? maxVal,
    String? helperSubtitle,
  }) {
    final canIncrement = maxVal == null || val < maxVal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: isCritical ? FontWeight.bold : FontWeight.normal,
                    color: isCritical && val > 0 ? Colors.red : Colors.black87,
                  ),
                ),
                if (helperSubtitle != null)
                  Text(
                    helperSubtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: val > 0 ? () => onChanged(val - 1) : null,
              ),
              Text('$val', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: canIncrement ? () => onChanged(val + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
