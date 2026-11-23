import 'dart:convert';
import 'dart:math';

import '../../../core/constants/enums.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json_helpers.dart';

// ----------------------------------------------------------------- Mantenimiento

enum IntervalType {
  hours('HOURS', 'Horas de vuelo'),
  days('DAYS', 'Días');

  const IntervalType(this.code, this.label);
  final String code;
  final String label;

  static IntervalType fromCode(String? code) => IntervalType.values
      .firstWhere((e) => e.code == code, orElse: () => IntervalType.hours);
}

/// Estado calculado de una tarea de mantenimiento.
class MaintenanceStatus {
  const MaintenanceStatus({
    required this.overdue,
    required this.soon,
    required this.detail,
    required this.progress,
  });

  final bool overdue;
  final bool soon;
  final String detail;

  /// 0..1 (puede pasar de 1 si está vencida; se recorta al dibujar).
  final double progress;
}

class MaintenanceTask {
  MaintenanceTask({
    required this.id,
    required this.aircraftId,
    required this.title,
    this.intervalType = IntervalType.hours,
    this.intervalValue = 25,
    this.lastDoneDate,
    this.lastDoneMinutes = 0,
    this.notes = '',
  });

  final String id;
  final String aircraftId;
  final String title;
  final IntervalType intervalType;
  final int intervalValue;

  /// Fecha de la última vez que se hizo (base para intervalos en días).
  final DateTime? lastDoneDate;

  /// Minutos totales de la aeronave cuando se hizo (base para intervalos en horas).
  final int lastDoneMinutes;
  final String notes;

  MaintenanceTask markDone(int aircraftMinutes) => MaintenanceTask(
        id: id,
        aircraftId: aircraftId,
        title: title,
        intervalType: intervalType,
        intervalValue: intervalValue,
        lastDoneDate: dateOnly(DateTime.now()),
        lastDoneMinutes: aircraftMinutes,
        notes: notes,
      );

  MaintenanceStatus statusFor(int aircraftMinutes, DateTime now) {
    if (intervalType == IntervalType.hours) {
      final total = max(1, intervalValue * 60);
      final used = max(0, aircraftMinutes - lastDoneMinutes);
      final remaining = total - used;
      final soonLimit = max(60, (total * 0.1).round());
      return MaintenanceStatus(
        overdue: remaining <= 0,
        soon: remaining > 0 && remaining <= soonLimit,
        detail: remaining <= 0
            ? 'Vencido por ${fmtDuration(-remaining)} de vuelo'
            : 'Faltan ${fmtDuration(remaining)} de vuelo',
        progress: used / total,
      );
    }
    final base = lastDoneDate;
    if (base == null) {
      return const MaintenanceStatus(
        overdue: false,
        soon: false,
        detail: 'Sin fecha base: márcalo como realizado para empezar a contar',
        progress: 0,
      );
    }
    final total = max(1, intervalValue);
    final due = dateOnly(base).add(Duration(days: total));
    final remaining = due.difference(dateOnly(now)).inDays;
    return MaintenanceStatus(
      overdue: remaining < 0,
      soon: remaining >= 0 && remaining <= 7,
      detail: remaining < 0
          ? 'Vencido hace ${-remaining} día(s)'
          : 'Vence el ${kDateFmt.format(due)} (en $remaining día(s))',
      progress: (total - remaining) / total,
    );
  }

  Map<String, Object?> toDbMap() => {
        'id': id,
        'aircraftId': aircraftId,
        'title': title,
        'intervalType': intervalType.code,
        'intervalValue': intervalValue,
        'lastDoneDate': lastDoneDate == null ? null : kYmd.format(lastDoneDate!),
        'lastDoneMinutes': lastDoneMinutes,
        'notes': notes,
      };

  factory MaintenanceTask.fromMap(Map<String, Object?> m) => MaintenanceTask(
        id: m['id'] as String,
        aircraftId: m['aircraftId'] as String,
        title: (m['title'] as String?) ?? '',
        intervalType: IntervalType.fromCode(m['intervalType'] as String?),
        intervalValue: asInt(m['intervalValue']),
        lastDoneDate: asDateOrNull(m['lastDoneDate']),
        lastDoneMinutes: asInt(m['lastDoneMinutes']),
        notes: (m['notes'] as String?) ?? '',
      );
}

// -------------------------------------------------------------------- Documentos

enum DocumentKind {
  insurance('INSURANCE', 'Seguro'),
  registration('REGISTRATION', 'Registro de la aeronave'),
  license('LICENSE', 'Licencia / certificado'),
  permit('PERMIT', 'Permiso / autorización'),
  other('OTHER', 'Otro');

