import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extras_providers.dart';
import '../../../core/providers.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../domain/models.dart';

/// Plantillas de checklist editables (un punto por línea).
class ChecklistsPage extends ConsumerWidget {
  const ChecklistsPage({super.key});

  Future<void> _openForm(BuildContext context, {ChecklistTemplate? template}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _ChecklistForm(template: template),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates =
        ref.watch(checklistTemplatesProvider).valueOrNull ?? const <ChecklistTemplate>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Checklists')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Nueva plantilla'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Estas plantillas aparecen en la pantalla de registro de vuelo. '
              'Si hay varias para una categoría, podrás elegir cuál usar.',
            ),
          ),
          for (final t in templates)
            Card(
              child: ListTile(
                leading: const Icon(Icons.checklist_rtl),
                title: Text(t.name),
                subtitle: Text('${t.category.label} · ${t.items.length} puntos'),
                onTap: () => _openForm(context, template: t),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Eliminar plantilla',
                      message: '¿Eliminar "${t.name}"?',
                    );
                    if (ok) {
                      await ref.read(extrasRepositoryProvider).deleteChecklist(t.id);
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

class _ChecklistForm extends ConsumerStatefulWidget {
  const _ChecklistForm({this.template});
  final ChecklistTemplate? template;

  @override
  ConsumerState<_ChecklistForm> createState() => _ChecklistFormState();
}

class _ChecklistFormState extends ConsumerState<_ChecklistForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _items;
  AircraftCategory _category = AircraftCategory.uas;

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    _name = TextEditingController(text: t?.name ?? '');
    _items = TextEditingController(text: (t?.items ?? const <String>[]).join('\n'));
    _category = t?.category ?? AircraftCategory.uas;
  }

  @override
  void dispose() {
    _name.dispose();
    _items.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final items = _items.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (items.isEmpty) {
      showSnack(context, 'Agrega al menos un punto a la lista.');
      return;
    }
    await ref.read(extrasRepositoryProvider).saveChecklist(ChecklistTemplate(
          id: widget.template?.id ?? newId(),
          name: _name.text.trim(),
          category: _category,
          items: items,
        ));
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
              Text(widget.template == null ? 'Nueva plantilla' : 'Editar plantilla',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AircraftCategory>(
                value: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: [
                  for (final c in AircraftCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _category = v ?? AircraftCategory.uas),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _items,
                minLines: 6,
                maxLines: 12,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Puntos (uno por línea)',
                  alignLabelWithHint: true,
                ),
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
