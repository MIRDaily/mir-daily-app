import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Réplica móvil del FallingBackground de la web: células médicas
/// (eritrocitos, linfocitos, virus) cayendo en capas con parallax,
/// deriva lateral, rotación y desenfoque por profundidad.
class FallingBackground extends StatefulWidget {
  const FallingBackground({super.key});

  @override
  State<FallingBackground> createState() => _FallingBackgroundState();
}

class _FallingItem {
  final String asset;
  final double size;
  final double startX; // fracción del ancho (-0.1 .. 1.1)
  final double drift; // px de deriva horizontal por ciclo
  final double rotations; // vueltas por ciclo (puede ser negativo)
  final double duration; // segundos por ciclo
  final double delay; // desfase inicial (segundos)
  final double blur;
  final double opacity;

  const _FallingItem({
    required this.asset,
    required this.size,
    required this.startX,
    required this.drift,
    required this.rotations,
    required this.duration,
    required this.delay,
    required this.blur,
    required this.opacity,
  });
}

class _FallingBackgroundState extends State<FallingBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _elapsed = 0;
  late final List<_FallingItem> _items;

  // Igual que la web: el eritrocito pesa 60, el linfocito 30, el virus 10.
  static final _weightedAssets = [
    ...List.filled(6, 'assets/images/falling_rbc.png'),
    ...List.filled(3, 'assets/images/falling_cell.png'),
    'assets/images/falling_virus.png',
  ];

  // Capas (count, sizeMin, sizeMax, blur, durMin, durMax) — versión móvil.
  static const _layers = [
    (1, 150.0, 210.0, 7.0, 14.0, 20.0),
    (3, 90.0, 130.0, 3.5, 20.0, 30.0),
    (8, 52.0, 80.0, 0.0, 30.0, 44.0),
    (10, 28.0, 48.0, 2.0, 46.0, 70.0),
  ];

  @override
  void initState() {
    super.initState();
    final random = math.Random(7);
    _items = [
      for (final (count, sMin, sMax, blur, dMin, dMax) in _layers)
        for (var i = 0; i < count; i++)
          _FallingItem(
            asset:
                _weightedAssets[random.nextInt(_weightedAssets.length)],
            size: sMin + random.nextDouble() * (sMax - sMin),
            startX: -0.1 + random.nextDouble() * 1.2,
            drift: (random.nextDouble() - 0.5) * 240,
            rotations: (random.nextDouble() - 0.5) * 2.4,
            duration: dMin + random.nextDouble() * (dMax - dMin),
            delay: random.nextDouble() * 160,
            blur: blur,
            opacity: blur > 4 ? 0.55 : (blur > 0 ? 0.8 : 1.0),
          ),
    ];

    _ticker = createTicker((elapsed) {
      setState(() => _elapsed = elapsed.inMilliseconds / 1000);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return ClipRect(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final item in _items) _buildItem(item, w, h),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildItem(_FallingItem item, double w, double h) {
    final progress = ((_elapsed + item.delay) % item.duration) / item.duration;
    final y = -item.size + progress * (h + item.size * 2);
    final x = item.startX * w + item.drift * progress;
    final angle = item.rotations * 2 * math.pi * progress;

    Widget child = Opacity(
      opacity: item.opacity,
      child: Image.asset(
        item.asset,
        width: item.size,
        filterQuality: FilterQuality.low,
      ),
    );

    if (item.blur > 0) {
      child = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: item.blur,
          sigmaY: item.blur,
        ),
        child: child,
      );
    }

    return Positioned(
      left: x,
      top: y,
      child: Transform.rotate(angle: angle, child: child),
    );
  }
}
