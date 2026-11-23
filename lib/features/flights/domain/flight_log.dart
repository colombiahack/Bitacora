import '../../../core/constants/enums.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json_helpers.dart';

/// Registro de un vuelo.
class FlightLog {
  FlightLog({
    required this.id,
    required this.date,
    required this.takeoffTime,
    required this.landingTime,
    required this.durationMinutes,
    required this.aircraftId,
    this.batteryIds = const [],
    required this.operationType,
    this.locationName = '',
    this.latitude,
    this.longitude,
    this.maxAltitudeAglMeters,
    this.weatherSummary = '',
    this.windSpeedKmh,
    this.preFlightChecklistPassed = false,
    this.remarks = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String id;

  /// Fecha del vuelo (solo día).
  final DateTime date;
  final DateTime takeoffTime;
  final DateTime landingTime;
  final int durationMinutes;
  final String aircraftId;

  /// IDs de las baterías usadas (tabla puente `flight_battery`).
  final List<String> batteryIds;
  final OperationType operationType;
  final String locationName;
  final double? latitude;
  final double? longitude;

  /// Altitud máxima sobre el nivel del suelo (AGL), en metros.
  final double? maxAltitudeAglMeters;
  final String weatherSummary;
  final double? windSpeedKmh;
  final bool preFlightChecklistPassed;

  /// Novedades o incidentes.
  final String remarks;
  final DateTime updatedAt;

  bool get isSimulator => operationType.isSimulator;

  /// Solo los vuelos reales suman horas a la aeronave y ciclos a las baterías.
  bool get countsTowardsTotals => !operationType.isSimulator;

  bool get hasCoordinates => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': kYmd.format(date),
        'takeoffTime': takeoffTime.toIso8601String(),
        'landingTime': landingTime.toIso8601String(),
        'durationMinutes': durationMinutes,
        'aircraftId': aircraftId,
        'batteryIds': batteryIds,
        'operationType': operationType.code,
        'locationName': locationName,
        'latitude': latitude,
        'longitude': longitude,
        'maxAltitudeAglMeters': maxAltitudeAglMeters,
        'weatherSummary': weatherSummary,
        'windSpeedKmh': windSpeedKmh,
        'preFlightChecklistPassed': preFlightChecklistPassed,
        'remarks': remarks,
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Mapa para la tabla `flight_log`: sin `batteryIds` (van en `flight_battery`)
  /// y con booleanos como 0/1.
  Map<String, dynamic> toDbMap() {
    final map = toJson()..remove('batteryIds');
    map['preFlightChecklistPassed'] = preFlightChecklistPassed ? 1 : 0;
    return map;
  }

  factory FlightLog.fromJson(Map<String, dynamic> j) => FlightLog(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        takeoffTime: DateTime.parse(j['takeoffTime'] as String),
        landingTime: DateTime.parse(j['landingTime'] as String),
        durationMinutes: asInt(j['durationMinutes']),
        aircraftId: j['aircraftId'] as String,
        batteryIds:
            ((j['batteryIds'] as List?) ?? const []).cast<String>().toList(),
        operationType: OperationType.fromCode(j['operationType'] as String?),
        locationName: (j['locationName'] as String?) ?? '',
        latitude: asDoubleOrNull(j['latitude']),
        longitude: asDoubleOrNull(j['longitude']),
        maxAltitudeAglMeters: asDoubleOrNull(j['maxAltitudeAglMeters']),
        weatherSummary: (j['weatherSummary'] as String?) ?? '',
        windSpeedKmh: asDoubleOrNull(j['windSpeedKmh']),
        preFlightChecklistPassed: asBool(j['preFlightChecklistPassed']),
        remarks: (j['remarks'] as String?) ?? '',
        updatedAt: asDateOrNull(j['updatedAt']),
      );
}
