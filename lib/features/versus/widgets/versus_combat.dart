import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/services/haptics_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../models/versus_models.dart';
import 'versus_avatar.dart';

// ============================================================================
// Presentación de los combatientes
// ============================================================================

/// Pase de lista antes de la primera pregunta.
///
/// Cabe entero en los 3 segundos de cuenta atrás que el servidor deja antes de
/// cada ronda, así que no alarga la partida ni un milisegundo: ocupa un hueco
/// que ya existía y en el que hasta ahora solo había un número.
///
/// Con dos jugadores es un cara a cara con el "VS" en medio; con más, una
/// formación que entra escalonada.
class VersusIntro extends StatefulWidget {
  final List<VersusPlayer> players;
  final String? meId;

  /// Guardia y sus vidas, para anunciar a qué se juega.
  final bool survival;
  final int lives;

  const VersusIntro({
    super.key,
    required this.players,
    required this.meId,
    required this.survival,
    required this.lives,
  });

  @override
  State<VersusIntro> createState() => _VersusIntroState();
}

class _VersusIntroState extends State<VersusIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
    // El choque del "VS" se acompaña con un golpe seco: es lo que convierte la
    // entrada en un combate y no en una transición.
    Future.delayed(const Duration(milliseconds: 620), () {
      if (mounted) HapticsService.medium();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duel = widget.players.length == 2;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // Entrada de los lados: llegan desde fuera y chocan en el centro.
        final slide = Curves.easeOutBack.transform((t / 0.32).clamp(0.0, 1.0));
        final vs = Curves.elasticOut.transform(
          ((t - 0.24) / 0.36).clamp(0.0, 1.0),
        );
        // Destello del choque: nace cuando el VS aterriza y se apaga rápido.
        final clash = ((t - 0.30) / 0.22).clamp(0.0, 1.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            // Fondo: rayos que giran y una viñeta. Es textura pintada, sin
            // imágenes, para que no dependa de ningún asset.
            CustomPaint(
              painter: _ArenaPainter(progress: t, clash: clash),
              size: Size.infinite,
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 2),
                    Opacity(
                      opacity: ((t - 0.05) / 0.2).clamp(0.0, 1.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          widget.survival
                              ? (widget.lives == 1
                                  ? 'GUARDIA · MUERTE SÚBITA'
                                  : 'GUARDIA · ${widget.lives} VIDAS')
                              : 'AL MEJOR MARCADOR',
                          style: const TextStyle(
                            color: AppColors.primaryDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (duel) _buildDuel(slide, vs) else _buildRoster(t),
                    const Spacer(),
                    // Corazones del combate, para que se vea a qué se juega.
                    if (widget.survival)
                      Opacity(
                        opacity: ((t - 0.5) / 0.25).clamp(0.0, 1.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (int i = 0; i < widget.lives; i++)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 3),
                                child: Icon(Icons.favorite_rounded,
                                    size: 20, color: AppColors.error),
                              ),
                          ],
                        ),
                      ),
                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDuel(double slide, double vs) {
    final left = widget.players[0];
    final right = widget.players[1];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Transform.translate(
            offset: Offset(-160 * (1 - slide), 0),
            child: Opacity(
              opacity: slide.clamp(0.0, 1.0),
              child: _Fighter(
                player: left,
                isMe: left.id == widget.meId,
                align: CrossAxisAlignment.end,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Transform.scale(
            scale: vs,
            child: Transform.rotate(
              angle: -0.12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryDark, AppColors.primary],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDark.withValues(alpha: 0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Text(
                  'VS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Transform.translate(
            offset: Offset(160 * (1 - slide), 0),
            child: Opacity(
              opacity: slide.clamp(0.0, 1.0),
              child: _Fighter(
                player: right,
                isMe: right.id == widget.meId,
                align: CrossAxisAlignment.start,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Más de dos: entran en formación, uno detrás de otro.
  Widget _buildRoster(double t) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 14,
      children: [
        for (int i = 0; i < widget.players.length; i++)
          Builder(builder: (context) {
            final start = 0.08 * i;
            final local =
                Curves.easeOutBack.transform(((t - start) / 0.3).clamp(0.0, 1.0));
            return Transform.scale(
              scale: local,
              child: Opacity(
                opacity: local.clamp(0.0, 1.0),
                child: _Fighter(
                  player: widget.players[i],
                  isMe: widget.players[i].id == widget.meId,
                  align: CrossAxisAlignment.center,
                  compact: true,
                ),
              ),
            );
          }),
      ],
    );
  }
}

/// Fondo del cara a cara: rayos que giran despacio desde el centro, un halo
/// cálido y el destello del choque. Todo pintado — ni una imagen, así que no
/// añade peso al APK ni depende de assets que haya que mantener.
class _ArenaPainter extends CustomPainter {
  final double progress;
  final double clash;

  _ArenaPainter({required this.progress, required this.clash});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.46);

    // Halo cálido detrás del choque.
    canvas.drawCircle(
      center,
      size.width * (0.45 + 0.12 * progress),
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.22),
            AppColors.primary.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(center: center, radius: size.width * 0.6),
        ),
    );

    // Rayos: cuñas finas que salen del centro y giran. Dan sensación de
    // velocidad sin tapar a los combatientes.
    const rays = 16;
    final rotation = progress * 0.5;
    final rayPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.07 + 0.05 * clash);

    for (int i = 0; i < rays; i++) {
      final angle = rotation + i * (2 * math.pi / rays);
      const half = 0.045;
      final far = size.longestSide;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + math.cos(angle - half) * far,
          center.dy + math.sin(angle - half) * far,
        )
        ..lineTo(
          center.dx + math.cos(angle + half) * far,
          center.dy + math.sin(angle + half) * far,
        )
        ..close();
      canvas.drawPath(path, rayPaint);
    }

    // Onda de choque: un anillo que se abre y se apaga cuando el VS aterriza.
    if (clash > 0 && clash < 1) {
      canvas.drawCircle(
        center,
        size.width * 0.15 + size.width * 0.6 * clash,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * (1 - clash)
          ..color = AppColors.primaryDark.withValues(alpha: 0.5 * (1 - clash)),
      );
    }

    // Viñeta: oscurece las esquinas para que la mirada caiga en el centro.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            AppColors.secondary.withValues(alpha: 0.14),
          ],
          stops: const [0.55, 1],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_ArenaPainter old) =>
      old.progress != progress || old.clash != clash;
}

class _Fighter extends StatelessWidget {
  final VersusPlayer player;
  final bool isMe;
  final CrossAxisAlignment align;
  final bool compact;

  const _Fighter({
    required this.player,
    required this.isMe,
    required this.align,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // Grandes de verdad: en la primera versión se perdían en medio de la
    // pantalla y el cara a cara no imponía nada.
    final size = compact ? 68.0 : 104.0;

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isMe ? kInk : kHairline,
              width: 3,
            ),
            boxShadow: isMe
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          child: VersusAvatar(player: player, size: size),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: size + 34,
          child: Text(
            player.nickname,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align == CrossAxisAlignment.end
                ? TextAlign.right
                : align == CrossAxisAlignment.start
                    ? TextAlign.left
                    : TextAlign.center,
            style: TextStyle(
              color: isMe ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 14,
              fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        if (isMe)
          const Text(
            'TÚ',
            style: TextStyle(
              color: AppColors.primaryDark,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// El corazón que cae
// ============================================================================

/// Despega un corazón del HUD y lo deja caer hasta el fondo de la pantalla.
///
/// Va en el Overlay de la ruta, así que cae POR DELANTE de la pregunta, de las
/// opciones y de la tarjeta de la explicación: es el aviso que no se puede
/// perder de vista, pase lo que pase por debajo.
void dropHeartFrom(BuildContext context, {double size = 22}) {
  final overlay = Overlay.maybeOf(context);
  final box = context.findRenderObject();
  if (overlay == null || box is! RenderBox || !box.hasSize) return;

  final origin = box.localToGlobal(Offset.zero);
  final screen = MediaQuery.of(context).size;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FallingHeart(
      from: origin + Offset(box.size.width / 2 - size / 2, 0),
      screenHeight: screen.height,
      size: size,
      onDone: () => entry.remove(),
    ),
  );

  overlay.insert(entry);
}

class _FallingHeart extends StatefulWidget {
  final Offset from;
  final double screenHeight;
  final double size;
  final VoidCallback onDone;

  const _FallingHeart({
    required this.from,
    required this.screenHeight,
    required this.size,
    required this.onDone,
  });

  @override
  State<_FallingHeart> createState() => _FallingHeartState();
}

class _FallingHeartState extends State<_FallingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  /// Deriva un poco al caer, para que no parezca un ascensor.
  late final double _drift = (math.Random().nextDouble() - 0.5) * 90;
  late final double _spin = (math.Random().nextDouble() - 0.5) * 3;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // Un salto corto hacia arriba antes de caer: sin ese respingo el
        // corazón no parece que se DESPEGUE, solo que se desliza.
        final hop = math.sin(math.pi * t.clamp(0.0, 0.18) / 0.18) * 26;
        final fall = Curves.easeInQuad.transform(t) *
            (widget.screenHeight - widget.from.dy + 60);

        return Positioned(
          left: widget.from.dx + _drift * t,
          top: widget.from.dy - hop + fall,
          child: IgnorePointer(
            child: Opacity(
              // Se apaga solo al final, para que se vea el recorrido entero.
              opacity: t > 0.75 ? (1 - (t - 0.75) / 0.25).clamp(0.0, 1.0) : 1,
              child: Transform.rotate(
                angle: _spin * t,
                child: Transform.scale(
                  scale: 1 + 0.5 * math.sin(math.pi * t.clamp(0.0, 0.3) / 0.3),
                  child: Icon(
                    Icons.heart_broken_rounded,
                    size: widget.size,
                    color: AppColors.error,
                    shadows: [
                      BoxShadow(
                        color: AppColors.error.withValues(alpha: 0.5),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// El golpe
// ============================================================================

/// Momento a pantalla completa cuando pierdes una vida, caes, o cae un rival.
///
/// Va por encima de todo y se quita solo. Es lo que faltaba para que perder una
/// vida se notara: antes se leía igual que acertar, en una línea de texto dentro
/// de una tarjeta que había que desplegar.
class VersusStrikeOverlay extends StatefulWidget {
  final VersusStrike strike;
  final VoidCallback onDone;

  const VersusStrikeOverlay({
    super.key,
    required this.strike,
    required this.onDone,
  });

  @override
  State<VersusStrikeOverlay> createState() => _VersusStrikeOverlayState();
}

class _VersusStrikeOverlayState extends State<VersusStrikeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.strike.kind == VersusStrikeKind.knockout
        ? const Duration(milliseconds: 3400)
        : const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();

    // La vibración va con el impacto, no con la aparición: el golpe se siente
    // cuando el corazón se rompe.
    switch (widget.strike.kind) {
      case VersusStrikeKind.knockout:
        HapticsService.strong();
      case VersusStrikeKind.hit:
        HapticsService.medium();
      case VersusStrikeKind.rivalDown:
        HapticsService.light();
    }

    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final knockout = widget.strike.kind == VersusStrikeKind.knockout;
    final rival = widget.strike.kind == VersusStrikeKind.rivalDown;

    final Color tint = rival ? AppColors.success : AppColors.error;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // El velo entra rápido, aguanta y se va: sin el aguante, el mensaje no
        // da tiempo a leerse.
        final veil = t < 0.12
            ? t / 0.12
            : t > 0.78
                ? (1 - (t - 0.78) / 0.22).clamp(0.0, 1.0)
                : 1.0;

        return IgnorePointer(
          child: Opacity(
            opacity: veil,
            child: ColoredBox(
              color: tint.withValues(alpha: knockout ? 0.93 : 0.86),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildIcon(t, knockout, rival),
                    const SizedBox(height: 22),
                    Text(
                      switch (widget.strike.kind) {
                        VersusStrikeKind.knockout => 'HAS CAÍDO',
                        VersusStrikeKind.hit => '−1 VIDA',
                        VersusStrikeKind.rivalDown =>
                          widget.strike.nickname == null
                              ? 'CAEN RIVALES'
                              : '${widget.strike.nickname!.toUpperCase()} CAE',
                      },
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      switch (widget.strike.kind) {
                        VersusStrikeKind.knockout =>
                          'Se acabó tu guardia. Mira cómo cae el resto.',
                        VersusStrikeKind.hit => widget.strike.livesLeft == 1
                            ? 'Te queda una. La siguiente decide.'
                            : 'Te quedan ${widget.strike.livesLeft}.',
                        VersusStrikeKind.rivalDown => 'Sigues en pie.',
                      },
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIcon(double t, bool knockout, bool rival) {
    // Golpe: entra de sopetón y rebota.
    final punch = Curves.elasticOut.transform((t / 0.3).clamp(0.0, 1.0));
    // Temblor solo en el impacto, y decreciente.
    final shake = t < 0.34
        ? math.sin(t * 60) * 8 * (1 - t / 0.34)
        : 0.0;

    return Transform.translate(
      offset: Offset(shake, 0),
      child: Transform.scale(
        scale: punch,
        child: Icon(
          rival
              ? Icons.military_tech_rounded
              : knockout
                  ? Icons.dangerous_rounded
                  : Icons.heart_broken_rounded,
          size: knockout ? 104 : 88,
          color: Colors.white,
        ),
      ),
    );
  }
}
