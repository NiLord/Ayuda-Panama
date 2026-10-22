import 'dart:convert';
import 'package:flutter/services.dart';

class PanamaDpaService {
  static Map<String, dynamic>? _dpaCache;

  /// Carga el catálogo nacional DPA desde el archivo local JSON
  static Future<void> init() async {
    if (_dpaCache != null) return;
    try {
      final jsonStr = await rootBundle.loadString('assets/data/panama_dpa.json');
      _dpaCache = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      _dpaCache = {};
    }
  }

  /// Retorna la lista de todas las provincias y comarcas del país
  static List<String> getProvincias() {
    if (_dpaCache == null || _dpaCache!.isEmpty) {
      return ['Los Santos', 'Herrera', 'Coclé', 'Panamá', 'Panamá Oeste', 'Chiriquí', 'Veraguas', 'Colón', 'Bocas del Toro', 'Darién'];
    }
    return _dpaCache!.keys.toList();
  }

  /// Retorna los distritos pertenecientes a una provincia dada
  static List<String> getDistritos(String provincia) {
    if (_dpaCache == null) return [];
    final provMap = _dpaCache![provincia] as Map<String, dynamic>?;
    if (provMap == null) return [];
    return provMap.keys.toList();
  }

  /// Retorna los corregimientos pertenecientes a un distrito dado
  static List<String> getCorregimientos(String provincia, String distrito) {
    if (_dpaCache == null) return [];
    final provMap = _dpaCache![provincia] as Map<String, dynamic>?;
    if (provMap == null) return [];
    final corrsList = provMap[distrito] as List<dynamic>?;
    if (corrsList == null) return [];
    return corrsList.map((e) => e.toString()).toList();
  }
}
