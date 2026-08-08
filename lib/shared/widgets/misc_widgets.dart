import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Logo de texto: MIR + Daily en coral, igual que la web.
class MirDailyLogo extends StatelessWidget {
  final double fontSize;
  final Color baseColor;

  const MirDailyLogo({
    super.key,
    this.fontSize = 32,
    this.baseColor = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: baseColor,
        ),
        children: const [
          TextSpan(text: 'MIR'),
          TextSpan(
            text: 'Daily',
            style: TextStyle(color: AppColors.primaryDark),
          ),
        ],
      ),
    );
  }
}

/// Número que cuenta hacia arriba con rebote (para puntuaciones).
class CountUpText extends StatelessWidget {
  final int value;
  final Duration duration;
  final TextStyle? style;
  final String suffix;

  const CountUpText({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 1400),
    this.style,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return Text('${animated.round()}$suffix', style: style);
      },
    );
  }
}

/// Entrada animada: aparece deslizándose hacia arriba con fade,
/// con retardo opcional (para listas escalonadas estilo Duolingo).
class SlideFadeIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset beginOffset;

  const SlideFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 480),
    this.beginOffset = const Offset(0, 0.18),
  });

  @override
  State<SlideFadeIn> createState() => _SlideFadeInState();
}

class _SlideFadeInState extends State<SlideFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _offset = Tween(begin: widget.beginOffset, end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

/// Avatar circular coral con inicial del usuario.
class UserAvatar extends StatelessWidget {
  final String name;
  final double size;

  const UserAvatar({super.key, required this.name, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.envelopeTop, AppColors.envelopeBottom],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}
