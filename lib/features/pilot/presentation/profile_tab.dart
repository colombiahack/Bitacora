import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../domain/pilot_profile.dart';

/// Datos del piloto, selector de modo (Solo UAS / Híbrido) y apariencia.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pilotProvider);
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (pilot) => _ProfileForm(key: ValueKey(pilot.id), pilot: pilot),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({super.key, required this.pilot});
  final PilotProfile pilot;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.pilot.fullName);
  late final _doc = TextEditingController(text: widget.pilot.documentId);
  late final _license = TextEditingController(text: widget.pilot.licenseNumber);

  late DateTime? _medical = widget.pilot.medicalCertExpiry;
  late bool _hybrid = widget.pilot.hybridEnabled;
  late PilotMode _preferred = widget.pilot.preferredMode;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _doc.dispose();
    _license.dispose();
    super.dispose();
  }

  Future<void> _pickMedical() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _medical ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) setState(() => _medical = picked);
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).savePilot(PilotProfile(
            id: widget.pilot.id,
            fullName: _name.text.trim(),
            documentId: _doc.text.trim(),
            licenseNumber: _license.text.trim(),
            medicalCertExpiry: _medical,
            // En modo "Solo UAS" el modo preferido siempre es UAS.
            preferredMode: _hybrid ? _preferred : PilotMode.uas,
            hybridEnabled: _hybrid,
          ));
      ref.refreshData();
      if (mounted) showSnack(context, 'Perfil guardado');
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return Form(
      key: _key,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre completo *',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: requiredValidator,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _doc,
            decoration: const InputDecoration(
              labelText: 'Documento de identidad',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _license,
            decoration: const InputDecoration(
              labelText: 'N.º de licencia / certificado',
              helperText: 'Ej.: certificado UAS RAC 100',
              prefixIcon: Icon(Icons.verified_outlined),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            leading: const Icon(Icons.medical_services_outlined),
            title: const Text('Vencimiento certificado médico'),
            subtitle: Text(_medical == null ? 'Sin definir' : kDateFmt.format(_medical!)),
            trailing: _medical == null
                ? null
                : IconButton(
                    tooltip: 'Quitar fecha',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _medical = null),
                  ),
            onTap: _pickMedical,
          ),
          const SizedBox(height: 24),
          Text('Modo de operación', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Solo UAS')),
                ButtonSegment(value: true, label: Text('Híbrido UAS + Tripulado')),
              ],
              selected: {_hybrid},
              onSelectionChanged: (s) => setState(() => _hybrid = s.first),
            ),
          ),
          if (_hybrid) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<PilotMode>(
              value: _preferred,
              decoration: const InputDecoration(labelText: 'Modo preferido'),
              items: [
                for (final m in PilotMode.values)
                  DropdownMenuItem(value: m, child: Text(m.label)),
              ],
              onChanged: (v) => setState(() => _preferred = v ?? _preferred),
            ),
          ],
          const SizedBox(height: 24),
          Text('Apariencia', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto),
                    label: Text('Sistema')),
                ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode),
                    label: Text('Claro')),
                ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode),
                    label: Text('Oscuro')),
              ],
              selected: {themeMode},
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).state = s.first,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar perfil'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}