  const DocumentKind(this.code, this.label);
  final String code;
  final String label;

  static DocumentKind fromCode(String? code) => DocumentKind.values
      .firstWhere((e) => e.code == code, orElse: () => DocumentKind.other);
}

class DocumentItem {
  DocumentItem({
    required this.id,
    this.aircraftId,
    this.kind = DocumentKind.other,
    required this.title,
    this.number = '',
    this.expiryDate,
    this.notes = '',
  });

  final String id;

  /// null = documento personal / general (no ligado a una aeronave).
  final String? aircraftId;
  final DocumentKind kind;
  final String title;
  final String number;
  final DateTime? expiryDate;
  final String notes;

  int? daysLeft(DateTime now) => expiryDate == null
      ? null
      : dateOnly(expiryDate!).difference(dateOnly(now)).inDays;

  Map<String, Object?> toDbMap() => {
        'id': id,
        'aircraftId': aircraftId,
        'kind': kind.code,
        'title': title,
        'number': number,
        'expiryDate': expiryDate == null ? null : kYmd.format(expiryDate!),
        'notes': notes,
      };

  factory DocumentItem.fromMap(Map<String, Object?> m) => DocumentItem(
        id: m['id'] as String,
        aircraftId: m['aircraftId'] as String?,
        kind: DocumentKind.fromCode(m['kind'] as String?),
        title: (m['title'] as String?) ?? '',
        number: (m['number'] as String?) ?? '',
        expiryDate: asDateOrNull(m['expiryDate']),
        notes: (m['notes'] as String?) ?? '',
      );
}

// --------------------------------------------------------------------- Incidentes

enum Severity {
  low('LOW', 'Leve'),
  medium('MEDIUM', 'Moderado'),
  high('HIGH', 'Grave');

  const Severity(this.code, this.label);
  final String code;
  final String label;

  static Severity fromCode(String? code) => Severity.values
      .firstWhere((e) => e.code == code, orElse: () => Severity.low);
}

class Incident {
  Incident({
    required this.id,
    required this.date,
    this.aircraftId,
    this.severity = Severity.low,
    required this.description,
    this.actionsTaken = '',
  });

  final String id;
  final DateTime date;
  final String? aircraftId;
  final Severity severity;
  final String description;
  final String actionsTaken;

  Map<String, Object?> toDbMap() => {
        'id': id,
        'date': kYmd.format(date),
        'aircraftId': aircraftId,
        'severity': severity.code,
        'description': description,
        'actionsTaken': actionsTaken,
      };

  factory Incident.fromMap(Map<String, Object?> m) => Incident(
        id: m['id'] as String,
        date: DateTime.parse(m['date'] as String),
        aircraftId: m['aircraftId'] as String?,
        severity: Severity.fromCode(m['severity'] as String?),
        description: (m['description'] as String?) ?? '',
        actionsTaken: (m['actionsTaken'] as String?) ?? '',
      );
}

// ---------------------------------------------------------------------- Checklists

class ChecklistTemplate {
  ChecklistTemplate({
    required this.id,
    required this.name,
    this.category = AircraftCategory.uas,
    this.items = const [],
  });

  final String id;
  final String name;
  final AircraftCategory category;
  final List<String> items;

  Map<String, Object?> toDbMap() => {
        'id': id,
        'name': name,
        'category': category.code,
        'itemsJson': jsonEncode(items),
      };

  factory ChecklistTemplate.fromMap(Map<String, Object?> m) {
    final raw = jsonDecode((m['itemsJson'] as String?) ?? '[]');
    return ChecklistTemplate(
      id: m['id'] as String,
      name: (m['name'] as String?) ?? '',
      category: AircraftCategory.fromCode(m['category'] as String?),
      items: (raw as List).map((e) => e.toString()).toList(),
    );
  }

  static const List<String> defaultUas = [
    'Hélices: estado y sujeción',
    'Firmware actualizado, sin avisos',
    'Calibración de IMU y brújula',
    'Espacio aéreo y permisos autorizados',
    'Enlace RC / telemetría / video OK',
    'Baterías cargadas y sin daños',
  ];

  static const List<String> defaultManned = [
    'Inspección exterior de la aeronave',
    'Combustible y aceite',
    'Documentos de la aeronave y licencias',
    'Meteorología y NOTAM',
    'Plan de vuelo, peso y balance',
    'Instrumentos y radios',
  ];
}
