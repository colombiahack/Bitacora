import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/errors/aero_exception.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../domain/aircraft.dart';

/// Listado y CRUD de aeronaves.
class AircraftTab extends ConsumerWidget {
  const AircraftTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(aircraftListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_aircraft',
        onPressed: () => showAircraftForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Aeronave'),
      ),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Tu hangar está vacío.\nAñade tu primer dron con el botón "Aeronave".',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: list.length,
            itemBuilder: (context, i) => _AircraftCard(aircraft: list[i]),
          );
        },
      ),
    );
  }
}

class _AircraftCard extends ConsumerWidget {
  const _AircraftCard({required this.aircraft});
  final Aircraft aircraft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inMaintenance = aircraft.status == AircraftStatus.maintenance;
    final subtitle = [
      if (aircraft.model.isNotEmpty) aircraft.model,
      if (aircraft.registrationCode.isNotEmpty) aircraft.registrationCode,
      if (aircraft.mtowKg > 0) 'MTOW ${aircraft.mtowKg} kg',
    ].join(' · ');

    return Card(
      child: ListTile(
        onTap: () => showAircraftForm(context, existing: aircraft),
        leading: Icon(
          aircraft.isUas ? Icons.flight : Icons.airplanemode_active,
          color: inMaintenance ? AlertColors.warning : null,
        ),
        title: Text(aircraft.name),
        subtitle: Text(
          '$subtitle\nTotal: ${fmtDuration(aircraft.totalFlightMinutes)}'
          '${inMaintenance ? '  ·  En mantenimiento' : ''}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'edit':
                await showAircraftForm(context, existing: aircraft);
              case 'status':
                await _toggleStatus(context, ref);
              case 'delete':
                await _delete(context, ref);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Editar')),
            PopupMenuItem(
              value: 'status',
              child: Text(inMaintenance ? 'Marcar como activa' : 'Enviar a mantenimiento'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleStatus(BuildContext context, WidgetRef ref) async {
    final next = aircraft.status == AircraftStatus.active
        ? AircraftStatus.maintenance
        : AircraftStatus.active;
    await ref.read(repositoryProvider).saveAircraft(Aircraft(
          id: aircraft.id,
          name: aircraft.name,
          model: aircraft.model,
          serialNumber: aircraft.serialNumber,
          registrationCode: aircraft.registrationCode,
          category: aircraft.category,
          mtowKg: aircraft.mtowKg,
          totalFlightMinutes: aircraft.totalFlightMinutes,
          status: next,
        ));
    ref.refreshData();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Eliminar aeronave',
      message: '¿Eliminar "${aircraft.name}"? Sus baterías quedarán sin aeronave asignada.',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteAircraft(aircraft.id);
      ref.refreshData();
    } on AeroException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }
}

Future<void> showAircraftForm(BuildContext context, {Aircraft? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _AircraftForm(existing: existing),
  );
}

class _AircraftForm extends ConsumerStatefulWidget {
  const _AircraftForm({this.existing});
  final Aircraft? existing;

  @override
  ConsumerState<_AircraftForm> createState() => _AircraftFormState();
}

class _AircraftFormState extends ConsumerState<_AircraftForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _model = TextEditingController(text: widget.existing?.model ?? '');
  late final _serial = TextEditingController(text: widget.existing?.serialNumber ?? '');
  late final _reg = TextEditingController(text: widget.existing?.registrationCode ?? '');
  late final _mtow = TextEditingController(
      text: (widget.existing?.mtowKg ?? 0) == 0 ? '' : '${widget.existing!.mtowKg}');
  late final _minutes = TextEditingController(
      text: '${widget.existing?.totalFlightMinutes ?? 0}');

  late AircraftCategory _category = widget.existing?.category ?? AircraftCategory.uas;
  late AircraftStatus _status = widget.existing?.status ?? AircraftStatus.active;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _model, _serial, _reg, _mtow, _minutes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveAircraft(Aircraft(
            id: widget.existing?.id ?? newId(),
            name: _name.text.trim(),
            model: _model.text.trim(),
            serialNumber: _serial.text.trim(),
            registrationCode: _reg.text.trim(),
            category: _category,
            mtowKg: parseDouble(_mtow.text) ?? 0,
            totalFlightMinutes: int.tryParse(_minutes.text.trim()) ?? 0,
            status: _status,
          ));
      ref.refreshData();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'No se pudo guardar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hybrid = ref.watch(pilotProvider).valueOrNull?.hybridEnabled ?? false;
    // "Tripulada" solo se ofrece en modo híbrido (o si la aeronave ya lo era).
    final categories = AircraftCategory.values
        .where((c) => c == AircraftCategory.uas || hybrid || c == _category)
        .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing == null ? 'Nueva aeronave' : 'Editar aeronave',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _model,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Modelo *'),
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _serial,
                      decoration: const InputDecoration(labelText: 'N.º de serie'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _reg,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Matrícula / registro'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AircraftCategory>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _mtow,
                      keyboardType: kDecimalKeyboard,
                      decoration: const InputDecoration(labelText: 'MTOW (kg)'),
                      validator: (v) => optionalNumberValidator(v, min: 0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Minutos acumulados',
                        helperText: 'Horas previas al uso de la app',
                      ),
                      validator: optionalIntValidator,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AircraftStatus>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: [
                  for (final s in AircraftStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
