import 'package:flutter/material.dart';
import '../models/disaster_report.dart';
import '../services/reporter_profile_service.dart';
import 'home_screen.dart';

class OnboardingProfileScreen extends StatefulWidget {
  const OnboardingProfileScreen({super.key});

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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración Inicial'),
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
              const Text(
                'Ayuda Panamá',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Configura tus datos de contacto una sola vez. Se reutilizarán automáticamente en cada reporte para que no pierdas tiempo en emergencias.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tu Nombre Completo *',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'Ingresa tu nombre' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cedulaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tu Cédula de Identidad Personal *',
                  prefixIcon: Icon(Icons.credit_card),
                  helperText: 'Ej. 7-123-456 o 8-123-4567',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => (val == null || val.trim().isEmpty)
                    ? 'Ingresa tu número de cédula'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono de Contacto (+507...) *',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                validator: (val) => (val == null || val.trim().isEmpty)
                    ? 'Ingresa un teléfono para los rescatistas'
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<RolInformante>(
                isExpanded: true,
                initialValue: _rolSeleccionado,
                decoration: const InputDecoration(
                  labelText: '¿Cuál es tu rol habitual?',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
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
                decoration: const InputDecoration(
                  labelText: 'Organización / Institución (Opcional)',
                  helperText: 'Ej. Cruz Roja, Junta Comunal, Independiente',
                  prefixIcon: Icon(Icons.apartment),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _guardando ? null : _guardarPerfil,
                icon: _guardando
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Icon(Icons.check_circle),
                label: const Text(
                  'Comenzar',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
