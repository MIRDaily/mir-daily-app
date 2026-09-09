/* ════════════════════════════════════════════════════════════════════════
   El nivel, montado sobre el icono de Perfil de la barra de navegación.

   En la web el aro acabó rodeando el avatar de la cabecera; aquí el
   equivalente natural es la pestaña de Perfil, porque es lo que pega el nivel
   a la identidad del usuario sin robarle un hueco a una barra ya llena.

   LA LECCIÓN QUE COSTÓ TIEMPO EN LA WEB: el aro tiene que caber DENTRO del
   sitio que ya ocupaba el icono, encogiéndolo, en vez de crecer por fuera. Si
   crece por fuera sube el alto de toda la barra y desplaza el resto.
═══════════════════════════════════════════════════════════════════════════ */
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/progress.dart';
import '../../../core/providers/progress_provider.dart';
import '../../../core/theme/levels.dart';

class AnilloNivel extends StatelessWidget {
  /// Lado que YA ocupaba el icono. El aro se dibuja dentro y el icono se
  /// encoge para dejarle sitio.
  final double lado;

  /// El icono, ya con su color y su escala.
  final Widget child;

  const AnilloNivel({super.key, required this.lado, required this.child});

  /// El progreso, o `null` si este aro se ha montado fuera del provider.
  ///
  /// La barra de navegación se pinta en sitios donde no siempre está el árbol
  /// entero —una prueba de widget, una vista suelta— y un adorno no puede
  /// tumbar la navegación. Es la misma decisión que en la web, donde
  /// `useProgressContext` devuelve un valor vacío fuera del provider.
  UserProgress? _progresoDe(BuildContext context) {
    try {
      return context.watch<ProgressProvider>().progress;
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _progresoDe(context);

    // Sin progreso (sesión recién abierta, o error) el icono se pinta tal
    // cual: mejor sin aro que con un aro a cero, que se leería como "vas por
    // 0". Y así la barra tampoco cambia de tamaño mientras carga.
    if (p == null) return SizedBox(width: lado, height: lado, child: child);

    final rango = rankForLevel(p.level);

    return SizedBox(
      width: lado,
      height: lado,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _AnilloPainter(
                fraccion: p.esTope ? 1 : p.fraccionNivel,
                color: rango.color,
              ),
            ),
          ),
          // El icono, encogido para caber dentro del aro.
          SizedBox(
            width: lado * 0.6,
            height: lado * 0.6,
            child: FittedBox(fit: BoxFit.contain, child: child),
          ),
          // El número, pegado al aro y con borde del color del fondo de la
          // barra para que se despegue del aro sea cual sea el color del rango.
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 15),
              height: 15,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: rango.color,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.6),
              ),
              child: Text(
                '${p.level}',
                style: const TextStyle(
                  fontSize: 8.5,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnilloPainter extends CustomPainter {
  final double fraccion;
  final Color color;

  const _AnilloPainter({required this.fraccion, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final grosor = size.shortestSide * 0.1;
    final radio = (size.shortestSide - grosor) / 2;
    final centro = size.center(Offset.zero);

    final pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(centro, radio, pincel..color = const Color(0xFFEAE4E2));

    if (fraccion <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: centro, radius: radio),
      -math.pi / 2,
      2 * math.pi * fraccion.clamp(0.0, 1.0),
      false,
      pincel..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _AnilloPainter old) =>
      old.fraccion != fraccion || old.color != color;
}
