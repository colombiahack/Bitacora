

########## ARCHIVO: lib/app.dart ##########
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/home_shell.dart';

class BitacoraApp extends ConsumerWidget {
  const BitacoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Bitácora de vuelos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeShell(),
    );
  }
}


########## ARCHIVO: lib/core/constants/app_constants.dart ##########
/// Umbrales de alertas del dashboard.

/// Ciclos a partir de los cuales una batería muestra advertencia.
const int kBatteryWarningCycles = 200;

/// Ciclos a partir de los cuales una batería muestra alerta crítica.
const int kBatteryCriticalCycles = 300;

/// Días de antelación para avisar del vencimiento del certificado médico.
const int kMedicalWarningDays = 30;


########## ARCHIVO: lib/core/constants/enums.dart ##########
/// Enumeraciones del dominio. Cada una guarda un `code` estable (el que se
/// persiste en SQLite / JSON) y una `label` legible en español para la UI.

/// Categoría de aeronave: dron (UAS) o aviación tripulada.
enum AircraftCategory {
  uas('UAS', 'UAS / Dron'),
  manned('MANNED', 'Tripulada');

  const AircraftCategory(this.code, this.label);
  final String code;
  final String label;

  static AircraftCategory fromCode(String? code) => AircraftCategory.values
      .firstWhere((e) => e.code == code, orElse: () => AircraftCategory.uas);
}

/// Estado operativo de la aeronave.
enum AircraftStatus {
  active('ACTIVE', 'Activa'),
  maintenance('MAINTENANCE', 'En mantenimiento');

  const AircraftStatus(this.code, this.label);
  final String code;
  final String label;

  static AircraftStatus fromCode(String? code) => AircraftStatus.values
      .firstWhere((e) => e.code == code, orElse: () => AircraftStatus.active);
}

/// Modo preferido del piloto.
enum PilotMode {
  uas('UAS', 'UAS'),
  manned('MANNED', 'Tripulado');

  const PilotMode(this.code, this.label);
  final String code;
  final String label;

  static PilotMode fromCode(String? code) => PilotMode.values
      .firstWhere((e) => e.code == code, orElse: () => PilotMode.uas);
}

/// Estado de salud de una batería.
enum BatteryHealth {
  good('GOOD', 'Buena'),
  fair('FAIR', 'Regular'),
  poor('POOR', 'Deficiente');

  const BatteryHealth(this.code, this.label);
  final String code;
  final String label;

  static BatteryHealth fromCode(String? code) => BatteryHealth.values
      .firstWhere((e) => e.code == code, orElse: () => BatteryHealth.good);
}

/// Tipo de operación del vuelo.
enum OperationType {
  vlos('VLOS', 'VLOS (a la vista)'),
  bvlos('BVLOS', 'BVLOS (más allá de la vista)'),
  simulator('SIMULATOR', 'Simulador'),
  training('TRAINING', 'Entrenamiento'),
  inspection('INSPECTION', 'Inspección'),
  photogrammetry('PHOTOGRAMMETRY', 'Fotogrametría'),
  vfr('VFR', 'VFR'),
  ifr('IFR', 'IFR');

  const OperationType(this.code, this.label);
  final String code;
  final String label;

  /// Las horas de simulador NO suman a la aeronave ni a los ciclos de batería.
  bool get isSimulator => this == OperationType.simulator;

  static OperationType fromCode(String? code) => OperationType.values
      .firstWhere((e) => e.code == code, orElse: () => OperationType.vlos);

  /// Tipos de operación válidos según la categoría de la aeronave.
  static List<OperationType> forCategory(AircraftCategory category) =>
      category == AircraftCategory.uas
          ? const [
              OperationType.vlos,
              OperationType.bvlos,
              OperationType.inspection,
              OperationType.photogrammetry,
              OperationType.training,
              OperationType.simulator,
            ]
          : const [
              OperationType.vfr,
              OperationType.ifr,
              OperationType.training,
              OperationType.simulator,
            ];
}


########## ARCHIVO: lib/core/database/aero_repository.dart ##########
import 'package:sqflite/sqflite.dart';

import '../../features/flights/domain/flight_filter.dart';
import '../../features/flights/domain/flight_log.dart';
import '../../features/hangar/domain/aircraft.dart';
import '../../features/hangar/domain/battery.dart';
import '../../features/pilot/domain/pilot_profile.dart';
import '../constants/enums.dart';
import '../errors/aero_exception.dart';
import '../utils/formatters.dart';

/// Acceso a datos (único punto que habla con SQLite).
///
/// La lógica crítica de negocio vive aquí dentro de transacciones:
///  * [saveFlight]  → inserta el vuelo, suma minutos a la aeronave y +1 ciclo a
///    cada batería, todo o nada.
///  * [deleteFlight] → revierte esos mismos acumulados.
class AeroRepository {
  AeroRepository(this._db);

  final Database _db;

  // ---------------------------------------------------------------- Helpers

  /// UPDATE-then-INSERT. Se evita `ConflictAlgorithm.replace` porque borra la
  /// fila y dispararía los ON DELETE (CASCADE / SET NULL) de las claves foráneas.
  Future<void> _upsert(
    DatabaseExecutor executor,
    String table,
    Map<String, Object?> row,
  ) async {
    final updated = await executor.update(
      table,
      row,
      where: 'id = ?',
      whereArgs: [row['id']],
    );
    if (updated == 0) await executor.insert(table, row);
  }

  Map<String, Object?> _stamp(Map<String, Object?> row) => {
        ...row,
        'updatedAt': DateTime.now().toIso8601String(),
        'synced': 0,
      };

  // ----------------------------------------------------------------- Piloto

  Future<PilotProfile> getPilot() async {
    final rows = await _db.query('pilot_profile', limit: 1);
    return rows.isEmpty
        ? PilotProfile.empty()
        : PilotProfile.fromJson(rows.first);
  }

  Future<void> savePilot(PilotProfile pilot) =>
      _upsert(_db, 'pilot_profile', pilot.toDbMap());

  // -------------------------------------------------------------- Aeronaves

  Future<List<Aircraft>> getAircraft() async {
    final rows = await _db.query('aircraft', orderBy: 'name COLLATE NOCASE');
    return rows.map(Aircraft.fromJson).toList();
  }

  Future<void> saveAircraft(Aircraft aircraft) =>
      _upsert(_db, 'aircraft', _stamp(aircraft.toDbMap()));

  Future<void> deleteAircraft(String id) async {
    final flights = Sqflite.firstIntValue(await _db.rawQuery(
            'SELECT COUNT(*) FROM flight_log WHERE aircraftId = ?', [id])) ??
        0;
    if (flights > 0) {
      throw AeroException(
        'No se puede eliminar: la aeronave tiene $flights vuelo(s) registrados. '
        'Márcala "En mantenimiento" para retirarla de uso.',
      );
    }
    await _db.delete('aircraft', where: 'id = ?', whereArgs: [id]);
  }

  // --------------------------------------------------------------- Baterías

  Future<List<Battery>> getBatteries() async {
    final rows = await _db.query('battery', orderBy: 'code COLLATE NOCASE');
    return rows.map(Battery.fromJson).toList();
  }

