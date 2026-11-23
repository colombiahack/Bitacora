import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Datos de una versión publicada en GitHub Releases.
class UpdateInfo {
  const UpdateInfo({
    required this.build,
    required this.apkUrl,
    required this.notes,
    required this.sizeBytes,
  });

  final int build;
  final String apkUrl;
  final String notes;
  final int sizeBytes;
}

/// Busca, descarga e instala actualizaciones desde GitHub Releases.
class UpdateService {
  /// Repositorio donde el workflow publica el APK. Si lo renombras, GitHub
  /// redirige solo; aun así puedes actualizar este valor.
  static const String repo = 'colombiahack/Bit%C3%A1cora';

  /// Número de compilación que inyecta el workflow (0 = compilación local).
  static const int currentBuild = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

  /// Devuelve la versión nueva o `null` si ya tienes la última.
  Future<UpdateInfo?> check() async {
    final res = await http
        .get(
          Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('GitHub respondió ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?) ?? '';
    final build = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (build <= currentBuild) return null;

    final assets = (json['assets'] as List?) ?? const [];
    for (final a in assets) {
      final m = a as Map<String, dynamic>;
      final name = (m['name'] as String?) ?? '';
      if (name.endsWith('.apk')) {
        return UpdateInfo(
          build: build,
          apkUrl: m['browser_download_url'] as String,
          notes: (json['body'] as String?) ?? '',
          sizeBytes: (m['size'] as int?) ?? 0,
        );
      }
    }
    return null;
  }

  /// Descarga el APK a la carpeta temporal informando el progreso (0..1).
  Future<String> download(UpdateInfo info, void Function(double) onProgress) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/actualizacion.apk');
    if (await file.exists()) await file.delete();

    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(info.apkUrl)));
      if (res.statusCode != 200) {
        throw Exception('Descarga fallida (${res.statusCode})');
      }
      final total = res.contentLength ?? info.sizeBytes;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.close();
    } finally {
      client.close();
    }
    return file.path;
  }

  /// Abre el instalador de Android con el APK descargado.
  Future<void> install(String path) async {
    final r = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
    if (r.type != ResultType.done) {
      throw Exception(r.message);
    }
  }
}
