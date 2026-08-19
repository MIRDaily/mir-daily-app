/* ════════════════════════════════════════════════════════════════════════
   Texturas del lenguaje visual.

   La regla de la casa: cada pantalla rediseñada añade **una** textura que
   explique la herramienta. En la web se pintan con `repeating-linear-gradient`
   (nunca imágenes) y aquí con un `Decoration` propio, que es el equivalente:
   se dibuja en cada repintado, escala a cualquier tamaño y no cuesta un asset.

   - papel rayado  → flashcards y mazos (una ficha de estudio de verdad)
   - papel milimetrado → electros (el papel del ECG)
   - carné plastificado → perfil (guilloche de documento acreditativo)
═══════════════════════════════════════════════════════════════════════════ */
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sticker.dart';

/// Base de las texturas: un `Decoration` que delega el pintado en una función.
/// Todas recortan a su propio rectángulo, así que se pueden meter dentro de
/// una [StickerCard] sin que se salgan de las esquinas.
class TextureDecoration extends Decoration {
  final Color background;
  final void Function(Canvas canvas, Rect rect) painter;

  /// Identidad para que Flutter no repinte de más cuando la decoración no ha
  /// cambiado: dos texturas del mismo tipo y color son la misma.
  final Object identity;

  const TextureDecoration({
    required this.background,
    required this.painter,
    required this.identity,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _TextureBoxPainter(this);

  @override
  bool operator ==(Object other) =>
      other is TextureDecoration &&
      other.background == background &&
      other.identity == identity;

  @override
  int get hashCode => Object.hash(background, identity);
}

class _TextureBoxPainter extends BoxPainter {
  final TextureDecoration decoration;

  _TextureBoxPainter(this.decoration);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size ?? Size.zero;
    if (size.isEmpty) return;
    final rect = offset & size;

    canvas.save();
    canvas.clipRect(rect);
    if (decoration.background.alpha != 0) {
      canvas.drawRect(rect, Paint()..color = decoration.background);
    }
    decoration.painter(canvas, rect);
    canvas.restore();
  }
}

/* ─── Utilidades de trazado ────────────────────────────────────────────── */

/// Dibuja un haz de líneas paralelas girado [degrees] grados, cubriendo todo
/// el rectángulo. Es la traducción de un `repeating-linear-gradient` en
/// diagonal: paso constante y sin costuras al cambiar de tamaño.
void _hatch(
  Canvas canvas,
  Rect rect, {
  required double degrees,
  required double step,
  required Color color,
  double width = 1,
}) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = width
    ..isAntiAlias = true;

  // Al girar, hace falta barrer más que el rectángulo para que no queden
  // esquinas sin rayar: la diagonal es la cota que siempre basta.
  final diagonal = math.sqrt(rect.width * rect.width + rect.height * rect.height);
  final half = diagonal / 2;

  canvas.save();
  canvas.translate(rect.center.dx, rect.center.dy);
  canvas.rotate(degrees * math.pi / 180);
  for (double y = -half; y <= half; y += step) {
    canvas.drawLine(Offset(-half, y), Offset(half, y), paint);
  }
  canvas.restore();
}

/// Rejilla recta (horizontales + verticales), anclada al origen del
/// rectángulo para que las líneas no bailen al hacer scroll.
void _grid(
  Canvas canvas,
  Rect rect, {
  required double step,
  required Color color,
  double width = 1,
  double offsetY = 0,
  bool vertical = true,
  bool horizontal = true,
}) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = width
    ..isAntiAlias = true;

  if (horizontal) {
    for (double y = rect.top + offsetY; y <= rect.bottom; y += step) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
  }
  if (vertical) {
    for (double x = rect.left; x <= rect.right; x += step) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
    }
  }
}

