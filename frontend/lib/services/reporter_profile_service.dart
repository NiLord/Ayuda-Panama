import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ReporterProfile {
  final String reporterId;
  final String installationId;
  final String nombre;
  final String cedula;
  final String telefono;
  final String rol;
  final String organizacion;

  ReporterProfile({
    required this.reporterId,
    required this.installationId,
    required this.nombre,
    this.cedula = '',
    required this.telefono,
    required this.rol,
    required this.organizacion,
  });
}

class ReporterProfileService {
  static const _keyReporterId = 'lse_reporter_id';
  static const _keyInstallationId = 'lse_installation_id';
  static const _keyNombre = 'lse_informante_nombre';
  static const _keyCedula = 'lse_informante_cedula';
  static const _keyTelefono = 'lse_informante_telefono';
  static const _keyRol = 'lse_informante_rol';
  static const _keyOrganizacion = 'lse_informante_organizacion';
  static const _keyProfileComplete = 'lse_profile_complete';

  static Future<bool> isProfileConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyProfileComplete) ?? false;
  }

  static Future<ReporterProfile> getOrCreateProfile() async {
    final prefs = await SharedPreferences.getInstance();

    String? reporterId = prefs.getString(_keyReporterId);
    if (reporterId == null || reporterId.isEmpty) {
      reporterId = 'rep_${const Uuid().v4()}';
      await prefs.setString(_keyReporterId, reporterId);
    }

    String? installationId = prefs.getString(_keyInstallationId);
    if (installationId == null || installationId.isEmpty) {
      installationId = 'inst_${const Uuid().v4()}';
      await prefs.setString(_keyInstallationId, installationId);
    }

    return ReporterProfile(
      reporterId: reporterId,
      installationId: installationId,
      nombre: prefs.getString(_keyNombre) ?? '',
      cedula: prefs.getString(_keyCedula) ?? '',
      telefono: prefs.getString(_keyTelefono) ?? '',
      rol: prefs.getString(_keyRol) ?? 'VECINO_O_TERCERO',
      organizacion: prefs.getString(_keyOrganizacion) ?? '',
    );
  }

  static Future<void> saveProfile({
    required String nombre,
    String cedula = '',
    required String telefono,
    required String rol,
    required String organizacion,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNombre, nombre.trim());
    await prefs.setString(_keyCedula, cedula.trim());
    await prefs.setString(_keyTelefono, telefono.trim());
    await prefs.setString(_keyRol, rol);
    await prefs.setString(_keyOrganizacion, organizacion.trim());
    await prefs.setBool(_keyProfileComplete, true);
  }
}