  Future<void> saveBattery(Battery battery) async {
    try {
      await _upsert(_db, 'battery', _stamp(battery.toDbMap()));
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw AeroException('Ya existe una batería con el código "${battery.code}".');
      }
      rethrow;
    }
  }

  Future<void> deleteBattery(String id) =>
      _db.delete('battery', where: 'id = ?', whereArgs: [id]);

  // ----------------------------------------------------------------- Vuelos

  Future<List<FlightLog>> getFlights([
    FlightFilter filter = const FlightFilter(),
  ]) async {
    final where = <String>[];
    final args = <Object?>[];

    if (filter.aircraftId != null) {
      where.add('aircraftId = ?');
      args.add(filter.aircraftId);
    }
    if (filter.operationType != null) {
      where.add('operationType = ?');
      args.add(filter.operationType!.code);
    }
    if (filter.kind == FlightKind.real) {
      where.add("operationType <> 'SIMULATOR'");
    } else if (filter.kind == FlightKind.simulator) {
      where.add("operationType = 'SIMULATOR'");
    }
    if (filter.from != null) {
      where.add('date >= ?');
      args.add(kYmd.format(filter.from!));
    }
    if (filter.to != null) {
      where.add('date <= ?');
      args.add(kYmd.format(filter.to!));
    }
    final q = filter.query.trim();
    if (q.isNotEmpty) {
      final like = '%$q%';
      where.add('(locationName LIKE ? OR remarks LIKE ? OR weatherSummary LIKE ? '
          'OR aircraftId IN (SELECT id FROM aircraft '
          'WHERE name LIKE ? OR registrationCode LIKE ?))');
      args.addAll([like, like, like, like, like]);
    }

    final rows = await _db.query(
      'flight_log',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC, takeoffTime DESC',
    );
    return _hydrateFlights(rows);
  }

  /// Vuelos pendientes de sincronizar con la nube (`synced = 0`).
  Future<List<FlightLog>> getUnsyncedFlights() async {
    final rows = await _db.query('flight_log', where: 'synced = 0');
    return _hydrateFlights(rows);
  }

  Future<void> markFlightsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final marks = List.filled(ids.length, '?').join(',');
    await _db.rawUpdate(
        'UPDATE flight_log SET synced = 1 WHERE id IN ($marks)', ids);
  }

  /// Adjunta a cada vuelo la lista de IDs de baterías (tabla puente).
  Future<List<FlightLog>> _hydrateFlights(
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return [];
    final links = await _db.query('flight_battery');
    final byFlight = <String, List<String>>{};
    for (final l in links) {
      (byFlight[l['flightId'] as String] ??= []).add(l['batteryId'] as String);
    }
    return rows
        .map((r) => FlightLog.fromJson({
              ...r,
              'batteryIds': byFlight[r['id'] as String] ?? const <String>[],
            }))
        .toList();
  }

  /// Guarda el vuelo y actualiza acumulados en UNA transacción:
  ///  1. inserta el vuelo y sus baterías,
  ///  2. suma `durationMinutes` a `aircraft.totalFlightMinutes`,
  ///  3. suma +1 a `battery.cycleCount` de cada batería usada.
  /// Los vuelos de simulador se registran pero NO modifican (2) ni (3).
  Future<void> saveFlight(FlightLog flight) async {
    if (flight.durationMinutes <= 0) {
      throw const AeroException('La duración del vuelo debe ser mayor a 0 minutos.');
    }
    await _db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();

      await txn.insert('flight_log', {
        ...flight.toDbMap(),
        'updatedAt': now,
        'synced': 0,
      });

      for (final batteryId in flight.batteryIds) {
        await txn.insert('flight_battery', {
          'flightId': flight.id,
          'batteryId': batteryId,
        });
      }

      if (flight.countsTowardsTotals) {
        await txn.rawUpdate(
          'UPDATE aircraft SET totalFlightMinutes = totalFlightMinutes + ?, '
          'updatedAt = ?, synced = 0 WHERE id = ?',
          [flight.durationMinutes, now, flight.aircraftId],
        );
        for (final batteryId in flight.batteryIds) {
          await txn.rawUpdate(
            'UPDATE battery SET cycleCount = cycleCount + 1, '
            'updatedAt = ?, synced = 0 WHERE id = ?',
            [now, batteryId],
          );
        }
      }
    });
  }

  /// Elimina un vuelo y revierte los minutos de la aeronave y los ciclos de
  /// las baterías (si era un vuelo real).
  Future<void> deleteFlight(String id) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'flight_log',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final row = rows.first;
      final now = DateTime.now().toIso8601String();

      final isSimulator = row['operationType'] == OperationType.simulator.code;
      if (!isSimulator) {
        await txn.rawUpdate(
          'UPDATE aircraft SET totalFlightMinutes = '
          'MAX(0, totalFlightMinutes - ?), updatedAt = ?, synced = 0 '
          'WHERE id = ?',
          [row['durationMinutes'], now, row['aircraftId']],
        );
        await txn.rawUpdate(
          'UPDATE battery SET cycleCount = MAX(0, cycleCount - 1), '
          'updatedAt = ?, synced = 0 '
          'WHERE id IN (SELECT batteryId FROM flight_battery WHERE flightId = ?)',
          [now, id],
        );
      }
      // flight_battery se elimina en cascada.
      await txn.delete('flight_log', where: 'id = ?', whereArgs: [id]);
    });
  }
}


########## ARCHIVO: lib/core/database/app_database.dart ##########
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Apertura y esquema de la base de datos SQLite local (offline-first).
///
/// Las columnas `updatedAt` y `synced` están preparadas para sincronizar con
/// Firestore: cualquier alta o edición deja `synced = 0` hasta que un
/// `SyncService` la suba y la marque como sincronizada.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const String _dbName = 'bitacora_de_vuelos.db';
  static const int _dbVersion = 1;

  static Future<AppDatabase> open() async {
    final path = p.join(await getDatabasesPath(), _dbName);
    final db = await openDatabase(
      path,
      version: _dbVersion,
      // Imprescindible: SQLite no aplica claves foráneas por defecto.
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return AppDatabase._(db);
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // --- Perfil del piloto (fila única) ---
    batch.execute('''
      CREATE TABLE pilot_profile (
        id TEXT PRIMARY KEY,
        fullName TEXT NOT NULL,
        documentId TEXT NOT NULL,
        licenseNumber TEXT NOT NULL,
        medicalCertExpiry TEXT,
        preferredMode TEXT NOT NULL DEFAULT 'UAS'
          CHECK (preferredMode IN ('UAS','MANNED')),
        hybridEnabled INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // --- Aeronaves ---
    batch.execute('''
      CREATE TABLE aircraft (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        model TEXT NOT NULL,
        serialNumber TEXT NOT NULL DEFAULT '',
        registrationCode TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT 'UAS'
          CHECK (category IN ('UAS','MANNED')),
        mtowKg REAL NOT NULL DEFAULT 0,
        totalFlightMinutes INTEGER NOT NULL DEFAULT 0
          CHECK (totalFlightMinutes >= 0),
        status TEXT NOT NULL DEFAULT 'ACTIVE'
          CHECK (status IN ('ACTIVE','MAINTENANCE')),
        updatedAt TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // --- Baterías (solo UAS) ---
    batch.execute('''
      CREATE TABLE battery (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL UNIQUE,
        aircraftId TEXT REFERENCES aircraft(id) ON DELETE SET NULL,
        cycleCount INTEGER NOT NULL DEFAULT 0 CHECK (cycleCount >= 0),
        healthStatus TEXT NOT NULL DEFAULT 'GOOD'
          CHECK (healthStatus IN ('GOOD','FAIR','POOR')),
        purchaseDate TEXT,
        updatedAt TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // --- Vuelos ---
    // `date` se guarda como 'yyyy-MM-dd' para poder filtrar por rango con
    // comparación de texto. No se puede borrar una aeronave con vuelos.
    batch.execute('''
      CREATE TABLE flight_log (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        takeoffTime TEXT NOT NULL,
        landingTime TEXT NOT NULL,
        durationMinutes INTEGER NOT NULL CHECK (durationMinutes >= 0),
        aircraftId TEXT NOT NULL REFERENCES aircraft(id) ON DELETE RESTRICT,
        operationType TEXT NOT NULL,
        locationName TEXT NOT NULL DEFAULT '',
        latitude REAL,
        longitude REAL,
        maxAltitudeAglMeters REAL,
        weatherSummary TEXT NOT NULL DEFAULT '',
        windSpeedKmh REAL,
        preFlightChecklistPassed INTEGER NOT NULL DEFAULT 0,
        remarks TEXT NOT NULL DEFAULT '',
        updatedAt TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute('CREATE INDEX idx_flight_date ON flight_log(date)');
    batch.execute('CREATE INDEX idx_flight_aircraft ON flight_log(aircraftId)');

    // --- Tabla puente vuelo <-> baterías usadas ---
    batch.execute('''
      CREATE TABLE flight_battery (
        flightId TEXT NOT NULL REFERENCES flight_log(id) ON DELETE CASCADE,
        batteryId TEXT NOT NULL REFERENCES battery(id) ON DELETE CASCADE,
        PRIMARY KEY (flightId, batteryId)
      )
    ''');

    await batch.commit(noResult: true);
  }

  /// Punto de extensión para migraciones futuras (versión 2, 3...).
  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // Ejemplo:
    // if (oldV < 2) await db.execute('ALTER TABLE flight_log ADD COLUMN ...');
  }
}


########## ARCHIVO: lib/core/errors/aero_exception.dart ##########
/// Error de negocio con un mensaje listo para mostrar al usuario.
class AeroException implements Exception {
  const AeroException(this.message);
  final String message;

  @override
  String toString() => message;
}


########## ARCHIVO: lib/core/providers.dart ##########
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/dashboard/domain/dashboard_stats.dart';
import '../features/flights/domain/flight_filter.dart';
import '../features/flights/domain/flight_log.dart';
import '../features/hangar/domain/aircraft.dart';
import '../features/hangar/domain/battery.dart';
import '../features/pilot/domain/pilot_profile.dart';
import 'constants/enums.dart';
import 'database/aero_repository.dart';
import 'services/pdf_service.dart';
import 'services/sync_service.dart';

/// Repositorio: se inyecta en `main()` con la base de datos ya abierta.
final repositoryProvider = Provider<AeroRepository>(
  (ref) => throw UnimplementedError('repositoryProvider debe sobrescribirse en main()'),
);

/// Sincronización en la nube (no-op hasta que se implemente Firestore).
final syncServiceProvider = Provider<SyncService>(
  (ref) => NoopSyncService(ref.watch(repositoryProvider)),
);

final pdfServiceProvider = Provider<PdfService>((ref) => PdfService());

/// Contador que se incrementa tras cada escritura; todos los providers de
/// datos lo observan y se recargan solos.
final dataVersionProvider = StateProvider<int>((ref) => 0);

extension DataRefresh on WidgetRef {
  /// Llamar después de cualquier alta / edición / baja.
  void refreshData() => read(dataVersionProvider.notifier).state++;
}

/// Pestaña activa de la navegación inferior (0 Inicio, 1 Registro, 2 Historial, 3 Hangar).
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// Tema claro / oscuro / sistema.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

// ------------------------------------------------------------------ Datos

final pilotProvider = FutureProvider<PilotProfile>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).getPilot();
});

