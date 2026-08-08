import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Las ilustraciones animadas de las tarjetas del Studio, portadas de la web
/// (`MazosHoverArt` y `SimulacrosHoverArt`) para sustituir a los iconos planos.
///
/// En la web la animación se dispara al pasar el ratón por encima. En el móvil
/// no hay ratón, así que se anima sola: los mazos rotan sus cartas en bucle y
/// las hojas del simulacro respiran abriendo y cerrando el abanico. Lo que se
/// conserva es el dibujo y el gesto, no el disparador.

// ============================================================================
// Mazos: tres cartas de pregunta que van rotando
// ============================================================================

class DeckCardArt extends StatefulWidget {
  final double size;

  const DeckCardArt({super.key, this.size = 58});

  @override
  State<DeckCardArt> createState() => _DeckCardArtState();
}

class _DeckCardArtState extends State<DeckCardArt>
    with SingleTickerProviderStateMixin {
  /// Un ciclo completo: la carta de delante se va al fondo y las otras avanzan.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  // Sitio de cada carta en el abanico: la de delante centrada y recta, y las de
  // detrás desplazadas, giradas y más pequeñas. Son los mismos valores que las
  // variantes `front`/`mid`/`back` de la web.
  static const List<Offset> _offsets = [
    Offset(0, 0),
    Offset(0.10, 0.05),
    Offset(0.20, 0.10),
  ];
  static const List<double> _turns = [-0.02, -0.10, -0.18];
  static const List<double> _scales = [1.0, 0.9, 0.8];
  static const List<double> _fades = [1.0, 0.85, 0.6];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // Se avanza un puesto por ciclo, con un tramo de reposo para que se
          // vea la baraja quieta antes de la siguiente rotación.
          final t = Curves.easeInOutCubic
              .transform(((_c.value - 0.55) / 0.45).clamp(0.0, 1.0));

          // Se pintan de la más pequeña a la más grande, es decir, del fondo
          // hacia delante. Hay que recalcularlo en cada frame: la carta que se
          // va al fondo tiene que dejar de estar por encima a mitad del giro, y
          // con un orden fijo se quedaba pegada delante.
          final layers = [0, 1, 2]
            ..sort((a, b) => _scaleOf(a, t).compareTo(_scaleOf(b, t)));

          return Stack(
            clipBehavior: Clip.none,
            children: [for (final layer in layers) _buildCard(layer, t)],
          );
        },
      ),
    );
  }

  /// Puesto de destino de cada carta: la de delante se va al fondo y las otras
  /// avanzan un sitio.
  static int _targetOf(int layer) => (layer + 2) % 3;

  double _scaleOf(int layer, double t) {
    final to = _targetOf(layer);
    return _scales[layer] + (_scales[to] - _scales[layer]) * t;
  }

  Widget _buildCard(int layer, double t) {
    final from = layer;
    final to = _targetOf(layer);

    final offset = Offset.lerp(_offsets[from], _offsets[to], t)!;
    final turn = _turns[from] + (_turns[to] - _turns[from]) * t;
    final scale = _scaleOf(layer, t);
    final fade = _fades[from] + (_fades[to] - _fades[from]) * t;

    return Positioned.fill(
      key: ValueKey(layer),
      child: FractionalTranslation(
        translation: offset,
        child: Transform.rotate(
          angle: turn * math.pi,
          // La baraja gira desde su base, como en la web.
          alignment: Alignment.bottomCenter,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: CustomPaint(painter: _QuestionCardPainter()),
            ),
          ),
        ),
      ),
    );
  }
}

/// La carta de pregunta del icono de Mazos. Traducción directa del SVG de la
/// web (`QuestionCardIcon`, viewBox 720×620), reescalada a la caja disponible.
class _QuestionCardPainter extends CustomPainter {
  static const double _vbW = 720;
  static const double _vbH = 620;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _vbW;
    double x(double v) => v * k;
    double y(double v) => v * (size.height / _vbH);

    Rect box(double a, double b, double w, double h) =>
        Rect.fromLTWH(x(a), y(b), x(w), y(h));

    // Cuerpo de la carta, con su sombra.
    final card = RRect.fromRectAndRadius(
      box(185, 115, 350, 390),
      Radius.circular(x(34)),
    );
    canvas.drawRRect(
      card.shift(Offset(0, y(14))),
      Paint()
        ..color = AppColors.textPrimary.withValues(alpha: 0.15)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, x(14)),
    );
    canvas.drawRRect(card, Paint()..color = Colors.white);
    canvas.drawRRect(
      card,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = x(8)
        ..color = AppColors.textPrimary,
    );

    // Globo con la interrogación.
    canvas.drawCircle(
      Offset(x(360), y(225)),
      x(52),
      Paint()..color = AppColors.primary,
    );
    final hook = Path()
      ..moveTo(x(340), y(211))
      ..cubicTo(x(343), y(190), x(377), y(184), x(388), y(203))
      ..cubicTo(x(399), y(224), x(371), y(234), x(371), y(251));
    canvas.drawPath(
      hook,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = x(7)
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(x(371), y(269)),
      x(5),
      Paint()..color = Colors.white,
    );

    // Renglones del enunciado.
    void line(double a, double b, double w, double h, Color c) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(box(a, b, w, h), Radius.circular(x(h / 2))),
        Paint()..color = c,
      );
    }

    line(245, 330, 230, 18, const Color(0xFFDCD5D1));
    line(245, 366, 175, 15, const Color(0xFFC7BDB8));

    // La opción marcada.
    canvas.drawCircle(
      Offset(x(255), y(430)),
      x(14),
      Paint()..color = AppColors.primary,
    );
    canvas.drawCircle(
      Offset(x(255), y(430)),
      x(14),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = x(5)
        ..color = AppColors.textPrimary,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x(247), y(430))
        ..lineTo(x(254), y(437))
        ..lineTo(x(267), y(421)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = x(5)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
    line(290, 421, 145, 16, const Color(0xFFC7BDB8));
  }

  @override
  bool shouldRepaint(_QuestionCardPainter oldDelegate) => false;
}

