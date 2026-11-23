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
import '../domain/battery.dart';

/// Listado y CRUD de baterías (solo UAS).
class BatteryTab extends ConsumerWidget {
  const BatteryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(batteryListProvider);
    final aircraft = ref.watch(aircraftListProvider).valueOrNull ?? const <Aircraft>[];
    final aircraftById = {for (final a in aircraft) a.id: a};
    final uasAircraft = aircraft.where((a) => a.isUas).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_battery',
        onPressed: () {
          if (uasAircraft.isEmpty) {
            showSnack(context, 'Primero registra un dron para vincular la batería.');
            return;
          }
          showBatteryForm(context, uasAircraft: uasAircraft);
        },
        icon: const Icon(Icons.add),
        label: const Text('Batería'),
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
                  'Sin baterías registradas.\nVincula cada batería a su dron para llevar sus ciclos.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final b = list[i];
              final color = b.isCritical
                  ? AlertColors.critical
                  : b.isWarning
                      ? AlertColors.warning
                      : AlertColors.ok;
              return Card(
                child: ListTile(
                  onTap: () =>
                      showBatteryForm(context, uasAircraft: uasAircraft, existing: b),
                  leading: Icon(Icons.battery_charging_full, color: color),
                  title: Text(b.code),
                  subtitle: Text(
                    '${aircraftById[b.aircraftId]?.name ?? 'Sin aeronave'} · '
                    '${b.cycleCount} ciclos · ${b.healthStatus.label}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Eliminar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(context, ref, b),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Battery b) async {
    final ok = await confirmDialog(
      context,
      title: 'Eliminar batería',
      message: '¿Eliminar la batería ${b.code}? Se quitará de los vuelos donde se usó.',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteBattery(b.id);
      ref.refreshData();
    } on AeroException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }
}

Future<void> showBatteryForm(
  BuildContext context, {
  required List<Aircraft> uasAircraft,
  Battery? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _BatteryForm(uasAircraft: uasAircraft, existing: existing),
  );
}

class _BatteryForm extends ConsumerStatefulWidget {
  const _BatteryForm({required this.uasAircraft, this.existing});
  final List<Aircraft> uasAircraft;
  final Battery? existing;

  @override
  ConsumerState<_BatteryForm> createState() => _BatteryFormState();
}

class _BatteryFormState extends ConsumerState<_BatteryForm> {
  final _key = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late final _cycles =
      TextEditingController(text: '${widget.existing?.cycleCount ?? 0}');

  late String? _aircraftId = widget.uasAircraft.any((a) => a.id == widget.existing?.aircraftId)
      ? widget.existing?.aircraftId
      : (widget.uasAircraft.length == 1 ? widget.uasAircraft.first.id : null);
  late BatteryHealth _health = widget.existing?.healthStatus ?? BatteryHealth.good;
  late DateTime? _purchase = widget.existing?.purchaseDate;
  bool _saving = false;

  @override
  void dispose() {
    _code.dispose();
    _cycles.dispose();
    super.dispose();
  }

  Future<void> _pickPurchaseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchase ?? DateTime.now(),
      firstDate: DateTime(2010),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _purchase = picked);
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveBattery(Battery(
            id: widget.existing?.id ?? newId(),
            code: _code.text.trim().toUpperCase(),
            aircraftId: _aircraftId,
            cycleCount: int.tryParse(_cycles.text.trim()) ?? 0,
            healthStatus: _health,
            purchaseDate: _purchase,
          ));
      ref.refreshData();
      if (mounted) Navigator.pop(context);
    } on AeroException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'No se pudo guardar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing == null ? 'Nueva batería' : 'Editar batería',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Código *',
                  hintText: 'BAT-01',
                ),
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _aircraftId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Aeronave vinculada *'),
                items: [
                  for (final a in widget.uasAircraft)
                    DropdownMenuItem(value: a.id, child: Text(a.displayName)),
                ],
                validator: (v) => v == null ? 'Selecciona una aeronave' : null,
                onChanged: (v) => setState(() => _aircraftId = v),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cycles,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Ciclos'),
                      validator: optionalIntValidator,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<BatteryHealth>(
                      value: _health,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Salud'),
                      items: [
                        for (final h in BatteryHealth.values)
                          DropdownMenuItem(value: h, child: Text(h.label)),
                      ],
                      onChanged: (v) => setState(() => _health = v ?? _health),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shopping_bag_outlined),
                title: const Text('Fecha de compra'),
                trailing: Text(_purchase == null ? 'Elegir' : kDateFmt.format(_purchase!)),
                onTap: _pickPurchaseDate,
              ),
              const SizedBox(height: 12),
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