final aircraftListProvider = FutureProvider<List<Aircraft>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).getAircraft();
});

final batteryListProvider = FutureProvider<List<Battery>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).getBatteries();
});

final allFlightsProvider = FutureProvider<List<FlightLog>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).getFlights();
});

// ---------------------------------------------------------------- Historial

class FlightFilterNotifier extends Notifier<FlightFilter> {
  @override
  FlightFilter build() => const FlightFilter();

  void setQuery(String query) => state = state.copyWith(query: query);
  void setKind(FlightKind kind) => state = state.copyWith(kind: kind);
  void setAircraft(String? id) => state = state.copyWith(aircraftId: () => id);
  void setOperation(OperationType? type) =>
      state = state.copyWith(operationType: () => type);
  void setRange(DateTime? from, DateTime? to) =>
      state = state.copyWith(from: () => from, to: () => to);

  /// Limpia filtros avanzados y tipo; conserva el texto de búsqueda.
  void clearAdvanced() => state = FlightFilter(query: state.query);
}

final flightFilterProvider =
    NotifierProvider<FlightFilterNotifier, FlightFilter>(FlightFilterNotifier.new);

final filteredFlightsProvider = FutureProvider<List<FlightLog>>((ref) {
  ref.watch(dataVersionProvider);
  final filter = ref.watch(flightFilterProvider);
  return ref.watch(repositoryProvider).getFlights(filter);
});

// ---------------------------------------------------------------- Dashboard

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final flights = await ref.watch(allFlightsProvider.future);
  final aircraft = await ref.watch(aircraftListProvider.future);
  final batteries = await ref.watch(batteryListProvider.future);
  final pilot = await ref.watch(pilotProvider.future);
  return DashboardStats.compute(
    flights: flights,
    aircraft: aircraft,
    batteries: batteries,
    pilot: pilot,
    now: DateTime.now(),
  );
});


########## ARCHIVO: lib/core/services/location_service.dart ##########
import 'package:geolocator/geolocator.dart';

import '../errors/aero_exception.dart';

/// Captura de coordenadas GPS (funciona sin internet: usa el chip GPS).
class LocationService {
  const LocationService();

  /// Devuelve (latitud, longitud) actuales o lanza [AeroException] con un
  /// mensaje claro si el GPS está apagado, el permiso fue negado o hubo timeout.
  Future<({double latitude, double longitude})> getCurrentCoordinates() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const AeroException('Activa el GPS del dispositivo e inténtalo de nuevo.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const AeroException('Permiso de ubicación denegado.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const AeroException(
          'Permiso de ubicación bloqueado. Actívalo en los ajustes del sistema.');
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      return (latitude: position.latitude, longitude: position.longitude);
    } catch (_) {
      throw const AeroException(
          'No se pudo obtener la posición. Sal a cielo abierto e inténtalo otra vez.');
    }
  }
}


########## ARCHIVO: lib/core/services/pdf_service.dart ##########
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/flights/domain/flight_filter.dart';
import '../../features/flights/domain/flight_log.dart';
import '../../features/hangar/domain/aircraft.dart';
import '../../features/pilot/domain/pilot_profile.dart';
import '../utils/formatters.dart';

/// Genera la bitácora oficial en PDF (A4 horizontal):
///  * encabezado con datos del piloto y filtros aplicados,
///  * tabla cronológica de vuelos,
///  * totales acumulados (reales / simulador / por aeronave),
///  * espacio para firma.
///
/// Usa solo fuentes integradas de PDF (Helvetica): no requiere internet, ideal
/// para zonas rurales. Los acentos y la "ñ" se imprimen correctamente.
class PdfService {
  static const _ink = PdfColors.blueGrey900;
  static const _accent = PdfColors.blueGrey800;
  static const _line = PdfColors.grey500;

