import 'package:flutter/material.dart';

import '../../../core/services/update_service.dart';
import '../../../core/widgets/ui_helpers.dart';

/// Busca actualizaciones y guía al usuario: aviso, descarga e instalación.
/// Con [silent] = true (arranque de la app) no muestra nada si no hay novedades
/// ni si falla la conexión.
Future<void> checkForUpdates(BuildContext context, {bool silent = false}) async {
  final service = UpdateService();
  final UpdateInfo? info;
  try {
    info = await service.check();
  } catch (e) {
    if (!silent && context.mounted) {
      showSnack(context, 'No se pudo buscar actualizaciones. Revisa tu internet.');
    }
    return;
  }
  if (!context.mounted) return;
  if (info == null) {
    if (!silent) showSnack(context, 'Ya tienes la última versión.');
    return;
  }

  final mb = info.sizeBytes > 0 ? ' (${(info.sizeBytes / 1048576).toStringAsFixed(1)} MB)' : '';
  final notes = info.notes.trim().isEmpty ? 'Mejoras y correcciones.' : info.notes.trim();
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.system_update),
      title: const Text('Actualización disponible'),
      content: Text('Hay una versión nueva de la app$mb.\n\n$notes'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Más tarde'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Descargar'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  final progress = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Descargando actualización'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, v, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: v == 0 ? null : v),
            const SizedBox(height: 8),
            Text('${(v * 100).toStringAsFixed(0)} %'),
          ],
        ),
      ),
    ),
  );

  final String path;
  try {
    path = await service.download(info, (v) => progress.value = v);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showSnack(context, 'No se pudo descargar: $e');
    }
    return;
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  final install = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.download_done),
      title: const Text('Descarga completa'),
      content: const Text(
          'Toca Instalar. Si Android lo pide, permite instalar apps desde Bitácora de vuelos.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Instalar'),
        ),
      ],
    ),
  );
  if (install != true) return;
  try {
    await service.install(path);
  } catch (e) {
    if (context.mounted) showSnack(context, 'No se pudo abrir el instalador: $e');
  }
}
