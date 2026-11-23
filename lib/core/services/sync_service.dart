import '../database/aero_repository.dart';

/// Contrato de sincronización en la nube (preparado, desactivado por defecto).
///
/// La app es 100 % offline-first: todo se escribe primero en SQLite con
/// `synced = 0`. Para activar Firestore:
///  1. Descomenta `firebase_core` y `cloud_firestore` en pubspec.yaml y ejecuta
///     `flutterfire configure`.
///  2. Implementa [SyncService] y sustituye [NoopSyncService] en
///     `syncServiceProvider` (core/providers.dart).
///  3. Llama a `sync()` al detectar conectividad o desde un botón.
///
/// Los modelos ya exponen `toJson()` / `fromJson()` y las tablas llevan
/// `updatedAt` para resolver conflictos por "última escritura gana".
abstract class SyncService {
  /// Sube los registros pendientes y descarga cambios remotos.
  Future<void> sync();
}

/// Implementación por defecto: no hace nada (app 100 % local).
class NoopSyncService implements SyncService {
  const NoopSyncService(AeroRepository repository);

  @override
  Future<void> sync() async {}
}
