import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors/aero_exception.dart';

class WeatherData {
  const WeatherData({
    required this.summary,
    required this.windKmh,
    required this.tempC,
  });

  final String summary;
  final double windKmh;
  final double tempC;
}

/// Clima actual desde Open-Meteo (gratuito, sin clave). Requiere internet.
class WeatherService {
  const WeatherService();

  Future<WeatherData> fetch(double latitude, double longitude) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(4),
      'longitude': longitude.toStringAsFixed(4),
      'current': 'temperature_2m,weather_code,wind_speed_10m',
      'wind_speed_unit': 'kmh',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw AeroException('El servicio del clima respondió con error ${res.statusCode}.');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final cur = body['current'] as Map<String, dynamic>?;
    if (cur == null) {
      throw const AeroException('No se recibieron datos del clima.');
    }
    final temp = (cur['temperature_2m'] as num?)?.toDouble() ?? 0;
    final wind = (cur['wind_speed_10m'] as num?)?.toDouble() ?? 0;
    final code = (cur['weather_code'] as num?)?.toInt() ?? 0;
    return WeatherData(
      summary: '${_describe(code)}, ${temp.toStringAsFixed(0)} °C',
      windKmh: wind,
      tempC: temp,
    );
  }

  static String _describe(int code) {
    if (code == 0) return 'Despejado';
    if (code == 1 || code == 2) return 'Parcialmente nublado';
    if (code == 3) return 'Nublado';
    if (code == 45 || code == 48) return 'Niebla';
    if (code >= 51 && code <= 57) return 'Llovizna';
    if (code >= 61 && code <= 67) return 'Lluvia';
    if (code >= 71 && code <= 77) return 'Nieve';
    if (code >= 80 && code <= 82) return 'Chubascos';
    if (code >= 95) return 'Tormenta';
    return 'Variable';
  }
}
