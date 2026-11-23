import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/dashboard/domain/dashboard_stats.dart';
import '../features/tools/domain/models.dart';
import 'database/extras_repository.dart';
import 'providers.dart';
import 'utils/formatters.dart';

final extrasRepositoryProvider = Provider<ExtrasRepository>(
  (ref) => ExtrasRepository(ref.watch(repositoryProvider).db),
);

final maintenanceProvider = FutureProvider<List<MaintenanceTask>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(extrasRepositoryProvider).getMaintenance();
});

final documentsProvider = FutureProvider<List<DocumentItem>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(extrasRepositoryProvider).getDocuments();
});

final incidentsProvider = FutureProvider<List<Incident>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(extrasRepositoryProvider).getIncidents();
});

final checklistTemplatesProvider = FutureProvider<List<ChecklistTemplate>>((ref) async {
  ref.watch(dataVersionProvider);
  final repo = ref.watch(extrasRepositoryProvider);
  await repo.seedChecklistsIfEmpty();
  return repo.getChecklists();
});

final flightPhotosProvider =
    FutureProvider.family<List<String>, String>((ref, flightId) {
  ref.watch(dataVersionProvider);
  return ref.watch(extrasRepositoryProvider).getPhotoPaths(flightId);
});

/// Alertas adicionales del Dashboard: mantenimiento y documentos por vencer.
final extraAlertsProvider = FutureProvider<List<DashboardAlert>>((ref) async {
  final tasks = await ref.watch(maintenanceProvider.future);
  final docs = await ref.watch(documentsProvider.future);
  final aircraft = await ref.watch(aircraftListProvider.future);
  final byId = {for (final a in aircraft) a.id: a};
  final now = DateTime.now();
  final alerts = <DashboardAlert>[];

  for (final t in tasks) {
    final a = byId[t.aircraftId];
    if (a == null) continue;
    final st = t.statusFor(a.totalFlightMinutes, now);
    if (st.overdue) {
      alerts.add(DashboardAlert(
          AlertLevel.critical, 'Mantenimiento vencido: ${t.title}', '${a.name}. ${st.detail}.'));
    } else if (st.soon) {
      alerts.add(DashboardAlert(
          AlertLevel.warning, 'Mantenimiento próximo: ${t.title}', '${a.name}. ${st.detail}.'));
    }
  }

  for (final d in docs) {
    final left = d.daysLeft(now);
    if (left == null) continue;
    if (left < 0) {
      alerts.add(DashboardAlert(AlertLevel.critical, 'Documento vencido: ${d.title}',
          'Venció el ${kDateFmt.format(d.expiryDate!)}.'));
    } else if (left <= 30) {
      alerts.add(DashboardAlert(AlertLevel.warning, 'Documento por vencer: ${d.title}',
          'Vence el ${kDateFmt.format(d.expiryDate!)} (en $left días).'));
    }
  }
  return alerts;
});
