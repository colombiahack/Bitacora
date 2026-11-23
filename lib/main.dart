import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/database/aero_repository.dart';
import 'core/database/app_database.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Datos de fecha en español (nombres de meses/días para intl).
  await initializeDateFormatting('es');

  // La BD se abre UNA vez antes de arrancar la UI (funciona sin internet).
  final database = await AppDatabase.open();

  runApp(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(AeroRepository(database.db)),
      ],
      child: const BitacoraApp(),
    ),
  );
}
