/* ════════════════════════════════════════════════════════════════════════
   Escaparate de la pestaña Premium.

   Enseña exactamente lo mismo que la versión anterior —el medallón, el
   "Próximamente", la descripción, las tres ventajas y el aviso de
   lanzamiento— pero contado con el lenguaje de pegatina del resto de la app
   (trazo de tinta, sombra dura, textura) y con una animación propia por
   pieza: una pantalla que todavía no se puede tocar no debería parecer un
   cartel muerto.

   Todas las animaciones son en bucle y baratas (un CustomPainter dentro de
   un RepaintBoundary) y se apagan solas si el sistema pide animaciones
   reducidas.
═══════════════════════════════════════════════════════════════════════════ */
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../../../shared/sticker/textures.dart';

// ============================================================================
// MEDALLÓN
// ============================================================================

/// Medallón dorado con un haz de rayos girando detrás y un halo que respira.
///
/// Es el icono grande de siempre, pero con la profundidad del sistema: disco
/// opaco, trazo de tinta y sombra dura. El relleno tiene que ser OPACO porque
/// lleva [inkShadow] debajo (ver `sticker.dart`).
class PremiumMedallion extends StatefulWidget {
  final double size;

  const PremiumMedallion({super.key, this.size = 96});

  @override
  State<PremiumMedallion> createState() => _PremiumMedallionState();
}

class _PremiumMedallionState extends State<PremiumMedallion>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  bool _running = false;

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Los bucles no arrancan en `initState`: hasta que no hay `MediaQuery` no
  /// se sabe si el sistema pide animaciones reducidas.
  void _sync(bool reduced) {
    if (reduced == !_running) return;
    _running = !reduced;
    if (reduced) {
      _spin.stop();
      _pulse.stop();
    } else {
      _spin.repeat();
      _pulse.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    _sync(reduced);

    final s = widget.size;
    final box = s * 1.62;

    return RepaintBoundary(
      child: SizedBox(
        width: box,
        height: box,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Haz de rayos: gira despacio y se desvanece por fuera, así que
            // no hay un borde duro que delate el cuadrado.
            AnimatedBuilder(
              animation: _spin,
              builder: (context, _) => CustomPaint(
                size: Size.square(box),
                painter: _RaysPainter(turns: _spin.value),
              ),
            ),
            // Halo que respira, justo por detrás del disco.
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_pulse.value);
                return Container(
                  width: s * (1.02 + 0.16 * t),
                  height: s * (1.02 + 0.16 * t),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.gold.withValues(alpha: 0.30 + 0.14 * t),
                        AppColors.gold.withValues(alpha: 0),
                      ],
                      stops: const [0.55, 1],
                    ),
                  ),
                );
              },
            ),
            // El disco. Relleno opaco (degradado sin alfa) porque debajo va
            // la sombra dura.
            Container(
              width: s,
              height: s,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.goldSoft,
                    AppColors.gold,
                    AppColors.primary,
                  ],
                  stops: [0, 0.52, 1],
                ),
                border: Border.all(color: kInk, width: 3),
                boxShadow: inkShadow(5),
              ),
              child: Icon(
                Icons.workspace_premium,
                size: s * 0.48,
                color: Colors.white,
              ),
            ),
            // Chispas: entran y salen desfasadas, para que el medallón nunca
            // se quede del todo quieto.
            for (final spark in _sparks)
              Align(
                alignment: spark.$1,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final phase = (_pulse.value + spark.$2) % 1.0;
                    final a = 0.25 + 0.75 * math.sin(phase * math.pi).abs();
                    return Icon(
                      Icons.auto_awesome_rounded,
                      size: spark.$3,
                      color: AppColors.gold.withValues(alpha: a),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// (posición, desfase, tamaño) de cada chispa.
  static const List<(Alignment, double, double)> _sparks = [
    (Alignment(0.86, -0.72), 0.0, 15),
    (Alignment(-0.9, 0.28), 0.37, 12),
    (Alignment(0.62, 0.88), 0.68, 11),
  ];
}

/// Rayos de sol dorados que salen del centro. Se pintan todos con un mismo
/// degradado radial: se desvanecen antes de llegar al borde, así que la caja
/// que los contiene no se ve.
class _RaysPainter extends CustomPainter {
  final double turns;

  /// Doce rayos: menos parecen aspas y más se emborronan al girar.
  static const int count = 12;

  const _RaysPainter({required this.turns});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    if (r <= 0) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: [
          AppColors.gold.withValues(alpha: 0),
          AppColors.gold.withValues(alpha: 0.34),
          AppColors.gold.withValues(alpha: 0),
        ],
        stops: const [0.34, 0.62, 1],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r));

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(turns * 2 * math.pi);

    const step = 2 * math.pi / count;
    const half = step * 0.30;
    final rect = Rect.fromCircle(center: Offset.zero, radius: r);

    for (var i = 0; i < count; i++) {
      final a = i * step;
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(math.cos(a - half) * r, math.sin(a - half) * r)
        ..arcTo(rect, a - half, half * 2, false)
        ..close();
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.turns != turns;
}

