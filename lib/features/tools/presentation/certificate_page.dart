import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/providers.dart';
import '../../../core/services/certificate_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../flights/domain/flight_filter.dart';

/// Pantalla "Certificar horas": elige periodo y aeronave y genera el PDF.
class CertificatePage extends ConsumerStatefulWidget {
  const CertificatePage({super.key});

  @override
  ConsumerState<CertificatePage> createState() => _CertificatePageState();
}

class _CertificatePageState extends ConsumerState<CertificatePage> {
  late DateTime _from;
  late DateTime _to;
  String? _aircraftId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, 1, 1);
    _to = dateOnly(now);
  }

  Future<void> _pick(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = dateOnly(picked);
      } else {
        _to = dateOnly(picked);
      }
    });
  }

  void _preset(DateTime from, DateTime to) =>
      setState(() {
        _from = dateOnly(from);
        _to = dateOnly(to);
      });

  Future<void> _generate() async {
    if (_to.isBefore(_from)) {
      showSnack(context, 'La fecha final no puede ser anterior a la inicial.');
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      final pilot = await ref.read(pilotProvider.future);
      if (!pilot.isComplete) {
        if (mounted) {
          showSnack(context, 'Completa tu nombre en el perfil de piloto antes de certificar.');
        }
        return;
      }
      final aircraft = await ref.read(aircraftListProvider.future);
      final flights = await repo.getFlights(
        FlightFilter(aircraftId: _aircraftId, from: _from, to: _to),
      );
      if (flights.isEmpty) {
        if (mounted) showSnack(context, 'No hay vuelos en ese periodo.');
        return;
      }
      final label = _aircraftId == null
          ? null
          : aircraft.where((a) => a.id == _aircraftId).map((a) => a.displayName).firstOrNull;
      final bytes = await CertificateService().build(
        pilot: pilot,
        flights: flights,
        aircraft: aircraft,
        from: _from,
        to: _to,
        aircraftLabel: label,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'certificacion_horas_${kYmd.format(DateTime.now())}.pdf',
      );
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo generar el PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aircraft = ref.watch(aircraftListProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Certificar horas')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Genera una autodeclaración de tus horas de vuelo con base en tu bitácora. '
            'Las horas de simulador salen aparte y no se suman a las reales. '
            'Es un documento firmado por ti: confirma que la entidad que lo pide lo acepta.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('Este año'),
                onPressed: () => _preset(DateTime(now.year, 1, 1), now),
              ),
              ActionChip(
                label: const Text('Año pasado'),
                onPressed: () =>
                    _preset(DateTime(now.year - 1, 1, 1), DateTime(now.year - 1, 12, 31)),
              ),
              ActionChip(
                label: const Text('Últimos 12 meses'),
                onPressed: () => _preset(DateTime(now.year - 1, now.month, now.day), now),
              ),
              ActionChip(
                label: const Text('Todo'),
                onPressed: () => _preset(DateTime(2000, 1, 1), now),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event),
              title: const Text('Desde'),
              subtitle: Text(kDateFmt.format(_from)),
              onTap: () => _pick(true),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_available),
              title: const Text('Hasta'),
              subtitle: Text(kDateFmt.format(_to)),
              onTap: () => _pick(false),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: _aircraftId,
            decoration: const InputDecoration(
              labelText: 'Aeronave',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
              for (final a in aircraft)
                DropdownMenuItem<String?>(value: a.id, child: Text(a.displayName)),
            ],
            onChanged: (v) => setState(() => _aircraftId = v),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _generate,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf),
            label: const Text('Generar PDF'),
          ),
        ],
      ),
    );
  }
}
