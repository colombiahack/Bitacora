import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extras_providers.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../hangar/domain/aircraft.dart';
import '../domain/models.dart';

/// Registro de incidentes y novedades de seguridad.
class IncidentsPage extends ConsumerWidget {
  const IncidentsPage({super.key});

  Future<void> _openForm(BuildContext context, List<Aircraft> aircraft,
      {Incident? incident}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _IncidentForm(aircraft: aircraft, incident: incident),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(incidentsProvider).valueOrNull ?? const <Incident>[];
    final aircraft = ref.watch(aircraftListProvider).valueOrNull ?? const <Aircraft>[];
    final byId = {for (final a in aircraft) a.id: a};

    return Scaffold(
      appBar: AppBar(title: const Text('Incidentes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, aircraft),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo incidente'),
      ),
      body: items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Sin incidentes registrados. Anota cualquier novedad de '
                  'seguridad para tener el historial.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final i in items)
                  Card(
                    child: ListTile(
                      isThreeLine: true,
                      leading: Icon(
                        Icons.report_problem_outlined,
                        color: i.severity == Severity.high
                            ? AlertColors.critical
                            : i.severity == Severity.medium
                                ? AlertColors.warning
                                : AlertColors.ok,
                      ),
                      title: Text(
                        '${kDateFmt.format(i.date)} · ${i.severity.label}'
                        '${i.aircraftId == null ? '' : ' · ${byId[i.aircraftId]?.name ?? 'Aeronave eliminada'}'}',
                      ),
                      subtitle: Text(
                        i.actionsTaken.isEmpty
                            ? i.description
                            : '${i.description}\nAcciones: ${i.actionsTaken}',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _openForm(context, aircraft, incident: i),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await confirmDialog(
                            context,
                            title: 'Eliminar incidente',
                            message: '¿Eliminar este registro?',
                          );
                          if (ok) {
                            await ref.read(extrasRepositoryProvider).deleteIncident(i.id);
                            ref.refreshData();
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _IncidentForm extends ConsumerStatefulWidget {
  const _IncidentForm({required this.aircraft, this.incident});
  final List<Aircraft> aircraft;
  final Incident? incident;

  @override
  ConsumerState<_IncidentForm> createState() => _IncidentFormState();
}

class _IncidentFormState extends ConsumerState<_IncidentForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _actions;
  late DateTime _date;
  String? _aircraftId;
  Severity _severity = Severity.low;

  @override
  void initState() {
    super.initState();
    final i = widget.incident;
    _description = TextEditingController(text: i?.description ?? '');
    _actions = TextEditingController(text: i?.actionsTaken ?? '');
    _date = i?.date ?? dateOnly(DateTime.now());
    _aircraftId = i?.aircraftId;
    _severity = i?.severity ?? Severity.low;
  }

  @override
  void dispose() {
    _description.dispose();
    _actions.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final incident = Incident(
      id: widget.incident?.id ?? newId(),
      date: _date,
      aircraftId: _aircraftId,
      severity: _severity,
      description: _description.text.trim(),
      actionsTaken: _actions.text.trim(),
    );
    await ref.read(extrasRepositoryProvider).saveIncident(incident);
    ref.refreshData();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.incident == null ? 'Nuevo incidente' : 'Editar incidente',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Fecha'),
                trailing: Text(kDateFmt.format(_date)),
                onTap: _pickDate,
              ),
              DropdownButtonFormField<String?>(
                value: _aircraftId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Aeronave (opcional)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Ninguna')),
                  for (final a in widget.aircraft)
                    DropdownMenuItem<String?>(value: a.id, child: Text(a.displayName)),
                ],
                onChanged: (v) => setState(() => _aircraftId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Severity>(
                value: _severity,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Gravedad'),
                items: [
                  for (final s in Severity.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _severity = v ?? Severity.low),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Qué ocurrió *', alignLabelWithHint: true),
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _actions,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Acciones tomadas', alignLabelWithHint: true),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
