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

  static const String fileName = 'bitacora_de_vuelos.db';
  static const int _dbVersion = 2;

  static Future<AppDatabase> open() async {
    final path = p.join(await getDatabasesPath(), fileName);
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

    _createExtraTables(batch);

    await batch.commit(noResult: true);
  }

  /// Tablas añadidas en la versión 2: mantenimiento, documentos, incidentes,
  /// plantillas de checklist y fotos de vuelo.
  static void _createExtraTables(Batch batch) {
    batch.execute('''
      CREATE TABLE IF NOT EXISTS maintenance_task (
        id TEXT PRIMARY KEY,
        aircraftId TEXT NOT NULL REFERENCES aircraft(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        intervalType TEXT NOT NULL DEFAULT 'HOURS',
        intervalValue INTEGER NOT NULL DEFAULT 25,
        lastDoneDate TEXT,
        lastDoneMinutes INTEGER NOT NULL DEFAULT 0,
        notes TEXT NOT NULL DEFAULT '',
        updatedAt TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS document_item (
        id TEXT PRIMARY KEY,
        aircraftId TEXT REFERENCES aircraft(id) ON DELETE CASCADE,
        kind TEXT NOT NULL DEFAULT 'OTHER',
        title TEXT NOT NULL,
        number TEXT NOT NULL DEFAULT '',
        expiryDate TEXT,
        notes TEXT NOT NULL DEFAULT '',
        updatedAt TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS incident (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        aircraftId TEXT REFERENCES aircraft(id) ON DELETE SET NULL,
        severity TEXT NOT NULL DEFAULT 'LOW',
        description TEXT NOT NULL,
        actionsTaken TEXT NOT NULL DEFAULT '',
        updatedAt TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS checklist_template (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'UAS',
        itemsJson TEXT NOT NULL DEFAULT '[]',
        updatedAt TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS flight_photo (
        id TEXT PRIMARY KEY,
        flightId TEXT NOT NULL REFERENCES flight_log(id) ON DELETE CASCADE,
        path TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
  }

  /// Migraciones: v1 -> v2 añade las tablas adicionales sin tocar los datos.
  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      final batch = db.batch();
      _createExtraTables(batch);
      await batch.commit(noResult: true);
    }
  }
}