// ============================================================================
// CABECERA
// ============================================================================

/// Tarjeta de cabecera: medallón, distintivo, "Próximamente" y la descripción.
///
/// Se recoloca sola: en móvil el medallón va encima y el texto centrado
/// debajo; en cuanto hay ancho (tablet, o el móvil en horizontal) pasa a fila
/// y la tarjeta deja de ser una columna altísima.
class PremiumHeroCard extends StatelessWidget {
  final String badge;
  final String title;
  final String description;

  const PremiumHeroCard({
    super.key,
    required this.badge,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      depth: 6,
      radius: 26,
      padding: EdgeInsets.zero,
      texture: tintedPaper(AppColors.gold, step: 34),
      child: Stack(
        children: [
          // El brillo recorre la tarjeta entera; se recorta contra el radio
          // INTERIOR para no pintar sobre la mitad interna del trazo.
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: const CardShimmer(
                sweep: Duration(milliseconds: 1400),
                wait: Duration(milliseconds: 4200),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
            child: LayoutBuilder(
              builder: (context, c) {
                final row = c.maxWidth >= 440;
                if (row) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const PremiumMedallion(size: 104),
                      const SizedBox(width: 10),
                      // La descripción se acota a un ancho de lectura: a lo
                      // ancho de una tablet apaisada salían renglones de más
                      // de cien caracteres, imposibles de seguir.
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxWidth: 560),
                            child: _texts(centered: false),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const PremiumMedallion(size: 94),
                    const SizedBox(height: 6),
                    _texts(centered: true),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _texts({required bool centered}) {
    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        _PremiumBadge(text: badge),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
            fontSize: 30,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: kInk,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          description,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.5,
            color: kMuted,
            // Un pelo de fondo bajo el texto: la textura rayada le resta
            // legibilidad en las líneas más apretadas.
            backgroundColor: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _PremiumBadge extends StatelessWidget {
  final String text;

  const _PremiumBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: tinted(AppColors.gold, 0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kInk, width: 2),
        boxShadow: inkShadow(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium, size: 14, color: kInk),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
                color: kInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// VENTAJAS
// ============================================================================

/// Una de las tres ventajas. Mantiene título y descripción de siempre y les
/// pone delante una ilustración animada en vez del icono plano, igual que las
/// tarjetas del Studio.
class PremiumFeatureCard extends StatelessWidget {
  final String title;
  final String description;
  final String tag;
  final Color accent;
  final Widget art;

  const PremiumFeatureCard({
    super.key,
    required this.title,
    required this.description,
    required this.tag,
    required this.accent,
    required this.art,
  });

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      depth: 5,
      radius: 20,
      texture: tintedPaper(accent, step: 26),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Tinte OPACO: debajo va la sombra dura.
              color: tinted(accent, 0.22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kInk, width: 2),
              boxShadow: inkShadow(3),
            ),
            child: art,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        // Dos líneas: en la rejilla de tres columnas de una
                        // tablet, "Preguntas ilimitadas" más su etiqueta se
                        // pasaban por unos pocos píxeles y el título salía
                        // recortado como "Preguntas ilimitad...".
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kInk,
                          fontWeight: FontWeight.w900,
                          fontSize: 16.5,
                          height: 1.15,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        tag.toUpperCase(),
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 9,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    color: kMuted,
                    fontSize: 12.5,
                    height: 1.4,
                    backgroundColor: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ILUSTRACIONES DE LAS VENTAJAS
// ============================================================================

/// Base común: un bucle continuo que se apaga con las animaciones reducidas y
/// deja el dibujo en un fotograma fijo.
abstract class _LoopArt extends StatefulWidget {
  final Color accent;
  final double size;
  final Duration period;

  const _LoopArt({
    super.key,
    required this.accent,
    required this.size,
    required this.period,
  });
}

abstract class _LoopArtState<W extends _LoopArt> extends State<W>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.period);

  bool _running = false;

  CustomPainter painter(double t);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != !_running) {
      _running = !reduced;
      if (reduced) {
        _ctrl.stop();
      } else {
        _ctrl.repeat();
      }
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: painter(_ctrl.value),
        ),
      ),
    );
  }
}

/// Preguntas ilimitadas: un ∞ con un punto dándole vueltas.
class InfinityArt extends _LoopArt {
  const InfinityArt({
    super.key,
    required super.accent,
    super.size = 34,
    super.period = const Duration(milliseconds: 3200),
  });

  @override
  State<InfinityArt> createState() => _InfinityArtState();
}

class _InfinityArtState extends _LoopArtState<InfinityArt> {
  @override
  CustomPainter painter(double t) =>
      _InfinityPainter(t: t, accent: widget.accent);
}

class _InfinityPainter extends CustomPainter {
  final double t;
  final Color accent;

  const _InfinityPainter({required this.t, required this.accent});

  /// Lemniscata de Bernoulli: el ∞ de toda la vida, parametrizado para poder
  /// poner un punto EN la curva y no cerca de ella.
  Offset _p(double a, double u) {
    final d = 1 + math.sin(u) * math.sin(u);
    return Offset(a * math.cos(u) / d, a * math.sin(u) * math.cos(u) / d);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final a = size.width * 0.46;
    canvas.translate(size.width / 2, size.height / 2);

    final path = Path();
    const steps = 72;
    for (var i = 0; i <= steps; i++) {
      final p = _p(a, i / steps * 2 * math.pi);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..color = kInk,
    );

    final head = _p(a, t * 2 * math.pi);
    canvas.drawCircle(head, 4.2, Paint()..color = accent);
    canvas.drawCircle(
      head,
      4.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kInk,
    );
  }

  @override
  bool shouldRepaint(_InfinityPainter old) => old.t != t;
}

/// Estadísticas avanzadas: cuatro barras que respiran desfasadas.
class BarsArt extends _LoopArt {
  const BarsArt({
    super.key,
    required super.accent,
    super.size = 30,
    super.period = const Duration(milliseconds: 2400),
  });

  @override
  State<BarsArt> createState() => _BarsArtState();
}

class _BarsArtState extends _LoopArtState<BarsArt> {
  @override
  CustomPainter painter(double t) => _BarsPainter(t: t, accent: widget.accent);
}

class _BarsPainter extends CustomPainter {
  final double t;
  final Color accent;

  const _BarsPainter({required this.t, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    const n = 4;
    final gap = size.width * 0.09;
    final w = (size.width - gap * (n - 1)) / n;
    final base = size.height;

    final fill = Paint()..color = accent;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = kInk;

    for (var i = 0; i < n; i++) {
      final phase = (t + i * 0.17) % 1.0;
      final f = 0.34 + 0.60 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi));
      final h = base * f;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * (w + gap), base - h, w, h),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, fill);
      canvas.drawRRect(rect, stroke);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.t != t;
}

/// Simulacros de examen: el aro del cronómetro dando la vuelta.
class TimerArt extends _LoopArt {
  const TimerArt({
    super.key,
    required super.accent,
    super.size = 32,
    super.period = const Duration(milliseconds: 2800),
  });

  @override
  State<TimerArt> createState() => _TimerArtState();
}

class _TimerArtState extends _LoopArtState<TimerArt> {
  @override
  CustomPainter painter(double t) => _TimerPainter(t: t, accent: widget.accent);
}

class _TimerPainter extends CustomPainter {
  final double t;
  final Color accent;

  const _TimerPainter({required this.t, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    final rect = Rect.fromCircle(center: c, radius: r);

    // Pista de fondo: el color de la ventaja, que sobre la pastilla teñida se
    // lee como un aro apagado sin tener que jugar con el alfa.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = accent,
    );

    canvas.drawArc(
      rect,
      -math.pi / 2,
      t * 2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..color = kInk,
    );

    // Aguja: marca por dónde va la vuelta sin necesidad de números.
    final a = -math.pi / 2 + t * 2 * math.pi;
    canvas.drawLine(
      c,
      c + Offset(math.cos(a), math.sin(a)) * (r * 0.58),
      Paint()
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = kInk,
    );
    canvas.drawCircle(c, 2.4, Paint()..color = kInk);
  }

  @override
  bool shouldRepaint(_TimerPainter old) => old.t != t;
}

// ============================================================================
// AVISO DE LANZAMIENTO
// ============================================================================

/// "Te avisaremos cuando esté disponible": la campana repica de vez en cuando
/// y suelta dos ondas, para que el aviso no pase inadvertido al final de la
/// lista de ventajas.
class PremiumNoticeCard extends StatefulWidget {
  final String message;

  const PremiumNoticeCard({super.key, required this.message});

  @override
  State<PremiumNoticeCard> createState() => _PremiumNoticeCardState();
}

class _PremiumNoticeCardState extends State<PremiumNoticeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  bool _running = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != !_running) {
      _running = !reduced;
      if (reduced) {
        _ctrl.stop();
      } else {
        _ctrl.repeat();
      }
    }

    return StickerCard(
      depth: 5,
      radius: 20,
      background: AppColors.surfaceVariant,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, child) {
                  // El repique ocupa el primer tercio del ciclo; el resto la
                  // campana está quieta, que es lo que hace que se note.
                  final t = _ctrl.value;
                  final ring = t < 0.34 ? t / 0.34 : 0.0;
                  final swing = ring == 0
                      ? 0.0
                      : math.sin(ring * math.pi * 5) * 0.24 * (1 - ring);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (ring > 0)
                        CustomPaint(
                          size: const Size.square(48),
                          painter: _RingsPainter(t: ring),
                        ),
                      Transform.rotate(angle: swing, child: child),
                    ],
                  );
                },
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: kInk, width: 2),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    size: 18,
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              widget.message,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: kInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final double t;

  const _RingsPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final p = (t - i * 0.22).clamp(0.0, 1.0);
      if (p <= 0) continue;
      canvas.drawCircle(
        c,
        17 + p * 7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.secondary.withValues(alpha: 0.45 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}
