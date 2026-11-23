import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/enums.dart';
import '../../../core/errors/aero_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../hangar/domain/aircraft.dart';
import '../domain/flight_filter.dart';
import '../domain/flight_log.dart';

/// Historial cronológico con búsqueda, filtros y exportación a PDF.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final _searchCtrl = TextEditingController();
  bool _exporting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportPdf() async {
    final flights = ref.read(filteredFlightsProvider).valueOrNull ?? const [];
    if (flights.isEmpty) {
      showSnack(context, 'No hay vuelos para exportar con los filtros actuales.');
      return;
    }
    setState(() => _exporting = true);
    try {
      final pilot = await ref.read(pilotProvider.future);
      final aircraft = await ref.read(aircraftListProvider.future);
      final bytes = await ref.read(pdfServiceProvider).buildLogbook(
            pilot: pilot,
            flights: flights,
            aircraft: aircraft,
            filter: ref.read(flightFilterProvider),
          );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'bitacora_vuelos_${kYmd.format(DateTime.now())}.pdf',
      );
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo generar el PDF: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const _FilterSheet(),
    );
  }

  Future<void> _delete(FlightLog flight) async {
    final ok = await confirmDialog(
      context,
      title: 'Eliminar vuelo',
      message: 'Se eliminará el vuelo del ${kDateFmt.format(flight.date)} y se '
          'restarán sus minutos y ciclos de batería. ¿Continuar?',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteFlight(flight.id);
      ref.refreshData();
    } on AeroException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(flightFilterProvider);
    final flightsAsync = ref.watch(filteredFlightsProvider);
    final aircraft = ref.watch(aircraftListProvider).valueOrNull ?? const <Aircraft>[];
    final aircraftById = {for (final a in aircraft) a.id: a};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        actions: [
          IconButton(
            tooltip: 'Filtros',
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: filter.hasAdvancedFilters,
              label: Text('${filter.activeCount}'),
              child: const Icon(Icons.filter_list),
            ),
          ),
          IconButton(
            tooltip: 'Exportar a PDF',
            onPressed: _exporting ? null : _exportPdf,
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: ref.read(flightFilterProvider.notifier).setQuery,
              decoration: InputDecoration(
                hintText: 'Buscar por lugar, aeronave, novedades...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: filter.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(flightFilterProvider.notifier).setQuery('');
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<FlightKind>(
                showSelectedIcon: false,
                segments: [
                  for (final k in FlightKind.values)
                    ButtonSegment(value: k, label: Text(k.label)),
                ],
                selected: {filter.kind},
                onSelectionChanged: (s) =>
                    ref.read(flightFilterProvider.notifier).setKind(s.first),
              ),
            ),
          ),
          Expanded(
            child: flightsAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (flights) {
                if (flights.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No hay vuelos que coincidan.\nRegistra uno desde la pestaña "Registro".',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final total = flights.fold<int>(0, (s, f) => s + f.durationMinutes);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Text('${flights.length} vuelo(s)',
                              style: Theme.of(context).textTheme.labelLarge),
                          const Spacer(),
                          Text('Total: ${fmtDuration(total)}',
                              style: Theme.of(context).textTheme.labelLarge),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: flights.length,
                        itemBuilder: (context, i) {
                          final f = flights[i];
                          return _FlightTile(
                            flight: f,
                            aircraft: aircraftById[f.aircraftId],
                            onTap: () => _showDetail(f, aircraftById[f.aircraftId]),
                            onDelete: () => _delete(f),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(FlightLog f, Aircraft? aircraft) {
    final batteries = ref.read(batteryListProvider).valueOrNull ?? const [];
    final codes = batteries
        .where((b) => f.batteryIds.contains(b.id))
        .map((b) => b.code)
        .join(', ');

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(label, style: Theme.of(context).textTheme.labelMedium),
              ),
              Expanded(child: Text(value.isEmpty ? '—' : value)),
            ],
          ),
        );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Vuelo del ${kDateFmt.format(f.date)}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row('Aeronave', aircraft?.displayName ?? 'Eliminada'),
              row('Operación', f.operationType.label),
              row('Despegue', kTimeFmt.format(f.takeoffTime)),
              row('Aterrizaje', kTimeFmt.format(f.landingTime)),
              row('Duración', fmtDuration(f.durationMinutes)),
              row('Baterías', codes),
              row('Lugar', f.locationName),
              row('Coordenadas',
                  f.hasCoordinates ? '${f.latitude!.toStringAsFixed(6)}, ${f.longitude!.toStringAsFixed(6)}' : ''),
              row('Alt. máx. AGL',
                  f.maxAltitudeAglMeters == null ? '' : '${f.maxAltitudeAglMeters!.toStringAsFixed(0)} m'),
              row('Clima', f.weatherSummary),
              row('Viento',
                  f.windSpeedKmh == null ? '' : '${f.windSpeedKmh!.toStringAsFixed(0)} km/h'),
              row('Checklist', f.preFlightChecklistPassed ? 'Completo' : 'Incompleto'),
              row('Novedades', f.remarks),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }
}

class _FlightTile extends StatelessWidget {
  const _FlightTile({
    required this.flight,
    required this.aircraft,
    required this.onTap,
    required this.onDelete,
  });

  final FlightLog flight;
  final Aircraft? aircraft;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sim = flight.isSimulator;
    final place = flight.locationName.isEmpty ? '' : ' · ${flight.locationName}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: sim
              ? theme.colorScheme.tertiaryContainer
              : theme.colorScheme.primaryContainer,
          child: Icon(
            sim ? Icons.computer : Icons.flight,
            color: sim
                ? theme.colorScheme.onTertiaryContainer
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          '${aircraft?.name ?? 'Aeronave eliminada'} · ${flight.operationType.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${kDateFmt.format(flight.date)} · '
          '${kTimeFmt.format(flight.takeoffTime)}-${kTimeFmt.format(flight.landingTime)}'
          '$place',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fmtHhMm(flight.durationMinutes),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Eliminar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja de filtros avanzados (aeronave, tipo de operación y rango de fechas).
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(flightFilterProvider);
    final notifier = ref.read(flightFilterProvider.notifier);
    final aircraft = ref.watch(aircraftListProvider).valueOrNull ?? const <Aircraft>[];

    final rangeText = (filter.from == null && filter.to == null)
        ? 'Todas las fechas'
        : '${filter.from == null ? '…' : kDateFmt.format(filter.from!)}  →  '
            '${filter.to == null ? '…' : kDateFmt.format(filter.to!)}';

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filtros', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              value: filter.aircraftId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Aeronave'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                for (final a in aircraft)
                  DropdownMenuItem<String?>(value: a.id, child: Text(a.displayName)),
              ],
              onChanged: notifier.setAircraft,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<OperationType?>(
              value: filter.operationType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo de operación'),
              items: [
                const DropdownMenuItem<OperationType?>(value: null, child: Text('Todos')),
                for (final o in OperationType.values)
                  DropdownMenuItem<OperationType?>(value: o, child: Text(o.label)),
              ],
              onChanged: notifier.setOperation,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(rangeText),
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDateRange: (filter.from != null && filter.to != null)
                      ? DateTimeRange(start: filter.from!, end: filter.to!)
                      : null,
                );
                if (range != null) notifier.setRange(range.start, range.end);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: notifier.clearAdvanced,
                  child: const Text('Limpiar filtros'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Listo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
