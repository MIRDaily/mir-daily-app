/* ════════════════════════════════════════════════════════════════════════
   Ilustraciones de la DISPOSICIÓN del test (Clásico / Deslizar).

   Enseñan el gesto en vez de describirlo: una hoja larga que se desplaza
   frente a tarjetas que entran una detrás de otra. Con dos líneas de texto
   había que imaginárselo.

   Los iconos de los atajos de asignatura NO están aquí: viven en
   `subject_shortcuts.dart`, junto al botón que los usa.
═══════════════════════════════════════════════════════════════════════════ */
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/sticker/sticker.dart';

/* ─── Disposición del test ─────────────────────────────────────────────── */

/// Clásico: una hoja larga que se desplaza dentro de la pantalla.
class ClassicLayoutArt extends StatefulWidget {
  const ClassicLayoutArt({super.key});

  @override
  State<ClassicLayoutArt> createState() => _ClassicLayoutArtState();
}

class _ClassicLayoutArtState extends State<ClassicLayoutArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: const Size(62, 86),
          painter: _ClassicPainter(_c),
        ),
      );
}

class _ClassicPainter extends CustomPainter {
  final Animation<double> t;

  _ClassicPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(0, 0, size.width, size.height);
    final rr = RRect.fromRectAndRadius(frame, const Radius.circular(11));

    canvas.drawRRect(rr, Paint()..color = Colors.white);
    canvas.save();
    canvas.clipRRect(rr);

    // La hoja mide el doble que la pantalla y sube y baja: eso es el scroll.
    final travel = size.height * 0.85;
    final ease = Curves.easeInOutCubic
        .transform((math.sin(t.value * math.pi * 2) + 1) / 2);
    final dy = -ease * travel;

    canvas.translate(0, dy);
    final bar = Paint()..color = kMuted.withOpacity(0.30);
    final accent = Paint()..color = kAccent;

    // Enunciado, imagen y opciones, todo seguido en la misma hoja.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(8, 9, size.width - 16, 5), const Radius.circular(3)),
      accent,
    );
    for (var i = 0; i < 2; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(8, 20.0 + i * 8, size.width - (16 + i * 10), 4),
            const Radius.circular(2)),
        bar,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(8, 40, size.width - 16, 26), const Radius.circular(6)),
      Paint()..color = kMuted.withOpacity(0.16),
    );
    for (var i = 0; i < 4; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(8, 72.0 + i * 12, size.width - 16, 8),
            const Radius.circular(4)),
        Paint()..color = kMuted.withOpacity(0.22),
      );
    }
    canvas.restore();

    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kInk,
    );

    // Barrita de scroll, para que se lea que hay más abajo.
    final trackH = size.height * 0.5;
    final top = 8 + ease * (size.height - 16 - trackH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width - 5, top, 2.5, trackH),
          const Radius.circular(2)),
      Paint()..color = kInk.withOpacity(0.35),
    );
  }

  @override
  bool shouldRepaint(_ClassicPainter old) => false;
}

/// Deslizar: tarjetas que entran una detrás de otra por la derecha.
class SwipeLayoutArt extends StatefulWidget {
  const SwipeLayoutArt({super.key});

  @override
  State<SwipeLayoutArt> createState() => _SwipeLayoutArtState();
}

class _SwipeLayoutArtState extends State<SwipeLayoutArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: const Size(62, 86),
          painter: _SwipePainter(_c),
        ),
      );
}

class _SwipePainter extends CustomPainter {
  final Animation<double> t;

  _SwipePainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(0, 0, size.width, size.height);
    final rr = RRect.fromRectAndRadius(frame, const Radius.circular(11));

    canvas.drawRRect(rr, Paint()..color = Colors.white);
    canvas.save();
    canvas.clipRRect(rr);

    // Tres tarjetas: enunciado, imagen y opciones. La tanda avanza una tarjeta
    // por tercio de ciclo, con una pausa para que se lea cada una.
    final step = (t.value * 3).floor();
    final local = ((t.value * 3) - step).clamp(0.0, 1.0);
    // El deslizamiento ocupa el último 35 % de cada tramo: antes, quieto.
    final slide = local < 0.65
        ? 0.0
        : Curves.easeInOutCubic.transform((local - 0.65) / 0.35);

    // La tarjeta no ocupa el ancho entero: así la siguiente asoma por el borde
    // y la ilustración cuenta que hay más incluso con la animación parada, que
    // es como se ve la mitad del tiempo.
    final cardW = size.width * 0.72;
    // El paso es MENOR que el marco a propósito: así la de al lado asoma por
    // el borde y se ve que hay más tarjetas aunque la animación esté parada.
    final pitch = cardW + size.width * 0.05;
    final x0 = (size.width - cardW) / 2;
    final shift = (step + slide) * pitch;

    for (var i = 0; i < 4; i++) {
      final x = x0 + i * pitch - shift;
      if (x > size.width || x + cardW < 0) continue;
      _card(canvas, size, x, cardW, i % 3);
    }
    canvas.restore();

    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kInk,
    );

    // Los puntos de paso, abajo.
    for (var i = 0; i < 3; i++) {
      final on = i == step % 3;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              size.width / 2 - 9 + i * 7, size.height - 7, on ? 5 : 3, 3),
          const Radius.circular(2),
        ),
        Paint()..color = on ? kInk : kInk.withOpacity(0.25),
      );
    }
  }

  /// Una de las tres caras del carrusel. [x] es su borde izquierdo y [w] su
  /// ancho, que es menor que el del marco para que asome la de al lado.
  void _card(Canvas canvas, Size size, double x, double w, int kind) {
    final bar = Paint()..color = kMuted.withOpacity(0.28);
    final pad = 7.0;

    // El papel de la tarjeta, para que se distinga del fondo al asomar.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 12, w, size.height - 26), const Radius.circular(7)),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 12, w, size.height - 26), const Radius.circular(7)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = kInk.withOpacity(0.55),
    );

    if (kind == 0) {
      // Enunciado.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x + pad, 22, w - pad * 2, 5),
            const Radius.circular(3)),
        Paint()..color = kAccent,
      );
      for (var i = 0; i < 3; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  x + pad, 34.0 + i * 9, w - pad * 2 - i * 8, 4),
              const Radius.circular(2)),
          bar,
        );
      }
    } else if (kind == 1) {
      // Imagen.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x + pad, 26, w - pad * 2, 36),
            const Radius.circular(6)),
        Paint()..color = kMuted.withOpacity(0.18),
      );
      canvas.drawCircle(
        Offset(x + w * 0.42, 44),
        4,
        Paint()..color = kMuted.withOpacity(0.45),
      );
    } else {
      // Opciones.
      for (var i = 0; i < 4; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x + pad, 24.0 + i * 12, w - pad * 2, 8),
              const Radius.circular(4)),
          Paint()..color = kMuted.withOpacity(i == 1 ? 0.42 : 0.22),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SwipePainter old) => false;
}
