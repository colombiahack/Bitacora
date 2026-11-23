import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../domain/dashboard_stats.dart';

/// Pantalla de inicio: tarjetas de resumen, alertas y FAB "+ Nuevo Vuelo".
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final pilot = ref.watch(pilotProvider).valueOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bitácora de vuelos'),
        actions: [
          IconButton(
            tooltip: isDark ? 'Modo claro' : 'Modo oscuro',
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => ref.read(themeModeProvider.notifier).state =
                isDark ? ThemeMode.light : ThemeMode.dark,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ref.read(tabIndexProvider.notifier).state = 1,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Vuelo'),
      ),
      body: statsAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error al cargar datos: $e')),
        data: (stats) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (pilot != null && pilot.fullName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Hola, ${pilot.fullName.split(' ').first}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            _SummaryGrid(stats: stats),
            const SizedBox(height: 20),
            Text('Alertas', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (stats.alerts.isEmpty)
              const _AlertTile(
                alert: DashboardAlert(
                  AlertLevel.warning,
                  'Todo en orden',
                  'No hay baterías, certificados ni equipos que requieran atención.',
                ),
                ok: true,
              )
            else
              for (final alert in stats.alerts) _AlertTile(alert: alert),
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.stats});
  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final top = stats.topAircraft;
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.flight,
                  label: 'Horas reales',
                  value: fmtDuration(stats.realMinutes),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.sports_esports_outlined,
                  label: 'Horas simulador',
                  value: fmtDuration(stats.simulatorMinutes),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.calendar_month_outlined,
                  label: 'Vuelos del mes',
                  value: '${stats.flightsThisMonth}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.emoji_events_outlined,
                  label: 'Más usada',
                  value: top?.name ?? '—',
                  caption: top == null ? 'Sin vuelos aún' : '${stats.topAircraftFlights} vuelos',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: theme.textTheme.labelMedium,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (caption != null)
              Text(caption!, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, this.ok = false});
  final DashboardAlert alert;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok
        ? AlertColors.ok
        : alert.level == AlertLevel.critical
            ? AlertColors.critical
            : AlertColors.warning;
    final icon = ok
        ? Icons.check_circle_outline
        : alert.level == AlertLevel.critical
            ? Icons.error_outline
            : Icons.warning_amber_rounded;

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(alert.title),
        subtitle: Text(alert.detail),
      ),
    );
  }
}
