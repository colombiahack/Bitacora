import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/id_generator.dart';

/// Toma o elige una foto y la copia a la carpeta privada de la app para que
/// siga disponible aunque se borre de la galería.
class PhotoService {
  const PhotoService();

  Future<String?> pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (picked == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final photos = Directory(p.join(dir.path, 'photos'));
    if (!await photos.exists()) await photos.create(recursive: true);
    final dest = p.join(photos.path, '${newId()}.jpg');
    await File(picked.path).copy(dest);
    return dest;
  }
}
