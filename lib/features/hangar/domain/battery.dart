import '../../../core/constants/app_constants.dart';
import '../../../core/constants/enums.dart';
import '../../../core/utils/json_helpers.dart';

/// Batería de un UAS (no aplica a aviación tripulada).
class Battery {
  Battery({
    required this.id,
    required this.code,
    this.aircraftId,
    this.cycleCount = 0,
    this.healthStatus = BatteryHealth.good,
    this.purchaseDate,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String id;

  /// Ej.: BAT-01 (único).
  final String code;

  /// Aeronave a la que está vinculada.
  final String? aircraftId;
  final int cycleCount;
  final BatteryHealth healthStatus;
  final DateTime? purchaseDate;
  final DateTime updatedAt;

  bool get isCritical =>
      cycleCount >= kBatteryCriticalCycles ||
      healthStatus == BatteryHealth.poor;
  bool get isWarning => cycleCount >= kBatteryWarningCycles;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'aircraftId': aircraftId,
        'cycleCount': cycleCount,
        'healthStatus': healthStatus.code,
        'purchaseDate': purchaseDate?.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  Map<String, dynamic> toDbMap() => toJson();

  factory Battery.fromJson(Map<String, dynamic> j) => Battery(
        id: j['id'] as String,
        code: (j['code'] as String?) ?? '',
        aircraftId: j['aircraftId'] as String?,
        cycleCount: asInt(j['cycleCount']),
        healthStatus: BatteryHealth.fromCode(j['healthStatus'] as String?),
        purchaseDate: asDateOrNull(j['purchaseDate']),
        updatedAt: asDateOrNull(j['updatedAt']),
      );
}
