import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extras_providers.dart';

/// Tira de miniaturas con las fotos de un vuelo; al tocar una se amplía.
class FlightPhotosStrip extends ConsumerWidget {
  const FlightPhotosStrip({super.key, required this.flightId});
  final String flightId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(flightPhotosProvider(flightId)).valueOrNull ?? const <String>[];
    if (photos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 84,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: photos.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final file = File(photos[i]);
            return GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(
                    child: Image.file(file, errorBuilder: (_, __, ___) =>
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No se encontró la foto.'),
                        )),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  file,
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 84,
                    height: 84,
                    color: Colors.black12,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
