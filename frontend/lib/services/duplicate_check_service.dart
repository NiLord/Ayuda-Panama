import 'api_service.dart';
import '../models/duplicate_check_result.dart';
import '../models/miviot_tramite_result.dart';

/// Servicio de alto nivel para validación de no duplicidad de cédula y consulta MIVIOT
class DuplicateCheckService {
  // Caché en memoria para no repetir consultas idénticas en la misma sesión
  static final Map<String, DuplicateCheckResult> _cache = {};

  static Future<DuplicateCheckResult> verificarCedula(String cedula, {bool force = false}) async {
    final clean = cedula.trim().toUpperCase();
    if (clean.isEmpty) {
      return DuplicateCheckResult.empty();
    }

    if (!force && _cache.containsKey(clean)) {
      return _cache[clean]!;
    }

    final result = await ApiService.checkCedulaDuplicate(clean);
    if (result.success) {
      _cache[clean] = result;
    }
    return result;
  }

  static Future<MiviotTramiteResult?> consultarTramiteMiviot(
    String cedula, {
    bool force = false,
  }) async {
    return ApiService.fetchMiviotTramite(cedula, force: force);
  }

  static void limpiarCache() {
    _cache.clear();
  }
}
