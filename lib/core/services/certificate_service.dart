import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/flights/domain/flight_log.dart';
import '../../features/hangar/domain/aircraft.dart';
import '../../features/pilot/domain/pilot_profile.dart';
import '../utils/formatters.dart';

/// Genera una autodeclaración de horas de vuelo (A4 vertical) a partir de la
/// bitácora personal. Es un documento firmado por el propio piloto; no es un
/// certificado emitido por una autoridad.
class CertificateService {
  static const _ink = PdfColors.blueGrey900;
  static const _accent = PdfColors.blueGrey800;
  static const _line = PdfColors.grey500;

  Future<Uint8List> build({
    required PilotProfile pilot,
    required List<FlightLog> flights,
    required List<Aircraft> aircraft,
    required DateTime from,
    required DateTime to,
    String? aircraftLabel,
    DateTime? generatedAt,
  }) async {
    final now = generatedAt ?? DateTime.now();
    final byId = {for (final a in aircraft) a.id: a};

    final real = flights.where((f) => !f.isSimulator).toList();
    final sim = flights.where((f) => f.isSimulator).toList();
    final realMin = real.fold<int>(0, (s, f) => s + f.durationMinutes);
    final simMin = sim.fold<int>(0, (s, f) => s + f.durationMinutes);

    final perAircraft = <String, ({int flights, int minutes})>{};
    final perOp = <String, ({int flights, int minutes})>{};
    for (final f in real) {
      final a = perAircraft[f.aircraftId] ?? (flights: 0, minutes: 0);
      perAircraft[f.aircraftId] =
          (flights: a.flights + 1, minutes: a.minutes + f.durationMinutes);
      final key = f.operationType.label;
      final o = perOp[key] ?? (flights: 0, minutes: 0);
      perOp[key] = (flights: o.flights + 1, minutes: o.minutes + f.durationMinutes);
    }

    // Código de verificación: huella de los datos certificados.
    final scope = aircraftLabel ?? 'Todas';
    final core = [
      pilot.fullName,
      pilot.documentId,
      kYmd.format(from),
      kYmd.format(to),
      scope,
      '${flights.length}',
      '$realMin',
      '$simMin',
      kYmd.format(now),
    ].join('|');
    final hex = sha256.convert(utf8.encode(core)).toString().toUpperCase();
    final code = 'BV-${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}';
    final qrText = 'BITACORA DE VUELOS - Autodeclaracion de horas\n'
        'Codigo: $code\n'
        'Piloto: ${pilot.fullName}\n'
        'Documento: ${pilot.documentId}\n'
        'Periodo: ${kDateFmt.format(from)} a ${kDateFmt.format(to)}\n'
        'Aeronave: $scope\n'
        'Vuelos: ${flights.length}\n'
        'Horas reales: ${fmtHhMm(realMin)}\n'
        'Simulador: ${fmtHhMm(simMin)}\n'
        'Emitido: ${kDateFmt.format(now)}';

    final doc = pw.Document(
      title: 'Certificación de horas de vuelo',
      author: pilot.fullName,
      creator: 'Bitácora de vuelos',
    );

    pw.Widget heading(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
          child: pw.Text(t,
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
        );

    pw.Widget kv(List<List<String>> rows) => pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.4),
          columnWidths: {
            0: const pw.FixedColumnWidth(150),
            1: const pw.FlexColumnWidth(),
          },
          children: [
            for (final r in rows)
              pw.TableRow(children: [
                pw.Container(
                  color: PdfColors.blueGrey50,
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(r[0],
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(r[1].isEmpty ? '-' : r[1],
                      style: const pw.TextStyle(fontSize: 9)),
                ),
              ]),
          ],
        );

    pw.Widget grid(List<String> headers, List<List<String>> data) =>
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: data.isEmpty ? [List.filled(headers.length, '-')] : data,
          border: pw.TableBorder.all(color: _line, width: 0.4),
          headerStyle: pw.TextStyle(
              fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: _accent),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.all(4),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            for (var i = 1; i < headers.length; i++) i: pw.Alignment.center,
          },
        );

    pw.Widget box(String label, String value) => pw.Container(
          width: 160,
          margin: const pw.EdgeInsets.only(right: 10),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.8)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label,
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              pw.SizedBox(height: 3),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 15, fontWeight: pw.FontWeight.bold, color: _ink)),
            ],
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(38),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generado con Bitácora de vuelos - ${kDateFmt.format(now)} ${kTimeFmt.format(now)}',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
            pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          ],
        ),
        build: (ctx) => [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 10),
            decoration: const pw.BoxDecoration(color: _accent),
            child: pw.Column(children: [
              pw.Text('CERTIFICACIÓN DE HORAS DE VUELO',
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white)),
              pw.SizedBox(height: 3),
              pw.Text('Autodeclaración del piloto con base en su bitácora personal',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.white)),
            ]),
          ),
          heading('DATOS DEL PILOTO'),
          kv([
            ['Nombre', pilot.fullName],
            ['Documento de identidad', pilot.documentId],
            ['Licencia / certificado', pilot.licenseNumber],
            ['Modo de operación', pilot.hybridEnabled ? 'Híbrido UAS + Tripulado' : 'Solo UAS'],
          ]),
          heading('PERIODO CERTIFICADO'),
          kv([
            ['Desde', kDateFmt.format(from)],
            ['Hasta', kDateFmt.format(to)],
            ['Aeronave', aircraftLabel ?? 'Todas'],
            ['Total de vuelos', '${flights.length}'],
          ]),
          heading('HORAS POR AERONAVE (VUELOS REALES)'),
          grid(
            ['Aeronave', 'Vuelos', 'Horas (h:min)'],
            [
              for (final e in perAircraft.entries)
                [
                  byId[e.key]?.displayName ?? 'Eliminada',
                  '${e.value.flights}',
                  fmtHhMm(e.value.minutes),
                ],
            ],
          ),
          heading('HORAS POR TIPO DE OPERACIÓN (VUELOS REALES)'),
          grid(
            ['Operación', 'Vuelos', 'Horas (h:min)'],
            [
              for (final e in perOp.entries)
                [e.key, '${e.value.flights}', fmtHhMm(e.value.minutes)],
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Row(children: [
            box('Total horas de vuelo reales', fmtHhMm(realMin)),
            box('Horas de simulador (aparte)', fmtHhMm(simMin)),
          ]),
          pw.SizedBox(height: 16),
          pw.Text(
            'Declaro que las horas aquí certificadas corresponden a los registros '
            'de mi bitácora personal de vuelos, que las horas de simulador se han '
            'contabilizado por separado y no están incluidas en el total de horas '
            'reales, y que la información es veraz según los datos que registré en '
            'cada vuelo.',
            textAlign: pw.TextAlign.justify,
            style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 3),
          ),
          pw.SizedBox(height: 22),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _sign('Firma del piloto', [
                    [
                      pilot.fullName,
                      if (pilot.documentId.isNotEmpty) 'Doc. ${pilot.documentId}',
                    ].where((x) => x.isNotEmpty).join(' - '),
                    'Fecha: ${kDateFmt.format(now)}',
                  ]),
                ],
              ),
              pw.Container(
                width: 120,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.6)),
                child: pw.Column(children: [
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: qrText,
                    width: 84,
                    height: 84,
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text('Código de verificación',
                      style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                  pw.Text(code,
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _ink)),
                  pw.SizedBox(height: 2),
                  pw.Text('Escanea y compara con este documento',
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700)),
                ]),
              ),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _sign(String label, List<String> lines) => pw.SizedBox(
        width: 250,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(height: 1, color: _ink),
            pw.SizedBox(height: 3),
            pw.Text(label,
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            for (final l in lines)
              pw.Text(l, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      );
}
