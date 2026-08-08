import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class _ConfettiParticle {
  final double startX; // 0..1 (fracción del ancho)
  final double angle; // dirección inicial
  final double velocity;
  final double size;
  final Color color;
  final double rotationSpeed;
  final double phase;
  final bool isCircle;

  _ConfettiParticle({
    required this.startX,
    required this.angle,
    required this.velocity,
    required this.size,
    required this.color,
    required this.rotationSpeed,
    required this.phase,
    required this.isCircle,
  });
}

/// Lluvia de confeti dibujada a mano (sin dependencias externas).
class ConfettiOverlay extends StatefulWidget {
  final bool play;
  final int particleCount;
  final Duration duration;

  const ConfettiOverlay({
    super.key,
    required this.play,
    this.particleCount = 90,
    this.duration = const Duration(milliseconds: 3200),
  });

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<_ConfettiParticle> _particles;
  final _random = math.Random();

  static const _palette = [
    AppColors.primary,
    AppColors.primaryDark,
    AppColors.envelopeAccent,
    AppColors.gold,
    AppColors.success,
    AppColors.emeraldLight,
    Colors.white,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _particles = _generate();
    if (widget.play) _controller.forward();
  }

  List<_ConfettiParticle> _generate() {
    return List.generate(widget.particleCount, (i) {
      return _ConfettiParticle(
        startX: _random.nextDouble(),
        angle: (-math.pi / 2) + (_random.nextDouble() - 0.5) * 1.2,
        velocity: 250 + _random.nextDouble() * 420,
        size: 5 + _random.nextDouble() * 8,
        color: _palette[_random.nextInt(_palette.length)],
        rotationSpeed: (_random.nextDouble() - 0.5) * 14,
        phase: _random.nextDouble() * math.pi * 2,
        isCircle: _random.nextBool(),
      );
    });
  }

  @override
  void didUpdateWidget(covariant ConfettiOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.play && !oldWidget.play) {
      _particles = _generate();
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.value == 0 || _controller.isDismissed) {
            return const SizedBox.shrink();
          }
          return CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(
              particles: _particles,
              progress: _controller.value,
            ),
          );
        },
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final t = progress;
    const gravity = 900.0;

    for (final p in particles) {
      final time = t * 2.6; // segundos virtuales
      final x = p.startX * size.width +
          math.cos(p.angle) * p.velocity * time * 0.35 +
          math.sin(time * 3 + p.phase) * 18;
      final y = size.height * 0.28 +
          math.sin(p.angle) * p.velocity * time +
          0.5 * gravity * time * time;

      if (y > size.height + 30) continue;

      final opacity = (1.0 - t).clamp(0.0, 1.0);
      paint.color = p.color.withValues(alpha: opacity);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.phase + time * p.rotationSpeed);
      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: p.size, height: p.size * 0.62),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