  Future<Uint8List> buildLogbook({
    required PilotProfile pilot,
    required List<FlightLog> flights,
    required List<Aircraft> aircraft,
    FlightFilter filter = const FlightFilter(),
    DateTime? generatedAt,
  }) async {
    final now = generatedAt ?? DateTime.now();
    final byId = {for (final a in aircraft) a.id: a};

    // Una bitácora oficial se lee de lo más antiguo a lo más reciente.
    final sorted = [...flights]..sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : a.takeoffTime.compareTo(b.takeoffTime);
      });

    final doc = pw.Document(
      title: 'Bitácora de vuelos',
      author: pilot.fullName,
      creator: 'Bitácora de vuelos',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Bitácora de vuelos - ${pilot.fullName}',
                        style: const pw.TextStyle(fontSize: 8, color: _ink)),
                    pw.Text('Continuación',
                        style: const pw.TextStyle(fontSize: 8, color: _ink)),
                  ],
                ),
              ),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Generado con Bitácora de vuelos - ${kDateFmt.format(now)} ${kTimeFmt.format(now)}',
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
              pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
            ],
          ),
        ),
        build: (ctx) => [
          _title(),
          pw.SizedBox(height: 8),
          _pilotBlock(pilot),
          pw.SizedBox(height: 6),
          pw.Text(_describeFilter(filter, byId),
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
          pw.SizedBox(height: 10),
          _flightsTable(sorted, byId),
          pw.SizedBox(height: 14),
          _totals(sorted, byId),
          pw.SizedBox(height: 40),
          _signatures(pilot),
        ],
      ),
    );

    return doc.save();
  }

  // ------------------------------------------------------------ Secciones

  pw.Widget _title() => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: const pw.BoxDecoration(color: _accent),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('BITÁCORA DE VUELOS',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                )),
            pw.Text('UAS',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.white)),
          ],
        ),
      );

  pw.Widget _pilotBlock(PilotProfile p) {
    pw.Widget field(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(right: 24, bottom: 3),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                    text: '$label: ',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
                pw.TextSpan(
                    text: value.isEmpty ? '-' : value,
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
        );

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.5)),
      child: pw.Wrap(
        children: [
          field('Piloto', p.fullName),
          field('Documento', p.documentId),
          field('Licencia / certificado', p.licenseNumber),
          field(
              'Certificado médico vence',
              p.medicalCertExpiry == null ? '' : kDateFmt.format(p.medicalCertExpiry!)),
          field('Modo', p.hybridEnabled ? 'Híbrido UAS + Tripulado' : 'Solo UAS'),
        ],
      ),
    );
  }

  pw.Widget _flightsTable(List<FlightLog> flights, Map<String, Aircraft> byId) {
    const headers = [
      '#',
      'Fecha',
      'Aeronave',
      'Operación',
      'Desp.',
      'Aterr.',
      'Duración',
      'Lugar',
      'Alt. máx (m)',
      'Check',
      'Novedades',
    ];

    final data = <List<String>>[
      for (var i = 0; i < flights.length; i++)
        [
          '${i + 1}',
          kDateFmt.format(flights[i].date),
          byId[flights[i].aircraftId]?.displayName ?? 'Eliminada',
          flights[i].operationType.label.split(' ').first,
          kTimeFmt.format(flights[i].takeoffTime),
          kTimeFmt.format(flights[i].landingTime),
          fmtHhMm(flights[i].durationMinutes),
          flights[i].locationName,
          flights[i].maxAltitudeAglMeters == null
              ? ''
              : flights[i].maxAltitudeAglMeters!.toStringAsFixed(0),
          flights[i].preFlightChecklistPassed ? 'Sí' : 'No',
          flights[i].remarks,
        ],
    ];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: _line, width: 0.4),
      headerStyle: pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: _accent),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      cellHeight: 18,
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.center,
        5: pw.Alignment.center,
        6: pw.Alignment.center,
        7: pw.Alignment.centerLeft,
        8: pw.Alignment.center,
        9: pw.Alignment.center,
        10: pw.Alignment.centerLeft,
      },
      columnWidths: {
        0: const pw.FixedColumnWidth(22),
        1: const pw.FixedColumnWidth(52),
        2: const pw.FixedColumnWidth(100),
        3: const pw.FixedColumnWidth(62),
        4: const pw.FixedColumnWidth(36),
        5: const pw.FixedColumnWidth(36),
        6: const pw.FixedColumnWidth(46),
        7: const pw.FixedColumnWidth(110),
        8: const pw.FixedColumnWidth(42),
        9: const pw.FixedColumnWidth(32),
        10: const pw.FlexColumnWidth(),
      },
    );
  }

  pw.Widget _totals(List<FlightLog> flights, Map<String, Aircraft> byId) {
    var real = 0;
    var sim = 0;
    final perAircraft = <String, ({int flights, int minutes})>{};

    for (final f in flights) {
      if (f.isSimulator) {
        sim += f.durationMinutes;
      } else {
        real += f.durationMinutes;
        final prev = perAircraft[f.aircraftId] ?? (flights: 0, minutes: 0);
        perAircraft[f.aircraftId] =
            (flights: prev.flights + 1, minutes: prev.minutes + f.durationMinutes);
      }
    }

    pw.Widget box(String label, String value) => pw.Container(
          width: 150,
          margin: const pw.EdgeInsets.only(right: 10),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.6)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label,
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              pw.SizedBox(height: 3),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink)),
            ],
          ),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('TOTALES ACUMULADOS',
            style: pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          box('Total de vuelos', '${flights.length}'),
          box('Tiempo real (h:min)', fmtHhMm(real)),
          box('Tiempo simulador (h:min)', fmtHhMm(sim)),
          box('Total general (h:min)', fmtHhMm(real + sim)),
        ]),
        if (perAircraft.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const ['Aeronave (vuelos reales)', 'Vuelos', 'Tiempo (h:min)'],
            data: [
              for (final e in perAircraft.entries)
                [
                  byId[e.key]?.displayName ?? 'Eliminada',
                  '${e.value.flights}',
                  fmtHhMm(e.value.minutes),
                ],
            ],
            border: pw.TableBorder.all(color: _line, width: 0.4),
            headerStyle: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _accent),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellHeight: 16,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              2: pw.Alignment.center,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(220),
              1: const pw.FixedColumnWidth(60),
              2: const pw.FixedColumnWidth(90),
            },
          ),
        ],
      ],
    );
  }

  pw.Widget _signatures(PilotProfile pilot) {
    pw.Widget slot(String label, String detail) => pw.SizedBox(
          width: 250,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                height: 1,
                color: _ink,
              ),
              pw.SizedBox(height: 3),
              pw.Text(label,
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              if (detail.isNotEmpty)
                pw.Text(detail, style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        );

    final detail = [
      pilot.fullName,
      if (pilot.documentId.isNotEmpty) 'Doc. ${pilot.documentId}',
    ].where((s) => s.isNotEmpty).join(' - ');

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        slot('Firma del piloto', detail),
        slot('Firma / sello del supervisor o explotador', ''),
      ],
    );
  }

  /// Texto con los filtros aplicados a la exportación.
  String _describeFilter(FlightFilter f, Map<String, Aircraft> byId) {
    final parts = <String>[
      if (f.aircraftId != null)
        'Aeronave: ${byId[f.aircraftId]?.displayName ?? '-'}',
      if (f.operationType != null) 'Operación: ${f.operationType!.label}',
      if (f.kind != FlightKind.all) 'Tipo: ${f.kind.label}',
      if (f.from != null) 'Desde: ${kDateFmt.format(f.from!)}',
      if (f.to != null) 'Hasta: ${kDateFmt.format(f.to!)}',
      if (f.query.trim().isNotEmpty) 'Búsqueda: "${f.query.trim()}"',
    ];
    return parts.isEmpty ? 'Filtros: ninguno (historial completo)' : 'Filtros: ${parts.join('  |  ')}';
  }
}


########## ARCHIVO: lib/core/services/sync_service.dart ##########
import '../database/aero_repository.dart';

/// Contrato de sincronización en la nube (preparado, desactivado por defecto).
///
/// La app es 100 % offline-first: todo se escribe primero en SQLite con
/// `synced = 0`. Para activar Firestore:
///  1. Descomenta `firebase_core` y `cloud_firestore` en pubspec.yaml y ejecuta
///     `flutterfire configure`.
///  2. Implementa [SyncService] (ver esqueleto abajo) y sustituye
///     [NoopSyncService] en `syncServiceProvider` (core/providers.dart).
///  3. Llama a `sync()` al detectar conectividad o desde un botón.
///
/// Esqueleto de implementación:
/// ```dart
/// class FirestoreSyncService implements SyncService {
///   FirestoreSyncService(this._repo, this._uid);
///   final AeroRepository _repo;
///   final String _uid;
///
///   @override
///   Future<void> sync() async {
///     final pending = await _repo.getUnsyncedFlights();
///     final col = FirebaseFirestore.instance
///         .collection('users').doc(_uid).collection('flights');
///     final batch = FirebaseFirestore.instance.batch();
///     for (final f in pending) {
///       batch.set(col.doc(f.id), f.toJson(), SetOptions(merge: true));
///     }
///     await batch.commit();
///     await _repo.markFlightsSynced(pending.map((f) => f.id).toList());
///   }
/// }
/// ```
/// (Los modelos ya exponen `toJson()` / `fromJson()` y las tablas llevan
/// `updatedAt` para resolver conflictos por "última escritura gana".)
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


########## ARCHIVO: lib/core/theme/app_theme.dart ##########
import 'package:flutter/material.dart';

/// Tema Material 3 claro y oscuro. El oscuro usa fondos casi negros con bajo
/// brillo, pensado para uso en exteriores al amanecer/atardecer y baja luz.
class AppTheme {
  AppTheme._();

  static const Color _seed = Color(0xFF0E7490); // azul petróleo aeronáutico

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0B0F14) : null,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: isDark ? const Color(0xFF0B0F14) : scheme.surface,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF10161D) : null,
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 12)),
    );
  }
}

/// Colores semánticos para alertas.
class AlertColors {
  AlertColors._();
  static const Color warning = Color(0xFFF59E0B);
  static const Color critical = Color(0xFFEF4444);
  static const Color ok = Color(0xFF22C55E);
}


########## ARCHIVO: lib/core/utils/formatters.dart ##########
import 'dart:math';

import 'package:intl/intl.dart';

/// Formatos de fecha/hora compartidos por toda la app.
final DateFormat kDateFmt = DateFormat('dd/MM/yyyy');
final DateFormat kTimeFmt = DateFormat('HH:mm');
final DateFormat kYmd = DateFormat('yyyy-MM-dd');

/// "12 h 05 min"
String fmtDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '$h h ${m.toString().padLeft(2, '0')} min';
}

/// "12:05" (horas:minutos) — formato típico de bitácora.
String fmtHhMm(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '$h:${m.toString().padLeft(2, '0')}';
}

/// "00:12:45" para el cronómetro en vivo.
String fmtClock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// Fecha sin componente horario.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Duración en minutos redondeada; un vuelo con duración > 0 cuenta al menos 1 min.
int minutesBetween(DateTime start, DateTime end) {
  final seconds = end.difference(start).inSeconds;
  if (seconds <= 0) return 0;
  return max(1, (seconds / 60).round());
}

/// Parseo tolerante a coma decimal ("12,5" → 12.5).
double? parseDouble(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));


########## ARCHIVO: lib/core/utils/id_generator.dart ##########
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


########## ARCHIVO: lib/core/utils/json_helpers.dart ##########
/// Conversores tolerantes: SQLite devuelve booleanos como 0/1 y JSON como true/false.
bool asBool(Object? v) => v == true || v == 1;

DateTime? asDateOrNull(Object? v) =>
    (v == null || (v is String && v.isEmpty)) ? null : DateTime.parse(v as String);

double? asDoubleOrNull(Object? v) => (v as num?)?.toDouble();

double asDouble(Object? v) => (v as num?)?.toDouble() ?? 0;

int asInt(Object? v) => (v as num?)?.toInt() ?? 0;


