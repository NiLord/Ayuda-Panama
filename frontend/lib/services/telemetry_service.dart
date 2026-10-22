import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';

class DeviceTelemetry {
  final bool esFisico;
  final String marca;
  final String modelo;
  final String sistemaOperativo;
  final int? nivelBateria;
  final String tipoConexion;
  final Position? posicionGps;

  DeviceTelemetry({
    required this.esFisico,
    required this.marca,
    required this.modelo,
    required this.sistemaOperativo,
    this.nivelBateria,
    required this.tipoConexion,
    this.posicionGps,
  });
}

class TelemetryService {
  static final _deviceInfo = DeviceInfoPlugin();
  static final _battery = Battery();

  static Future<DeviceTelemetry> captureTelemetry() async {
    bool esFisico = true;
    String marca = 'Desconocido';
    String modelo = 'Desconocido';
    String so = Platform.operatingSystem;

    try {
      if (Platform.isAndroid) {
        final android = await _deviceInfo.androidInfo;
        esFisico = android.isPhysicalDevice;
        marca = android.manufacturer;
        modelo = android.model;
        so = 'Android ${android.version.release} (SDK ${android.version.sdkInt})';
      } else if (Platform.isIOS) {
        final ios = await _deviceInfo.iosInfo;
        esFisico = ios.isPhysicalDevice;
        marca = 'Apple';
        modelo = ios.utsname.machine;
        so = '${ios.systemName} ${ios.systemVersion}';
      }
    } catch (_) {}

    int? nivelBateria;
    try {
      nivelBateria = await _battery.batteryLevel;
    } catch (_) {}

    String tipoConexion = 'CELULAR';
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      if (connectivityResults.contains(ConnectivityResult.wifi)) {
        tipoConexion = 'WIFI';
      } else if (connectivityResults.contains(ConnectivityResult.mobile)) {
        tipoConexion = 'CELULAR';
      } else if (connectivityResults.contains(ConnectivityResult.none)) {
        tipoConexion = 'OFFLINE_COLA';
      }
    } catch (_) {}

    Position? posicion;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          posicion = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 4),
          );
        }
      }
    } catch (_) {}

    return DeviceTelemetry(
      esFisico: esFisico,
      marca: marca,
      modelo: modelo,
      sistemaOperativo: so,
      nivelBateria: nivelBateria,
      tipoConexion: tipoConexion,
      posicionGps: posicion,
    );
  }
}
