import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../flights/domain/flight_log.dart';
import '../../hangar/domain/aircraft.dart';

/// Estadísticas con gráficos de barras (sin dependencias externas).
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  static const _months = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flights = ref.watch(allFlightsProvider).valueOrNull ?? const <FlightLog>[];
    final aircraft = ref.watch(aircraftListProvider).valueOrNull ?? const <Aircraft>[];
    final byId = {for (final a in aircraft) a.id: a};
    final real = flights.where((f) => !f.isSimulator).toList();

    // Últimos 12 meses (horas reales).
    final now = DateTime.now();
    final monthKeys = <DateTime>[];
    for (var i = 11; i >= 0; i--) {
      monthKeys.add(DateTime(now.year, now.month - i, 1));
    }
    final perMonth = <DateTime, int>{for (final m in monthKeys) m: 0};
    for (final f in real) {
      final key = DateTime(f.date.year, f.date.month, 1);
      if (perMonth.containsKey(key)) {
        perMonth[key] = perMonth[key]! + f.durationMinutes;
      }
    }

    final perAircraft = <String, int>{};
    final perOperation = <String, int>{};
    var totalMinutes = 0;
    for (final f in real) {
      totalMinutes += f.durationMinutes;
      final name = byId[f.aircraftId]?.name ?? 'Eliminada';
      perAircraft.update(name, (v) => v + f.durationMinutes,
          ifAbsent: () => f.durationMinutes);
      perOperation.update(f.operationType.label, (v) => v + 1, ifAbsent: () => 1);
    }
    final avg = real.isEmpty ? 0 : (totalMinutes / real.length).round();
    final longest =
        real.isEmpty ? 0 : real.map((f) => f.durationMinutes).reduce((a, b) => a > b ? a : b);

    final aircraftEntries = perAircraft.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final opEntries = perOperation.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('Estadísticas')),
      body: real.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Aún no hay vuelos reales para graficar.',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(child: _Kpi(label: 'Vuelos reales', value: '${real.length}')),
                    const SizedBox(width: 12),
                    Expanded(child: _Kpi(label: 'Duración media', value: fmtDuration(avg))),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _Kpi(label: 'Total horas', value: fmtDuration(totalMinutes))),
                    const SizedBox(width: 12),
                    Expanded(child: _Kpi(label: 'Vuelo más largo', value: fmtDuration(longest))),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Horas por mes (últimos 12)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _MonthlyBars(
                  labels: [for (final m in monthKeys) _months[m.month - 1]],
                  values: [for (final m in monthKeys) perMonth[m]!],
                ),
                const SizedBox(height: 24),
                Text('Horas por aeronave', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final e in aircraftEntries)
                  _HBar(
                    label: e.key,
                    value: e.value,
                    max: aircraftEntries.first.value,
                    text: fmtDuration(e.value),
                  ),
                const SizedBox(height: 24),
                Text('Vuelos por tipo de operación',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final e in opEntries)
                  _HBar(
                    label: e.key,
                    value: e.value,
                    max: opEntries.first.value,
                    text: '${e.value}',
                  ),
              ],
            ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Text(value,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _MonthlyBars extends StatelessWidget {
  const _MonthlyBars({required this.labels, required this.values});
  final List<String> labels;
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final maxV = values.fold<int>(0, (a, b) => a > b ? a : b);
    final color = Theme.of(context).colorScheme.primary;
    const barArea = 130.0;
    return SizedBox(
      height: barArea + 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      values[i] == 0 ? '' : (values[i] / 60).toStringAsFixed(1),
                      style: const TextStyle(fontSize: 9),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: maxV == 0 ? 2 : (values[i] / maxV) * barArea + 2,
                      decoration: BoxDecoration(
                        color: values[i] == 0 ? color.withOpacity(0.25) : color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(labels[i], style: const TextStyle(fontSize: 9)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HBar extends StatelessWidget {
  const _HBar({
    required this.label,
    required this.value,
    required this.max,
    required this.text,
  });

  final String label;
  final int value;
  final int max;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: max == 0 ? 0.0 : value / max,
              minHeight: 12,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(text, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
