import 'dart:math';

/// Genera un identificador único sin dependencias externas
/// (timestamp en microsegundos + 6 bytes aleatorios). Válido para offline-first:
/// no requiere servidor y es seguro para sincronizar con Firestore.
String newId() {
  final random = Random.secure();
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final rnd = List.generate(
    6,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return '$ts-$rnd';
}