// ============================================================================
// Simulacros: hojas de examen en abanico
// ============================================================================

class ExamSheetArt extends StatefulWidget {
  final double size;

  const ExamSheetArt({super.key, this.size = 58});

  @override
  State<ExamSheetArt> createState() => _ExamSheetArtState();
}

class _ExamSheetArtState extends State<ExamSheetArt>
    with SingleTickerProviderStateMixin {
  /// El abanico se abre y se cierra en bucle. En la web esto lo hacía el hover;
  /// aquí respira solo.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_c.value);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Las dos de detrás se abren en abanico; la de delante apenas se
              // mueve. Mismos ángulos que las variantes de la web.
              _sheet(turn: -0.30 * t, scale: 0.8, fade: 0.5 * t, outline: true),
              _sheet(turn: -0.16 * t, scale: 0.9, fade: 0.78 * t, outline: true),
              _sheet(turn: -0.03 * t, scale: 1, fade: 1, outline: false),
            ],
          );
        },
      ),
    );
  }

  Widget _sheet({
    required double turn,
    required double scale,
    required double fade,
    required bool outline,
  }) {
    return Positioned.fill(
      child: Transform.rotate(
        angle: turn * math.pi,
        // El abanico pivota por la esquina de abajo a la derecha, como en la
        // web (transformOrigin 82% 100%).
        alignment: const Alignment(0.64, 1),
        child: Transform.scale(
          scale: scale,
          alignment: const Alignment(0.64, 1),
          child: Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: CustomPaint(painter: _ExamSheetPainter(outline: outline)),
          ),
        ),
      ),
    );
  }
}

/// La hoja de examen del icono de Simulacros. Traducción del SVG de la web
/// (`ExamSheetIcon`, viewBox 720×760). En [outline] se pinta solo la silueta,
/// que es lo que la web usa para las hojas del fondo.
class _ExamSheetPainter extends CustomPainter {
  final bool outline;

  _ExamSheetPainter({required this.outline});

  static const double _vbW = 720;
  static const double _vbH = 760;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _vbW;
    double x(double v) => v * k;
    double y(double v) => v * (size.height / _vbH);

    Rect box(double a, double b, double w, double h) =>
        Rect.fromLTWH(x(a), y(b), x(w), y(h));

    void round(double a, double b, double w, double h, Color c, double r) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(box(a, b, w, h), Radius.circular(x(r))),
        Paint()..color = c,
      );
    }

    // La hoja.
    final sheet = RRect.fromRectAndRadius(
      box(135, 75, 420, 590),
      Radius.circular(x(30)),
    );
    if (!outline) {
      canvas.drawRRect(
        sheet.shift(Offset(0, y(16))),
        Paint()
          ..color = AppColors.textPrimary.withValues(alpha: 0.16)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, x(15)),
      );
    }
    canvas.drawRRect(sheet, Paint()..color = Colors.white);
    canvas.drawRRect(
      sheet,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = x(8)
        ..color = AppColors.textPrimary,
    );

    // Las del fondo van sin relleno: solo se ve su borde asomando.
    if (outline) return;

    round(190, 130, 235, 20, const Color(0xFFEAE4E2), 10);

    // Tres preguntas; la del medio, contestada.
    for (final (top, marked) in [(205.0, false), (310.0, true), (415.0, false)]) {
      round(185, top, 320, 78, const Color(0xFFF2EFED), 20);

      final dot = Offset(x(220), y(top + 39));
      canvas.drawCircle(
        dot,
        x(14),
        Paint()..color = marked ? AppColors.primary : Colors.white,
      );
      canvas.drawCircle(
        dot,
        x(14),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = x(5)
          ..color = AppColors.textPrimary,
      );
      if (marked) {
        canvas.drawPath(
          Path()
            ..moveTo(x(212), y(top + 39))
            ..lineTo(x(219), y(top + 46))
            ..lineTo(x(232), y(top + 30)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = x(5)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.white,
        );
      }

      round(255, top + 20, 190, 15, const Color(0xFFDCD5D1), 7.5);
      round(255, top + 45, 150, 13, const Color(0xFFC7BDB8), 6.5);
    }

    // El pie, con el botón de corregir.
    round(205, 545, 280, 64, const Color(0xFFFFF0EC), 20);
    canvas.drawCircle(
      Offset(x(240), y(577)),
      x(12),
      Paint()..color = AppColors.primary,
    );
    round(270, 567, 155, 18, const Color(0xFFE6B9AE), 9);
  }

  @override
  bool shouldRepaint(_ExamSheetPainter oldDelegate) =>
      oldDelegate.outline != outline;
}
