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

  /// Acceso a la base para los repositorios de funciones adicionales.
  Database get db => _db;

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
