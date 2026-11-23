import 'package:flutter/material.dart';

import '../utils/formatters.dart';

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Eliminar',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

// --------------------------------------------------------------- Validadores

String? requiredValidator(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

/// Número opcional (vacío es válido), con coma o punto decimal.
String? optionalNumberValidator(String? v, {double? min, double? max}) {
  if (v == null || v.trim().isEmpty) return null;
  final n = parseDouble(v);
  if (n == null) return 'Número inválido';
  if (min != null && n < min) return 'Mínimo $min';
  if (max != null && n > max) return 'Máximo $max';
  return null;
}

String? optionalIntValidator(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  final n = int.tryParse(v.trim());
  if (n == null || n < 0) return 'Entero ≥ 0';
  return null;
}

/// Teclado numérico con decimales.
const TextInputType kDecimalKeyboard =
    TextInputType.numberWithOptions(decimal: true, signed: true);
