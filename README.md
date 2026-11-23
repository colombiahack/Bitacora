# Bitácora de vuelos

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

## Reglas de negocio clave

- Guardar un vuelo es **una transacción**: inserta el vuelo, suma sus minutos a las
  horas de la aeronave y `+1` ciclo a cada batería seleccionada.
- Los vuelos de **simulador** se registran pero **no** suman horas ni ciclos.
- Eliminar un vuelo revierte esos acumulados.
- No se puede eliminar una aeronave con vuelos; se marca "En mantenimiento".
- Alertas: batería ≥ 200 ciclos (aviso) / ≥ 300 (crítica); certificado médico
  vencido o a ≤ 30 días.
