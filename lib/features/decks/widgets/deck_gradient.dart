/* ════════════════════════════════════════════════════════════════════════
   Portada de un mazo: los mismos gradientes que la web.

   Portado de `src/components/studio/deckUi.tsx` (DECK_GRADIENTS +
   DeckBannerGradient). Los HEX son EXACTAMENTE los mismos a propósito: el
   preset se guarda en `decks.banner_gradient`, así que el mazo que el usuario
   pinta de "Noche Azul" en la web tiene que verse igual aquí.

   La composición también es la misma: un fondo del tono claro y encima dos
   elipses SÓLIDAS mucho más grandes que la tarjeta, desenfocadas. Es lo que
   da la frontera curva y limpia entre tonos; un degradado radial que se
   desvanece difumina el color en vez de dejar el arco.

   En la web el desenfoque es un `filter: blur(38px)` sobre un div; aquí es un
   [MaskFilter] sobre la propia elipse — mismo resultado visual y mucho más
   barato que montar una capa aparte para desenfocarla entera.
═══════════════════════════════════════════════════════════════════════════ */
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../shared/sticker/sticker.dart';
import '../../../shared/sticker/textures.dart';

/// Un preset de portada: tres tonos (claro / oscuro / medio) y su nombre.
class DeckGradient {
  final String label;
  final Color light;
  final Color dark;
  final Color mid;

  const DeckGradient({
    required this.label,
    required this.light,
    required this.dark,
    required this.mid,
  });
}

/// Los ocho presets, en el mismo orden que la web (los dos azules los añadió
/// el usuario desde un prototipo propio y se incorporaron el 24/08/2026).
const Map<String, DeckGradient> kDeckGradients = {
  'apricot': DeckGradient(
    label: 'Albaricoque',
    light: Color(0xFFFFDAB9),
    dark: Color(0xFF4E2C23),
    mid: Color(0xFFE2725B),
  ),
  'slate': DeckGradient(
    label: 'Pizarra',
    light: Color(0xFFE5E4E2),
    dark: Color(0xFF0A0A0A),
    mid: Color(0xFF536878),
  ),
  'ember': DeckGradient(
    label: 'Brasa',
    light: Color(0xFFFFD700),
    dark: Color(0xFF800020),
    mid: Color(0xFFFF4500),
  ),
  'violet': DeckGradient(
    label: 'Violeta',
    light: Color(0xFFE6E6FA),
    dark: Color(0xFF240A24),
    mid: Color(0xFF9932CC),
  ),
  'inferno': DeckGradient(
    label: 'Carmesí',
    light: Color(0xFFFAFBFD),
    dark: Color(0xFFAA0003),
    mid: Color(0xFFBFB4DC),
  ),
  'sage': DeckGradient(
    label: 'Salvia',
    light: Color(0xFFF0E5DE),
    dark: Color(0xFF6F1D1B),
    mid: Color(0xFFADBDAB),
  ),
  'blueMist': DeckGradient(
    label: 'Bruma Azul',
    light: Color(0xFFEEF5F8),
    dark: Color(0xFF1D3144),
    mid: Color(0xFF7AA7C7),
  ),
  'blueNight': DeckGradient(
    label: 'Noche Azul',
    light: Color(0xFFC8D8E6),
    dark: Color(0xFF050B16),
    mid: Color(0xFF193B61),
  ),
};

const String kDefaultDeckGradient = 'apricot';

/// Ids en orden estable, para el selector.
const List<String> kDeckGradientIds = [
  'apricot',
  'slate',
  'ember',
  'violet',
  'inferno',
  'sage',
  'blueMist',
  'blueNight',
];

/// Cae al preset por defecto ante cualquier valor que no conozcamos — es lo
/// que hace que el mazo automático de fallos (al que nunca se le guarda
/// gradiente) salga siempre en albaricoque, igual que en la web.
String normalizeDeckGradient(String? id) =>
    kDeckGradients.containsKey(id) ? id! : kDefaultDeckGradient;

DeckGradient deckGradientOf(String? id) =>
    kDeckGradients[normalizeDeckGradient(id)]!;

/* ─── Geometría de las bandas ──────────────────────────────────────────── */

class _Band {
  /// 'mid' o 'dark'. El claro es el fondo, no una banda.
  final bool isDark;

  /// Caja de la elipse, en fracción de la tarjeta (se sale por todos lados).
  final double left, top, width, height;

  /// Fotogramas del vaivén. x/y en fracción de la PROPIA caja (como los % de
  /// `transform: translate` en CSS), rotación en grados.
  final List<double> driftX, driftY, rotate, scale;

  /// Segundos de un recorrido de ida (el de vuelta dura lo mismo).
  final double duration;

