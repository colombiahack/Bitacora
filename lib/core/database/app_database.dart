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

  static const String _dbName = 'aerolog_uas.db';
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
