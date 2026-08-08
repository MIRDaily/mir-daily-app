import 'dart:math' as math;

import 'package:flutter/material.dart';

/// "G" multicolor de Google dibujada a mano (sin assets externos).
class GoogleLogo extends StatelessWidget {
  final double size;

  const GoogleLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.22;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    double deg(double d) => d * math.pi / 180;

    // Arcos del anillo (aproximación del logo oficial)
    paint.color = _red; // superior
    canvas.drawArc(rect, deg(-200), deg(110), false, paint);
    paint.color = _yellow; // izquierda-abajo
    canvas.drawArc(rect, deg(95), deg(70), false, paint);
    paint.color = _green; // inferior-derecha
    canvas.drawArc(rect, deg(28), deg(70), false, paint);
    paint.color = _blue; // derecha (hasta la barra)
    canvas.drawArc(rect, deg(-12), deg(42), false, paint);

    // Barra horizontal azul de la G
    final barPaint = Paint()..color = _blue;
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.5,
        size.height * 0.5 - stroke / 2,
        size.width * 0.5,
        stroke,
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
