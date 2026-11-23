import '../../../core/constants/enums.dart';
import '../../../core/utils/json_helpers.dart';

/// Aeronave (dron o avión/helicóptero tripulado).
class Aircraft {
  Aircraft({
    required this.id,
    required this.name,
    required this.model,
    this.serialNumber = '',
    this.registrationCode = '',
    this.category = AircraftCategory.uas,
    this.mtowKg = 0,
    this.totalFlightMinutes = 0,
    this.status = AircraftStatus.active,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final String model;
  final String serialNumber;
  final String registrationCode;
  final AircraftCategory category;

  /// Peso máximo de despegue (kg).
  final double mtowKg;

  /// Tiempo total acumulado en vuelos reales (el simulador no suma).
  final int totalFlightMinutes;
  final AircraftStatus status;
  final DateTime updatedAt;

  bool get isUas => category == AircraftCategory.uas;
  bool get isActive => status == AircraftStatus.active;

  /// Texto corto para listas: "Matrice 300 (HK-1234)".
  String get displayName =>
      registrationCode.isEmpty ? name : '$name ($registrationCode)';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'model': model,
        'serialNumber': serialNumber,
        'registrationCode': registrationCode,
        'category': category.code,
        'mtowKg': mtowKg,
        'totalFlightMinutes': totalFlightMinutes,
        'status': status.code,
        'updatedAt': updatedAt.toIso8601String(),
      };

  Map<String, dynamic> toDbMap() => toJson();

  factory Aircraft.fromJson(Map<String, dynamic> j) => Aircraft(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        model: (j['model'] as String?) ?? '',
        serialNumber: (j['serialNumber'] as String?) ?? '',
        registrationCode: (j['registrationCode'] as String?) ?? '',
        category: AircraftCategory.fromCode(j['category'] as String?),
        mtowKg: asDouble(j['mtowKg']),
        totalFlightMinutes: asInt(j['totalFlightMinutes']),
        status: AircraftStatus.fromCode(j['status'] as String?),
        updatedAt: asDateOrNull(j['updatedAt']),
      );
}
