import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';

/// Hueco reservado para el próximo mazo del sistema.
///
/// Port del `ConstructionDeckPlaceholder` de la web: cuando el único mazo
/// automático es el de fallos, la galería enseña una tarjeta precintada con
/// cinta de obra. No es decoración — es la señal de que ahí va a aparecer algo
/// (el mazo rotatorio), y de que ese sitio no es del usuario.
class ConstructionDeckCard extends StatelessWidget {
  const ConstructionDeckCard({super.key});

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      margin: const EdgeInsets.only(bottom: 14),
      depth: 4,
      radius: 20,
      background: const Color(0xFFEDF2F6),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 118,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // La cinta cruza la tarjeta en diagonal, igual que en la web
            // (-17 grados, rayas amarillas y negras a 45).
            Positioned.fill(
              child: CustomPaint(painter: _HazardTapePainter()),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kInk, width: 2),
                boxShadow: inkShadow(3),
              ),
              child: const Text(
                '¡En construcción!',
                style: TextStyle(
                  color: kInk,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
            const Positioned(
              left: 14,
              bottom: 10,
              child: Text(
                'PRÓXIMAMENTE',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HazardTapePainter extends CustomPainter {
  static const _amarillo = Color(0xFFFACC15);
  static const _negro = Color(0xFF111827);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);

    // Banda ancha centrada y girada; se sale por los lados a propósito.
    const anguloBanda = -17 * math.pi / 180;
    final alto = size.height * 0.34;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(anguloBanda);

    final banda = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 1.6,
      height: alto,
    );

    canvas.drawRect(banda, Paint()..color = _amarillo);

    // Rayas a 45 grados dentro de la banda. Se dibujan como paralelogramos
    // recorridos de izquierda a derecha; el paso es el mismo de la web
    // (16 px de amarillo, 16 de negro).
    canvas.save();
    canvas.clipRect(banda);
    const paso = 32.0;
    final raya = Paint()..color = _negro;
    for (var x = banda.left - alto; x < banda.right + alto; x += paso) {
      final camino = Path()
        ..moveTo(x, banda.bottom)
        ..lineTo(x + alto, banda.top)
        ..lineTo(x + alto + paso / 2, banda.top)
        ..lineTo(x + paso / 2, banda.bottom)
        ..close();
      canvas.drawPath(camino, raya);
    }
    canvas.restore();

    // Filos de tinta arriba y abajo de la cinta.
    final filo = Paint()
      ..color = kInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(banda.topLeft, banda.topRight, filo);
    canvas.drawLine(banda.bottomLeft, banda.bottomRight, filo);

    canvas.restore();

    // Velo blanco: en la web es un `backdrop-blur`; aquí basta con bajarle el
    // contraste para que el cartel de encima se lea sin pelearse con la cinta.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_HazardTapePainter oldDelegate) => false;
}