########## ARCHIVO: lib/core/widgets/ui_helpers.dart ##########
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


########## ARCHIVO: lib/features/dashboard/domain/dashboard_stats.dart ##########
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/enums.dart';
import '../../../core/utils/formatters.dart';
import '../../flights/domain/flight_log.dart';
import '../../hangar/domain/aircraft.dart';
import '../../hangar/domain/battery.dart';
import '../../pilot/domain/pilot_profile.dart';

enum AlertLevel { warning, critical }

class DashboardAlert {
  const DashboardAlert(this.level, this.title, this.detail);
  final AlertLevel level;
  final String title;
  final String detail;
}

/// Resumen calculado en memoria a partir de los datos locales.
class DashboardStats {
  const DashboardStats({
    required this.realMinutes,
    required this.simulatorMinutes,
    required this.flightsThisMonth,
    required this.topAircraft,
    required this.topAircraftFlights,
    required this.alerts,
  });

  final int realMinutes;
  final int simulatorMinutes;
  final int flightsThisMonth;
  final Aircraft? topAircraft;
  final int topAircraftFlights;
  final List<DashboardAlert> alerts;

  static DashboardStats compute({
    required List<FlightLog> flights,
    required List<Aircraft> aircraft,
    required List<Battery> batteries,
    required PilotProfile pilot,
    required DateTime now,
  }) {
    var real = 0;
    var sim = 0;
    var month = 0;
    final flightsByAircraft = <String, int>{};

    for (final f in flights) {
      if (f.isSimulator) {
        sim += f.durationMinutes;
      } else {
        real += f.durationMinutes;
        flightsByAircraft.update(f.aircraftId, (n) => n + 1, ifAbsent: () => 1);
      }
      if (f.date.year == now.year && f.date.month == now.month) month++;
    }

    // Aeronave más usada (por número de vuelos reales).
    Aircraft? top;
    var topCount = 0;
    for (final a in aircraft) {
      final n = flightsByAircraft[a.id] ?? 0;
      if (n > topCount) {
        top = a;
        topCount = n;
      }
    }

    // ---- Alertas ----
    final alerts = <DashboardAlert>[];

    for (final b in batteries) {
      if (b.cycleCount >= kBatteryCriticalCycles) {
        alerts.add(DashboardAlert(AlertLevel.critical, 'Batería ${b.code}',
            '${b.cycleCount} ciclos: supera el límite recomendado (${kBatteryCriticalCycles}).'));
      } else if (b.healthStatus == BatteryHealth.poor) {
        alerts.add(DashboardAlert(AlertLevel.critical, 'Batería ${b.code}',
            'Estado de salud deficiente. Considera retirarla.'));
      } else if (b.cycleCount >= kBatteryWarningCycles) {
        alerts.add(DashboardAlert(AlertLevel.warning, 'Batería ${b.code}',
            '${b.cycleCount} ciclos: revisa su capacidad.'));
      }
    }

    final expiry = pilot.medicalCertExpiry;
    if (expiry != null) {
      final days = dateOnly(expiry).difference(dateOnly(now)).inDays;
      if (days < 0) {
        alerts.add(DashboardAlert(AlertLevel.critical, 'Certificado médico vencido',
            'Venció el ${kDateFmt.format(expiry)}.'));
      } else if (days <= kMedicalWarningDays) {
        alerts.add(DashboardAlert(AlertLevel.warning, 'Certificado médico por vencer',
            'Vence el ${kDateFmt.format(expiry)} (en $days días).'));
      }
    }

    for (final a in aircraft) {
      if (a.status == AircraftStatus.maintenance) {
        alerts.add(DashboardAlert(AlertLevel.warning, '${a.name} en mantenimiento',
            'No aparece disponible al registrar vuelos.'));
      }
    }

    alerts.sort((a, b) => b.level.index.compareTo(a.level.index)); // críticas primero

    return DashboardStats(
      realMinutes: real,
      simulatorMinutes: sim,
      flightsThisMonth: month,
      topAircraft: top,
      topAircraftFlights: topCount,
      alerts: alerts,
    );
  }
}


########## ARCHIVO: lib/features/dashboard/presentation/dashboard_page.dart ##########
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../domain/dashboard_stats.dart';

/// Pantalla de inicio: tarjetas de resumen, alertas y FAB "+ Nuevo Vuelo".
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final pilot = ref.watch(pilotProvider).valueOrNull;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bitácora de vuelos'),
        actions: [
          IconButton(
            tooltip: isDark ? 'Modo claro' : 'Modo oscuro',
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => ref.read(themeModeProvider.notifier).state =
                (isDark || themeMode == ThemeMode.dark)
                    ? ThemeMode.light
                    : ThemeMode.dark,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ref.read(tabIndexProvider.notifier).state = 1,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Vuelo'),
      ),
      body: statsAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error al cargar datos: $e')),
        data: (stats) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (pilot != null && pilot.fullName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Hola, ${pilot.fullName.split(' ').first}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            _SummaryGrid(stats: stats),
            const SizedBox(height: 20),
            Text('Alertas', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (stats.alerts.isEmpty)
              const _AlertTile(
                alert: DashboardAlert(
                  AlertLevel.warning,
                  'Todo en orden',
                  'No hay baterías, certificados ni equipos que requieran atención.',
                ),
                ok: true,
              )
            else
              for (final alert in stats.alerts) _AlertTile(alert: alert),
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.stats});
  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final top = stats.topAircraft;
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.flight,
                  label: 'Horas reales',
                  value: fmtDuration(stats.realMinutes),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.sports_esports_outlined,
                  label: 'Horas simulador',
                  value: fmtDuration(stats.simulatorMinutes),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.calendar_month_outlined,
                  label: 'Vuelos del mes',
                  value: '${stats.flightsThisMonth}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.emoji_events_outlined,
                  label: 'Más usada',
                  value: top?.name ?? '—',
                  caption: top == null ? 'Sin vuelos aún' : '${stats.topAircraftFlights} vuelos',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: theme.textTheme.labelMedium,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (caption != null)
              Text(caption!, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, this.ok = false});
  final DashboardAlert alert;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok
        ? AlertColors.ok
        : alert.level == AlertLevel.critical
            ? AlertColors.critical
            : AlertColors.warning;
    final icon = ok
        ? Icons.check_circle_outline
        : alert.level == AlertLevel.critical
            ? Icons.error_outline
            : Icons.warning_amber_rounded;

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(alert.title),
        subtitle: Text(alert.detail),
      ),
    );
  }
}


########## ARCHIVO: lib/features/flights/domain/flight_filter.dart ##########
import '../../../core/constants/enums.dart';

/// Separa vuelos reales de horas de simulador.
enum FlightKind {
  all('Todos'),
  real('Reales'),
  simulator('Simulador');

  const FlightKind(this.label);
  final String label;
}

/// Filtros del historial (inmutable). Los campos anulables en `copyWith`
/// reciben una función para poder distinguir "no cambiar" de "poner a null".
class FlightFilter {
  const FlightFilter({
    this.query = '',
    this.aircraftId,
    this.operationType,
    this.kind = FlightKind.all,
    this.from,
    this.to,
  });

  final String query;
  final String? aircraftId;
  final OperationType? operationType;
  final FlightKind kind;
  final DateTime? from;
  final DateTime? to;

  bool get hasAdvancedFilters =>
      aircraftId != null ||
      operationType != null ||
      from != null ||
      to != null;

  int get activeCount =>
      (aircraftId != null ? 1 : 0) +
      (operationType != null ? 1 : 0) +
      (from != null || to != null ? 1 : 0);

  FlightFilter copyWith({
    String? query,
    String? Function()? aircraftId,
    OperationType? Function()? operationType,
    FlightKind? kind,
    DateTime? Function()? from,
    DateTime? Function()? to,
  }) =>
      FlightFilter(
        query: query ?? this.query,
        aircraftId: aircraftId != null ? aircraftId() : this.aircraftId,
        operationType:
            operationType != null ? operationType() : this.operationType,
        kind: kind ?? this.kind,
        from: from != null ? from() : this.from,
        to: to != null ? to() : this.to,
      );
}


########## ARCHIVO: lib/features/flights/domain/flight_log.dart ##########
import '../../../core/constants/enums.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json_helpers.dart';

