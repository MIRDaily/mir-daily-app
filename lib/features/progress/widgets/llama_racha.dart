/* ════════════════════════════════════════════════════════════════════════
   La llama de la racha.

   No es un icono de Material metido en un círculo naranja: es una llama
   dibujada a medida, con el borde de tinta del kit sticker, así que envejece
   con el resto de la app y no depende de la fuente de iconos.

   CAMBIA DE COLOR CON LA RACHA, y ese es el punto: el usuario ve que su fuego
   sube de temperatura sin leer un número. Los cortes son los mismos que los
   del multiplicador de XP a propósito, para que lo que ve concuerde con lo que
   gana: el día 30 el multiplicador toca su techo (×1,5) y la llama llega a su
   color final.
═══════════════════════════════════════════════════════════════════════════ */
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/sticker/sticker.dart';

@immutable
class AspectoLlama {
  /// Racha mínima para este aspecto.
  final int min;

  /// Cuerpo de la llama.
  final Color cuerpo;

  /// Corazón, la parte caliente de abajo.
  final Color corazon;

  const AspectoLlama(this.min, this.cuerpo, this.corazon);
}

/// Ceniza → ámbar → naranja → rojo vivo.
const List<AspectoLlama> kEscalaLlama = [
  AspectoLlama(0, Color(0xFFC9C3BE), Color(0xFFEAE4E2)),
  AspectoLlama(1, Color(0xFFEDB53F), Color(0xFFFBE2A0)),
  AspectoLlama(7, Color(0xFFEA8600), Color(0xFFFFCE7A)),
  AspectoLlama(15, Color(0xFFDE6A2B), Color(0xFFFFB067)),
  AspectoLlama(30, Color(0xFFC4655A), Color(0xFFF3A183)),
];

AspectoLlama aspectoDeRacha(int racha) {
  var out = kEscalaLlama.first;
  for (final e in kEscalaLlama) {
    if (racha >= e.min) out = e;
  }
  return out;
}

class LlamaRacha extends StatefulWidget {
  final int racha;

  /// Alto en píxeles; el ancho sale de la proporción del dibujo (28 × 34).
  final double size;

  const LlamaRacha({super.key, required this.racha, this.size = 28});

  @override
  State<LlamaRacha> createState() => _LlamaRachaState();
}

class _LlamaRachaState extends State<LlamaRacha>
    with SingleTickerProviderStateMixin {
  late final AnimationController _latido;

  @override
  void initState() {
    super.initState();
    _latido = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ajustar();
  }

  @override
  void didUpdateWidget(covariant LlamaRacha old) {
    super.didUpdateWidget(old);
    if (old.racha != widget.racha) _ajustar();
  }

  /// Una llama apagada no late, y con las animaciones desactivadas en el
  /// sistema tampoco: se queda quieta y se ve igual de bien.
  void _ajustar() {
    final viva = widget.racha > 0 &&
        !MediaQuery.disableAnimationsOf(context);
    if (viva && !_latido.isAnimating) {
      _latido.repeat();
    } else if (!viva && _latido.isAnimating) {
      _latido.stop();
      _latido.value = 0;
    }
  }

  @override
  void dispose() {
    _latido.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aspecto = aspectoDeRacha(widget.racha);
    return SizedBox(
      width: widget.size * 28 / 34,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _latido,
        builder: (context, _) => CustomPaint(
          painter: _LlamaPainter(aspecto: aspecto, fase: _latido.value),
        ),
      ),
    );
  }
}

class _LlamaPainter extends CustomPainter {
  final AspectoLlama aspecto;

  /// 0..1 del ciclo del latido.
  final double fase;

  const _LlamaPainter({required this.aspecto, required this.fase});

  /// El dibujo original va en una caja de 28 × 34.
  static const Size _base = Size(28, 34);

  /// El cuerpo: la lengua de fuego, con la punta ladeada para que no parezca
  /// una gota simétrica.
  static Path _cuerpo() => Path()
    ..moveTo(14, 1.5)
    ..cubicTo(17.2, 5.9, 16.1, 8.7, 14.4, 11.1)
    ..cubicTo(13.2, 12.8, 12.0, 14.3, 12.4, 16.2)
    ..cubicTo(12.7, 17.7, 14.0, 18.6, 15.3, 18.2)
    ..cubicTo(16.8, 17.7, 17.3, 16.0, 16.9, 14.0)
    ..cubicTo(19.5, 16.0, 21.5, 19.0, 21.5, 22.5)
    ..cubicTo(21.5, 27.7, 17.2, 31.5, 13.0, 31.5)
    ..cubicTo(8.8, 31.5, 4.5, 27.7, 4.5, 22.5)
    ..cubicTo(4.5, 17.9, 7.1, 15.3, 9.2, 12.5)
    ..cubicTo(11.6, 9.3, 13.2, 6.2, 14, 1.5)
    ..close();

  /// El corazón. Sin borde, para que lea como luz y no como una segunda pieza
  /// pegada encima.
  static Path _corazon() => Path()
    ..moveTo(14, 17.8)
    ..cubicTo(16.2, 19.6, 17.4, 21.8, 17.4, 24.0)
    ..cubicTo(17.4, 26.6, 15.8, 28.4, 14.0, 28.4)
    ..cubicTo(12.2, 28.4, 10.6, 26.6, 10.6, 24.0)
    ..cubicTo(10.6, 21.8, 11.8, 19.6, 14, 17.8)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.height / _base.height;

    // El latido va en el dibujo y pivota desde la BASE, no desde el centro:
    // una llama crece hacia arriba, no se hincha por igual en los dos sentidos.
    final t = fase * 2 * math.pi;
    final escalaY = 1 + 0.035 * (1 - math.cos(t)) / 2 * 2;
    final escalaX = 1 - 0.02 * (1 - math.cos(t)) / 2 * 2;

    canvas.save();
    canvas.translate(size.width / 2, size.height);
    canvas.scale(k * escalaX, k * escalaY);
    canvas.translate(-_base.width / 2, -_base.height);

    // El trazo de tinta va en coordenadas del dibujo, así que se compensa la
    // escala para que salga a 2 px reales sea cual sea el tamaño pedido.
    final grosor = 2 / (k * escalaX);

    canvas.drawPath(_cuerpo(), Paint()..color = aspecto.cuerpo);
    canvas.drawPath(
      _cuerpo(),
      Paint()
        ..color = kInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = grosor
        ..strokeJoin = StrokeJoin.round,
    );

    // El corazón respira en opacidad, medio ciclo por delante del cuerpo.
    final brillo = 0.85 + 0.15 * (1 - math.cos(t * 1.5)) / 2;
    canvas.drawPath(
      _corazon(),
      Paint()..color = aspecto.corazon.withValues(alpha: brillo),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LlamaPainter old) =>
      old.aspecto != aspecto || old.fase != fase;
}
