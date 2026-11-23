import '../../../core/constants/enums.dart';
import '../../../core/utils/json_helpers.dart';

/// Perfil del piloto (una sola fila en la base de datos local).
class PilotProfile {
  const PilotProfile({
    required this.id,
    required this.fullName,
    required this.documentId,
    required this.licenseNumber,
    this.medicalCertExpiry,
    this.preferredMode = PilotMode.uas,
    this.hybridEnabled = false,
  });

  /// Id fijo: la app maneja un único perfil de piloto.
  static const String singletonId = 'pilot';

  factory PilotProfile.empty() => const PilotProfile(
        id: singletonId,
        fullName: '',
        documentId: '',
        licenseNumber: '',
      );

  final String id;
  final String fullName;
  final String documentId;

  /// Ej.: certificado UAS RAC 100.
  final String licenseNumber;
  final DateTime? medicalCertExpiry;
  final PilotMode preferredMode;

  /// `false` = "Solo UAS"; `true` = "Híbrido UAS + Tripulado".
  final bool hybridEnabled;

  bool get isComplete => fullName.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fullName': fullName,
        'documentId': documentId,
        'licenseNumber': licenseNumber,
        'medicalCertExpiry': medicalCertExpiry?.toIso8601String(),
        'preferredMode': preferredMode.code,
        'hybridEnabled': hybridEnabled,
      };

  /// Mapa para SQLite (los booleanos se guardan como 0/1).
  Map<String, dynamic> toDbMap() =>
      toJson()..['hybridEnabled'] = hybridEnabled ? 1 : 0;

  factory PilotProfile.fromJson(Map<String, dynamic> j) => PilotProfile(
        id: j['id'] as String,
        fullName: (j['fullName'] as String?) ?? '',
        documentId: (j['documentId'] as String?) ?? '',
        licenseNumber: (j['licenseNumber'] as String?) ?? '',
        medicalCertExpiry: asDateOrNull(j['medicalCertExpiry']),
        preferredMode: PilotMode.fromCode(j['preferredMode'] as String?),
        hybridEnabled: asBool(j['hybridEnabled']),
      );
}
