import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Widget de fondo animado con efecto de ondas y partículas flotantes
class AnimatedFocusBackground extends StatefulWidget {
  final Color primaryColor;
  final Color secondaryColor;

  const AnimatedFocusBackground({
    super.key,
    this.primaryColor = const Color(0xFF6B7FD7),
    this.secondaryColor = const Color(0xFF9B59B6),
  });

  @override
  State<AnimatedFocusBackground> createState() => _AnimatedFocusBackgroundState();
}

class _AnimatedFocusBackgroundState extends State<AnimatedFocusBackground>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _particleController;
  late List<Particle> _particles;

  @override
  void initState() {
    super.initState();

    // Controlador para las ondas (más lento y suave)
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    // Controlador para las partículas (más lento y suave)
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();

    // Inicializar partículas
    _particles = List.generate(
      15,
      (index) => Particle(
        offsetX: math.Random().nextDouble(),
        offsetY: math.Random().nextDouble(),
        size: 2 + math.Random().nextDouble() * 4,
        speed: 0.5 + math.Random().nextDouble() * 1.5,
        phase: math.Random().nextDouble() * 2 * math.pi,
      ),
    );
  }

  @override
  void dispose() {
    _waveController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Gradiente de fondo
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.primaryColor,
                widget.secondaryColor,
              ],
            ),
          ),
        ),
        
        // Ondas animadas
        AnimatedBuilder(
          animation: _waveController,
          builder: (context, child) {
            return CustomPaint(
              painter: WavePainter(
                animation: _waveController.value,
                color: Colors.white.withOpacity(0.05),
              ),
              size: Size.infinite,
            );
          },
        ),

        // Partículas flotantes
        AnimatedBuilder(
          animation: _particleController,
          builder: (context, child) {
            return CustomPaint(
              painter: ParticlePainter(
                particles: _particles,
                animation: _particleController.value,
              ),
              size: Size.infinite,
            );
          },
        ),

        // Overlay sutil
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.1),
                Colors.black.withOpacity(0.3),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Pintor de ondas sinusoidales
class WavePainter extends CustomPainter {
  final double animation;
  final Color color;

  WavePainter({
    required this.animation,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();
    final waveHeight = size.height * 0.1;
    final waveLength = size.width / 2;
    
    // Dibujar múltiples ondas
    for (int i = 0; i < 3; i++) {
      path.reset();
      final yOffset = size.height * (0.3 + i * 0.2);
      final phase = animation * 2 * math.pi + i * math.pi / 3;
      
      path.moveTo(0, yOffset);
      
      for (double x = 0; x <= size.width; x += 5) {
        final y = yOffset +
            math.sin((x / waveLength) * 2 * math.pi + phase) * waveHeight;
        path.lineTo(x, y);
      }
      
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(WavePainter oldDelegate) => true;
}

/// Clase para representar una partícula
class Particle {
  final double offsetX;
  final double offsetY;
  final double size;
  final double speed;
  final double phase;

  Particle({
    required this.offsetX,
    required this.offsetY,
    required this.size,
    required this.speed,
    required this.phase,
  });
}

/// Pintor de partículas flotantes
class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double animation;

  ParticlePainter({
    required this.particles,
    required this.animation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    for (final particle in particles) {
      // Movimiento vertical con efecto sinusoidal
      final x = size.width * particle.offsetX +
          math.sin(animation * 2 * math.pi * particle.speed + particle.phase) *
              20;
      final y = ((size.height * particle.offsetY +
                  animation * size.height * 0.1 * particle.speed) %
              size.height);

      // Dibujar partícula con efecto de brillo
      canvas.drawCircle(
        Offset(x, y),
        particle.size,
        paint,
      );

      // Halo
      final haloPaint = Paint()
        ..color = Colors.white.withOpacity(0.1)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        Offset(x, y),
        particle.size * 2,
        haloPaint,
      );
    }
  }

  @override
  bool shouldRepaint(ParticlePainter oldDelegate) => true;
}
