import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_helpers.dart';

/// Exportación a CSV y copia de seguridad de la base de datos.
class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});

  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  bool _busy = false;

  String _csv(String v) {
    final escaped = v.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      final flights = await ref.read(allFlightsProvider.future);
      final aircraft = await ref.read(aircraftListProvider.future);
      final batteries = await ref.read(batteryListProvider.future);
      final aById = {for (final a in aircraft) a.id: a};
      final bById = {for (final b in batteries) b.id: b};

      final sb = StringBuffer('﻿');
      sb.writeln('Fecha,Despegue,Aterrizaje,Duración (min),Aeronave,Matrícula,'
          'Operación,Baterías,Lugar,Latitud,Longitud,Altitud AGL (m),Clima,'
          'Viento (km/h),Checklist,Novedades');
      for (final f in flights) {
        final a = aById[f.aircraftId];
        final codes = f.batteryIds.map((id) => bById[id]?.code ?? '?').join(' / ');
        sb.writeln([
          kYmd.format(f.date),
          kTimeFmt.format(f.takeoffTime),
          kTimeFmt.format(f.landingTime),
          '${f.durationMinutes}',
          _csv(a?.name ?? 'Eliminada'),
          _csv(a?.registrationCode ?? ''),
          _csv(f.operationType.label),
          _csv(codes),
          _csv(f.locationName),
          f.latitude?.toString() ?? '',
          f.longitude?.toString() ?? '',
          f.maxAltitudeAglMeters?.toString() ?? '',
          _csv(f.weatherSummary),
          f.windSpeedKmh?.toString() ?? '',
          f.preFlightChecklistPassed ? 'Completo' : 'Incompleto',
          _csv(f.remarks),
        ].join(','));
      }

      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'bitacora_vuelos_${kYmd.format(DateTime.now())}.csv'));
      await file.writeAsString(sb.toString());
      await Share.shareXFiles([XFile(file.path)], text: 'Bitácora de vuelos (CSV)');
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo exportar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupDb() async {
    setState(() => _busy = true);
    try {
      // Vuelca el contenido pendiente del registro WAL al archivo principal.
      try {
        await ref.read(repositoryProvider).db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {}
      final src = File(p.join(await getDatabasesPath(), AppDatabase.fileName));
      final dir = await getTemporaryDirectory();
      final dest = File(p.join(
          dir.path, 'respaldo_bitacora_${kYmd.format(DateTime.now())}.db'));
      await src.copy(dest.path);
      await Share.shareXFiles([XFile(dest.path)], text: 'Respaldo de Bitácora de vuelos');
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo crear el respaldo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exportar y respaldo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Exportar vuelos a CSV'),
              subtitle: const Text(
                  'Todos tus vuelos en una hoja que abre Excel o Google Sheets.'),
              onTap: _busy ? null : _exportCsv,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Copia de seguridad (base de datos)'),
              subtitle: const Text(
                  'Guarda el archivo en Drive, WhatsApp o correo para no perder tus datos.'),
              onTap: _busy ? null : _backupDb,
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'El PDF de la bitácora se exporta desde la pestaña Historial.',
            ),
          ),
        ],
      ),
    );
  }
}
