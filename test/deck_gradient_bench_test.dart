// Medición del coste de pintar el fondo de una tarjeta de la galería.
// No es una prueba de regresión: es la herramienta con la que se localizó el
// problema de rendimiento de la pantalla de mazos.
//
//   flutter test test/deck_gradient_bench_test.dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/features/decks/widgets/deck_gradient.dart';
import 'package:mirdaily_app/shared/sticker/textures.dart';

void main() {
  test('coste de pintar el fondo de una tarjeta', () {
    const size = Size(384, 150);
    final rect = Offset.zero & size;

    double timeIt(String label, void Function(Canvas canvas) body) {
      // Una pasada de calentamiento, para no medir la primera compilación.
      final warm = ui.PictureRecorder();
      body(Canvas(warm));
      warm.endRecording();

      const runs = 30;
      final sw = Stopwatch()..start();
      for (var i = 0; i < runs; i++) {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        body(canvas);
        // endRecording + toImage fuerza la rasterización de verdad: sin esto
        // solo se mide construir la lista de comandos, no ejecutarlos.
        final picture = rec.endRecording();
        picture.toImageSync(size.width.round(), size.height.round()).dispose();
        picture.dispose();
      }
      sw.stop();
      final per = sw.elapsedMicroseconds / runs / 1000;
      // ignore: avoid_print
      print('$label: ${per.toStringAsFixed(2)} ms por tarjeta');
      return per;
    }

    final gradiente = timeIt('degradado (MaskFilter.blur)', (canvas) {
      final painter = deckGradientTexture('blueNight').createBoxPainter();
      painter.paint(
        canvas,
        Offset.zero,
        const ImageConfiguration(size: size),
      );
    });

    final cartulina = timeIt('cartulina teñida', (canvas) {
      final painter = tintedPaper(const Color(0xFF4CAF50), step: 24)
          .createBoxPainter();
      painter.paint(
        canvas,
        Offset.zero,
        const ImageConfiguration(size: size),
      );
    });

    // ignore: avoid_print
    print('El degradado cuesta ${(gradiente / cartulina).toStringAsFixed(1)}x '
        'lo que la cartulina. Rect medido: $rect');
  });
}
