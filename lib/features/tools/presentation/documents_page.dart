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

/// Documentos con vencimiento: seguros, registros, licencias y permisos.
class DocumentsPage extends ConsumerWidget {
  const DocumentsPage({super.key});

  Future<void> _openForm(BuildContext context, List<Aircraft> aircraft,
      {DocumentItem? doc}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _DocForm(aircraft: aircraft, doc: doc),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider).valueOrNull ?? const <DocumentItem>[];
    final aircraft = ref.watch(aircraftListProvider).valueOrNull ?? const <Aircraft>[];
    final byId = {for (final a in aircraft) a.id: a};
    final now = DateTime.now();

    final sorted = [...docs]..sort((a, b) {
        final da = a.expiryDate;
        final db = b.expiryDate;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Documentos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, aircraft),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo documento'),
      ),
      body: sorted.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Registra tu seguro, licencia o permisos para recibir '
                  'avisos antes de que venzan.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final d in sorted)
                  Builder(builder: (context) {
                    final left = d.daysLeft(now);
                    final color = left == null
                        ? null
                        : left < 0
                            ? AlertColors.critical
                            : left <= 30
                                ? AlertColors.warning
                                : AlertColors.ok;
                    final owner = d.aircraftId == null
                        ? 'Personal'
                        : (byId[d.aircraftId]?.displayName ?? 'Aeronave eliminada');
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.description_outlined, color: color),
                        title: Text(d.title),
                        subtitle: Text([
                          d.kind.label,
                          owner,
                          if (d.number.isNotEmpty) 'N.º ${d.number}',
                          left == null
                              ? 'Sin vencimiento'
                              : left < 0
                                  ? 'Venció el ${kDateFmt.format(d.expiryDate!)}'
                                  : 'Vence el ${kDateFmt.format(d.expiryDate!)} ($left días)',
                        ].join(' · ')),
                        onTap: () => _openForm(context, aircraft, doc: d),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await confirmDialog(
                              context,
                              title: 'Eliminar documento',
                              message: '¿Eliminar "${d.title}"?',
                            );
                            if (ok) {
                              await ref.read(extrasRepositoryProvider).deleteDocument(d.id);
                              ref.refreshData();
                            }
                          },
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class _DocForm extends ConsumerStatefulWidget {
  const _DocForm({required this.aircraft, this.doc});
  final List<Aircraft> aircraft;
  final DocumentItem? doc;

  @override
  ConsumerState<_DocForm> createState() => _DocFormState();
}

class _DocFormState extends ConsumerState<_DocForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _number;
  late final TextEditingController _notes;
  DocumentKind _kind = DocumentKind.insurance;
  String? _aircraftId;
  DateTime? _expiry;

  @override
  void initState() {
    super.initState();
    final d = widget.doc;
    _title = TextEditingController(text: d?.title ?? '');
    _number = TextEditingController(text: d?.number ?? '');
    _notes = TextEditingController(text: d?.notes ?? '');
    _kind = d?.kind ?? DocumentKind.insurance;
    _aircraftId = d?.aircraftId;
    _expiry = d?.expiryDate;
  }

  @override
  void dispose() {
    _title.dispose();
    _number.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _expiry = dateOnly(picked));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final doc = DocumentItem(
      id: widget.doc?.id ?? newId(),
      aircraftId: _aircraftId,
      kind: _kind,
      title: _title.text.trim(),
      number: _number.text.trim(),
      expiryDate: _expiry,
      notes: _notes.text.trim(),
    );
    await ref.read(extrasRepositoryProvider).saveDocument(doc);
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
              Text(widget.doc == null ? 'Nuevo documento' : 'Editar documento',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<DocumentKind>(
                value: _kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final k in DocumentKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (v) => setState(() => _kind = v ?? DocumentKind.other),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _number,
                decoration: const InputDecoration(labelText: 'Número / póliza'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: _aircraftId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Pertenece a'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Personal / general')),
                  for (final a in widget.aircraft)
                    DropdownMenuItem<String?>(value: a.id, child: Text(a.displayName)),
                ],
                onChanged: (v) => setState(() => _aircraftId = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Vencimiento'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_expiry == null ? 'Sin fecha' : kDateFmt.format(_expiry!)),
                    if (_expiry != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _expiry = null),
                      ),
                  ],
                ),
                onTap: _pickExpiry,
              ),
              TextFormField(
                controller: _notes,
                maxLines: 2,
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
