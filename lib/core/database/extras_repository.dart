import 'package:sqflite/sqflite.dart';

import '../../features/tools/domain/models.dart';
import '../constants/enums.dart';
import '../utils/id_generator.dart';

/// Acceso a datos de las funciones adicionales: mantenimiento, documentos,
/// incidentes, plantillas de checklist y fotos de vuelo.
class ExtrasRepository {
  ExtrasRepository(this._db);

  final Database _db;

  Future<void> _upsert(String table, Map<String, Object?> row) async {
    final updated =
        await _db.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
    if (updated == 0) await _db.insert(table, row);
  }

  Map<String, Object?> _stamp(Map<String, Object?> row) => {
        ...row,
        'updatedAt': DateTime.now().toIso8601String(),
        'synced': 0,
      };

  // ------------------------------------------------------------ Mantenimiento

  Future<List<MaintenanceTask>> getMaintenance() async {
    final rows = await _db.query('maintenance_task', orderBy: 'title COLLATE NOCASE');
    return rows.map(MaintenanceTask.fromMap).toList();
  }

  Future<void> saveMaintenance(MaintenanceTask t) =>
      _upsert('maintenance_task', _stamp(t.toDbMap()));

  Future<void> deleteMaintenance(String id) =>
      _db.delete('maintenance_task', where: 'id = ?', whereArgs: [id]);

  // -------------------------------------------------------------- Documentos

  Future<List<DocumentItem>> getDocuments() async {
    final rows = await _db.query('document_item', orderBy: 'title COLLATE NOCASE');
    return rows.map(DocumentItem.fromMap).toList();
  }

  Future<void> saveDocument(DocumentItem d) =>
      _upsert('document_item', _stamp(d.toDbMap()));

  Future<void> deleteDocument(String id) =>
      _db.delete('document_item', where: 'id = ?', whereArgs: [id]);

  // -------------------------------------------------------------- Incidentes

  Future<List<Incident>> getIncidents() async {
    final rows = await _db.query('incident', orderBy: 'date DESC');
    return rows.map(Incident.fromMap).toList();
  }

  Future<void> saveIncident(Incident i) => _upsert('incident', _stamp(i.toDbMap()));

  Future<void> deleteIncident(String id) =>
      _db.delete('incident', where: 'id = ?', whereArgs: [id]);

  // -------------------------------------------------------------- Checklists

  Future<List<ChecklistTemplate>> getChecklists() async {
    final rows = await _db.query('checklist_template', orderBy: 'name COLLATE NOCASE');
    return rows.map(ChecklistTemplate.fromMap).toList();
  }

  Future<void> saveChecklist(ChecklistTemplate c) =>
      _upsert('checklist_template', _stamp(c.toDbMap()));

  Future<void> deleteChecklist(String id) =>
      _db.delete('checklist_template', where: 'id = ?', whereArgs: [id]);

  /// Crea las plantillas por defecto la primera vez.
  Future<void> seedChecklistsIfEmpty() async {
    final count = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(*) FROM checklist_template')) ??
        0;
    if (count > 0) return;
    await saveChecklist(ChecklistTemplate(
      id: newId(),
      name: 'Pre-vuelo UAS',
      category: AircraftCategory.uas,
      items: ChecklistTemplate.defaultUas,
    ));
    await saveChecklist(ChecklistTemplate(
      id: newId(),
      name: 'Pre-vuelo tripulada',
      category: AircraftCategory.manned,
      items: ChecklistTemplate.defaultManned,
    ));
  }

  // ------------------------------------------------------------------ Fotos

  Future<List<String>> getPhotoPaths(String flightId) async {
    final rows = await _db.query('flight_photo',
        where: 'flightId = ?', whereArgs: [flightId], orderBy: 'createdAt');
    return rows.map((r) => r['path'] as String).toList();
  }

  Future<void> addPhoto(String flightId, String path) => _db.insert('flight_photo', {
        'id': newId(),
        'flightId': flightId,
        'path': path,
        'createdAt': DateTime.now().toIso8601String(),
      });
}
