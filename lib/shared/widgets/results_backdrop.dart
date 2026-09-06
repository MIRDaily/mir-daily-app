import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'goo_fission_loader.dart';

/// Fondo animado de la revisión del daily: degradado cálido con orbes
/// difuminados que derivan, tintados por un color de acento.
///
/// Vive fuera de `results_screen.dart` porque lo comparten dos pantallas: la
/// espera de "Corrigiendo tu daily…" (mientras se envía) y la propia revisión.
/// Así la transición entre las dos no da un salto: mismo fondo, mismo loader.
class ResultsBackdrop extends StatefulWidget {
  final Color accent;
  const ResultsBackdrop({super.key, required this.accent});

  @override
  State<ResultsBackdrop> createState() => _ResultsBackdropState();
}

class _ResultsBackdropState extends State<ResultsBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: widget.accent),
      duration: const Duration(milliseconds: 700),
      builder: (context, color, _) {
        final accent = color ?? widget.accent;
        return AnimatedBuilder(
          animation: _c,
          builder: (context, __) {
            return CustomPaint(
              painter: _BackdropPainter(accent: accent, t: _c.value),
              size: Size.infinite,
            );
          },
        );
      },
    );
  }
}

class _BackdropPainter extends CustomPainter {
  final Color accent;
  final double t;

  _BackdropPainter({required this.accent, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Degradado base cálido con un ligero tinte del acento.
    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(AppColors.background, accent, 0.06)!,
          AppColors.background,
          Color.lerp(AppColors.background, accent, 0.10)!,
        ],
        stops: const [0, 0.5, 1],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    void orb(double baseX, double baseY, double r, Color c, double phase) {
      final angle = 2 * math.pi * (t + phase);
      final dx = math.cos(angle) * size.width * 0.08;
      final dy = math.sin(angle * 0.8) * size.height * 0.05;
      final paint = Paint()
        ..color = c
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
      canvas.drawCircle(
        Offset(baseX * size.width + dx, baseY * size.height + dy),
        r,
        paint,
      );
    }

    orb(0.18, 0.16, size.width * 0.34,
        accent.withValues(alpha: 0.22), 0.0);
    orb(0.85, 0.28, size.width * 0.30,
        AppColors.gold.withValues(alpha: 0.16), 0.33);
    orb(0.72, 0.82, size.width * 0.38,
        accent.withValues(alpha: 0.16), 0.66);
    orb(0.12, 0.78, size.width * 0.26,
        AppColors.success.withValues(alpha: 0.12), 0.5);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) =>
      old.t != t || old.accent != accent;
}

/// Pantalla de espera del daily: el fondo vivo de la revisión con el loader
/// "goo" en el centro. La usan tanto el envío de respuestas ("Corrigiendo tu
/// daily…") como la preparación de la revisión, para que pasar de una a otra
/// sea un fundido y no un corte entre dos pantallas distintas.
class ResultsLoader extends StatelessWidget {
  final String label;

  const ResultsLoader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: ResultsBackdrop(accent: AppColors.primary),
          ),
          Center(child: GooFissionLoader(size: 168, label: label)),
        ],
      ),
    );
  }
}
