import '../../../core/constants/enums.dart';

/// Separa vuelos reales de horas de simulador.
enum FlightKind {
  all('Todos'),
  real('Reales'),
  simulator('Simulador');

  const FlightKind(this.label);
  final String label;
}

/// Filtros del historial (inmutable). Los campos anulables en `copyWith`
/// reciben una función para poder distinguir "no cambiar" de "poner a null".
class FlightFilter {
  const FlightFilter({
    this.query = '',
    this.aircraftId,
    this.operationType,
    this.kind = FlightKind.all,
    this.from,
    this.to,
  });

  final String query;
  final String? aircraftId;
  final OperationType? operationType;
  final FlightKind kind;
  final DateTime? from;
  final DateTime? to;

  bool get hasAdvancedFilters =>
      aircraftId != null ||
      operationType != null ||
      from != null ||
      to != null;

  int get activeCount =>
      (aircraftId != null ? 1 : 0) +
      (operationType != null ? 1 : 0) +
      (from != null || to != null ? 1 : 0);

  FlightFilter copyWith({
    String? query,
    String? Function()? aircraftId,
    OperationType? Function()? operationType,
    FlightKind? kind,
    DateTime? Function()? from,
    DateTime? Function()? to,
  }) =>
      FlightFilter(
        query: query ?? this.query,
        aircraftId: aircraftId != null ? aircraftId() : this.aircraftId,
        operationType:
            operationType != null ? operationType() : this.operationType,
        kind: kind ?? this.kind,
        from: from != null ? from() : this.from,
        to: to != null ? to() : this.to,
      );
}
