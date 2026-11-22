# Bitácora de vueloss

App Flutter **offline-first** para registrar vuelos de UAS (drones) con modo opcional
para aviación tripulada. Clean Architecture ligera, Riverpod, SQLite (`sqflite`).

## Puesta en marcha

Este paquete contiene `lib/`, `pubspec.yaml` y `analysis_options.yaml`. Genera las
carpetas de plataforma y copia el código encima:

```bash
flutter create bitacora_de_vuelos --org com.bitacora --platforms android,ios
cd bitacora_de_vuelos
# copia lib/, pubspec.yaml y analysis_options.yaml de este paquete (sobrescribe)
rm test/widget_test.dart   # el test de plantilla referencia MyApp y ya no aplica
flutter pub get
flutter run
```

### Permisos de ubicación (botón "Capturar GPS")

**Android** — `android/app/src/main/AndroidManifest.xml`, dentro de `<manifest>`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

Además, `minSdkVersion 21` o superior (Flutter lo trae por defecto).

**iOS** — `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Bitácora de vuelos usa tu ubicación para registrar dónde se realizó el vuelo.</string>
```

## Estructura

```
lib/
├── main.dart                  # abre la BD y arranca Riverpod
├── app.dart                   # MaterialApp, temas, localización es
├── core/
│   ├── constants/             # enums, umbrales de alertas
│   ├── database/              # app_database.dart (esquema) + aero_repository.dart (transacciones)
│   ├── errors/  theme/  utils/  widgets/
│   ├── services/              # pdf_service, location_service, sync_service (Firestore listo)
│   └── providers.dart         # providers Riverpod
└── features/
    ├── pilot/      (domain + presentation/profile_tab)
    ├── hangar/     (domain: aircraft, battery · presentation: aeronaves, baterías)
    ├── flights/    (domain: flight_log, flight_filter · presentation: nuevo vuelo, historial)
    ├── dashboard/  (domain: stats · presentation)
    └── home/       (navegación inferior de 4 pestañas)
```

## Reglas de negocio clave

- Guardar un vuelo (`AeroRepository.saveFlight`) es **una transacción**: inserta el
  vuelo, suma sus minutos a `aircraft.totalFlightMinutes` y `+1` a `battery.cycleCount`
  de cada batería seleccionada.
- Los vuelos de **simulador** se registran pero **no** suman horas a la aeronave ni
  ciclos a las baterías (se muestran aparte en dashboard e historial).
- Eliminar un vuelo revierte esos acumulados.
- No se puede eliminar una aeronave con vuelos; se marca "En mantenimiento".
- Alertas: batería ≥ 200 ciclos (aviso) / ≥ 300 (crítica) o salud deficiente;
  certificado médico vencido o a ≤ 30 días. Ajustables en `core/constants/app_constants.dart`.

## Sincronización con Firestore (opcional)

Todas las tablas llevan `updatedAt` y `synced`. Descomenta `firebase_core` /
`cloud_firestore` en `pubspec.yaml`, implementa `SyncService` (esqueleto comentado en
`core/services/sync_service.dart`) y cámbialo en `syncServiceProvider`.