/// Mancha radial suave, para las viñetas del carné.
void _radial(
  Canvas canvas,
  Rect rect, {
  required Alignment at,
  required Color color,
  required double radiusFactor,
}) {
  final center = at.withinRect(rect);
  final radius = math.max(rect.width, rect.height) * radiusFactor;
  final paint = Paint()
    ..shader = RadialGradient(
      colors: [color, color.withOpacity(0)],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
  canvas.drawCircle(center, radius, paint);
}

/* ─── Texturas ─────────────────────────────────────────────────────────── */

/// Cartulina rayada: renglones como los de una ficha de estudio.
/// Equivale al `ruledPaper()` de `components/flashcards/ui.tsx`.
Decoration ruledPaper({
  Color line = const Color(0x297D8A96), // rgba(125,138,150,0.16)
  double step = 28,
  Color background = Colors.white,
}) {
  return TextureDecoration(
    background: background,
    identity: 'ruled:$step:${line.value}',
    painter: (canvas, rect) => _grid(
      canvas,
      rect,
      step: step,
      color: line,
      offsetY: 6,
      vertical: false,
    ),
  );
}

/// Variante teñida con el color de la asignatura, para las caras de tarjeta.
/// Equivale al `tintedPaper()` de la web: renglones más tenues y un barrido
/// diagonal del tinte que se apaga a media tarjeta.
Decoration tintedPaper(Color tint, {double step = 30}) {
  return TextureDecoration(
    background: Colors.white,
    identity: 'tinted:$step:${tint.value}',
    painter: (canvas, rect) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint.withOpacity(0.08), tint.withOpacity(0)],
            stops: const [0, 0.55],
          ).createShader(rect),
      );
      _grid(
        canvas,
        rect,
        step: step,
        color: const Color(0x217D8A96), // rgba(125,138,150,0.13)
        offsetY: 8,
        vertical: false,
      );
    },
  );
}

/// Papel milimetrado del ECG: cuadrícula fina y, cada cinco, una más marcada.
/// Es la textura con la que nació el lenguaje, en la Academia de Electros.
Decoration graphPaper({
  Color tint = kAccent,
  double step = 13,
  Color background = Colors.white,
}) {
  return TextureDecoration(
    background: background,
    identity: 'graph:$step:${tint.value}',
    painter: (canvas, rect) {
      _grid(canvas, rect, step: step, color: tint.withOpacity(0.13));
      _grid(
        canvas,
        rect,
        step: step * 5,
        color: tint.withOpacity(0.26),
        width: 1.5,
      );
    },
  );
}

/// Carné plastificado: guilloche cruzado (el entramado de líneas finas de los
/// documentos acreditativos) más una viñeta tenue del color de marca.
/// Equivale al `laminatedPaper()` de `components/Profile/ui.tsx`.
Decoration laminatedPaper({Color tint = kAccent}) {
  return TextureDecoration(
    background: Colors.white,
    identity: 'laminated:${tint.value}',
    painter: (canvas, rect) {
      // El fondo de papel: blanco que se calienta hacia la esquina inferior.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFFFF), Color(0xFFFFFCFB), Color(0xFFFFF4EF)],
            stops: [0, 0.55, 1],
          ).createShader(rect),
      );
      // Las dos familias de líneas que se cruzan y forman el guilloche.
      _hatch(canvas, rect, degrees: 56, step: 10, color: tint.withOpacity(0.10));
      _hatch(canvas, rect, degrees: -56, step: 10, color: tint.withOpacity(0.08));
      // Y las dos manchas que le dan cuerpo, en esquinas opuestas.
      _radial(canvas, rect,
          at: const Alignment(0.68, -0.88),
          color: tint.withOpacity(0.18),
          radiusFactor: 0.42);
      _radial(canvas, rect,
          at: const Alignment(-0.92, 0.92),
          color: tint.withOpacity(0.12),
          radiusFactor: 0.38);
    },
  );
}

/* ─── Código de barras del carné ───────────────────────────────────────── */

