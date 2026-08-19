import 'package:flutter/material.dart';

import '../../../shared/sticker/sticker.dart';

/// Las dos ilustraciones del modo de visualización.
///
/// Explican el gesto mejor que la frase que las acompañaba: en Clásico la
/// pantalla **baja** por una página larga, y en Deslizar las tarjetas **pasan**
/// de lado. Antes eran una maqueta estática con una flechita; ahora se ve el
/// movimiento, que es justo lo que distingue a un modo del otro.

const _accent = Color(0xFF6E8E6B);
const _paper = Color(0xFFE8E2DE);
const _image = Color(0xFFDED7D2);
const _option = Color(0xFFF2EDEA);

/// Marco de pantalla común a las dos, para que se lean como el mismo objeto.
class _Screen extends StatelessWidget {
  final Widget child;

  const _Screen({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 88,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kInk, width: 2),
        boxShadow: inkShadow(3),
      ),
      clipBehavior: Clip.antiAlias,
      child: RepaintBoundary(child: child),
    );
  }
}

/// Recorta el lienzo al interior del marco de [_Screen].
///
/// El radio es el del marco menos su trazo: el `Container` ya mete al hijo
/// esos 2 px, así que por dentro la curva es un poco más cerrada.
void _clipScreen(Canvas canvas, Size size) {
  canvas.clipRRect(
    RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
  );
}

// ============================================================================
// Clásico: una página larga por la que se baja
// ============================================================================

class ClassicLayoutArt extends StatefulWidget {
  const ClassicLayoutArt({super.key});

  @override
  State<ClassicLayoutArt> createState() => _ClassicLayoutArtState();
}

class _ClassicLayoutArtState extends State<ClassicLayoutArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Screen(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _ClassicPainter(_c.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ClassicPainter extends CustomPainter {
  final double t;

  const _ClassicPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    // `CustomPaint` NO recorta a su pintor: sin esto, la parte de la página
    // que ya ha subido se pinta por encima del marco y asoma por arriba.
    //
    // Y el recorte va REDONDEADO al radio interior del marco: con un
    // rectángulo, un bloque a ras del borde metía sus esquinas cuadradas en
    // la curva y seguía pareciendo que se salía.
    _clipScreen(canvas, size);

    final pad = size.width * 0.13;
    final w = size.width - pad * 2;
    final h = size.height;

    // El recorrido se saca de lo que MIDE la página, no de un número puesto a
    // ojo: antes se desplazaba más de lo que había y quedaba medio marco en
    // blanco, como si el contenido se hubiera acabado.
    final content = <({double h, double factor, Color c, double r})>[
      (h: h * 0.055, factor: 0.50, c: _accent, r: 3), // asignatura
      (h: h * 0.030, factor: 1.00, c: _paper, r: 2), // enunciado
      (h: h * 0.030, factor: 0.92, c: _paper, r: 2),
      (h: h * 0.030, factor: 0.70, c: _paper, r: 2),
      (h: h * 0.300, factor: 1.00, c: _image, r: 4), // imagen
      (h: h * 0.110, factor: 1.00, c: _option, r: 4), // opciones
      (h: h * 0.110, factor: 1.00, c: _option, r: 4),
      (h: h * 0.110, factor: 1.00, c: _option, r: 4),
      (h: h * 0.110, factor: 1.00, c: _option, r: 4),
    ];
    const gap = 0.030;

    var total = pad;
    for (final b in content) {
      total += b.h + h * gap;
    }
    total += pad;

    final overflow = (total - h).clamp(0.0, double.infinity);
    final travel = _phase(t) * overflow;

    canvas.save();
    canvas.translate(0, -travel);
    var y = pad;
    for (final b in content) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(pad, y, w * b.factor, b.h),
          Radius.circular(b.r),
        ),
        Paint()..color = b.c,
      );
      y += b.h + h * gap;
    }
    canvas.restore();

    // Barra de desplazamiento: la pista de que esto se recorre bajando. Su
    // largo es proporcional a lo que se ve de la página, como una de verdad.
    if (overflow <= 0) return;
    final visible = (h / total).clamp(0.15, 1.0);
    final trackTop = h * 0.06;
    final trackH = h * 0.88;
    final thumbH = trackH * visible;
    final top = trackTop + _phase(t) * (trackH - thumbH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 5.5, top, 2.5, thumbH),
        const Radius.circular(2),
      ),
      Paint()..color = _accent.withOpacity(0.5),
    );
  }

  /// Baja, se queda un momento abajo, sube y espera arriba.
  double _phase(double t) {
    if (t < 0.40) return Curves.easeInOut.transform(t / 0.40);
    if (t < 0.55) return 1;
    if (t < 0.90) return 1 - Curves.easeInOut.transform((t - 0.55) / 0.35);
    return 0;
  }

  @override
  bool shouldRepaint(_ClassicPainter old) => old.t != t;
}

