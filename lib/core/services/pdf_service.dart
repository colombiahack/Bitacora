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
