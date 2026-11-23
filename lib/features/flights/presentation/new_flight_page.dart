import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/enums.dart';
import '../../../core/errors/aero_exception.dart';
import '../../../core/extras_providers.dart';
import '../../../core/providers.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../core/services/weather_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../hangar/domain/aircraft.dart';
import '../../tools/domain/models.dart';
import '../domain/flight_log.dart';

/// Formulario de registro de vuelo:
///  * Checklist pre-vuelo colapsable
///  * Cronómetro en vivo (despegue / aterrizaje) o ingreso manual
///  * Captura de GPS
///  * Al guardar, el repositorio suma los minutos a la aeronave y +1 ciclo a
///    cada batería seleccionada (en una sola transacción).
class NewFlightPage extends ConsumerStatefulWidget {
  const NewFlightPage({super.key});

  @override
  ConsumerState<NewFlightPage> createState() => _NewFlightPageState();
}

class _NewFlightPageState extends ConsumerState<NewFlightPage> {
  static const _uasChecklist = [
    'Hélices: estado y sujeción',
    'Firmware actualizado, sin avisos',
    'Calibración de IMU y brújula',
    'Espacio aéreo y permisos autorizados',
    'Enlace RC / telemetría / video OK',
    'Baterías cargadas y sin daños',
  ];

  static const _mannedChecklist = [
    'Inspección exterior de la aeronave',
    'Combustible y aceite',
    'Documentos de la aeronave y licencias',
    'Meteorología y NOTAM',
    'Plan de vuelo, peso y balance',
    'Instrumentos y radios',
  ];

  final _formKey = GlobalKey<FormState>();
  final _locationCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _altCtrl = TextEditingController();
  final _weatherCtrl = TextEditingController();
  final _windCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();

  String? _aircraftId;
  OperationType? _operation;
  final Set<String> _batteryIds = {};
  final Set<String> _checked = {};

  // Tiempos
  bool _manual = false;
  DateTime _date = dateOnly(DateTime.now());
  DateTime? _takeoff;
  DateTime? _landing;
  TimeOfDay? _manualTakeoff;
  TimeOfDay? _manualLanding;
  Timer? _ticker;

  bool _capturingGps = false;
  bool _fetchingWeather = false;
  bool _saving = false;

  String? _templateId;
  final List<String> _photoPaths = [];