/// FNV-1a: barajado barato y estable para derivar el código del id.
/// Mismo algoritmo que en la web, así que el usuario ve el mismo código en
/// los dos sitios.
int _hashSeed(String seed) {
  var hash = 2166136261;
  for (var i = 0; i < seed.length; i++) {
    hash ^= seed.codeUnitAt(i);
    // En Dart los enteros son de 64 bits: hay que recortar a 32 a mano para
    // que el desbordamiento coincida con el `Math.imul` de JavaScript.
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  return hash & 0xFFFFFFFF;
}

/// Serie legible del carné, derivada del id del usuario.
String serialOf(String seed) {
  final base = _hashSeed(seed).toRadixString(36).toUpperCase();
  return base.padLeft(7, '0').substring(math.max(0, base.length - 7));
}

/// Anchos de las 42 barras, memorizados por semilla.
///
/// El usuario es siempre el mismo, así que esto se calcula una vez en toda la
/// vida de la app en vez de 42 hashes por cada build del perfil.
final Map<String, List<double>> _barCache = {};

List<double> _barsFor(String seed) => _barCache.putIfAbsent(
      seed,
      () => List<double>.generate(
        42,
        (i) => 1 + (_hashSeed('$seed:$i') % 3).toDouble(),
      ),
    );

/// Barras deterministas: el mismo usuario ve siempre su mismo código.
///
/// Va con un pintor y no con una fila de 84 `Container`: son unos pocos
/// rectángulos en un solo paso de pintado, y no un subárbol que recorrer.
class SerialBarcode extends StatelessWidget {
  final String seed;
  final double height;

  const SerialBarcode({super.key, required this.seed, this.height = 26});

  @override
  Widget build(BuildContext context) {
    final bars = _barsFor(seed);
    // Ancho exacto del dibujo: cada barra más 2 px de aire.
    final width = bars.fold<double>(0, (a, w) => a + w + 2);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(width, height),
        painter: _BarcodePainter(bars),
        isComplex: false,
      ),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  final List<double> bars;

  const _BarcodePainter(this.bars);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = kInk;
    var x = 0.0;
    for (var i = 0; i < bars.length; i++) {
      if (i.isEven) {
        // Una de cada cinco barras llega arriba del todo: es lo que hace que
        // el código se lea como un código y no como una trama.
        final h = i % 5 == 0 ? size.height : size.height - 5;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, size.height - h, bars[i], h),
            const Radius.circular(1),
          ),
          paint,
        );
      }
      x += bars[i] + 2;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => !identical(old.bars, bars);
}

/// Brillo del plastificado: una banda de luz que cruza el carné muy de vez en
/// cuando, como cuando giras un documento bajo una lámpara.
///
/// Es la única animación en bucle del perfil, así que se porta bien: para
/// cuando se lo piden (diálogo abierto encima), respeta que el sistema tenga
/// las animaciones reducidas y va dentro de su propio límite de repintado,
/// para no arrastrar consigo el guilloche de debajo en cada fotograma.
class LaminateSheen extends StatefulWidget {
  final bool paused;

  const LaminateSheen({super.key, this.paused = false});

  @override
  State<LaminateSheen> createState() => _LaminateSheenState();
}

class _LaminateSheenState extends State<LaminateSheen>
    with SingleTickerProviderStateMixin {
  // 1,6 s de barrido + 8,4 s de espera. Antes cruzaba en 3,2 s y con una
  // banda ancha y muy blanca: se veía el rectángulo, no el reflejo.
  static const _sweep = 1.6 / 10.0;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 10000),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.paused) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant LaminateSheen old) {
    super.didUpdateWidget(old);
    if (widget.paused) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.paused || MediaQuery.of(context).disableAnimations) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: ClipRect(
        child: RepaintBoundary(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              // La banda se inclina, así que tiene que sobresalir por arriba y
              // por abajo o dejaría dos triángulos sin cubrir.
              final band = SizedBox(
                width: w * 0.26,
                height: h * 2.4,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0x14E8A598),
                        Color(0x59FFFFFF),
                        Color(0x14E8A598),
                        Color(0x00FFFFFF),
                      ],
                      stops: [0, 0.34, 0.5, 0.66, 1],
                    ),
                  ),
                ),
              );

              return AnimatedBuilder(
                animation: _ctrl,
                // La banda se construye UNA vez y solo se mueve: el
                // AnimatedBuilder no vuelve a montarla en cada fotograma.
                child: band,
                builder: (context, child) {
                  final t = _ctrl.value;
                  if (t > _sweep) return const SizedBox.shrink();
                  final p = Curves.easeInOutSine.transform(t / _sweep);
                  return Transform.translate(
                    offset: Offset(-w * 0.4 + p * w * 1.6, -h * 0.7),
                    child: Transform.rotate(
                      angle: 0.32,
                      child: child,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