/// Registro de un vuelo.
class FlightLog {
  FlightLog({
    required this.id,
    required this.date,
    required this.takeoffTime,
    required this.landingTime,
    required this.durationMinutes,
    required this.aircraftId,
    this.batteryIds = const [],
    required this.operationType,
    this.locationName = '',
    this.latitude,
    this.longitude,
    this.maxAltitudeAglMeters,
    this.weatherSummary = '',
    this.windSpeedKmh,
    this.preFlightChecklistPassed = false,
    this.remarks = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String id;

  /// Fecha del vuelo (solo día).
  final DateTime date;
  final DateTime takeoffTime;
  final DateTime landingTime;
  final int durationMinutes;
  final String aircraftId;

  /// IDs de las baterías usadas (tabla puente `flight_battery`).
  final List<String> batteryIds;
  final OperationType operationType;
  final String locationName;
  final double? latitude;
  final double? longitude;

  /// Altitud máxima sobre el nivel del suelo (AGL), en metros.
  final double? maxAltitudeAglMeters;
  final String weatherSummary;
  final double? windSpeedKmh;
  final bool preFlightChecklistPassed;

  /// Novedades o incidentes.
  final String remarks;
  final DateTime updatedAt;

  bool get isSimulator => operationType.isSimulator;

  /// Solo los vuelos reales suman horas a la aeronave y ciclos a las baterías.
  bool get countsTowardsTotals => !operationType.isSimulator;

  bool get hasCoordinates => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': kYmd.format(date),
        'takeoffTime': takeoffTime.toIso8601String(),
        'landingTime': landingTime.toIso8601String(),
        'durationMinutes': durationMinutes,
        'aircraftId': aircraftId,
        'batteryIds': batteryIds,
        'operationType': operationType.code,
        'locationName': locationName,
        'latitude': latitude,
        'longitude': longitude,
        'maxAltitudeAglMeters': maxAltitudeAglMeters,
        'weatherSummary': weatherSummary,
        'windSpeedKmh': windSpeedKmh,
        'preFlightChecklistPassed': preFlightChecklistPassed,
        'remarks': remarks,
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Mapa para la tabla `flight_log`: sin `batteryIds` (van en `flight_battery`)
  /// y con booleanos como 0/1.
  Map<String, dynamic> toDbMap() {
    final map = toJson()..remove('batteryIds');
    map['preFlightChecklistPassed'] = preFlightChecklistPassed ? 1 : 0;
    return map;
  }

  factory FlightLog.fromJson(Map<String, dynamic> j) => FlightLog(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        takeoffTime: DateTime.parse(j['takeoffTime'] as String),
        landingTime: DateTime.parse(j['landingTime'] as String),
        durationMinutes: asInt(j['durationMinutes']),
        aircraftId: j['aircraftId'] as String,
        batteryIds:
            ((j['batteryIds'] as List?) ?? const []).cast<String>().toList(),
        operationType: OperationType.fromCode(j['operationType'] as String?),
        locationName: (j['locationName'] as String?) ?? '',
        latitude: asDoubleOrNull(j['latitude']),
        longitude: asDoubleOrNull(j['longitude']),
        maxAltitudeAglMeters: asDoubleOrNull(j['maxAltitudeAglMeters']),
        weatherSummary: (j['weatherSummary'] as String?) ?? '',
        windSpeedKmh: asDoubleOrNull(j['windSpeedKmh']),
        preFlightChecklistPassed: asBool(j['preFlightChecklistPassed']),
        remarks: (j['remarks'] as String?) ?? '',
        updatedAt: asDateOrNull(j['updatedAt']),
      );
}


########## ARCHIVO: lib/features/flights/presentation/history_page.dart ##########
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/enums.dart';
import '../../../core/errors/aero_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../hangar/domain/aircraft.dart';
import '../domain/flight_filter.dart';
import '../domain/flight_log.dart';

/// Historial cronológico con búsqueda, filtros y exportación a PDF.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final _searchCtrl = TextEditingController();
  bool _exporting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportPdf() async {
    final flights = ref.read(filteredFlightsProvider).valueOrNull ?? const [];
    if (flights.isEmpty) {
      showSnack(context, 'No hay vuelos para exportar con los filtros actuales.');
      return;
    }
    setState(() => _exporting = true);
    try {
      final pilot = await ref.read(pilotProvider.future);
      final aircraft = await ref.read(aircraftListProvider.future);
      final bytes = await ref.read(pdfServiceProvider).buildLogbook(
            pilot: pilot,
            flights: flights,
            aircraft: aircraft,
            filter: ref.read(flightFilterProvider),
          );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'bitacora_vuelos_${kYmd.format(DateTime.now())}.pdf',
      );
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo generar el PDF: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const _FilterSheet(),
    );
  }

  Future<void> _delete(FlightLog flight) async {
    final ok = await confirmDialog(
      context,
      title: 'Eliminar vuelo',
      message: 'Se eliminará el vuelo del ${kDateFmt.format(flight.date)} y se '
          'restarán sus minutos y ciclos de batería. ¿Continuar?',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteFlight(flight.id);
      ref.refreshData();
    } on AeroException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(flightFilterProvider);
    final flightsAsync = ref.watch(filteredFlightsProvider);
    final aircraft = ref.watch(aircraftListProvider).valueOrNull ?? const <Aircraft>[];
    final aircraftById = {for (final a in aircraft) a.id: a};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        actions: [
          IconButton(
            tooltip: 'Filtros',
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: filter.hasAdvancedFilters,
              label: Text('${filter.activeCount}'),
              child: const Icon(Icons.filter_list),
            ),
          ),
          IconButton(
            tooltip: 'Exportar a PDF',
            onPressed: _exporting ? null : _exportPdf,
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: ref.read(flightFilterProvider.notifier).setQuery,
              decoration: InputDecoration(
                hintText: 'Buscar por lugar, aeronave, novedades...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: filter.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(flightFilterProvider.notifier).setQuery('');
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<FlightKind>(
                showSelectedIcon: false,
                segments: [
                  for (final k in FlightKind.values)
                    ButtonSegment(value: k, label: Text(k.label)),
                ],
                selected: {filter.kind},
                onSelectionChanged: (s) =>
                    ref.read(flightFilterProvider.notifier).setKind(s.first),
              ),
            ),
          ),
          Expanded(
            child: flightsAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (flights) {
                if (flights.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No hay vuelos que coincidan.\nRegistra uno desde la pestaña "Registro".',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final total = flights.fold<int>(0, (s, f) => s + f.durationMinutes);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Text('${flights.length} vuelo(s)',
                              style: Theme.of(context).textTheme.labelLarge),
                          const Spacer(),
                          Text('Total: ${fmtDuration(total)}',
                              style: Theme.of(context).textTheme.labelLarge),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: flights.length,
                        itemBuilder: (context, i) {
                          final f = flights[i];
                          return _FlightTile(
                            flight: f,
                            aircraft: aircraftById[f.aircraftId],
                            onTap: () => _showDetail(f, aircraftById[f.aircraftId]),
                            onDelete: () => _delete(f),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(FlightLog f, Aircraft? aircraft) {
    final batteries = ref.read(batteryListProvider).valueOrNull ?? const [];
    final codes = batteries
        .where((b) => f.batteryIds.contains(b.id))
        .map((b) => b.code)
        .join(', ');

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(label, style: Theme.of(context).textTheme.labelMedium),
              ),
              Expanded(child: Text(value.isEmpty ? '—' : value)),
            ],
          ),
        );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Vuelo del ${kDateFmt.format(f.date)}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row('Aeronave', aircraft?.displayName ?? 'Eliminada'),
              row('Operación', f.operationType.label),
              row('Despegue', kTimeFmt.format(f.takeoffTime)),
              row('Aterrizaje', kTimeFmt.format(f.landingTime)),
              row('Duración', fmtDuration(f.durationMinutes)),
              row('Baterías', codes),
              row('Lugar', f.locationName),
              row('Coordenadas',
                  f.hasCoordinates ? '${f.latitude!.toStringAsFixed(6)}, ${f.longitude!.toStringAsFixed(6)}' : ''),
              row('Alt. máx. AGL',
                  f.maxAltitudeAglMeters == null ? '' : '${f.maxAltitudeAglMeters!.toStringAsFixed(0)} m'),
              row('Clima', f.weatherSummary),
              row('Viento',
                  f.windSpeedKmh == null ? '' : '${f.windSpeedKmh!.toStringAsFixed(0)} km/h'),
              row('Checklist', f.preFlightChecklistPassed ? 'Completo' : 'Incompleto'),
              row('Novedades', f.remarks),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }
}

class _FlightTile extends StatelessWidget {
  const _FlightTile({
    required this.flight,
    required this.aircraft,
    required this.onTap,
    required this.onDelete,
  });