  /// Retardo inicial, para que las dos bandas no vayan a la vez.
  final double delay;

  const _Band({
    required this.isDark,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.driftX,
    required this.driftY,
    required this.rotate,
    required this.scale,
    required this.duration,
    required this.delay,
  });
}

// Se pintan en orden: primero el medio, y encima el oscuro. Las elipses no
// son enormes de más: si se pasan de alto, su borde cruza la tarjeta casi
// recto y se pierde la curva; estas alturas dejan ver el arco.
const List<_Band> _kBands = [
  _Band(
    isDark: false,
    left: 0.30,
    top: -1.15,
    width: 2.05,
    height: 3.30,
    driftX: [0, -0.04, 0.02],
    driftY: [0, 0.03, -0.02],
    rotate: [-9, -3, -7],
    scale: [1, 1.06, 0.98],
    duration: 10.5,
    delay: 0,
  ),
  _Band(
    isDark: true,
    left: 0.76,
    top: -1.35,
    width: 2.05,
    height: 3.70,
    driftX: [0, 0.04, -0.02],
    driftY: [0, -0.04, 0.02],
    rotate: [7, 2, 5],
    scale: [1, 1.05, 0.99],
    duration: 8.5,
    delay: 1.2,
  ),
];

/// Periodo que cierra el ciclo de las DOS bandas a la vez: 21 s (ida y vuelta
/// de la primera) × 17 s (la de la segunda). Así el controlador puede dar la
/// vuelta sin que se vea ningún salto.
const double _kCyclePeriod = 357;

/// Interpola los tres fotogramas de un vaivén. [t] va de 0 a 1 en la ida.
double _keyframe(List<double> frames, double t) {
  if (t <= 0.5) return frames[0] + (frames[1] - frames[0]) * (t * 2);
  return frames[1] + (frames[2] - frames[1]) * ((t - 0.5) * 2);
}

/// Fase de ida y vuelta (0→1→0) de una banda en el segundo [seconds].
double _bandPhase(double seconds, _Band band) {
  final cycles = (seconds - band.delay) / band.duration;
  var p = cycles % 2.0;
  if (p < 0) p += 2.0;
  return p <= 1 ? p : 2 - p;
}

/// Desenfoque equivalente al `filter: blur(38px)` de la web, escalado con el
/// alto de la caja: la misma pieza sirve para una portada de 150 px y para una
/// tarjeta de lista, y la frontera curva tiene que verse igual de suave en
/// las dos.
double _sigmaFor(double height) => (height * 0.17).clamp(8.0, 44.0);

/* ─── Caché de fondos ya pintados ──────────────────────────────────────────
   Un desenfoque gaussiano de este tamaño es de lo más caro que se le puede
   pedir a la GPU, y aquí se repetía por CADA tarjeta de la galería — y en
   CADA fotograma de la portada animada. Medido con
   `test/deck_gradient_bench_test.dart`: 4x lo que costaba la cartulina teñida
   que había antes, y al pulsar una tarjeta el cambio de escala invalida la
   caché de rasterizado, así que se volvía a desenfocar varias veces por toque.

   Como el resultado es siempre el mismo para un preset y un tamaño dados, se
   pinta UNA vez a un cuarto de resolución y después solo se estira: una imagen
   ya borrosa ampliada es indistinguible de la original, porque no tiene
   detalle fino que perder. Es lo mismo que hace el navegador con el
   `filter: blur` de la web, que tampoco se recalcula al mover el div.
─────────────────────────────────────────────────────────────────────────── */
const double _kSnapshotScale = 0.25;
const int _kSnapshotCacheMax = 24;

final Map<String, ui.Image> _snapshotCache = {};
final List<String> _snapshotOrder = [];

/// Cuántas veces se ha pintado un fondo y cuántas ha habido que desenfocar de
/// verdad. Solo los usa `test/deck_gallery_bench_test.dart`: si al hacer
/// scroll suben los pintados pero NO los desenfoques, la caché funciona.
int debugDeckGradientPaints = 0;
int debugDeckGradientBlurs = 0;

/// Redondea el tamaño a múltiplos de 8 px para que dos tarjetas de alto casi
/// igual compartan la misma imagen en vez de generar una cada una.
Size _quantize(Size size) => Size(
      math.max(8, (size.width / 8).ceil() * 8).toDouble(),
      math.max(8, (size.height / 8).ceil() * 8).toDouble(),
    );

