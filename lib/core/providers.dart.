import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/dashboard/domain/dashboard_stats.dart';
import '../features/flights/domain/flight_filter.dart';
import '../features/flights/domain/flight_log.dart';
import '../features/hangar/domain/aircraft.dart';
import '../features/hangar/domain/battery.dart';
import '../features/pilot/domain/pilot_profile.dart';
import 'constants/enums.dart';
import 'database/aero_repository.dart';
import 'services/pdf_service.dart';
import 'services/sync_service.dart';

/// Repositorio: se inyecta en `main()` con la base de datos ya abierta.
final repositoryProvider = Provider<AeroRepository>(
  (ref) => throw UnimplementedError('repositoryProvider debe sobrescribirse en main()'),
);

/// Sincronización en la nube (no-op hasta que se implemente Firestore).
final syncServiceProvider = Provider<SyncService>(
  (ref) => NoopSyncService(ref.watch(repositoryProvider)),
);

final pdfServiceProvider = Provider<PdfService>((ref) => PdfService());

/// Contador que se incrementa tras cada escritura; todos los providers de
/// datos lo observan y se recargan solos.
final dataVersionProvider = StateProvider<int>((ref) => 0);

extension DataRefresh on WidgetRef {
  /// Llamar después de cualquier alta / edición / baja.
  void refreshData() => read(dataVersionProvider.notifier).state++;
}

/// Pestaña activa de la navegación inferior (0 Inicio, 1 Registro, 2 Historial, 3 Hangar).
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// Tema claro / oscuro / sistema.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

// ------------------------------------------------------------------ Datos

final pilotProvider = FutureProvider<PilotProfile>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).getPilot();
});

final aircraftListProvider = FutureProvider<List<Aircraft>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).getAircraft();
});

final batteryListProvider = FutureProvider<List<Battery>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).getBatteries();
});

final allFlightsProvider = FutureProvider<List<FlightLog>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).getFlights();
});

// ---------------------------------------------------------------- Historial

class FlightFilterNotifier extends Notifier<FlightFilter> {
  @override
  FlightFilter build() => const FlightFilter();

  void setQuery(String query) => state = state.copyWith(query: query);
  void setKind(FlightKind kind) => state = state.copyWith(kind: kind);
  void setAircraft(String? id) => state = state.copyWith(aircraftId: () => id);
  void setOperation(OperationType? type) =>
      state = state.copyWith(operationType: () => type);
  void setRange(DateTime? from, DateTime? to) =>
      state = state.copyWith(from: () => from, to: () => to);

  /// Limpia filtros avanzados y tipo; conserva el texto de búsqueda.
  void clearAdvanced() => state = FlightFilter(query: state.query);
}

final flightFilterProvider =
    NotifierProvider<FlightFilterNotifier, FlightFilter>(FlightFilterNotifier.new);

final filteredFlightsProvider = FutureProvider<List<FlightLog>>((ref) {
  ref.watch(dataVersionProvider);
  final filter = ref.watch(flightFilterProvider);
  return ref.watch(repositoryProvider).getFlights(filter);
});

// ---------------------------------------------------------------- Dashboard

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final flights = await ref.watch(allFlightsProvider.future);
  final aircraft = await ref.watch(aircraftListProvider.future);
  final batteries = await ref.watch(batteryListProvider.future);
  final pilot = await ref.watch(pilotProvider.future);
  return DashboardStats.compute(
    flights: flights,
    aircraft: aircraft,
    batteries: batteries,
    pilot: pilot,
    now: DateTime.now(),
  );
});
