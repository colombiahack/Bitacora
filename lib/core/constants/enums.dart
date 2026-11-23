/// Enumeraciones del dominio. Cada una guarda un `code` estable (el que se
/// persiste en SQLite / JSON) y una `label` legible en español para la UI.

/// Categoría de aeronave: dron (UAS) o aviación tripulada.
enum AircraftCategory {
  uas('UAS', 'UAS / Dron'),
  manned('MANNED', 'Tripulada');

  const AircraftCategory(this.code, this.label);
  final String code;
  final String label;

  static AircraftCategory fromCode(String? code) => AircraftCategory.values
      .firstWhere((e) => e.code == code, orElse: () => AircraftCategory.uas);
}

/// Estado operativo de la aeronave.
enum AircraftStatus {
  active('ACTIVE', 'Activa'),
  maintenance('MAINTENANCE', 'En mantenimiento');

  const AircraftStatus(this.code, this.label);
  final String code;
  final String label;

  static AircraftStatus fromCode(String? code) => AircraftStatus.values
      .firstWhere((e) => e.code == code, orElse: () => AircraftStatus.active);
}

/// Modo preferido del piloto.
enum PilotMode {
  uas('UAS', 'UAS'),
  manned('MANNED', 'Tripulado');

  const PilotMode(this.code, this.label);
  final String code;
  final String label;

  static PilotMode fromCode(String? code) => PilotMode.values
      .firstWhere((e) => e.code == code, orElse: () => PilotMode.uas);
}

/// Estado de salud de una batería.
enum BatteryHealth {
  good('GOOD', 'Buena'),
  fair('FAIR', 'Regular'),
  poor('POOR', 'Deficiente');

  const BatteryHealth(this.code, this.label);
  final String code;
  final String label;

  static BatteryHealth fromCode(String? code) => BatteryHealth.values
      .firstWhere((e) => e.code == code, orElse: () => BatteryHealth.good);
}

/// Tipo de operación del vuelo.
enum OperationType {
  vlos('VLOS', 'VLOS (a la vista)'),
  bvlos('BVLOS', 'BVLOS (más allá de la vista)'),
  simulator('SIMULATOR', 'Simulador'),
  training('TRAINING', 'Entrenamiento'),
  inspection('INSPECTION', 'Inspección'),
  photogrammetry('PHOTOGRAMMETRY', 'Fotogrametría'),
  vfr('VFR', 'VFR'),
  ifr('IFR', 'IFR');

  const OperationType(this.code, this.label);
  final String code;
  final String label;

  /// Las horas de simulador NO suman a la aeronave ni a los ciclos de batería.
  bool get isSimulator => this == OperationType.simulator;

  static OperationType fromCode(String? code) => OperationType.values
      .firstWhere((e) => e.code == code, orElse: () => OperationType.vlos);

  /// Tipos de operación válidos según la categoría de la aeronave.
  static List<OperationType> forCategory(AircraftCategory category) =>
      category == AircraftCategory.uas
          ? const [
              OperationType.vlos,
              OperationType.bvlos,
              OperationType.inspection,
              OperationType.photogrammetry,
              OperationType.training,
              OperationType.simulator,
            ]
          : const [
              OperationType.vfr,
              OperationType.ifr,
              OperationType.training,
              OperationType.simulator,
            ];
}
