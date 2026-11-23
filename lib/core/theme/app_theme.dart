import 'package:flutter/material.dart';

/// Tema Material 3 claro y oscuro. El oscuro usa fondos casi negros con bajo
/// brillo, pensado para uso en exteriores al amanecer/atardecer y baja luz.
class AppTheme {
  AppTheme._();

  static const Color _seed = Color(0xFF0E7490); // azul petróleo aeronáutico

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0B0F14) : null,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: isDark ? const Color(0xFF0B0F14) : scheme.surface,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF10161D) : null,
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 12)),
    );
  }
}

/// Colores semánticos para alertas.
class AlertColors {
  AlertColors._();
  static const Color warning = Color(0xFFF59E0B);
  static const Color critical = Color(0xFFEF4444);
  static const Color ok = Color(0xFF22C55E);
}
