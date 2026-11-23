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
