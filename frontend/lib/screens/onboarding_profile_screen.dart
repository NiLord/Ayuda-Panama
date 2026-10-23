import 'package:flutter/material.dart';
import '../l10n/app_messages.dart';
import '../models/disaster_report.dart';
import '../services/reporter_profile_service.dart';
import 'home_screen.dart';

class OnboardingProfileScreen extends StatefulWidget {
  final bool isFirstReportFlow;
  const OnboardingProfileScreen({super.key, this.isFirstReportFlow = false});

  @override
  State<OnboardingProfileScreen> createState() => _OnboardingProfileScreenState();
}

class _OnboardingProfileScreenState extends State<OnboardingProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();
  RolInformante _rolSeleccionado = RolInformante.afectadoDirecto;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarPerfilExistente();
  }

  Future<void> _cargarPerfilExistente() async {
    final profile = await ReporterProfileService.getOrCreateProfile();
    if (mounted) {
      setState(() {
        if (profile.nombre.isNotEmpty) _nombreCtrl.text = profile.nombre;
        if (profile.cedula.isNotEmpty) _cedulaCtrl.text = profile.cedula;
        if (profile.telefono.isNotEmpty) _telefonoCtrl.text = profile.telefono;
        if (profile.organizacion.isNotEmpty) _orgCtrl.text = profile.organizacion;

        final rolMatch = RolInformante.values.where((r) => r.value == profile.rol);
        if (rolMatch.isNotEmpty) {
          _rolSeleccionado = rolMatch.first;
        }
      });
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _cedulaCtrl.dispose();
    _telefonoCtrl.dispose();
    _orgCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardarPerfil() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);
    await ReporterProfileService.saveProfile(
      nombre: _nombreCtrl.text,
      cedula: _cedulaCtrl.text,
      telefono: _telefonoCtrl.text,
      rol: _rolSeleccionado.value,
      organizacion: _orgCtrl.text,
    );

    if (mounted) {
      if (widget.isFirstReportFlow || Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final msg = AppMessages.current;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isFirstReportFlow ? msg.profileTitleReporter : msg.profileTitleInitial),
        centerTitle: true,
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.emergency_share, size: 64, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                msg.appTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                msg.profileDescription,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nombreCtrl,
                decoration: InputDecoration(
                  labelText: msg.profileNameLabel,
                  prefixIcon: const Icon(Icons.person),
                  border: const OutlineInputBorder(),
                ),
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? msg.profileNameError : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cedulaCtrl,
                decoration: InputDecoration(
                  labelText: msg.profileCedulaLabel,
                  prefixIcon: const Icon(Icons.credit_card),
                  helperText: msg.profileCedulaHelper,
                  border: const OutlineInputBorder(),
                ),
                validator: (val) => (val == null || val.trim().isEmpty)
                    ? msg.profileCedulaError
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: msg.profilePhoneLabel,
                  prefixIcon: const Icon(Icons.phone),
                  helperText: msg.profilePhoneHelper,
                  border: const OutlineInputBorder(),
                ),
                validator: (val) => (val == null || val.trim().isEmpty)
                    ? msg.profilePhoneError
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<RolInformante>(
                isExpanded: true,
                initialValue: _rolSeleccionado,
                decoration: InputDecoration(
                  labelText: msg.profileRoleLabel,
                  prefixIcon: const Icon(Icons.badge),
                  border: const OutlineInputBorder(),
                ),
                items: RolInformante.values.map((r) {
                  return DropdownMenuItem(value: r, child: Text(r.label));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _rolSeleccionado = val);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _orgCtrl,
                decoration: InputDecoration(
                  labelText: msg.profileOrgLabel,
                  helperText: msg.profileOrgHelper,
                  prefixIcon: const Icon(Icons.apartment),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _guardando ? null : _guardarPerfil,
                icon: _guardando
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Icon(Icons.check_circle),
                label: Text(
                  widget.isFirstReportFlow ? msg.continueToReport : msg.begin,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
