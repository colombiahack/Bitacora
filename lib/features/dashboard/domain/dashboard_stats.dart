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
            '${b.cycleCount} ciclos: supera el límite recomendado ($kBatteryCriticalCycles).'));
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