ui.Image _cachedSnapshot(String key, Size logical, void Function(Canvas) paint) {
  final hit = _snapshotCache[key];
  if (hit != null) {
    _snapshotOrder.remove(key);
    _snapshotOrder.add(key);
    return hit;
  }

  debugDeckGradientBlurs++;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // El desenfoque se escala solo con la matriz del canvas, así que pintar a
  // 1/4 da un sigma de 1/4 en píxeles reales — justo lo que corresponde a una
  // imagen de 1/4 de tamaño.
  canvas.scale(_kSnapshotScale);
  paint(canvas);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(
    math.max(1, (logical.width * _kSnapshotScale).round()),
    math.max(1, (logical.height * _kSnapshotScale).round()),
  );
  picture.dispose();

  _snapshotCache[key] = image;
  _snapshotOrder.add(key);
  if (_snapshotOrder.length > _kSnapshotCacheMax) {
    _snapshotCache.remove(_snapshotOrder.removeAt(0))?.dispose();
  }
  return image;
}

final Paint _stretch = Paint()..filterQuality = FilterQuality.low;

void _drawSnapshot(Canvas canvas, ui.Image image, Rect dst) {
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    dst,
    _stretch,
  );
}

/// Composición real, con el desenfoque de verdad. Solo se ejecuta al grabar
/// una imagen para la caché, nunca en el camino de pintado normal.
void _paintBandsDirect(
  Canvas canvas,
  Rect rect,
  DeckGradient palette,
  double t,
) {
  canvas.drawRect(rect, Paint()..color = palette.light);

  final blur = MaskFilter.blur(BlurStyle.normal, _sigmaFor(rect.height));

  for (final band in _kBands) {
    final w = rect.width * band.width;
    final h = rect.height * band.height;
    final box = Rect.fromLTWH(
      rect.left + rect.width * band.left + w * _keyframe(band.driftX, t),
      rect.top + rect.height * band.top + h * _keyframe(band.driftY, t),
      w,
      h,
    );

    final center = box.center;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(_keyframe(band.rotate, t) * math.pi / 180);
    canvas.scale(_keyframe(band.scale, t));
    canvas.translate(-center.dx, -center.dy);
    canvas.drawOval(
      box,
      Paint()
        ..color = band.isDark ? palette.dark : palette.mid
        ..maskFilter = blur,
    );
    canvas.restore();
  }
}

/// Versión animada: cada banda es una imagen desenfocada ya cacheada, y el
/// vaivén es solo una transformación encima — igual que en la web, donde el
/// navegador aplica `transform` sobre un div ya desenfocado sin recalcular el
/// desenfoque en cada fotograma.
void _paintBandsCached(
  Canvas canvas,
  Rect rect,
  String id,
  DeckGradient palette,
  double seconds,
) {
  canvas.drawRect(rect, Paint()..color = palette.light);

  final sigma = _sigmaFor(rect.height);
  // Margen para que el desenfoque no se corte contra el borde de la imagen.
  final pad = sigma * 3;

  for (var i = 0; i < _kBands.length; i++) {
    final band = _kBands[i];
    final t = _bandPhase(seconds, band);
    final w = rect.width * band.width;
    final h = rect.height * band.height;
    final padded = _quantize(Size(w + pad * 2, h + pad * 2));
    final color = band.isDark ? palette.dark : palette.mid;

    final image = _cachedSnapshot(
      'band:$id:$i:${padded.width.toInt()}x${padded.height.toInt()}:${sigma.round()}',
      padded,
      (c) => c.drawOval(
        Rect.fromLTWH(
          pad,
          pad,
          padded.width - pad * 2,
          padded.height - pad * 2,
        ),
        Paint()
          ..color = color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
      ),
    );

    final left = rect.left + rect.width * band.left + w * _keyframe(band.driftX, t);
    final top = rect.top + rect.height * band.top + h * _keyframe(band.driftY, t);
    final center = Rect.fromLTWH(left, top, w, h).center;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(_keyframe(band.rotate, t) * math.pi / 180);
    canvas.scale(_keyframe(band.scale, t));
    canvas.translate(-center.dx, -center.dy);
    _drawSnapshot(
      canvas,
      image,
      Rect.fromLTWH(left - pad, top - pad, w + pad * 2, h + pad * 2),
    );
    canvas.restore();
  }
}

/// Pinta el fondo completo (tono claro + las dos bandas desenfocadas) dentro
/// de [rect]. [seconds] fija el fotograma; 0 es el estado de reposo, que es
/// justo el que usa la galería congelada — y ese caso se resuelve con UNA
/// imagen cacheada de toda la composición, no repintando nada.
void paintDeckGradient(
  Canvas canvas,
  Rect rect,
  String id, {
  double seconds = 0,
}) {
  if (rect.isEmpty) return;
  debugDeckGradientPaints++;
  final palette = deckGradientOf(id);

  if (seconds == 0) {
    final size = _quantize(rect.size);
    final image = _cachedSnapshot(
      'still:$id:${size.width.toInt()}x${size.height.toInt()}',
      size,
      (c) => _paintBandsDirect(c, Offset.zero & size, palette, 0),
    );
    _drawSnapshot(canvas, image, rect);
    return;
  }

  _paintBandsCached(canvas, rect, id, palette, seconds);
}

