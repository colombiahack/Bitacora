import 'package:geolocator/geolocator.dart';

import '../errors/aero_exception.dart';

/// Captura de coordenadas GPS (funciona sin internet: usa el chip GPS).
class LocationService {
  const LocationService();

  /// Devuelve (latitud, longitud) actuales o lanza [AeroException] con un
  /// mensaje claro si el GPS está apagado, el permiso fue negado o hubo timeout.
  Future<({double latitude, double longitude})> getCurrentCoordinates() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const AeroException('Activa el GPS del dispositivo e inténtalo de nuevo.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const AeroException('Permiso de ubicación denegado.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const AeroException(
          'Permiso de ubicación bloqueado. Actívalo en los ajustes del sistema.');
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      return (latitude: position.latitude, longitude: position.longitude);
    } catch (_) {
      throw const AeroException(
          'No se pudo obtener la posición. Sal a cielo abierto e inténtalo otra vez.');
    }
  }
}