  @override
  void dispose() {
    _ticker?.cancel();
    for (final c in [
      _locationCtrl,
      _latCtrl,
      _lngCtrl,
      _altCtrl,
      _weatherCtrl,
      _windCtrl,
      _remarksCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------ Cronómetro

  bool get _running => !_manual && _takeoff != null && _landing == null;

  Duration get _elapsed {
    if (_takeoff == null) return Duration.zero;
    return (_landing ?? DateTime.now()).difference(_takeoff!);
  }

  void _startFlight() {
    final now = DateTime.now();
    setState(() {
      _takeoff = now;
      _landing = null;
      _date = dateOnly(now);
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopFlight() {
    _ticker?.cancel();
    setState(() => _landing = DateTime.now());
  }

  void _resetTimer() {
    _ticker?.cancel();
    setState(() {
      _takeoff = null;
      _landing = null;
    });
  }

  /// Devuelve (despegue, aterrizaje) según el modo, o null si faltan datos.
  ({DateTime takeoff, DateTime landing})? _resolveTimes() {
    if (_manual) {
      final t = _manualTakeoff;
      final l = _manualLanding;
      if (t == null || l == null) return null;
      final takeoff = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);
      var landing = DateTime(_date.year, _date.month, _date.day, l.hour, l.minute);
      // Vuelo que cruza la medianoche.
      if (!landing.isAfter(takeoff)) landing = landing.add(const Duration(days: 1));
      return (takeoff: takeoff, landing: landing);
    }
    if (_takeoff == null || _landing == null) return null;
    return (takeoff: _takeoff!, landing: _landing!);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  Future<void> _pickTime({required bool takeoff}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (takeoff ? _manualTakeoff : _manualLanding) ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() {
      if (takeoff) {
        _manualTakeoff = picked;
      } else {
        _manualLanding = picked;
      }
    });
  }

  // ------------------------------------------------------------------- GPS

  Future<void> _captureGps() async {
    setState(() => _capturingGps = true);
    try {
      final pos = await const LocationService().getCurrentCoordinates();
      _latCtrl.text = pos.latitude.toStringAsFixed(6);
      _lngCtrl.text = pos.longitude.toStringAsFixed(6);
      if (mounted) showSnack(context, 'Coordenadas capturadas');
    } on AeroException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _capturingGps = false);
    }
  }

  // ------------------------------------------------------------- Guardado

  List<ChecklistTemplate> _templatesFor(AircraftCategory? category) {
    final all = ref.read(checklistTemplatesProvider).valueOrNull ??
        const <ChecklistTemplate>[];
    final cat = category ?? AircraftCategory.uas;
    return all.where((t) => t.category == cat).toList();
  }

  ChecklistTemplate? _activeTemplate(AircraftCategory? category) {
    final list = _templatesFor(category);
    if (list.isEmpty) return null;
    for (final t in list) {
      if (t.id == _templateId) return t;
    }
    return list.first;
  }

  List<String> _checklistFor(AircraftCategory? category) {
    final t = _activeTemplate(category);
    if (t != null && t.items.isNotEmpty) return t.items;
    return category == AircraftCategory.manned ? _mannedChecklist : _uasChecklist;
  }

  // ----------------------------------------------------------------- Clima

  Future<void> _fetchWeather() async {
    var lat = parseDouble(_latCtrl.text);
    var lng = parseDouble(_lngCtrl.text);
    if (lat == null || lng == null) {
      await _captureGps();
      lat = parseDouble(_latCtrl.text);
      lng = parseDouble(_lngCtrl.text);
    }
    if (lat == null || lng == null) return;
    setState(() => _fetchingWeather = true);
    try {
      final w = await const WeatherService().fetch(lat, lng);
      _weatherCtrl.text = w.summary;
      _windCtrl.text = w.windKmh.toStringAsFixed(0);
      if (mounted) showSnack(context, 'Clima actualizado');
    } on AeroException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (_) {
      if (mounted) {
        showSnack(context, 'No se pudo obtener el clima. Revisa tu conexión a internet.');
      }
    } finally {
      if (mounted) setState(() => _fetchingWeather = false);
    }
  }

  // ----------------------------------------------------------------- Fotos

  Future<void> _addPhoto(ImageSource source) async {
    try {
      final path = await const PhotoService().pick(source);
      if (path != null && mounted) setState(() => _photoPaths.add(path));
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo agregar la foto: $e');
    }
  }

  Future<void> _save(List<Aircraft> aircraftList) async {
    if (!_formKey.currentState!.validate()) return;

    if (_running) {
      showSnack(context, 'Registra el aterrizaje antes de guardar.');
      return;
    }
    final times = _resolveTimes();
    if (times == null) {
      showSnack(
        context,
        _manual
            ? 'Indica la hora de despegue y de aterrizaje.'
            : 'Pulsa "Iniciar despegue" y "Registrar aterrizaje", o usa el ingreso manual.',
      );
      return;
    }
    final minutes = minutesBetween(times.takeoff, times.landing);
    if (minutes <= 0) {
      showSnack(context, 'La duración del vuelo debe ser mayor a 0.');
      return;
    }

    final aircraft = aircraftList.firstWhere((a) => a.id == _aircraftId);
    final checklist = _checklistFor(aircraft.category);
    final operation = _operation!;

    final flight = FlightLog(
      id: newId(),
      date: _manual ? _date : dateOnly(times.takeoff),
      takeoffTime: times.takeoff,
      landingTime: times.landing,
      durationMinutes: minutes,
      aircraftId: aircraft.id,
      // El simulador no consume baterías.
      batteryIds: operation.isSimulator ? const [] : _batteryIds.toList(),
      operationType: operation,
      locationName: _locationCtrl.text.trim(),
      latitude: parseDouble(_latCtrl.text),
      longitude: parseDouble(_lngCtrl.text),
      maxAltitudeAglMeters: parseDouble(_altCtrl.text),
      weatherSummary: _weatherCtrl.text.trim(),
      windSpeedKmh: parseDouble(_windCtrl.text),
      preFlightChecklistPassed: _checked.length == checklist.length,
      remarks: _remarksCtrl.text.trim(),
    );

    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveFlight(flight);
      final extras = ref.read(extrasRepositoryProvider);
      for (final path in _photoPaths) {
        await extras.addPhoto(flight.id, path);
      }
      ref.refreshData(); // recarga dashboard, historial, hangar...
      if (!mounted) return;
      showSnack(
        context,
        operation.isSimulator
            ? 'Sesión de simulador guardada (${fmtDuration(minutes)})'
            : 'Vuelo guardado: ${fmtDuration(minutes)} sumados a ${aircraft.name}',
      );
      _resetForm();
      ref.read(tabIndexProvider.notifier).state = 0;
    } on AeroException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, 'No se pudo guardar el vuelo: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Limpia el formulario conservando la aeronave elegida (comodidad).
  void _resetForm() {
    _ticker?.cancel();
    for (final c in [
      _locationCtrl,
      _latCtrl,
      _lngCtrl,
      _altCtrl,
      _weatherCtrl,
      _windCtrl,
      _remarksCtrl,
    ]) {
      c.clear();
    }
    setState(() {
      _operation = null;
      _batteryIds.clear();
      _checked.clear();
      _photoPaths.clear();
      _manual = false;
      _date = dateOnly(DateTime.now());
      _takeoff = null;
      _landing = null;
      _manualTakeoff = null;
      _manualLanding = null;
    });
  }

  // ----------------------------------------------------------------- Build

  @override
  Widget build(BuildContext context) {
    final aircraftAsync = ref.watch(aircraftListProvider);
    ref.watch(checklistTemplatesProvider); // para reconstruir si cambian las plantillas
    final batteries = ref.watch(batteryListProvider).valueOrNull ?? const [];
    final hybrid = ref.watch(pilotProvider).valueOrNull?.hybridEnabled ?? false;

    // Aeronaves seleccionables: activas y, si el modo es "Solo UAS", solo drones.
    final aircraftList = aircraftAsync.valueOrNull ?? const <Aircraft>[];
    final selectable = aircraftList
        .where((a) => a.isActive && (hybrid || a.isUas))
        .toList();

    if (_aircraftId != null && !selectable.any((a) => a.id == _aircraftId)) {
      _aircraftId = null;
      _operation = null;
      _batteryIds.clear();
    }
    final selected = selectable.where((a) => a.id == _aircraftId).firstOrNull;
    final operations =
        selected == null ? const <OperationType>[] : OperationType.forCategory(selected.category);
    if (_operation != null && !operations.contains(_operation)) _operation = null;

    final aircraftBatteries =
        batteries.where((b) => b.aircraftId == _aircraftId).toList();
    final showBatteries = selected != null &&
        selected.isUas &&
        _operation != null &&
        !_operation!.isSimulator;

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar vuelo')),
      body: aircraftAsync.isLoading && aircraftList.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : selectable.isEmpty
              ? _NoAircraftNotice(
                  onGoToHangar: () => ref.read(tabIndexProvider.notifier).state = 3,
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      _sectionTitle('Aeronave y operación'),
                      DropdownButtonFormField<String>(
                        value: _aircraftId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Aeronave *'),
                        items: [
                          for (final a in selectable)
                            DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.displayName} · ${a.category.label}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        validator: (v) => v == null ? 'Selecciona una aeronave' : null,
                        onChanged: (v) => setState(() {
                          _aircraftId = v;
                          _operation = null;
                          _batteryIds.clear();
                          _checked.clear();
                        }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<OperationType>(
                        value: _operation,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Tipo de operación *'),
                        items: [
                          for (final o in operations)
                            DropdownMenuItem(value: o, child: Text(o.label)),
                        ],
                        validator: (v) => v == null ? 'Selecciona el tipo de operación' : null,
                        onChanged: selected == null
                            ? null
                            : (v) => setState(() {
                                  _operation = v;
                                  if (v?.isSimulator ?? false) _batteryIds.clear();
                                }),
                      ),
                      if (showBatteries) ...[
                        const SizedBox(height: 12),
                        Text('Baterías utilizadas',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        if (aircraftBatteries.isEmpty)
                          Text(
                            'Esta aeronave no tiene baterías vinculadas (agrégalas en Hangar).',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final b in aircraftBatteries)
                                FilterChip(
                                  label: Text('${b.code} · ${b.cycleCount} ciclos'),
                                  avatar: b.isCritical
                                      ? const Icon(Icons.warning_amber_rounded, size: 18)
                                      : null,
                                  selected: _batteryIds.contains(b.id),
                                  onSelected: (on) => setState(() {
                                    if (on) {
                                      _batteryIds.add(b.id);
                                    } else {
                                      _batteryIds.remove(b.id);
                                    }
                                  }),
                                ),
                            ],
                          ),
                      ],
                      const SizedBox(height: 16),
                      _buildChecklist(selected),
                      const SizedBox(height: 8),
                      _sectionTitle('Tiempo de vuelo'),
                      _buildTimerCard(),
                      const SizedBox(height: 8),
                      _sectionTitle('Ubicación'),
                      TextFormField(
                        controller: _locationCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Lugar / zona de operación',
                          prefixIcon: Icon(Icons.place_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _latCtrl,
                              keyboardType: kDecimalKeyboard,
                              decoration: const InputDecoration(labelText: 'Latitud'),
                              validator: (v) =>
                                  optionalNumberValidator(v, min: -90, max: 90),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _lngCtrl,
                              keyboardType: kDecimalKeyboard,
                              decoration: const InputDecoration(labelText: 'Longitud'),
                              validator: (v) =>
                                  optionalNumberValidator(v, min: -180, max: 180),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _capturingGps ? null : _captureGps,
                          icon: _capturingGps
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.my_location),
                          label: Text(_capturingGps ? 'Buscando señal...' : 'Capturar GPS'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _altCtrl,
                        keyboardType: kDecimalKeyboard,
                        decoration: const InputDecoration(
                          labelText: 'Altitud máxima AGL (m)',
                          prefixIcon: Icon(Icons.height),
                        ),
                        validator: (v) => optionalNumberValidator(v, min: 0),
                      ),
                      const SizedBox(height: 8),
                      _sectionTitle('Condiciones'),
                      TextFormField(
                        controller: _weatherCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Resumen meteorológico',
                          hintText: 'Ej.: despejado, 28 °C',
                          prefixIcon: Icon(Icons.wb_sunny_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _windCtrl,
                        keyboardType: kDecimalKeyboard,
                        decoration: const InputDecoration(
                          labelText: 'Viento (km/h)',
                          prefixIcon: Icon(Icons.air),
                        ),
                        validator: (v) => optionalNumberValidator(v, min: 0),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _fetchingWeather ? null : _fetchWeather,
                          icon: _fetchingWeather
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_download_outlined),
                          label: Text(_fetchingWeather
                              ? 'Consultando clima...'
                              : 'Clima automático (usa tu GPS)'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _sectionTitle('Novedades'),
                      TextFormField(
                        controller: _remarksCtrl,
                        minLines: 3,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Novedades o incidentes',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _sectionTitle('Fotos'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final path in _photoPaths)
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(path),
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const SizedBox(
                                      width: 80,
                                      height: 80,
                                      child: Icon(Icons.broken_image_outlined),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: InkWell(
                                    onTap: () => setState(() => _photoPaths.remove(path)),
                                    child: const CircleAvatar(
                                      radius: 11,
                                      backgroundColor: Colors.black54,
                                      child: Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          OutlinedButton.icon(
                            onPressed: () => _addPhoto(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Cámara'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _addPhoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Galería'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _saving ? null : () => _save(aircraftList),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('Guardar vuelo'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  // ------------------------------------------------------------- Checklist

  Widget _buildChecklist(Aircraft? aircraft) {
    final items = _checklistFor(aircraft?.category);
    final templates = _templatesFor(aircraft?.category);
    final active = _activeTemplate(aircraft?.category);
    final done = items.where(_checked.contains).length;
    final allDone = done == items.length;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(
          allDone ? Icons.fact_check : Icons.checklist_rtl,
          color: allDone ? Colors.green : scheme.primary,
        ),
        title: const Text('Checklist pre-vuelo'),
        subtitle: Text(allDone ? 'Completo' : '$done de ${items.length} verificados'),
        children: [
          if (templates.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: DropdownButtonFormField<String>(
                value: active?.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Plantilla'),
                items: [
                  for (final t in templates)
                    DropdownMenuItem(value: t.id, child: Text(t.name)),
                ],
                onChanged: (v) => setState(() {
                  _templateId = v;
                  _checked.clear();
                }),
              ),
            ),
          for (final item in items)
            CheckboxListTile(
              dense: true,
              value: _checked.contains(item),
              title: Text(item),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _checked.add(item);
                } else {
                  _checked.remove(item);
                }
              }),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() {
                if (allDone) {
                  _checked.clear();
                } else {
                  _checked.addAll(items);
                }
              }),
              icon: Icon(allDone ? Icons.remove_done : Icons.done_all),
              label: Text(allDone ? 'Desmarcar todo' : 'Marcar todo'),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ Cronómetro

  Widget _buildTimerCard() {
    final theme = Theme.of(context);
    final landed = !_manual && _takeoff != null && _landing != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ingreso manual'),
              subtitle: const Text('Para vuelos ya realizados'),
              value: _manual,
              onChanged: _running
                  ? null
                  : (v) => setState(() {
                        _manual = v;
                        _resetTimerState();
                      }),
            ),
            const Divider(),
            if (_manual) ..._manualInputs() else ...[
              const SizedBox(height: 8),
              Text(
                fmtClock(_elapsed),
                style: theme.textTheme.displayMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _takeoff == null
                    ? 'Listo para despegar'
                    : 'Despegue ${kTimeFmt.format(_takeoff!)}'
                        '${_landing != null ? '  ·  Aterrizaje ${kTimeFmt.format(_landing!)}' : ''}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (_takeoff == null)
                FilledButton.icon(
                  onPressed: _startFlight,
                  icon: const Icon(Icons.flight_takeoff),
                  label: const Text('Iniciar despegue'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                )
              else if (_running)
                FilledButton.icon(
                  onPressed: _stopFlight,
                  icon: const Icon(Icons.flight_land),
                  label: const Text('Registrar aterrizaje'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                )
              else if (landed)
                OutlinedButton.icon(
                  onPressed: _resetTimer,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reiniciar cronómetro'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _resetTimerState() {
    _ticker?.cancel();
    _takeoff = null;
    _landing = null;
    _manualTakeoff = null;
    _manualLanding = null;
  }

  List<Widget> _manualInputs() {
    final times = _resolveTimes();
    final minutes =
        times == null ? null : minutesBetween(times.takeoff, times.landing);
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event),
        title: const Text('Fecha'),
        trailing: Text(kDateFmt.format(_date)),
        onTap: _pickDate,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.flight_takeoff),
        title: const Text('Hora de despegue'),
        trailing: Text(_manualTakeoff?.format(context) ?? 'Elegir'),
        onTap: () => _pickTime(takeoff: true),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.flight_land),
        title: const Text('Hora de aterrizaje'),
        trailing: Text(_manualLanding?.format(context) ?? 'Elegir'),
        onTap: () => _pickTime(takeoff: false),
      ),
      if (minutes != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Duración: ${fmtDuration(minutes)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
    ];
  }
}

class _NoAircraftNotice extends StatelessWidget {
  const _NoAircraftNotice({required this.onGoToHangar});
  final VoidCallback onGoToHangar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              'Aún no tienes aeronaves activas',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Registra tu primer dron en el Hangar para poder anotar vuelos.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onGoToHangar,
              icon: const Icon(Icons.add),
              label: const Text('Ir al Hangar'),
            ),
          ],
        ),
      ),
    );
  }
}