/* ─── Piezas de UI ─────────────────────────────────────────────────────── */

/// Portada animada de un mazo, para la cabecera de su pantalla.
///
/// Con [animated] a false se queda en su primer fotograma — mismo aspecto
/// orgánico sin nada corriendo, que es como la web pinta la galería cuando
/// hay muchas tarjetas a la vez.
class DeckBannerGradient extends StatefulWidget {
  final String id;
  final bool animated;

  const DeckBannerGradient({super.key, required this.id, this.animated = true});

  @override
  State<DeckBannerGradient> createState() => _DeckBannerGradientState();
}

class _DeckBannerGradientState extends State<DeckBannerGradient>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (widget.animated) _start();
  }

  void _start() {
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_kCyclePeriod * 1000).round()),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant DeckBannerGradient old) {
    super.didUpdateWidget(old);
    if (widget.animated && _ctrl == null) {
      _start();
    } else if (!widget.animated && _ctrl != null) {
      _ctrl!.dispose();
      _ctrl = null;
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = normalizeDeckGradient(widget.id);
    final ctrl = _ctrl;

    if (ctrl == null) {
      return RepaintBoundary(
        child: CustomPaint(
          painter: _DeckGradientPainter(id: id, seconds: 0),
          size: Size.infinite,
        ),
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (context, _) => CustomPaint(
          painter: _DeckGradientPainter(
            id: id,
            // Nunca exactamente 0: ese valor es el atajo de "quieto", que
            // pinta la composición entera de una imagen cacheada.
            seconds: ctrl.value * _kCyclePeriod + 0.0001,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _DeckGradientPainter extends CustomPainter {
  final String id;
  final double seconds;

  _DeckGradientPainter({required this.id, required this.seconds});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.clipRect(rect);
    paintDeckGradient(canvas, rect, id, seconds: seconds);
  }

  @override
  bool shouldRepaint(_DeckGradientPainter old) =>
      old.seconds != seconds || old.id != id;
}

/// El mismo fondo, pero como [Decoration] — así entra tal cual en el hueco de
/// `texture` de una [StickerCard] y hereda su recorte y su límite de
/// repintado, sin montar otra capa por tarjeta.
Decoration deckGradientTexture(String? id) {
  final resolved = normalizeDeckGradient(id);
  final palette = kDeckGradients[resolved]!;
  return TextureDecoration(
    background: palette.light,
    identity: 'deckGradient:$resolved',
    painter: (canvas, rect) => paintDeckGradient(canvas, rect, resolved),
  );
}

/// Muestra circular de un preset, para el selector.
class DeckGradientSwatch extends StatelessWidget {
  final String id;
  final double size;
  final bool selected;

  const DeckGradientSwatch({
    super.key,
    required this.id,
    this.size = 34,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = deckGradientOf(id);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: kInk, width: selected ? 3 : 2),
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 0.9,
          colors: [palette.light, palette.mid, palette.dark],
          stops: const [0, 0.55, 1],
        ),
        boxShadow: selected ? inkShadow(2) : const [],
      ),
    );
  }
}

/// Insignia de dominio para la esquina de la portada: disco blanco con borde
/// de tinta, el anillo de progreso y el % dentro. Es la traducción de
/// `DeckMasteryBadge`.
///
/// [percent] a null cuando aún no hay datos suficientes (menos de 25
/// respuestas en el mazo): el anillo se queda apagado y se pinta un guion.
class DeckMasteryBadge extends StatelessWidget {
  final int? percent;

  const DeckMasteryBadge({super.key, required this.percent});

  @override
  Widget build(BuildContext context) {
    final known = percent != null;
    final value = known ? (percent! / 100).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kInk, width: 2),
        boxShadow: inkShadow(3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: const Duration(milliseconds: 900),
              curve: kEaseOut,
              builder: (context, v, _) => CustomPaint(
                painter: _RingPainter(v),
                child: Center(
                  child: Text(
                    known ? '${percent!}%' : '–',
                    style: const TextStyle(
                      color: kInk,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'DOMINIO',
            style: TextStyle(
              color: kMuted,
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;

  _RingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height)
        .deflate(stroke / 2 + 1);

    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = const Color(0xFFEFEAE7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    if (value <= 0) return;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..color = kAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}