// ============================================================================
// Deslizar: tarjetas que pasan de lado
// ============================================================================

class SwipeLayoutArt extends StatefulWidget {
  const SwipeLayoutArt({super.key});

  @override
  State<SwipeLayoutArt> createState() => _SwipeLayoutArtState();
}

class _SwipeLayoutArtState extends State<SwipeLayoutArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Screen(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _SwipePainter(_c.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _SwipePainter extends CustomPainter {
  final double t;

  const _SwipePainter(this.t);

  /// Tres tarjetas: enunciado, imagen y opciones. Es el orden real del modo.
  static const _cards = 3;

  @override
  void paint(Canvas canvas, Size size) {
    _clipScreen(canvas, size);

    // Un paso por tercio de ciclo, con reposo entre medias.
    final step = t * _cards;
    final index = step.floor().clamp(0, _cards - 1);
    final local = step - index;
    final slide = local < 0.35
        ? Curves.easeInOut.transform(local / 0.35)
        : (local < 1 ? 1.0 : 1.0);
    final pos = index + slide;

    final cardW = size.width * 0.74;
    final gap = size.width * 0.16;
    final pitch = cardW + gap;

    for (var i = 0; i < _cards; i++) {
      // La distancia al centro se envuelve: la tarjeta que sale por la
      // izquierda vuelve a entrar por la derecha, así que al cerrar el ciclo
      // (pos = 3 ≡ 0) no hay salto. Sin esto, las tres volvían de golpe a su
      // sitio y se veía el corte.
      var d = (i - pos) % _cards;
      if (d > _cards / 2) d -= _cards;
      if (d < -_cards / 2) d += _cards;

      final dx = size.width / 2 - cardW / 2 + d * pitch;
      final rect = Rect.fromLTWH(
        dx,
        size.height * 0.16,
        cardW,
        size.height * 0.60,
      );
      if (rect.right < -4 || rect.left > size.width + 4) continue;

      // La del centro va entera; las de al lado, apagadas.
      final focus = (1 - d.abs()).clamp(0.0, 1.0);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));

      canvas.drawRRect(rr, Paint()..color = Colors.white);
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = kInk.withOpacity(0.25 + 0.6 * focus),
      );
      _content(canvas, rect, i, focus);
    }

    // Los puntos de posición, abajo.
    final dotY = size.height * 0.88;
    for (var i = 0; i < _cards; i++) {
      final on = (pos.round() % _cards) == i;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size.width / 2 + (i - 1) * 8, dotY),
            width: on ? 8 : 4,
            height: 3,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = on ? _accent : _paper,
      );
    }
  }

  /// Lo que lleva dentro cada tarjeta: enunciado, imagen y opciones.
  void _content(Canvas canvas, Rect r, int index, double focus) {
    final pad = r.width * 0.14;
    final w = r.width - pad * 2;
    final paint = Paint()..color = _paper.withOpacity(0.45 + 0.55 * focus);

    void bar(double top, double widthFactor, double h, [Color? c]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(r.left + pad, r.top + top, w * widthFactor, h),
          const Radius.circular(2),
        ),
        c == null ? paint : (Paint()..color = c.withOpacity(0.45 + 0.55 * focus)),
      );
    }

    switch (index) {
      case 0: // enunciado
        bar(r.height * 0.14, 0.55, 3, _accent);
        bar(r.height * 0.30, 1.0, 3);
        bar(r.height * 0.44, 0.9, 3);
        bar(r.height * 0.58, 0.7, 3);
      case 1: // imagen
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
                r.left + pad, r.top + r.height * 0.18, w, r.height * 0.62),
            const Radius.circular(3),
          ),
          paint,
        );
      default: // opciones
        for (var i = 0; i < 4; i++) {
          bar(r.height * (0.14 + i * 0.20), 1.0, r.height * 0.13,
              const Color(0xFFF2EDEA));
        }
    }
  }

  @override
  bool shouldRepaint(_SwipePainter old) => old.t != t;
}