  final FlightLog flight;
  final Aircraft? aircraft;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sim = flight.isSimulator;
    final place = flight.locationName.isEmpty ? '' : ' · ${flight.locationName}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: sim
              ? theme.colorScheme.tertiaryContainer
              : theme.colorScheme.primaryContainer,
          child: Icon(
            sim ? Icons.computer : Icons.flight,
            color: sim
                ? theme.colorScheme.onTertiaryContainer
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          '${aircraft?.name ?? 'Aeronave eliminada'} · ${flight.operationType.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${kDateFmt.format(flight.date)} · '
          '${kTimeFmt.format(flight.takeoffTime)}-${kTimeFmt.format(flight.landingTime)}'
          '$place',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fmtHhMm(flight.durationMinutes),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Eliminar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja de filtros avanzados (aeronave, tipo de operación y rango de fechas).
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(flightFilterProvider);
    final notifier = ref.read(flightFilterProvider.notifier);
    final aircraft = ref.watch(aircraftListProvider).valueOrNull ?? const <Aircraft>[];

    final rangeText = (filter.from == null && filter.to == null)
        ? 'Todas las fechas'
        : '${filter.from == null ? '…' : kDateFmt.format(filter.from!)}  →  '
            '${filter.to == null ? '…' : kDateFmt.format(filter.to!)}';

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filtros', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              value: filter.aircraftId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Aeronave'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                for (final a in aircraft)
                  DropdownMenuItem<String?>(value: a.id, child: Text(a.displayName)),
              ],
              onChanged: notifier.setAircraft,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<OperationType?>(
              value: filter.operationType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo de operación'),
              items: [
                const DropdownMenuItem<OperationType?>(value: null, child: Text('Todos')),
                for (final o in OperationType.values)
                  DropdownMenuItem<OperationType?>(value: o, child: Text(o.label)),
              ],
              onChanged: notifier.setOperation,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(rangeText),
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDateRange: (filter.from != null && filter.to != null)
                      ? DateTimeRange(start: filter.from!, end: filter.to!)
                      : null,
                );
                if (range != null) notifier.setRange(range.start, range.end);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: notifier.clearAdvanced,
                  child: const Text('Limpiar filtros'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Listo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


########## ARCHIVO: lib/features/flights/presentation/new_flight_page.dart ##########
import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/errors/aero_exception.dart';
import '../../../core/providers.dart';
import '../../../core/services/location_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../hangar/domain/aircraft.dart';
import '../domain/flight_log.dart';

/// Formulario de registro de vuelo:
///  * Checklist pre-vuelo colapsable
///  * Cronómetro en vivo (despegue / aterrizaje) o ingreso manual
///  * Captura de GPS
///  * Al guardar, el repositorio suma los minutos a la aeronave y +1 ciclo a
///    cada batería seleccionada (en una sola transacción).
class NewFlightPage extends ConsumerStatefulWidget {
  const NewFlightPage({super.key});

  @override
  ConsumerState<NewFlightPage> createState() => _NewFlightPageState();
}

class _NewFlightPageState extends ConsumerState<NewFlightPage> {
  static const _uasChecklist = [
    'Hélices: estado y sujeción',
    'Firmware actualizado, sin avisos',
    'Calibración de IMU y brújula',
    'Espacio aéreo y permisos autorizados',
    'Enlace RC / telemetría / video OK',
    'Baterías cargadas y sin daños',
  ];

  static const _mannedChecklist = [
    'Inspección exterior de la aeronave',
    'Combustible y aceite',
    'Documentos de la aeronave y licencias',
    'Meteorología y NOTAM',
    'Plan de vuelo, peso y balance',
    'Instrumentos y radios',
  ];

  final _formKey = GlobalKey<FormState>();
  final _locationCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _altCtrl = TextEditingController();
  final _weatherCtrl = TextEditingController();
  final _windCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();

  String? _aircraftId;
  OperationType? _operation;
  final Set<String> _batteryIds = {};
  final Set<String> _checked = {};

  // Tiempos
  bool _manual = false;
  DateTime _date = dateOnly(DateTime.now());
  DateTime? _takeoff;
  DateTime? _landing;
  TimeOfDay? _manualTakeoff;
  TimeOfDay? _manualLanding;
  Timer? _ticker;

  bool _capturingGps = false;
  bool _saving = false;

  @override
  void dispose() {
    _ticker?.cancel();
    for (final c in [
      _locationCtrl,
      _latCtrl,
      _lngCtrl,
      _altCtrl,
      _weatherCtrl,
      _windCtrl,
      _remarksCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------ Cronómetro

  bool get _running => !_manual && _takeoff != null && _landing == null;

  Duration get _elapsed {
    if (_takeoff == null) return Duration.zero;
    return (_landing ?? DateTime.now()).difference(_takeoff!);
  }

  void _startFlight() {
    final now = DateTime.now();
    setState(() {
      _takeoff = now;
      _landing = null;
      _date = dateOnly(now);
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopFlight() {
    _ticker?.cancel();
    setState(() => _landing = DateTime.now());
  }

  void _resetTimer() {
    _ticker?.cancel();
    setState(() {
      _takeoff = null;
      _landing = null;
    });
  }

  /// Devuelve (despegue, aterrizaje) según el modo, o null si faltan datos.
  ({DateTime takeoff, DateTime landing})? _resolveTimes() {
    if (_manual) {
      final t = _manualTakeoff;
      final l = _manualLanding;
      if (t == null || l == null) return null;
      final takeoff = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);
      var landing = DateTime(_date.year, _date.month, _date.day, l.hour, l.minute);
      // Vuelo que cruza la medianoche.
      if (!landing.isAfter(takeoff)) landing = landing.add(const Duration(days: 1));
      return (takeoff: takeoff, landing: landing);
    }
    if (_takeoff == null || _landing == null) return null;
    return (takeoff: _takeoff!, landing: _landing!);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  Future<void> _pickTime({required bool takeoff}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (takeoff ? _manualTakeoff : _manualLanding) ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() {
      if (takeoff) {
        _manualTakeoff = picked;
      } else {
        _manualLanding = picked;
      }
    });
  }

  // ------------------------------------------------------------------- GPS

  Future<void> _captureGps() async {
    setState(() => _capturingGps = true);
    try {
      final pos = await const LocationService().getCurrentCoordinates();
      _latCtrl.text = pos.latitude.toStringAsFixed(6);
      _lngCtrl.text = pos.longitude.toStringAsFixed(6);
      if (mounted) showSnack(context, 'Coordenadas capturadas');
    } on AeroException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _capturingGps = false);
    }
  }

  // ------------------------------------------------------------- Guardado

  List<String> _checklistFor(AircraftCategory? category) =>
      category == AircraftCategory.manned ? _mannedChecklist : _uasChecklist;

  Future<void> _save(List<Aircraft> aircraftList) async {
    if (!_formKey.currentState!.validate()) return;

    if (_running) {
      showSnack(context, 'Registra el aterrizaje antes de guardar.');
      return;
    }
    final times = _resolveTimes();
    if (times == null) {
      showSnack(
        context,
        _manual
            ? 'Indica la hora de despegue y de aterrizaje.'
            : 'Pulsa "Iniciar despegue" y "Registrar aterrizaje", o usa el ingreso manual.',
      );
      return;
    }
    final minutes = minutesBetween(times.takeoff, times.landing);
    if (minutes <= 0) {
      showSnack(context, 'La duración del vuelo debe ser mayor a 0.');
      return;
    }

    final aircraft = aircraftList.firstWhere((a) => a.id == _aircraftId);
    final checklist = _checklistFor(aircraft.category);
    final operation = _operation!;

    final flight = FlightLog(
      id: newId(),
      date: _manual ? _date : dateOnly(times.takeoff),
      takeoffTime: times.takeoff,
      landingTime: times.landing,
      durationMinutes: minutes,
      aircraftId: aircraft.id,
      // El simulador no consume baterías.
      batteryIds: operation.isSimulator ? const [] : _batteryIds.toList(),
      operationType: operation,
      locationName: _locationCtrl.text.trim(),
      latitude: parseDouble(_latCtrl.text),
      longitude: parseDouble(_lngCtrl.text),
      maxAltitudeAglMeters: parseDouble(_altCtrl.text),
      weatherSummary: _weatherCtrl.text.trim(),
      windSpeedKmh: parseDouble(_windCtrl.text),
      preFlightChecklistPassed: _checked.length == checklist.length,
      remarks: _remarksCtrl.text.trim(),
    );

    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveFlight(flight);
      ref.refreshData(); // recarga dashboard, historial, hangar...
      if (!mounted) return;
      showSnack(
        context,
        operation.isSimulator
            ? 'Sesión de simulador guardada (${fmtDuration(minutes)})'
            : 'Vuelo guardado: ${fmtDuration(minutes)} sumados a ${aircraft.name}',
      );
      _resetForm();
      ref.read(tabIndexProvider.notifier).state = 0;
    } on AeroException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo guardar el vuelo: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Limpia el formulario conservando la aeronave elegida (comodidad).
  void _resetForm() {
    _ticker?.cancel();
    for (final c in [
      _locationCtrl,
      _latCtrl,
      _lngCtrl,
      _altCtrl,
      _weatherCtrl,
      _windCtrl,
      _remarksCtrl,
    ]) {
      c.clear();
    }
    setState(() {
      _operation = null;
      _batteryIds.clear();
      _checked.clear();
      _manual = false;
      _date = dateOnly(DateTime.now());
      _takeoff = null;
      _landing = null;
      _manualTakeoff = null;
      _manualLanding = null;
    });
  }

  // ----------------------------------------------------------------- Build

  @override
  Widget build(BuildContext context) {
    final aircraftAsync = ref.watch(aircraftListProvider);
    final batteries = ref.watch(batteryListProvider).valueOrNull ?? const [];
    final hybrid = ref.watch(pilotProvider).valueOrNull?.hybridEnabled ?? false;

    // Aeronaves seleccionables: activas y, si el modo es "Solo UAS", solo drones.
    final aircraftList = aircraftAsync.valueOrNull ?? const <Aircraft>[];
    final selectable = aircraftList
        .where((a) => a.isActive && (hybrid || a.isUas))
        .toList();

    if (_aircraftId != null && !selectable.any((a) => a.id == _aircraftId)) {
      _aircraftId = null;
      _operation = null;
      _batteryIds.clear();
    }
    final selected = selectable.where((a) => a.id == _aircraftId).firstOrNull;
    final operations =
        selected == null ? const <OperationType>[] : OperationType.forCategory(selected.category);
    if (_operation != null && !operations.contains(_operation)) _operation = null;

    final aircraftBatteries =
        batteries.where((b) => b.aircraftId == _aircraftId).toList();
    final showBatteries = selected != null &&
        selected.isUas &&
        _operation != null &&
        !_operation!.isSimulator;

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar vuelo')),
      body: aircraftAsync.isLoading && aircraftList.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : selectable.isEmpty
              ? _NoAircraftNotice(
                  onGoToHangar: () => ref.read(tabIndexProvider.notifier).state = 3,
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      _sectionTitle('Aeronave y operación'),
                      DropdownButtonFormField<String>(
                        value: _aircraftId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Aeronave *'),
                        items: [
                          for (final a in selectable)
                            DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.displayName} · ${a.category.label}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        validator: (v) => v == null ? 'Selecciona una aeronave' : null,
                        onChanged: (v) => setState(() {
                          _aircraftId = v;
                          _operation = null;
                          _batteryIds.clear();
                          _checked.clear();
                        }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<OperationType>(
                        value: _operation,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Tipo de operación *'),
                        items: [
                          for (final o in operations)
                            DropdownMenuItem(value: o, child: Text(o.label)),
                        ],
                        validator: (v) => v == null ? 'Selecciona el tipo de operación' : null,
                        onChanged: selected == null
                            ? null
                            : (v) => setState(() {
                                  _operation = v;
                                  if (v?.isSimulator ?? false) _batteryIds.clear();
                                }),
                      ),
                      if (showBatteries) ...[
                        const SizedBox(height: 12),
                        Text('Baterías utilizadas',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        if (aircraftBatteries.isEmpty)
                          Text(
                            'Esta aeronave no tiene baterías vinculadas (agrégalas en Hangar).',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final b in aircraftBatteries)
                                FilterChip(
                                  label: Text('${b.code} · ${b.cycleCount} ciclos'),
                                  avatar: b.isCritical
                                      ? const Icon(Icons.warning_amber_rounded, size: 18)
                                      : null,
                                  selected: _batteryIds.contains(b.id),
                                  onSelected: (on) => setState(() {
                                    if (on) {
                                      _batteryIds.add(b.id);
                                    } else {
                                      _batteryIds.remove(b.id);
                                    }
                                  }),
                                ),
                            ],
                          ),
                      ],
                      const SizedBox(height: 16),
                      _buildChecklist(selected),
                      const SizedBox(height: 8),
                      _sectionTitle('Tiempo de vuelo'),
                      _buildTimerCard(),
                      const SizedBox(height: 8),
                      _sectionTitle('Ubicación'),
                      TextFormField(
                        controller: _locationCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Lugar / zona de operación',
                          prefixIcon: Icon(Icons.place_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _latCtrl,
                              keyboardType: kDecimalKeyboard,
                              decoration: const InputDecoration(labelText: 'Latitud'),
                              validator: (v) =>
                                  optionalNumberValidator(v, min: -90, max: 90),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _lngCtrl,
                              keyboardType: kDecimalKeyboard,
                              decoration: const InputDecoration(labelText: 'Longitud'),
                              validator: (v) =>
                                  optionalNumberValidator(v, min: -180, max: 180),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _capturingGps ? null : _captureGps,
                          icon: _capturingGps
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.my_location),
                          label: Text(_capturingGps ? 'Buscando señal...' : 'Capturar GPS'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _altCtrl,
                        keyboardType: kDecimalKeyboard,
                        decoration: const InputDecoration(
                          labelText: 'Altitud máxima AGL (m)',
                          prefixIcon: Icon(Icons.height),
                        ),
                        validator: (v) => optionalNumberValidator(v, min: 0),
                      ),
                      const SizedBox(height: 8),
                      _sectionTitle('Condiciones'),
                      TextFormField(
                        controller: _weatherCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Resumen meteorológico',
                          hintText: 'Ej.: despejado, 28 °C',
                          prefixIcon: Icon(Icons.wb_sunny_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _windCtrl,
                        keyboardType: kDecimalKeyboard,
                        decoration: const InputDecoration(
                          labelText: 'Viento (km/h)',
                          prefixIcon: Icon(Icons.air),
                        ),
                        validator: (v) => optionalNumberValidator(v, min: 0),
                      ),
                      const SizedBox(height: 8),
                      _sectionTitle('Novedades'),
                      TextFormField(
                        controller: _remarksCtrl,
                        minLines: 3,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Novedades o incidentes',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _saving ? null : () => _save(aircraftList),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('Guardar vuelo'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  // ------------------------------------------------------------- Checklist

  Widget _buildChecklist(Aircraft? aircraft) {
    final items = _checklistFor(aircraft?.category);
    final done = items.where(_checked.contains).length;
    final allDone = done == items.length;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(
          allDone ? Icons.fact_check : Icons.checklist_rtl,
          color: allDone ? Colors.green : scheme.primary,
        ),
        title: const Text('Checklist pre-vuelo'),
        subtitle: Text(allDone ? 'Completo' : '$done de ${items.length} verificados'),
        children: [
          for (final item in items)
            CheckboxListTile(
              dense: true,
              value: _checked.contains(item),
              title: Text(item),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _checked.add(item);
                } else {
                  _checked.remove(item);
                }
              }),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() {
                if (allDone) {
                  _checked.clear();
                } else {
                  _checked.addAll(items);
                }
              }),
              icon: Icon(allDone ? Icons.remove_done : Icons.done_all),
              label: Text(allDone ? 'Desmarcar todo' : 'Marcar todo'),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ Cronómetro

  Widget _buildTimerCard() {
    final theme = Theme.of(context);
    final landed = !_manual && _takeoff != null && _landing != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ingreso manual'),
              subtitle: const Text('Para vuelos ya realizados'),
              value: _manual,
              onChanged: _running
                  ? null
                  : (v) => setState(() {
                        _manual = v;
                        _resetTimerState();
                      }),
            ),
            const Divider(),
            if (_manual) ..._manualInputs() else ...[
              const SizedBox(height: 8),
              Text(
                fmtClock(_elapsed),
                style: theme.textTheme.displayMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _takeoff == null
                    ? 'Listo para despegar'
                    : 'Despegue ${kTimeFmt.format(_takeoff!)}'
                        '${_landing != null ? '  ·  Aterrizaje ${kTimeFmt.format(_landing!)}' : ''}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (_takeoff == null)
                FilledButton.icon(
                  onPressed: _startFlight,
                  icon: const Icon(Icons.flight_takeoff),
                  label: const Text('Iniciar despegue'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                )
              else if (_running)
                FilledButton.icon(
                  onPressed: _stopFlight,
                  icon: const Icon(Icons.flight_land),
                  label: const Text('Registrar aterrizaje'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                )
              else if (landed)
                OutlinedButton.icon(
                  onPressed: _resetTimer,
                  icon: const Icon(Icons.restart_alt),
