/* ════════════════════════════════════════════════════════════════════════
   El marco de ficha: la "skin" de la insignia de nivel.

   La insignia no es un cuadrado de color: es una ficha de cartón de la misma
   familia visual que el carné del perfil —fondo crema, filo dorado y un
   cosido de puntos por dentro—. Se dibuja con un CustomPainter y no con una
   imagen: así escala a cualquier tamaño sin pixelarse y no gasta un asset.

   DOS COSAS QUE NO SON OPCIONALES:

   1. TODO el contenido tiene que caber DENTRO del cosido de puntos, o sea
      dentro del 77,3 % central. Por eso los cuerpos de letra salen de una
      proporción del lado y no de valores fijos, y por eso el nivel 100 baja de
      cuerpo: con tres cifras es el caso apurado.

   2. La cifra NO va en el color puro del rango. Esos colores se eligieron para
      pintar sobre blanco, y sobre el crema del marco el gris de Novato —el que
      ve todo el mundo el primer día— se queda en 2,7:1 de contraste, por
      debajo del mínimo. Arrimándolo un 28 % a la tinta sube a 3,98:1.
═══════════════════════════════════════════════════════════════════════════ */
import 'package:flutter/material.dart';

import '../../../shared/sticker/sticker.dart';

/// Crema del cartón.
const Color _kFondo = Color(0xFFF5EBCE);

/// Dorado del filo exterior.
const Color _kFilo = Color(0xFFDEBB7E);

/// Terracota del cosido.
const Color _kCosido = Color(0xFFC4856A);

/// Marrón cálido del rótulo. El color del rango se reserva para la cifra: a
/// 9 px, un gris de rango sobre crema se lee mal.
const Color _kRotulo = Color(0xFF7A5943);

/// Del hueco total, cuánto ocupa la zona segura de dentro del cosido.
const double _kDentro = 0.75;

/// Arrima [color] a la tinta del kit. Ver el punto 2 de la cabecera.
Color haciaLaTinta(Color color, [double cuanto = 0.28]) =>
    Color.lerp(color, kInk, cuanto)!;

class MarcoNivel extends StatelessWidget {
  /// Nivel a rotular.
  final int nivel;

  /// Lado en píxeles. 64 en la tarjeta del perfil, 96 en la celebración.
  final double tamano;

  /// Color del rango. Solo para la cifra, y ya mezclado hacia la tinta.
  final Color color;

  const MarcoNivel({
    super.key,
    required this.nivel,
    required this.tamano,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final rotulo = tamano * 0.13 < 9 ? 9.0 : tamano * 0.13;
    // Con tres cifras (el nivel 100, el último) el cuerpo baja: medido, un
    // "100" al 0,36 dejaba 3,6 px de aire hasta el cosido y eso ya se lee como
    // que roza. Al 0,30 respira. Es el único caso, no merece más lógica.
    final cifra = tamano * (nivel >= 100 ? 0.30 : 0.36);

    return SizedBox(
      width: tamano,
      height: tamano,
      child: CustomPaint(
        painter: const _MarcoPainter(),
        child: Center(
          child: SizedBox(
            width: tamano * _kDentro,
            height: tamano * _kDentro,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'NIVEL',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: rotulo,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: rotulo * 0.14,
                    color: _kRotulo,
                  ),
                ),
                Text(
                  '$nivel',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: cifra,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: haciaLaTinta(color),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MarcoPainter extends CustomPainter {
  const _MarcoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final l = size.shortestSide;

    // El recuadro exterior deja un respiro para que el filo no se corte: va del
    // 4,55 % al 95,45 % del hueco, con radio del 10 % de su propio lado.
    final lado = l * 0.9091;
    final marco = Rect.fromLTWH(l * 0.0455, l * 0.0455, lado, lado);
    final rrect = RRect.fromRectAndRadius(marco, Radius.circular(lado * 0.10));

    canvas.drawRRect(rrect, Paint()..color = _kFondo);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = _kFilo
        ..style = PaintingStyle.stroke
        ..strokeWidth = l * 0.0227
        ..strokeJoin = StrokeJoin.round,
    );

    // El cosido de puntos, del 11,36 % al 88,64 %. Es el límite: nada de lo que
    // se escriba puede salirse de aquí.
    final ladoInterior = l * 0.7727;
    final interior = RRect.fromRectAndRadius(
      Rect.fromLTWH(l * 0.1136, l * 0.1136, ladoInterior, ladoInterior),
      Radius.circular(ladoInterior * 0.0784),
    );

    // Guion 7 / hueco 5 a escala 132, que es la del original.
    final escala = l / 132;
    _dibujarPunteado(
      canvas,
      Path()..addRRect(interior),
      guion: 7 * escala,
      hueco: 5 * escala,
      pincel: Paint()
        ..color = _kCosido
        ..style = PaintingStyle.stroke
        ..strokeWidth = l * 0.019
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Flutter no tiene `strokeDasharray`: hay que trocear el trazado a mano
  /// recorriéndolo con sus métricas.
  static void _dibujarPunteado(
    Canvas canvas,
    Path camino, {
    required double guion,
    required double hueco,
    required Paint pincel,
  }) {
    if (guion <= 0 || hueco <= 0) return;
    for (final metrica in camino.computeMetrics()) {
      var d = 0.0;
      while (d < metrica.length) {
        final hasta = d + guion;
        canvas.drawPath(
          metrica.extractPath(d, hasta.clamp(0.0, metrica.length)),
          pincel,
        );
        d = hasta + hueco;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MarcoPainter oldDelegate) => false;
}
