import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extras_providers.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../hangar/domain/aircraft.dart';
import '../domain/models.dart';

/// Mantenimiento programado por aeronave (por horas de vuelo o por días).
class MaintenancePage extends ConsumerWidget {
  const MaintenancePage({super.key});

  Future<void> _openForm(BuildContext context, List<Aircraft> aircraft,
      {MaintenanceTask? task}) async {
    if (aircraft.isEmpty) {
      showSnack(context, 'Primero registra una aeronave en el Hangar.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _TaskForm(aircraft: aircraft, task: task),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(maintenanceProvider).valueOrNull ?? const <MaintenanceTask>[];
    final aircraft = ref.watch(aircraftListProvider).valueOrNull ?? const <Aircraft>[];
    final byId = {for (final a in aircraft) a.id: a};
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Mantenimiento')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, aircraft),
        icon: const Icon(Icons.add),
        label: const Text('Nueva tarea'),
      ),
      body: tasks.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aún no hay tareas de mantenimiento.\n'
                  'Crea una, por ejemplo "Cambio de hélices cada 50 h".',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final t in tasks)
                  Builder(builder: (context) {
                    final a = byId[t.aircraftId];
                    final st = t.statusFor(a?.totalFlightMinutes ?? 0, now);
                    final color = st.overdue
                        ? AlertColors.critical
                        : st.soon
                            ? AlertColors.warning
                            : AlertColors.ok;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(t.title,
                                      style: Theme.of(context).textTheme.titleMedium),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    final repo = ref.read(extrasRepositoryProvider);
                                    if (v == 'done') {
                                      await repo.saveMaintenance(
                                          t.markDone(a?.totalFlightMinutes ?? 0));
                                      ref.refreshData();
                                    } else if (v == 'edit') {
                                      await _openForm(context, aircraft, task: t);
                                    } else if (v == 'delete') {
                                      final ok = await confirmDialog(
                                        context,
                                        title: 'Eliminar tarea',
                                        message: '¿Eliminar "${t.title}"?',
                                      );
                                      if (ok) {
                                        await repo.deleteMaintenance(t.id);
                                        ref.refreshData();
                                      }
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'done', child: Text('Marcar como realizado')),
                                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                                  ],
                                ),
                              ],
                            ),
                            Text(
                              '${a?.displayName ?? 'Aeronave eliminada'} · cada '
                              '${t.intervalValue} ${t.intervalType == IntervalType.hours ? 'h de vuelo' : 'días'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: LinearProgressIndicator(
                                value: st.progress.clamp(0.0, 1.0).toDouble(),
                                color: color,
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(st.detail, style: TextStyle(color: color)),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class _TaskForm extends ConsumerStatefulWidget {
  const _TaskForm({required this.aircraft, this.task});
  final List<Aircraft> aircraft;
  final MaintenanceTask? task;

  @override
  ConsumerState<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends ConsumerState<_TaskForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _value;
  late final TextEditingController _notes;
  String? _aircraftId;
  IntervalType _type = IntervalType.hours;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _value = TextEditingController(text: '${t?.intervalValue ?? 25}');
    _notes = TextEditingController(text: t?.notes ?? '');
    _aircraftId = t?.aircraftId ??
        (widget.aircraft.length == 1 ? widget.aircraft.first.id : null);
    _type = t?.intervalType ?? IntervalType.hours;
  }

  @override
  void dispose() {
    _title.dispose();
    _value.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final aircraft = widget.aircraft.firstWhere((a) => a.id == _aircraftId);
    final old = widget.task;
    final task = MaintenanceTask(
      id: old?.id ?? newId(),
      aircraftId: aircraft.id,
      title: _title.text.trim(),
      intervalType: _type,
      intervalValue: int.parse(_value.text.trim()),
      // Una tarea nueva empieza a contar desde hoy y desde las horas actuales.
      lastDoneDate: old?.lastDoneDate ?? dateOnly(DateTime.now()),
      lastDoneMinutes: old?.lastDoneMinutes ?? aircraft.totalFlightMinutes,
      notes: _notes.text.trim(),
    );
    await ref.read(extrasRepositoryProvider).saveMaintenance(task);
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
              Text(widget.task == null ? 'Nueva tarea' : 'Editar tarea',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _aircraftId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Aeronave *'),
                items: [
                  for (final a in widget.aircraft)
                    DropdownMenuItem(value: a.id, child: Text(a.displayName)),
                ],
                validator: (v) => v == null ? 'Selecciona una aeronave' : null,
                onChanged: (v) => setState(() => _aircraftId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Tarea *', hintText: 'Ej.: Cambio de hélices'),
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _value,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cada *'),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return (n == null || n <= 0) ? 'Número > 0' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<IntervalType>(
                      value: _type,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Unidad'),
                      items: [
                        for (final t in IntervalType.values)
                          DropdownMenuItem(value: t, child: Text(t.label)),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? IntervalType.hours),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Notas'),
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
